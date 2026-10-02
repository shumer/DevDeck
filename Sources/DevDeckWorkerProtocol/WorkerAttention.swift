import DevDeckCore
import Foundation

public struct WorkerAttentionAction: Codable, Sendable {
    public var kind: String
    public var url: String? = nil
    public var service: String? = nil
    public var accountID: String? = nil
    public var cardID: String? = nil
    public var path: String? = nil
    public var checkout: WorkerCheckoutTarget? = nil
}

/// Exact captured Inbox source; it carries no credential or arbitrary mutation URL.
public struct WorkerInboxReadTarget: Codable, Sendable, Equatable {
    public let cardID: String
    public let accountID: String
    public let threadID: String
    public let endpoint: String
    public init(cardID: String, accountID: String, threadID: String, endpoint: String) {
        self.cardID = cardID; self.accountID = accountID; self.threadID = threadID; self.endpoint = endpoint
    }
}

public struct WorkerAttentionItem: Codable, Sendable {
    public let id: String
    public var key: String
    public let tier: String
    public let mark: String
    public let title: String
    public let subtitle: String
    public let since: TimeInterval?
    public let action: WorkerAttentionAction
    public let enabled: Bool
    public let dismissible: Bool
    public var inboxRead: WorkerInboxReadTarget? = nil
}

public struct WorkerAlert: Codable, Sendable {
    public let id: String
    public let kind: String
    public let source: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let subject: String
    public let target: WorkerAttentionAction
    public let quiet: Bool
}

public struct WorkerAttentionSnapshot: Codable, Sendable {
    public let scope: String
    public let items: [WorkerAttentionItem]
    public let alerts: [WorkerAlert]
    public var dockerState: String? = nil
    public var containerStartAllowed: Bool? = nil

    /// Source-bound Inbox items have already passed the unchanged shared digest ordering.
    init(scope: String, projectedItems: [WorkerAttentionItem], alerts: [WorkerAlert]) {
        self.scope = scope; self.items = projectedItems; self.alerts = alerts
    }

    public init(scope: String, items: [AttentionItem], alerts: [DeckAlert], reviewThreadIDs: Set<String> = []) {
        self.scope = scope
        self.items = AttentionDigest(items: items).items.map { WorkerAttentionBridge.item($0, reviewThreadIDs: reviewThreadIDs) }
        self.alerts = alerts.map(WorkerAttentionBridge.alert)
    }
}

enum WorkerAttentionBridge {
    static func action(_ value: AttentionAction) -> WorkerAttentionAction {
        switch value {
        case .open(let url, let service, let account): return .init(kind: "open", url: url.absoluteString, service: service.rawValue, accountID: account)
        case .accountSettings(let service, let account): return .init(kind: "accountSettings", service: service.rawValue, accountID: account)
        case .showCard(let card): return .init(kind: "showCard", cardID: card.rawValue)
        case .startDocker: return .init(kind: "startDocker")
        case .openTerminal(let url): return .init(kind: "openTerminal", path: url.path)
        case .installUpdate: return .init(kind: "update")
        case .none: return .init(kind: "none")
        }
    }
    static func item(_ value: AttentionItem, reviewThreadIDs: Set<String> = []) -> WorkerAttentionItem {
        let tier: String
        switch value.tier {
        case .waiting: tier = "waiting"
        case .needsFixing: tier = "needsFixing"
        case .stuck: tier = "stuck"
        case .goodToKnow: tier = "goodToKnow"
        }
        let mark: String
        switch value.mark {
        case .github: mark = "github"
        case .gitlab: mark = "gitlab"
        case .arc: mark = "arc"
        case .ddev: mark = "ddev"
        case .project: mark = "project"
        case .docker: mark = "docker"
        case .token: mark = "token"
        case .network: mark = "network"
        case .rateLimit: mark = "rateLimit"
        case .update: mark = "update"
        case .unpushed: mark = "unpushed"
        case .noRemote: mark = "noRemote"
        }
        let target = action(value.action)
        // The inbox and PR surfaces describe one review, including across configured accounts.
        let key = value.id.hasPrefix("review:") || value.inboxThreadID.map({ reviewThreadIDs.contains($0) }) == true
            ? target.url.map { (target.service ?? "github") + ":review:" + $0 } ?? value.id : value.id
        return WorkerAttentionItem(id: value.id, key: key, tier: tier, mark: mark, title: value.title, subtitle: value.subtitle,
                                   since: value.since?.timeIntervalSince1970, action: target, enabled: value.isEnabled, dismissible: value.isDismissible)
    }
    static func alert(_ value: DeckAlert) -> WorkerAlert {
        let target: WorkerAttentionAction
        switch value.target {
        case .url(let url, let account): target = .init(kind: "open", url: url.absoluteString, service: value.source.rawValue, accountID: account)
        case .card(let card): target = .init(kind: "showCard", cardID: card.rawValue)
        case .accountSettings(let service, let account): target = .init(kind: "accountSettings", service: service, accountID: account)
        case .menu: target = .init(kind: "menu")
        }
        return WorkerAlert(id: value.id, kind: value.kind.rawValue, source: value.source.rawValue, title: value.title,
                           subtitle: value.subtitle, body: value.body, subject: value.subject, target: target, quiet: value.isQuiet)
    }
}

