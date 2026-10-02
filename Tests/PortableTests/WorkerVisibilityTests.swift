import DevDeckCore
import DevDeckWorkerProtocol
import Foundation
import TestHarness

private actor VisibilityRunner: CommandRunning {
    private var commands: [String] = []
    func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
             onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        commands.append(command)
        return CommandResult(exitCode: 1, standardOutput: "", standardError: "Offline visibility fixture")
    }
    func recorded() -> [String] { commands }
}

private actor VisibilityResponses {
    private var responses: [WorkerResponse] = []
    func append(_ value: WorkerResponse) { responses.append(value) }
    func values() -> [WorkerResponse] { responses }
}

/// Only synthetic command answers. The continuation models an owned job, never a shell.
private actor VisibilityJobRunner: CommandRunning {
    private let inventory: String
    private var commands: [String] = []
    private var started = false
    private var finished = false
    private var cancelled = false
    private var suspension: CheckedContinuation<CommandResult, Never>?
    init(folder: String) throws {
        inventory = String(decoding: try JSONSerialization.data(withJSONObject: ["raw": [
            ["name": "job", "approot": folder, "status": "running", "type": "php"]
        ]]), as: UTF8.self)
    }
    func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
             onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        commands.append(command)
        cancelled = cancelled || Task.isCancelled
        if command == "ddev start" {
            started = true
            let result: CommandResult
            if finished { result = CommandResult(exitCode: 0, standardOutput: "", standardError: "") }
            else { result = await withCheckedContinuation { suspension = $0 } }
            cancelled = cancelled || Task.isCancelled
            return result
        }
        return CommandResult(exitCode: 0, standardOutput: command == "ddev list -j" ? inventory : "28.0", standardError: "")
    }
    func hasStarted() -> Bool { started }
    func wasCancelled() -> Bool { cancelled }
    func recorded() -> [String] { commands }
    func finish() {
        finished = true
        suspension?.resume(returning: CommandResult(exitCode: 0, standardOutput: "", standardError: ""))
        suspension = nil
    }
}

