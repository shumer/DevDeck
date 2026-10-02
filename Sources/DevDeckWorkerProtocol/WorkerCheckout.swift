import DevDeckCore
import Foundation

/// One authoritative configured checkout. Titles are display data, never shell input.
public struct WorkerCheckoutReference: Codable, Sendable, Equatable {
    public let projectID: String
    public let distribution: String
    public let path: String
    public let title: String
    public init(projectID: String, distribution: String, path: String, title: String) {
        self.projectID = projectID; self.distribution = distribution; self.path = path; self.title = title
    }
}
public struct WorkerCheckoutRequest: Codable, Sendable, Equatable {
    public let cardID: String
    public let passToken: String
    public let reference: WorkerCheckoutReference
    public init(cardID: String = "local.workInFlight", passToken: String, reference: WorkerCheckoutReference) {
        self.cardID = cardID; self.passToken = passToken; self.reference = reference
    }
}
public struct WorkerCheckoutTarget: Codable, Sendable, Equatable {
    public let distribution: String
    public let projectID: String
    public let path: String
    public init(distribution: String, projectID: String, path: String) {
        self.distribution = distribution; self.projectID = projectID; self.path = path
    }
}
public struct WorkerCheckoutSummaryFact: Codable, Sendable, Equatable {
    public let kind: String
    public let count: Int32?
    public init(kind: String, count: Int32? = nil) { self.kind = kind; self.count = count }
}
public struct WorkerCheckoutState: Codable, Sendable, Equatable {
    public let branch: String
    public let dirtyFiles: Int32
    public let ahead: Int32
    public let behind: Int32
    public let hasUpstream: Bool
    public let localCommits: Int32
    public let oldestLocalCommitAt: Double?
    public let inFlight: Bool
    public let urgent: Bool
    public let summaryFacts: [WorkerCheckoutSummaryFact]

    init(_ state: CheckoutState) {
        branch = state.branch; dirtyFiles = Int32(state.dirtyFiles); ahead = Int32(state.ahead); behind = Int32(state.behind)
        hasUpstream = state.hasUpstream; localCommits = Int32(state.localCommits)
        oldestLocalCommitAt = state.oldestLocalCommitAt?.timeIntervalSince1970
        inFlight = state.isInFlight; urgent = state.isUrgent
        var facts: [WorkerCheckoutSummaryFact] = []
        if state.dirtyFiles > 0 { facts.append(.init(kind: "changed", count: dirtyFiles)) }
        if state.ahead > 0 { facts.append(.init(kind: "unpushed", count: ahead)) }
        if !state.hasUpstream { facts.append(.init(kind: "noRemote")) }
        if state.behind > 0 { facts.append(.init(kind: "behind", count: behind)) }
        summaryFacts = Array(facts.prefix(2))
    }
}
public struct WorkerCheckoutFailure: Codable, Sendable, Equatable {
    public let stage: String
    public let code: String
    public init(stage: String, code: String) { self.stage = stage; self.code = code }
}
public struct WorkerCheckoutResult: Codable, Sendable {
    public let cardID: String
    public let passToken: String
    public let projectID: String
    public let path: String
    public let checkedAt: Double
    public let state: WorkerCheckoutState?
    public let failure: WorkerCheckoutFailure?
    public let signals: [WorkerAttentionItem]
    public init(request: WorkerCheckoutRequest, checkedAt: Double, state: WorkerCheckoutState?, failure: WorkerCheckoutFailure?, signals: [WorkerAttentionItem]) {
        cardID = request.cardID; passToken = request.passToken; projectID = request.reference.projectID; path = request.reference.path
        self.checkedAt = checkedAt; self.state = state; self.failure = failure; self.signals = signals
    }
}

/// Fixed child environment: no process-global environment or repository configuration writes.
public struct OfflineCheckoutRunner: CommandRunning {
    // The empty transport allowlist is independent of version-specific lazy-fetch support
    // and overrides a repository's explicitly allowed promisor transport for these reads.
    public static let prefix = "env GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 GIT_ALLOW_PROTOCOL= "
    private let base: any CommandRunning
    public init(base: any CommandRunning) { self.base = base }
    public func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
                    onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        guard command == WorkInFlight.command || command == WorkInFlight.localCommitsCommand,
              timeout == 20, !isInteractive, onOutput == nil else { throw CommandError.launchFailed("Unsupported checkout read.") }
        return try await base.run(Self.prefix + command, in: directory, timeout: timeout, isInteractive: false, onOutput: nil)
    }
}