/// State belongs to this worker session. No credential or upstream error body is retained.
public actor WorkerAttentionState {
    private var watch = ProjectWatch()
    private var settler = StateSettler()
    private var projects: [String: WatchedProject] = [:]
    private var statuses: [String: WorkerStatus] = [:]
    private struct FailureScope: Sendable { let service: AttentionService; let failures: [AccountFailure] }
    private var remoteFailures: [String: FailureScope] = [:]
    private var failingSince: [String: Date] = [:]
    private var docker = DockerStatus(state: .unknown)
    private var dockerDownSince: Date?
    private var dockerProbe: Task<DockerStatus, Never>?
    private var dockerCheckedAt: Date?
    private var ddevReferences: [String: WorkerProject] = [:]
    private var ddevEpoch: UInt64 = 0
    private struct PowerOffOverlay: Sendable {
        let token: String
        var references: [String: WorkerProject]
        var watch: ProjectWatch
        var settler: StateSettler
        var statuses: [String: WorkerStatus]
    }
    private var powerOff: PowerOffOverlay?

    public init() {}

    public func observationEpoch(_ project: WorkerProject) -> UInt64? { project.kind == .ddev ? ddevEpoch : nil }

    public func preparePowerOff(token: String, projects supplied: [WorkerProject]) {
        ddevEpoch &+= 1
        var references=ddevReferences
        for project in supplied { references[project.id]=project }
        var overlay=PowerOffOverlay(token:token,references:references,watch:watch,settler:settler,statuses:statuses)
        for id in references.keys { overlay.watch.noteAction(id,isStop:true,at:Date()) }
        powerOff=overlay
    }
    public func powerOffReferences(token: String) -> [WorkerProject] {
        guard let powerOff,powerOff.token==token else{return []}
        return powerOff.references.values.sorted{$0.id<$1.id}
    }
    public func abortPowerOff(token: String, distribution: String, now: Date, activeProjectIDs: [String]?) -> WorkerAttentionSnapshot {
        if powerOff?.token==token {powerOff=nil;ddevEpoch &+= 1}
        return localSnapshot(distribution:distribution,now:now,activeProjectIDs:activeProjectIDs)
    }
    public func snapshot(distribution: String, now: Date, activeProjectIDs: [String]?) -> WorkerAttentionSnapshot {
        localSnapshot(distribution:distribution,now:now,activeProjectIDs:activeProjectIDs)
    }
    public func finishPowerOff(token: String, statuses physical: [String:WorkerStatus], distribution: String, now: Date, activeProjectIDs: [String]?) -> WorkerAttentionSnapshot {
        guard let overlay=powerOff,overlay.token==token else{return localSnapshot(distribution:distribution,now:now,activeProjectIDs:activeProjectIDs)}
        ddevEpoch &+= 1
        for (id,status) in physical {
            statuses[id]=status
            // Never mass-register hidden references and evict unrelated watches.
            guard projects[id]?.mark == .ddev else{continue}
            settler.reset(id);watch.noteAction(id,isStop:true,at:now)
            if ["running","stopped","paused","starting"].contains(status.state) {
                watch.observe(id,running:status.state=="running",notAnswering:status.notAnswering,syncBroken:status.syncBroken,
                    dockerDown:!docker.isReady && docker.state != .unknown,at:now)
                if status.state=="running" {watch.noteAction(id,isStop:true,at:now);watch.noteStopDidNotTakeEffect(id,at:now)}
            }
        }
        statuses=statuses.filter{projects[$0.key] != nil || overlay.references[$0.key] != nil}
        powerOff=nil
        return localSnapshot(distribution:distribution,now:now,activeProjectIDs:activeProjectIDs)
    }

    public func dockerStatus(runner: any CommandRunning, now: Date) async -> DockerStatus {
        if let dockerCheckedAt, now.timeIntervalSince(dockerCheckedAt) < 10, let dockerProbe { return await dockerProbe.value }
        let probe = Task { await DockerEnvironment(runner: runner).status() }
        dockerProbe = probe; dockerCheckedAt = now
        return await probe.value
    }

    public func noteAction(_ project: WorkerProject, action: String, now: Date) {
        register(project)
        settler.reset(project.id)
        watch.noteAction(project.id, isStop: action == "stop" || action == "restart", at: now)
    }

    private func register(_ project: WorkerProject) {
        if projects[project.id] == nil, projects.count >= 128, let first = projects.keys.first {
            projects.removeValue(forKey: first); statuses.removeValue(forKey: first)
            ddevReferences.removeValue(forKey:first)
            watch.keep(only: Set(projects.keys))
        }
        let kind = project.kind == .ddev ? "DDEV" : project.kind == .arc ? "Arc XP" : "Project"
        let mark: AttentionMark = project.kind == .ddev ? .ddev : project.kind == .arc ? .arc : .project("project")
        projects[project.id] = WatchedProject(id: project.id, cardID: CardID(rawValue: project.id),
            title: project.title ?? URL(fileURLWithPath: project.path).lastPathComponent, kind: kind, mark: mark,
            needsDocker: project.kind != .local || project.requiresDocker == true)
        if project.kind == .ddev {ddevReferences[project.id]=project}
        else {ddevReferences.removeValue(forKey:project.id)}
    }

    public func observe(_ project: WorkerProject, status: WorkerStatus?, error: WorkerFailure?, action: String?, docker: DockerStatus, now: Date, activeProjectIDs: [String]? = nil, observationEpoch: UInt64? = nil) -> (WorkerStatus?, WorkerAttentionSnapshot) {
        if project.kind == .ddev, let observationEpoch, observationEpoch != ddevEpoch {
            return (powerOff?.statuses[project.id] ?? statuses[project.id] ?? WorkerStatus(projectID:project.id,state:"unknown"),localSnapshot(distribution:project.distribution,now:now,activeProjectIDs:activeProjectIDs))
        }
        if project.kind != .local || project.requiresDocker == true || docker.state != .unknown {
            if docker.state != self.docker.state { dockerDownSince = docker.isReady ? nil : now }
            self.docker = docker
        }
        if project.kind == .ddev, var overlay=powerOff {
            guard overlay.references[project.id] != nil || overlay.references.count<1152 else{return(WorkerStatus(projectID:project.id,state:"unknown"),localSnapshot(distribution:project.distribution,now:now,activeProjectIDs:activeProjectIDs))}
            overlay.references[project.id]=project
            var settled=status
            if let status,["running","stopped","paused","starting"].contains(status.state) {
                if !overlay.settler.shouldApply(isGood:status.state=="running",wasGood:overlay.statuses[project.id]?.state=="running",for:project.id) {settled=overlay.statuses[project.id]}
                else {overlay.statuses[project.id]=status;overlay.watch.noteAction(project.id,isStop:true,at:now)
                    overlay.watch.observe(project.id,running:status.state=="running",at:now)
                    if status.state=="running" {overlay.watch.noteAction(project.id,isStop:true,at:now)}}
            }
            powerOff=overlay
            return(settled,localSnapshot(distribution:project.distribution,now:now,activeProjectIDs:activeProjectIDs))
        }
        register(project)
        var settled = status
        if let status, ["running", "stopped", "paused", "starting"].contains(status.state) {
            if action == nil && !settler.shouldApply(isGood: status.state == "running", wasGood: statuses[project.id]?.state == "running", for: project.id) {
                settled = statuses[project.id]
            } else {
                statuses[project.id] = status
                watch.observe(project.id, running: status.state == "running" || status.notAnswering != nil,
                    notAnswering: status.notAnswering, syncBroken: status.syncBroken, dockerDown: !docker.isReady && docker.state != .unknown, at: now)
            }
        }
        if let error, let action, error.code != "cancelled" {
            if action == "stop" {
                if statuses[project.id]?.state == "running" || error.code == "outcomeNotConfirmed" { watch.noteStopDidNotTakeEffect(project.id, at: now) }
            } else { watch.noteStartFailed(project.id, line: error.message, at: now) }
        }
        return (settled, localSnapshot(distribution: project.distribution, now: now, activeProjectIDs: activeProjectIDs))
    }

    public func dismiss(_ project: WorkerProject, now: Date, activeProjectIDs: [String]? = nil) -> WorkerAttentionSnapshot {
        watch.dismiss(project.id)
        return localSnapshot(distribution: project.distribution, now: now, activeProjectIDs: activeProjectIDs)
    }

    private func localSnapshot(distribution: String, now: Date, activeProjectIDs: [String]?) -> WorkerAttentionSnapshot {
        // A hidden card may still own a command. Filter the original presentation builders,
        // never its registration, watch episode or settled status.
        let allowed = activeProjectIDs.map(Set.init)
        let values = projects.values.filter { (allowed?.contains($0.id) ?? true) && !(powerOff != nil && $0.mark == .ddev) }.sorted { $0.id < $1.id }
        var snapshot = WorkerAttentionSnapshot(scope: "local:" + distribution,
            items: ProjectAttention.items(projects: values, watch: watch, docker: docker, dockerDownSince: dockerDownSince, now: now),
            alerts: ProjectAttention.alerts(projects: values, watch: watch, docker: docker, dockerDownSince: dockerDownSince,
                source: { $0.mark == .arc ? .arc : $0.mark == .ddev ? .ddev : .project }, now: now))
        snapshot.dockerState = docker.state.rawValue; snapshot.containerStartAllowed = docker.allowsStart
        return snapshot
    }

    public func remote(_ snapshot: WorkerRemoteSnapshot, request: WorkerRemoteRequest, now: Date) -> WorkerAttentionSnapshot {
        let service: AttentionService = request.kind == .mergeRequests ? .gitlab : .github
        var seenAccounts = Set<String>()
        let failures = snapshot.failures.filter { seenAccounts.insert($0.accountID ?? "").inserted }.map { failure in
            let account = request.accounts.first { $0.id == failure.accountID }
            let kind = AccountFailure.Kind(rawValue: failure.kind) ?? .other
            let error: APIError
            switch kind {
            case .rejected: error = .unauthorized
            case .forbidden: error = .forbidden(nil)
            case .rateLimited: error = .rateLimited(resetAt: failure.resetAt.map(Date.init(timeIntervalSince1970:)))
            case .unreachable: error = .transport("")
            case .other: error = .decoding("")
            }
            return AccountFailure(account: account?.label ?? service.name, message: error.displayMessage,
                                  accountID: failure.accountID, kind: kind, resetAt: failure.resetAt.map(Date.init(timeIntervalSince1970:)))
        }
        if remoteFailures[request.cardID] == nil, remoteFailures.count >= 128, let first = remoteFailures.keys.first { remoteFailures.removeValue(forKey: first) }
        remoteFailures[request.cardID] = FailureScope(service: service, failures: failures)
        let active = Set(remoteFailures.values.flatMap { scope in scope.failures.map { scope.service.rawValue + ":" + ($0.accountID ?? $0.account) } })
        failingSince = failingSince.filter { active.contains($0.key) }
        for failure in failures { let key = service.rawValue + ":" + (failure.accountID ?? failure.account); failingSince[key] = failingSince[key] ?? now }
        var since: [String: Date] = [:]
        for failure in failures {
            let key = failure.accountID ?? failure.account
            since[key] = failingSince[service.rawValue + ":" + key] ?? now
        }
        let items = AccountAttention.items(failures: failures, service: service, now: now, failingSince: since)
        let alerts = failures.compactMap { AccountAttention.alert(for: $0, service: service, since: since[$0.accountID ?? $0.account]) }
        let base = snapshot.signals ?? WorkerAttentionSnapshot(scope: request.cardID, items: [AttentionItem](), alerts: [DeckAlert]())
        let accountItems = zip(items, failures).map { item, failure in
            var result = WorkerAttentionBridge.item(item)
            result.key = service.rawValue + ":account:" + (failure.accountID ?? failure.account)
            return result
        }
        return WorkerAttentionSnapshot(scope: base.scope, items: base.items + accountItems, alerts: base.alerts + alerts.map(WorkerAttentionBridge.alert))
    }
}

private extension WorkerAttentionSnapshot {
    init(scope: String, items: [WorkerAttentionItem], alerts: [WorkerAlert]) { self.scope = scope; self.items = items; self.alerts = alerts }
}