func runWorkerVisibilityTests(_ run: TestRun) async {
    run.section("Worker visibility context")
    await run.test("an explicitly empty active-project list hides Docker attention without changing physical readiness") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let worker = WorkerService(distribution: "Test", runner: VisibilityRunner(),
            arcHTTPClient: FakeHTTPClient([.failure(APIError.transport("Offline visibility fixture"))]))
        let project = WorkerProject(id: "arc.visibility", distribution: "Test", kind: .arc, path: directory.path,
            title: "Hidden fixture", arc: WorkerArcConfiguration(localURL: "http://localhost:8112"))
        var envelope = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WorkerRequest(id: "hidden", operation: "project.status", project: project))) as! [String: Any]
        envelope["activeProjectIDs"] = [String]()
        let response = await worker.handle(try JSONSerialization.data(withJSONObject: envelope))
        try expectNil(response.error)
        try expectEqual(response.attention?.items.count, 0)
        try expectEqual(response.attention?.alerts.count, 0)
        try expectEqual(response.attention?.dockerState, "notRunning")
        try expectEqual(response.attention?.containerStartAllowed, false)
    }
    await run.test("malformed visibility context rejects a lifecycle request before runner or project registration") {
        let runner = VisibilityRunner()
        let worker = WorkerService(distribution: "Test", runner: runner)
        let malformed = [[""], ["repeat", "repeat"], ["bad\nID"], [String(repeating: "Ж", count: 65)], (0...1024).map { "project.\($0)" }]
        for (index, ids) in malformed.enumerated() {
            let response = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "bad-context-\(index)", operation: "project.start",
                project: WorkerProject(id: "bad-visibility", distribution: "Test", kind: .local, path: "/tmp/visibility-never-created"), activeProjectIDs: ids)))
            try expectEqual(response.error?.code, "invalidRequest")
            try expectEqual(response.id, "bad-context-\(index)")
            try expectNil(response.attention)
        }
        try expectEqual(await runner.recorded(), [])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let other = WorkerProject(id: "valid-other", distribution: "Test", kind: .local, path: directory.path, startCommand: "synthetic no-op")
        let observed = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "after-bad", operation: "project.status", project: other)))
        try expectNil(observed.error)
        try expect(observed.attention?.items.isEmpty == true, "Rejected start registered a failed hidden project.")
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("legacy nil and explicit empty contexts roundtrip separately and advertise bounded support") {
        let decoder = JSONDecoder()
        let legacy = try decoder.decode(WorkerRequest.self, from: Data(#"{"protocolVersion":1,"id":"legacy","operation":"hello"}"#.utf8))
        try expectNil(legacy.activeProjectIDs)
        let empty = try decoder.decode(WorkerRequest.self, from: JSONEncoder().encode(WorkerRequest(id: "empty", operation: "hello", activeProjectIDs: [])))
        try expectEqual(empty.activeProjectIDs, [])
        let nilJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        try expectNil(nilJSON["activeProjectIDs"])
        let runner = VisibilityRunner()
        let worker = WorkerService(distribution: "Test", runner: runner)
        let response = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "bounds", operation: "hello", activeProjectIDs: [String(repeating: "Ж", count: 64)])))
        try expectNil(response.error)
        try expectEqual(response.protocolVersion, 1)
        try expect(response.capabilities?.contains("attention.activeProjects") == true)
        let maximum = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "maximum", operation: "hello", activeProjectIDs: (0..<1024).map { "project.\($0)" })))
        try expectNil(maximum.error)
        try expectEqual(await runner.recorded(), [])
    }
    let start = Date(timeIntervalSince1970: 1000)
    let hidden = WorkerProject(id: "a.hidden", distribution: "Test", kind: .ddev, path: "/tmp/hidden", title: "Hidden project")
    let visible = WorkerProject(id: "z.visible", distribution: "Test", kind: .ddev, path: "/tmp/visible", title: "Visible project")
    let ready = DockerStatus(state: .running)
    let lost = DockerStatus(state: .notRunning)
    func up(_ project: WorkerProject) -> WorkerStatus { WorkerStatus(projectID: project.id, state: "running") }
    func down(_ project: WorkerProject) -> WorkerStatus { WorkerStatus(projectID: project.id, state: "stopped") }
    await run.test("Docker grouping removes hidden names and retargets its alert to the visible project") {
        let state = WorkerAttentionState()
        for project in [hidden, visible] {
            _ = await state.observe(project, status: up(project), error: nil, action: nil, docker: ready, now: start)
        }
        for moment in [1.0, 2.0] {
            for project in [hidden, visible] {
                _ = await state.observe(project, status: down(project), error: nil, action: nil, docker: lost, now: start.addingTimeInterval(moment))
            }
        }
        let filtered = await state.observe(visible, status: down(visible), error: nil, action: nil, docker: lost, now: start.addingTimeInterval(3), activeProjectIDs: [visible.id])
        try expectEqual(filtered.1.items.count, 1)
        try expectEqual(filtered.1.items.first?.id, "docker:quit")
        try expectEqual(filtered.1.items.first?.action.kind, "startDocker")
        try expect(filtered.1.items.first?.subtitle.contains("Visible project") == true)
        try expect(filtered.1.items.first?.subtitle.contains("Hidden project") == false)
        try expectEqual(filtered.1.alerts.first?.target.cardID, visible.id)
        try expect(!String(decoding: JSONEncoder().encode(filtered.1), as: UTF8.self).contains("Hidden project"))
        let all = await state.observe(visible, status: down(visible), error: nil, action: nil, docker: lost, now: start.addingTimeInterval(4))
        try expect(all.1.items.first?.subtitle.contains("Hidden project") == true)
        try expectEqual(all.1.alerts.first?.target.cardID, hidden.id)
        try expectEqual(all.1.alerts.first?.id, filtered.1.alerts.first?.id)
    }
    await run.test("Docker-off requirements use only active projects and exclude a plain non-Docker checkout") {
        let state = WorkerAttentionState()
        for project in [hidden, visible] {
            _ = await state.observe(project, status: down(project), error: nil, action: nil, docker: lost, now: start)
        }
        let one = await state.observe(visible, status: down(visible), error: nil, action: nil, docker: lost, now: start, activeProjectIDs: [visible.id])
        try expectEqual(one.1.items.first?.id, "docker:off")
        try expectEqual(one.1.items.first?.subtitle, L("attention.docker.needs.one", "Visible project"))
        let plain = WorkerProject(id: "plain", distribution: "Test", kind: .local, path: "/tmp/plain", title: "Plain")
        let plainOnly = await state.observe(plain, status: down(plain), error: nil, action: nil, docker: DockerStatus(state: .unknown), now: start, activeProjectIDs: [plain.id])
        try expect(plainOnly.1.items.isEmpty && plainOnly.1.alerts.isEmpty)
        try expectEqual(plainOnly.1.dockerState, "notRunning")
        try expectEqual(plainOnly.1.containerStartAllowed, false)
    }
    await run.test("hidden project problems cannot reappear through sibling polls and reveal keeps the original episode") {
        let state = WorkerAttentionState()
        let fault = WorkerStatus(projectID: visible.id, state: "running", syncBroken: "synthetic sync")
        _ = await state.observe(hidden, status: up(hidden), error: nil, action: nil, docker: ready, now: start)
        _ = await state.observe(visible, status: fault, error: nil, action: nil, docker: ready, now: start)
        _ = await state.observe(hidden, status: down(hidden), error: nil, action: nil, docker: ready, now: start.addingTimeInterval(1))
        let original = await state.observe(hidden, status: down(hidden), error: nil, action: nil, docker: ready, now: start.addingTimeInterval(2))
        let episode = original.1.alerts.first { $0.target.cardID == hidden.id }!
        for moment in [3.0, 4.0, 5.0] {
            let next = await state.observe(visible, status: fault, error: nil, action: nil, docker: ready, now: start.addingTimeInterval(moment), activeProjectIDs: [visible.id])
            try expectEqual(next.1.items.map(\.action.cardID), [visible.id])
            try expect(next.1.alerts.allSatisfy { $0.target.cardID == visible.id })
        }
        let revealed = await state.observe(visible, status: fault, error: nil, action: nil, docker: ready, now: start.addingTimeInterval(6), activeProjectIDs: [hidden.id, visible.id])
        try expectEqual(revealed.1.items.first { $0.action.cardID == hidden.id }?.since, start.addingTimeInterval(2).timeIntervalSince1970)
        try expectEqual(revealed.1.alerts.first { $0.target.cardID == hidden.id }?.id, episode.id)
        try expectEqual(revealed.1.items.count, 2)
    }
    await run.test("hiding changes presentation without resetting project or sibling polling settlement") {
        let state = WorkerAttentionState()
        for project in [hidden, visible] {
            _ = await state.observe(project, status: up(project), error: nil, action: nil, docker: ready, now: start)
        }
        let first = await state.observe(hidden, status: down(hidden), error: nil, action: nil, docker: ready, now: start.addingTimeInterval(1), activeProjectIDs: [visible.id])
        try expectEqual(first.0?.state, "running")
        try expect(first.1.items.isEmpty)
        let visibleFirst = await state.observe(visible, status: down(visible), error: nil, action: nil, docker: ready, now: start.addingTimeInterval(2), activeProjectIDs: [visible.id])
        try expectEqual(visibleFirst.0?.state, "running")
        let confirmed = await state.observe(hidden, status: down(hidden), error: nil, action: nil, docker: ready, now: start.addingTimeInterval(3), activeProjectIDs: [hidden.id])
        try expectEqual(confirmed.0?.state, "stopped")
        try expectEqual(confirmed.1.items.first?.action.cardID, hidden.id)
        let sibling = await state.observe(visible, status: down(visible), error: nil, action: nil, docker: ready, now: start.addingTimeInterval(4), activeProjectIDs: [visible.id])
        try expectEqual(sibling.0?.state, "stopped")
        try expectEqual(sibling.1.items.first?.action.cardID, visible.id)
    }
    await run.test("a hidden failed job retains its status and failure episode without removing sibling faults") {
        let state = WorkerAttentionState()
        let fault = WorkerStatus(projectID: visible.id, state: "running", syncBroken: "synthetic sync")
        _ = await state.observe(visible, status: fault, error: nil, action: nil, docker: ready, now: start)
        await state.noteAction(hidden, action: "start", now: start)
        let failed = await state.observe(hidden, status: down(hidden), error: WorkerFailure(code: "commandFailed", message: "Synthetic job failure"), action: "start",
            docker: ready, now: start.addingTimeInterval(16), activeProjectIDs: [visible.id])
        try expectEqual(failed.0?.projectID, hidden.id)
        try expectEqual(failed.0?.state, "stopped")
        try expectEqual(failed.1.items.map(\.action.cardID), [visible.id])
        let revealed = await state.observe(visible, status: fault, error: nil, action: nil, docker: ready, now: start.addingTimeInterval(17), activeProjectIDs: [hidden.id, visible.id])
        try expectEqual(revealed.1.items.first { $0.action.cardID == hidden.id }?.id, "project:\(hidden.id):start")
        try expectEqual(revealed.1.alerts.first { $0.target.cardID == hidden.id }?.id, "start:\(hidden.id):1016")
        let dismissed = await state.dismiss(hidden, now: start.addingTimeInterval(18), activeProjectIDs: [visible.id])
        try expectEqual(dismissed.items.map(\.action.cardID), [visible.id])
        try expectEqual(dismissed.alerts.map(\.target.cardID), [visible.id])
    }
    await run.test("an executing hidden job finishes through the service while a sibling uses its own visibility context") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(".ddev"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "name: job\ntype: php\n".write(to: directory.appendingPathComponent(".ddev/config.yaml"), atomically: true, encoding: .utf8)
        let runner = try VisibilityJobRunner(folder: directory.path)
        let worker = WorkerService(distribution: "Test", runner: runner)
        let executing = WorkerProject(id: "job.hidden", distribution: "Test", kind: .ddev, path: directory.path, title: "Hidden job")
        let sibling = WorkerProject(id: "job.sibling", distribution: "Test", kind: .local, path: directory.path, startCommand: "synthetic no-op")
        let bytes = try JSONEncoder().encode(WorkerRequest(id: "job", operation: "project.start", project: executing, activeProjectIDs: [sibling.id]))
        let task = Task { await worker.handle(bytes) }
        for _ in 0..<100 {
            if await runner.hasStarted() { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let didStart = await runner.hasStarted()
        let siblingRead = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "sibling", operation: "project.status", project: sibling, activeProjectIDs: [sibling.id])))
        await runner.finish()
        let completed = await task.value
        try expect(didStart, "The hidden job was incorrectly blocked by its attention context.")
        try expectNil(siblingRead.error)
        try expectNil(completed.error)
        try expectEqual(completed.status?.projectID, executing.id)
        try expectEqual(completed.status?.state, "running")
        try expect(completed.attention?.items.isEmpty == true && completed.attention?.alerts.isEmpty == true)
        try expectEqual(await runner.wasCancelled(), false)
        try expectEqual(await runner.recorded().filter { $0 == "ddev start" }.count, 1)
    }
    await run.test("the session rejects invalid context synchronously before resolving or scheduling its project") {
        let runner = VisibilityRunner()
        let worker = WorkerService(distribution: "Test", runner: runner)
        let sink = VisibilityResponses()
        let session = WorkerSession(service: worker) { await sink.append($0) }
        let request = WorkerRequest(id: "session-bad", operation: "project.start",
            project: WorkerProject(id: "session-hidden", distribution: "Test", kind: .ddev, path: "/tmp/visibility-never-created"), activeProjectIDs: ["duplicate", "duplicate"])
        await session.accept(.data(try JSONEncoder().encode(request)))
        let responses = await sink.values()
        await session.close()
        try expectEqual(responses.count, 1)
        try expectEqual(responses.first?.id, request.id)
        try expectEqual(responses.first?.error?.code, "invalidRequest")
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("settings-only checks ignore visibility presentation and never register a hidden card") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = VisibilityRunner()
        let worker = WorkerService(distribution: "Test", runner: runner,
            arcHTTPClient: FakeHTTPClient([.failure(APIError.transport("Offline visibility fixture"))]))
        let checked = WorkerProject(id: "checked-hidden", distribution: "Test", kind: .arc, path: directory.path,
            title: "Should never register", arc: WorkerArcConfiguration(localURL: "http://localhost:8112"))
        let check = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "check", operation: "project.check", project: checked, activeProjectIDs: [])))
        try expectNil(check.error)
        try expectNil(check.attention)
        let plain = WorkerProject(id: "plain-after-check", distribution: "Test", kind: .local, path: directory.path, startCommand: "synthetic no-op")
        let actual = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "actual", operation: "project.status", project: plain)))
        try expectNil(actual.error)
        try expect(actual.attention?.items.isEmpty == true && actual.attention?.alerts.isEmpty == true)
        try expectEqual(await runner.recorded(), [])
    }
}