/// This scanner has no ProjectWatch, settling, runtime, Docker, provider or inventory ownership.
public struct WorkerCheckoutScanner: Sendable {
    private let runner: OfflineCheckoutRunner
    private let dates: any DateProvider
    public init(runner: any CommandRunning, dates: any DateProvider = SystemDateProvider()) {
        self.runner = OfflineCheckoutRunner(base: runner); self.dates = dates
    }
    public func read(_ request: WorkerCheckoutRequest) async -> WorkerCheckoutResult {
        func result(_ state: CheckoutState? = nil, _ failure: WorkerCheckoutFailure? = nil) -> WorkerCheckoutResult {
            let now = dates.now
            let timestamp = now.timeIntervalSince1970
            // Production wall time is bounded; a broken injected clock cannot export invalid JSON.
            let checkedAt = Self.validTime(timestamp) ? timestamp : Date().timeIntervalSince1970
            let signals = state.map { Self.signals(state: $0, request: request, now: Date(timeIntervalSince1970: checkedAt)) } ?? []
            return WorkerCheckoutResult(request: request, checkedAt: checkedAt, state: state.map(WorkerCheckoutState.init), failure: failure, signals: signals)
        }
        if Task.isCancelled { return result(nil, .init(stage: "status", code: "cancelled")) }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: request.reference.path, isDirectory: &directory), directory.boolValue else {
            return result(nil, .init(stage: "status", code: "missingFolder"))
        }
        let folder = URL(fileURLWithPath: request.reference.path)
        let status: CommandResult
        do { status = try await runner.run(WorkInFlight.command, in: folder, timeout: 20, isInteractive: false, onOutput: nil) }
        catch { return result(nil, .init(stage: "status", code: Self.failureCode(error))) }
        if Task.isCancelled { return result(nil, .init(stage: "status", code: "cancelled")) }
        guard status.exitCode == 0 else { return result(nil, .init(stage: "status", code: status.exitCode == 127 ? "gitUnavailable" : "statusFailed")) }
        guard status.standardOutput.utf8.count < WorkerProtocol.maximumFrameBytes else { return result(nil, .init(stage: "status", code: "outputTooLarge")) }
        guard Self.validStatusOutput(status.standardOutput),
              var state = WorkInFlight.parse(status.standardOutput, id: request.reference.projectID, title: request.reference.title),
              Self.validState(state) else { return result(nil, .init(stage: "status", code: "invalidState")) }
        if state.isUrgent {
            let log: CommandResult
            do { log = try await runner.run(WorkInFlight.localCommitsCommand, in: folder, timeout: 20, isInteractive: false, onOutput: nil) }
            catch { return result(state, .init(stage: "localCommits", code: Self.failureCode(error))) }
            if Task.isCancelled { return result(state, .init(stage: "localCommits", code: "cancelled")) }
            guard log.exitCode == 0 else { return result(state, .init(stage: "localCommits", code: log.exitCode == 127 ? "gitUnavailable" : "localCommitsFailed")) }
            guard log.standardOutput.utf8.count < WorkerProtocol.maximumFrameBytes else { return result(state, .init(stage: "localCommits", code: "outputTooLarge")) }
            guard log.standardOutput.split(separator: "\n").allSatisfy({
                Double($0.trimmingCharacters(in: .whitespaces)).map(Self.validTime) == true
            }) else { return result(state, .init(stage: "localCommits", code: "invalidState")) }
            let commits = WorkInFlight.parseLocalCommits(log.standardOutput)
            state.localCommits = commits.count; state.oldestLocalCommitAt = commits.oldest
            guard Self.validState(state) else { return result(nil, .init(stage: "status", code: "invalidState")) }
        }
        return result(state)
    }

    public static func signalIdentity(distribution: String, projectID: String, hasUpstream: Bool) -> String {
        "checkout:\(distribution.utf8.count):\(distribution):\(projectID.utf8.count):\(projectID):\(hasUpstream ? "unpushed" : "noremote")"
    }
    private static func signals(state: CheckoutState, request: WorkerCheckoutRequest, now: Date) -> [WorkerAttentionItem] {
        CheckoutAttention.items(checkouts: [state], folders: [state.id: URL(fileURLWithPath: request.reference.path)], now: now).map { original in
            let value = WorkerAttentionBridge.item(original)
            let identity = signalIdentity(distribution: request.reference.distribution, projectID: request.reference.projectID, hasUpstream: state.hasUpstream)
            var action = value.action
            action.checkout = .init(distribution: request.reference.distribution, projectID: request.reference.projectID, path: request.reference.path)
            return WorkerAttentionItem(id: identity, key: identity, tier: value.tier, mark: value.mark, title: value.title,
                subtitle: value.subtitle, since: value.since, action: action, enabled: value.enabled, dismissible: value.dismissible)
        }
    }
    private static func validTime(_ value: Double) -> Bool { value.isFinite && (0...253_402_300_799).contains(value) }
    private static func bounded(_ value: String, _ limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= limit
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    private static func validState(_ state: CheckoutState) -> Bool {
        bounded(state.branch, 512) && [state.dirtyFiles, state.ahead, state.behind, state.localCommits].allSatisfy { (0...Int(Int32.max)).contains($0) }
            && (state.localCommits > 0 ? state.oldestLocalCommitAt.map { validTime($0.timeIntervalSince1970) } == true : state.oldestLocalCommitAt == nil)
    }
    /// Shared parsing is deliberately permissive. Reject malformed required metadata before its
    /// integer conversions, then let the unchanged parser derive all checkout facts.
    private static func validStatusOutput(_ output: String) -> Bool {
        let lines = output.split(separator: "\n")
        let heads = lines.filter { $0.hasPrefix("# branch.head ") }
        guard heads.count == 1, bounded(String(heads[0].dropFirst("# branch.head ".count)), 512) else { return false }
        let upstreams = lines.filter { $0.hasPrefix("# branch.upstream ") }
        guard upstreams.count <= 1, upstreams.allSatisfy({ !$0.dropFirst("# branch.upstream ".count).isEmpty }) else { return false }
        let counts = lines.filter { $0.hasPrefix("# branch.ab ") }
        guard counts.count <= 1, counts.isEmpty || !upstreams.isEmpty else { return false }
        for line in counts {
            let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
            guard parts.count == 2, parts[0].hasPrefix("+"), parts[1].hasPrefix("-"),
                  parts.allSatisfy({ !$0.dropFirst().isEmpty && $0.dropFirst().utf8.allSatisfy { (48...57).contains($0) }
                      && Int32($0.dropFirst()).map { $0 >= 0 } == true }) else { return false }
        }
        return lines.allSatisfy { line in
            ["# branch.head ", "# branch.upstream ", "# branch.ab ", "# branch.oid ", "1 ", "2 ", "u ", "? ", "! "].contains { line.hasPrefix($0) }
        }
    }
    private static func failureCode(_ error: any Error) -> String {
        if error is CancellationError || Task.isCancelled { return "cancelled" }
        if case CommandError.timedOut = error { return "timedOut" }
        return "runnerUnavailable"
    }
}

extension WorkerService {
    /// Pure admission; must precede Session path resolution and every Service state boundary.
    public static func validateCheckout(_ request: WorkerRequest, distribution: String) -> WorkerFailure? {
        func invalid() -> WorkerFailure { .init(code: "invalidRequest", message: "Checkout reads require one bounded typed reference for this distribution.") }
        guard request.operation == "checkouts.snapshot" else { return request.checkout == nil ? nil : invalid() }
        func valid(_ value: String, _ limit: Int) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= limit
                && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }
        guard let checkout = request.checkout, checkout.cardID == "local.workInFlight", valid(checkout.passToken, 128),
              request.project == nil, request.remote == nil, request.powerOff == nil, request.refreshCycle == nil,
              request.targetRequestID == nil, request.activeProjectIDs == nil else { return invalid() }
        let reference = checkout.reference
        guard valid(reference.projectID, 128), reference.distribution == distribution, valid(reference.distribution, 128),
              valid(reference.title, 512), isLinuxPath(reference.path), reference.path.utf8.count <= 4096 else { return invalid() }
        return nil
    }
}
