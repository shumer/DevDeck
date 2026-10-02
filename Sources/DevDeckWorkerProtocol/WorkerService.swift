import ArcKit
import DDEVKit
import DevDeckCore
import Foundation
import ProjectKit

/// Integration rules stay in the existing kits; Linux execution/cancellation stays in this target.
public struct WorkerService: Sendable {
    public let distribution: String
    private let runner: any CommandRunning
    private let remoteService: WorkerRemoteService
    private let attention: WorkerAttentionState
    private let ddevInventory: WorkerDDEVInventory
    private let powerOff: WorkerPowerOffCoordinator
    private let arcHTTPClient: any HTTPClient
    private let checkoutScanner: WorkerCheckoutScanner
    public init(distribution: String, runner: any CommandRunning = WSLCommandRunner(), remoteService: WorkerRemoteService = WorkerRemoteService(), arcHTTPClient: any HTTPClient = URLSessionHTTPClient.makeDefault(timeout: 3), leaseClock: any WorkerLeaseClock = WorkerContinuousLeaseClock(), dates: any DateProvider = SystemDateProvider()) {
        self.distribution = distribution; self.runner = runner
        self.remoteService = remoteService
        self.arcHTTPClient = arcHTTPClient
        self.checkoutScanner = WorkerCheckoutScanner(runner: runner, dates: dates)
        let attention=WorkerAttentionState(),inventory=WorkerDDEVInventory()
        self.attention=attention;self.ddevInventory=inventory
        self.powerOff=WorkerPowerOffCoordinator(distribution:distribution,runner:runner,clock:leaseClock,dates:dates,attention:attention,inventory:inventory)
    }

    public func handle(_ data: Data, onProgress: (@Sendable (String) -> Void)? = nil) async -> WorkerResponse {
        guard data.count <= WorkerProtocol.maximumFrameBytes,
              let request = try? JSONDecoder().decode(WorkerRequest.self, from: data), request.protocolVersion == WorkerProtocol.version,
              !request.id.isEmpty, request.id.utf8.count <= 128,
              !request.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return await execute(data, onProgress: onProgress)
        }
        guard Self.validActiveProjectIDs(request.activeProjectIDs) else {
            return failure(request.id, "invalidRequest", "Active project IDs must be distinct bounded IDs without control characters.")
        }
        if let problem=Self.validateCheckout(request,distribution:distribution) {return failure(request.id,problem.code,problem.message)}
        if let problem=Self.validatePowerOff(request,distribution:distribution) {return failure(request.id,problem.code,problem.message)}
        if request.operation == "checkouts.snapshot", let checkout = request.checkout {
            let response = WorkerResponse(id: request.id, distribution: distribution, checkout: await checkoutScanner.read(checkout))
            guard let encoded = try? JSONEncoder().encode(response), encoded.count <= WorkerProtocol.maximumFrameBytes else {
                return failure(request.id, "frameTooLarge", "Checkout result exceeds the bounded protocol frame.")
            }
            return response
        }
        if ["ddev.poweroff.prepare","ddev.poweroff.run","ddev.poweroff.finalize","ddev.poweroff.abort"].contains(request.operation) {
            let response=await powerOff.handle(request,progress:onProgress)
            guard let encoded=try? JSONEncoder().encode(response),encoded.count<=WorkerProtocol.maximumFrameBytes else{return failure(request.id,"frameTooLarge","DDEV poweroff result exceeds the bounded protocol frame.")}
            return response
        }
        let project = request.project.flatMap { project -> WorkerProject? in
            guard project.distribution == distribution, Self.validProjectOptions(project), !project.id.isEmpty,
                  project.id.utf8.count <= 128, !project.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  project.title.map({ !$0.isEmpty && $0.utf8.count <= 512 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) ?? true else { return nil }
            return project
        }
        if request.operation == "attention.dismiss" {
            guard let project else { return failure(request.id, "invalidProject", "A valid project reference is required.") }
            return WorkerResponse(id: request.id, distribution: distribution, attention: await attention.dismiss(project, now: Date(), activeProjectIDs: request.activeProjectIDs))
        }
        let action = ["project.start", "project.stop", "project.restart"].contains(request.operation)
            ? request.operation.replacingOccurrences(of: "project.", with: "") : nil
        let ddevMutation=project?.kind == .ddev && action != nil
        if ddevMutation, !(await powerOff.beginMutation(request.id)) {return failure(request.id,"ddevBusy","A DDEV environment transaction is in progress.")}
        let observationEpoch=project == nil ? nil : await attention.observationEpoch(project!)
        if let project, let action { await attention.noteAction(project, action: action, now: Date()) }
        if project?.kind == .ddev, action != nil { await ddevInventory.invalidate() }
        let response = await execute(data, onProgress: onProgress)
        if project?.kind == .ddev, action != nil { await ddevInventory.invalidate() }
        if response.error?.code == "cancelled" {if ddevMutation {await powerOff.endMutation(request.id)};return response}
        let signals: WorkerAttentionSnapshot?
        var status = response.status
        if let remote = request.remote, let snapshot = response.remote, request.operation == "remote.snapshot" {
            signals = await attention.remote(snapshot, request: remote, now: Date())
        } else if let project, !project.path.isEmpty, request.operation == "project.status" || action != nil {
            let docker = project.kind != .local || project.requiresDocker == true
                ? await attention.dockerStatus(runner: runner, now: Date()) : DockerStatus(state: .unknown)
            (status, signals) = await attention.observe(project, status: status, error: response.error, action: action, docker: docker, now: Date(), activeProjectIDs: request.activeProjectIDs, observationEpoch:observationEpoch)
            // Poll settling protects a card from a brief failure. A settings answer must still
            // describe this exact request, especially after its URL or folder has changed.
            if project.kind != .ddev {
                status?.checkSummary = response.status?.checkSummary
                status?.checkedAt = response.status?.checkedAt
            }
        } else { signals = nil }
        // project.check is an ephemeral settings read: never register its edited project,
        // advance card settling or change the deck's remembered attention episodes.
        if ddevMutation {await powerOff.endMutation(request.id)}
        return WorkerResponse(id: response.id, distribution: response.distribution, capabilities: response.capabilities,
                              status: status, projects: response.projects, error: response.error, logs: response.logs,
                              event: response.event, remote: response.remote, attention: signals, suggestion: response.suggestion)
    }

    public func closePowerOffState() async {await powerOff.close()}
    public func beginClosePowerOffState() async {await powerOff.beginClose()}
    public static func validatePowerOff(_ request: WorkerRequest, distribution: String) -> WorkerFailure? {
        let operations=["ddev.poweroff.prepare","ddev.poweroff.run","ddev.poweroff.finalize","ddev.poweroff.abort"]
        func invalid() -> WorkerFailure {WorkerFailure(code:"invalidRequest",message:"DDEV poweroff requires a bounded typed transaction context for this distribution.")}
        guard operations.contains(request.operation) else{return request.powerOff == nil ? nil : invalid()}
        func valid(_ value: String,_ maximum: Int) -> Bool {!value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && value.utf8.count<=maximum && !value.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)})}
        guard let context=request.powerOff,valid(context.groupToken,128),request.project == nil,request.remote == nil,request.refreshCycle == nil,request.targetRequestID == nil else{return invalid()}
        if request.operation == "ddev.poweroff.prepare" {
            guard request.activeProjectIDs == nil,let projects=context.projects,!projects.isEmpty,projects.count<=1024,Set(projects.map(\.id)).count==projects.count else{return invalid()}
            for project in projects {
                guard project.kind=="ddev",valid(project.id,128),project.distribution==distribution,valid(project.distribution,128),isLinuxPath(project.path),project.path.utf8.count<=4096,
                      project.title.map({valid($0,512)}) ?? true else{return invalid()}
            }
        }else if context.projects != nil || (["ddev.poweroff.run"].contains(request.operation) && request.activeProjectIDs != nil) {return invalid()}
        return nil
    }

    private func execute(_ data: Data, onProgress: (@Sendable (String) -> Void)? = nil) async -> WorkerResponse {
        guard data.count <= WorkerProtocol.maximumFrameBytes else {
            return failure(nil, "frameTooLarge", "Request exceeds the frame limit.")
        }
        guard let request = try? JSONDecoder().decode(WorkerRequest.self, from: data) else {
            return failure(nil, "invalidRequest", "A valid request envelope is required.")
        }
        guard !request.id.isEmpty, request.id.utf8.count <= 128,
              !request.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return failure(nil, "invalidRequestID", "Request ID must contain 1 to 128 bytes without control characters.")
        }
        guard request.protocolVersion == WorkerProtocol.version else {
            return failure(request.id, "unsupportedVersion", "Worker protocol version is incompatible.")
        }
        if let cycle = request.refreshCycle, cycle.isEmpty || cycle.utf8.count > 128 || cycle.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return failure(request.id, "invalidRequest", "Refresh cycle must contain 1 to 128 bytes without control characters.")
        }
        guard Self.validActiveProjectIDs(request.activeProjectIDs) else {
            return failure(request.id, "invalidRequest", "Active project IDs must be distinct bounded IDs without control characters.")
        }
        switch request.operation {
        case "hello":
            return WorkerResponse(id: request.id, distribution: distribution, capabilities: WorkerProtocol.capabilities)
        case "remote.snapshot", "remote.verify", "remote.markRead", "remote.markRest", "remote.markAll":
            guard let remote = request.remote else { return failure(request.id, "missingRemote", "Remote card settings are required.") }
            do {
                if request.operation == "remote.markRead" || request.operation == "remote.markRest" {
                    try await remoteService.markRead(remote, rest: request.operation == "remote.markRest", onProgress: onProgress)
                    if Task.isCancelled { return failure(request.id, "cancelled", "Operation was cancelled.") }
                    return WorkerResponse(id: request.id, distribution: distribution)
                }
                if request.operation == "remote.markAll" {
                    try await remoteService.markAllRead(remote, onProgress: onProgress)
                    if Task.isCancelled { return failure(request.id, "cancelled", "Operation was cancelled.") }
                    return WorkerResponse(id: request.id, distribution: distribution)
                }
                if request.operation == "remote.verify" {
                    try await remoteService.verify(remote)
                    if Task.isCancelled { return failure(request.id, "cancelled", "Operation was cancelled.") }
                    return WorkerResponse(id: request.id, distribution: distribution)
                }
                let snapshot = try await remoteService.fetch(remote)
                if Task.isCancelled { return failure(request.id, "cancelled", "Operation was cancelled.") }
                return WorkerResponse(id: request.id, distribution: distribution, remote: snapshot)
            } catch let problem as WorkerRemoteError {
                if Task.isCancelled { return failure(request.id, "cancelled", "Operation was cancelled.") }
                if request.operation == "remote.snapshot", !problem.failures.isEmpty {
                    let diagnostic = WorkerRemoteSnapshot(cardID: remote.cardID, kind: remote.kind, total: 0, blocked: 0, successRate: nil,
                        rows: [], failures: problem.failures, capped: false)
                    return WorkerResponse(id: request.id, distribution: distribution, error: WorkerFailure(code: problem.code, message: problem.message), remote: diagnostic)
                }
                return failure(request.id, problem.code, problem.message)
            } catch {
                return failure(request.id, Task.isCancelled ? "cancelled" : "remoteUnavailable", "Remote refresh failed. Check the account token, permissions or network.")
            }
        case "ddev.list":
            guard let entries = await ddevInventory.list(cycle: nil, runner: runner) else {
                return failure(request.id, "ddevUnavailable", "DDEV could not be queried in this distribution.")
            }
            return WorkerResponse(id: request.id, distribution: distribution, projects: entries.map {
                WorkerDiscoveredProject(name: $0.name, distribution: distribution, path: $0.approot, state: $0.state.rawValue)
            })
        case "project.probe", "project.check", "project.status", "project.logs", "project.preflight", "project.start", "project.stop", "project.restart":
            guard let project = request.project else {
                return failure(request.id, "missingProject", "A project reference is required.")
            }
            guard project.distribution == distribution else {
                return failure(request.id, "wrongDistribution", "Project belongs to another WSL distribution.")
            }
            guard Self.validProjectOptions(project), !project.id.isEmpty, project.id.utf8.count <= 128,
                  !project.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  project.title.map({ !$0.isEmpty && $0.utf8.count <= 512 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) ?? true else {
                return failure(request.id, "invalidProject", "A stable project ID and an absolute Linux path are required.")
            }
            if project.path.isEmpty {
                guard request.operation == "project.status" || request.operation == "project.check" else { return failure(request.id, "missingFolder", "No local project folder is configured.") }
                let summary = LocalStackStatus.unavailable.summary(checkedAddress: "", currentAddress: "")
                return WorkerResponse(id: request.id, distribution: distribution, status: WorkerStatus(projectID: project.id, state: "unavailable",
                    checkSummary: WorkerCheckSummary(summary)))
            }
            if request.operation == "project.preflight" {
                return WorkerResponse(id: request.id, distribution: distribution, error: await startPreflight(project))
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return failure(request.id, "missingFolder", "Project directory is unavailable in this distribution.")
            }
            if request.operation == "project.probe" {
                guard project.kind == .local else { return failure(request.id, "invalidProject", "Detection requires a plain local project.") }
                if Task.isCancelled { return failure(request.id, "cancelled", "Operation was cancelled.") }
                return WorkerResponse(id: request.id, distribution: distribution,
                    suggestion: ProjectProbe.suggestion(for: URL(fileURLWithPath: project.path)).map(WorkerProjectSuggestion.init))
            }
            if request.operation == "project.logs" {
                let result: LogLines
                switch project.kind {
                case .ddev:
                    result = await DDEVEnvironment(runner: runner).logs(for: DDEVProject(id: project.id, name: "", folder: project.path), limit: LogTail.windowLineLimit)
                case .arc:
                    result = await LocalStackService(project: arcProject(project), runner: runner, httpClient: arcHTTPClient).logs(limit: LogTail.windowLineLimit)
                case .local:
                    result = await genericService(project).logs(limit: LogTail.windowLineLimit)
                }
                if Task.isCancelled { return failure(request.id, "cancelled", "Operation was cancelled.") }
                return WorkerResponse(id: request.id, distribution: distribution, logs: WorkerLogs(lines: result.lines, source: result.source, detail: result.detail, filePath: result.fileURL?.path))
            }
            let action = request.operation.replacingOccurrences(of: "project.", with: "")
            if ["start", "stop", "restart"].contains(action) {
                let previousPID = project.kind == .local ? genericService(project).storedPID() : nil
                if project.kind == .local, action == "start" {
                    let current = await projectStatus(project)
                    if current.state == "running" { return WorkerResponse(id: request.id, distribution: distribution, status: current) }
                }
                if Task.isCancelled {
                    await cleanCancelledStart(project, previousPID: previousPID)
                    return failure(request.id, "cancelled", "Operation was cancelled.")
                }
                if action != "stop", let problem = await startPreflight(project) {
                    return WorkerResponse(id: request.id, distribution: distribution, error: problem)
                }
                let result: CommandResult?
                switch project.kind {
                case .ddev:
                    guard FileManager.default.fileExists(atPath: project.path + "/.ddev/config.yaml") else {
                        return failure(request.id, "invalidProject", "DDEV configuration is missing in this directory.")
                    }
                    result = await DDEVEnvironment(runner: ProgressCommandRunner(base: runner, progress: onProgress)).perform(DDEVAction(rawValue: action)!, for: DDEVProject(id: project.id, name: "", folder: project.path))
                case .arc:
                    let stack = LocalStackService(project: arcProject(project), runner: runner, httpClient: arcHTTPClient)
                    if action == "restart" {
                        guard let stopped = await stack.perform(.stop, onOutput: onProgress), stopped.succeeded, !Task.isCancelled else {
                            return failure(request.id, Task.isCancelled ? "cancelled" : "commandFailed", "Fusion did not stop successfully before restart.")
                        }
                        let deadline = Date().addingTimeInterval(30)
                        while (await stack.status()).isRunning {
                            if Date() >= deadline { return failure(request.id, "outcomeNotConfirmed", "Fusion is still serving after Stop. Restart did not start another stack.") }
                            do { try await Task.sleep(for: .seconds(1)) }
                            catch { return failure(request.id, "cancelled", "Operation was cancelled.") }
                        }
                        result = await stack.perform(.start, onOutput: onProgress)
                    } else { result = await stack.perform(LocalStackAction(rawValue: action)!, onOutput: onProgress) }
                case .local:
                    guard !(project.startCommand ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return failure(request.id, "invalidProject", "A generic project requires a start command.")
                    }
                    let service = genericService(project, progress: onProgress)
                    if action == "restart" {
                        if (await service.status()).state != .stopped {
                            guard let stopped = await service.perform(.stop), stopped.succeeded else {
                                return failure(request.id, "commandFailed", "The project could not be stopped before restart.")
                            }
                        }
                        result = await service.perform(.start)
                    } else { result = await service.perform(LocalProjectAction(rawValue: action)!) }
                }
                if Task.isCancelled {
                    await cleanCancelledStart(project, previousPID: previousPID)
                    return failure(request.id, "cancelled", "Operation was cancelled.")
                }
                guard let result, result.succeeded else {
                    return failure(request.id, "commandFailed", "Project command failed. Read project logs for details.")
                }
                // The CLI returning zero is insufficient: Fusion can return before its engine is ready.
                let deadline = Date().addingTimeInterval(action == "stop" ? 30 : 180)
                while true {
                    if Task.isCancelled {
                        await cleanCancelledStart(project, previousPID: previousPID)
                        return failure(request.id, "cancelled", "Operation was cancelled.")
                    }
                    let status = await projectStatus(project)
                    if (action == "stop" && ["stopped", "paused"].contains(status.state)) || (action != "stop" && status.state == "running") {
                        return WorkerResponse(id: request.id, distribution: distribution, status: status)
                    }
                    if project.kind == .local, project.holdsProcess != false, action != "stop", status.state == "stopped" {
                        return failure(request.id, "outcomeNotConfirmed", "The started project process exited before becoming ready. Read its logs.")
                    }
                    if Date() >= deadline { return failure(request.id, "outcomeNotConfirmed", "Command completed, but the expected project state was not confirmed.") }
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch {
                        await cleanCancelledStart(project, previousPID: previousPID)
                        return failure(request.id, "cancelled", "Operation was cancelled.")
                    }
                }
            }
            return WorkerResponse(id: request.id, distribution: distribution, status: await projectStatus(project, refreshCycle: request.refreshCycle))
        default:
            return failure(request.id, "unsupportedOperation", "Operation is not available in this worker.")
        }
    }

    private func cleanCancelledStart(_ project: WorkerProject, previousPID: Int32?) async {
        guard project.kind == .local, project.holdsProcess != false, let current = genericService(project).storedPID(), current != previousPID else { return }
        let managed = WorkerProject(id: project.id, distribution: project.distribution, kind: .local, path: project.path,
                                    startCommand: project.startCommand, stopCommand: "", holdsProcess: true, healthURL: project.healthURL)
        _ = await Task.detached { await genericService(managed).perform(.stop) }.value
    }

    private func arcProject(_ project: WorkerProject) -> ArcProject {
        project.arcModel
    }

    private func projectStatus(_ project: WorkerProject, refreshCycle: String? = nil) async -> WorkerStatus {
            let status: WorkerStatus
            switch project.kind {
            case .ddev:
                let environment = DDEVEnvironment(runner: runner)
                // The host's saved switches filter capabilities; omitting a URL makes enabling it impossible.
                status = Self.ddevStatus(project,environment:environment,entries:await ddevInventory.list(cycle:refreshCycle,runner:runner))
            case .arc:
                let model = arcProject(project)
                let result = await LocalStackService(project: model, runner: runner, httpClient: arcHTTPClient).status()
                let address = "\(model.folder ?? "")|\(model.effectiveLocalURL)|\(model.healthPath)"
                status = WorkerStatus(projectID: project.id, state: result.state.rawValue, branch: result.branch,
                                      siteURL: result.siteURL?.absoluteString, engineVersion: result.engineVersion,
                                      notAnswering: result.healthStatusCode.map { L("project.health.answered", $0) },
                                      repositoryURL: result.repositoryURL?.absoluteString, localEditorURL: model.localPageBuilderURL?.absoluteString,
                                      checkSummary: WorkerCheckSummary(result.summary(checkedAddress: address, currentAddress: address)),
                                      checkedAt: result.checkedAt?.timeIntervalSince1970)
            case .local:
                let result = await genericService(project).status()
                let healthURL = project.healthURL ?? ""
                status = WorkerStatus(projectID: project.id, state: result.state.rawValue, branch: result.branch, siteURL: project.localModel().siteURL?.absoluteString,
                                      framework: project.subtitle.flatMap { $0.isEmpty ? nil : $0 },
                                      notAnswering: result.state == .starting ? L("check.starting.detail") : nil,
                                      repositoryURL: result.repositoryURL?.absoluteString,
                                      checkSummary: WorkerCheckSummary(result.summary(checkedURL: healthURL, currentURL: healthURL)),
                                      checkedAt: result.checkedAt?.timeIntervalSince1970)
            }
            return status
    }
    static func ddevStatus(_ project: WorkerProject,environment: DDEVEnvironment,entries: [DDEVListEntry]?, includeCheckedAt: Bool = false) -> WorkerStatus {
        let model=DDEVProject(id:project.id,name:"",folder:project.path,showsXhgui:true)
        let result=environment.status(for:model,entries:entries)
        return WorkerStatus(projectID:project.id,state:result.state.rawValue,branch:result.branch,siteURL:result.entry?.primaryURL?.absoluteString,framework:result.frameworkLabel,
            syncBroken:result.mutagenWarning == nil ? nil : "mutagen",repositoryURL:result.repositoryURL?.absoluteString,
            toolLinks:model.toolLinks(status:result).map{WorkerLink(label:$0.label,url:$0.url.absoluteString)},versionsLine:result.versionsLine,checkedAt:includeCheckedAt ? result.checkedAt?.timeIntervalSince1970 : nil)
    }

    private func startPreflight(_ project: WorkerProject) async -> WorkerFailure? {
        if project.kind == .local {
            if [project.startCommand, project.stopCommand].compactMap({ $0 }).contains(where: { $0.contains("\u{0}") || $0.utf8.count > 65_536 }) {
                return WorkerFailure(code: "invalidProject", message: "Project command is invalid or exceeds its size limit.")
            }
            let health = (project.healthURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if (!health.isEmpty && !(URL(string: health).map { ["http", "https"].contains($0.scheme ?? "") && $0.host != nil } ?? false))
                || (project.holdsProcess == false && health.isEmpty) {
                return WorkerFailure(code: "invalidProject", message: "A returning start command requires an absolute HTTP health URL.")
            }
        }
        if project.kind == .local && project.requiresDocker != true { return nil }
        let docker = await DockerEnvironment(runner: runner).status()
        guard docker.isReady else { return WorkerFailure(code: "dockerUnavailable", message: "Docker is unavailable in this WSL distribution.") }
        if project.kind == .arc {
            return await ArcStartPreflight(runner: runner).check(folder: URL(fileURLWithPath: project.path),
                requiresLocalCLI: project.startCommand == nil || project.startCommand == "npx --no-install fusion daemon")
        }
        return nil
    }

    private func genericService(_ project: WorkerProject, progress: (@Sendable (String) -> Void)? = nil) -> LocalProjectService {
        // Map IDs to a reversible filename-safe value; the externally persisted card ID never changes.
        let filename = Data(project.id.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
        let model = project.localModel(runtimeID: filename)
        let files = ProjectRuntimeFiles(directory: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share/devdeck/projects"))
        let managed = WSLGenericRunner(base: ProgressCommandRunner(base: runner, progress: progress), project: model, files: files)
        return LocalProjectService(project: model, runner: managed, files: files)
    }

    private static func validProjectOptions(_ project: WorkerProject) -> Bool {
        guard isLinuxPath(project.path) || project.kind == .arc && project.path.isEmpty,
              [project.startCommand, project.stopCommand].compactMap({ $0 }).allSatisfy({ !$0.contains("\u{0}") && $0.utf8.count <= 65_536 }) else { return false }
        guard project.subtitle.map({ $0.utf8.count <= 512 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) ?? true,
              project.openURL.map({ $0.isEmpty || $0.utf8.count <= 2048 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) && URLComponents(string: $0).map({ ["http", "https"].contains($0.scheme ?? "") && $0.host != nil && $0.user == nil && $0.password == nil }) == true }) ?? true else { return false }
        guard let arc = project.arc else { return true }
        guard project.kind == .arc, arc.organization.utf8.count <= 253,
              arc.organization.isEmpty || arc.organization.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                  $0.range(of: "^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$", options: .regularExpression) != nil
              }), arc.site.map({ $0.utf8.count <= 128 && $0.range(of: "^[a-zA-Z0-9_-]*$", options: .regularExpression) != nil }) ?? true,
              arc.localURL.utf8.count <= 2048,
              arc.localURL.isEmpty || URLComponents(string: arc.localURL).map({ ["http", "https"].contains($0.scheme ?? "") && $0.host != nil && $0.user == nil && $0.password == nil }) == true,
              arc.healthPath.utf8.count <= 2048, arc.healthPath.hasPrefix("/"), !arc.healthPath.hasPrefix("//"),
              !arc.healthPath.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else { return false }
        return true
    }

    /// Validate before any registration, path resolution or command dispatch.
    public static func validActiveProjectIDs(_ ids: [String]?) -> Bool {
        guard let ids else { return true }
        guard ids.count <= WorkerProtocol.maximumActiveProjectIDs else { return false }
        var distinct = Set<String>()
        return ids.allSatisfy { id in
            !id.isEmpty && id.utf8.count <= 128
                && !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                && distinct.insert(id).inserted
        }
    }

    public static func isLinuxPath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.hasPrefix("//") && !path.contains("\\")
            && !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && !path.split(separator: "/").contains("..")
    }

    public func failure(_ id: String?, _ code: String, _ message: String) -> WorkerResponse {
        WorkerResponse(id: id, distribution: distribution, error: WorkerFailure(code: code, message: message))
    }
}
