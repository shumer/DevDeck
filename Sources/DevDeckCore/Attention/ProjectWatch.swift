import Foundation

/// What happened to the projects on this Mac that their cards stop saying a poll later.
///
/// A card shows the state now. "Stopped" does not say whether you stopped it or it fell over at
/// lunch, and a failed start's reason used to be wiped by the next poll. This remembers the few
/// things worth telling somebody who was not looking, from the observations the deck already
/// makes, and decides nothing on a single poll: the controller only reports what `StateSettler`
/// let through.
public struct ProjectWatch: Sendable, Equatable {
    /// How long a project may be up without answering before it is worth saying. A dev server
    /// compiling or a stack pulling images is silent for a while and fine.
    public static let notAnsweringAfter: TimeInterval = 120
    /// A start that failed faster than this was watched as it failed, so there is no banner.
    public static let startFailedBannerAfter: TimeInterval = 15

    public enum Problem: Sendable, Equatable {
        /// Was running, is not, and nobody pressed Stop. `withDocker` when Docker went first.
        case stoppedOnItsOwn(wasRunningAt: Date, at: Date, withDocker: Bool)
        case startFailed(line: String, at: Date, tookLong: Bool)
        /// Its process or containers are up and the health check does not answer, or answers an
        /// error.
        case notAnswering(detail: String, since: Date)
        case stopDidNotTakeEffect(at: Date)
        case syncBroken(detail: String, since: Date)
    }

    struct Record: Sendable, Equatable {
        /// Nil until the first settled observation, so a launch never reports a project that was
        /// already stopped as having stopped.
        var isRunning: Bool?
        var lastRunningAt: Date?
        var stopRequested = false
        var stopped: (at: Date, wasRunningAt: Date, withDocker: Bool)?
        var startFailure: (line: String, at: Date, tookLong: Bool)?
        var notAnswering: (detail: String, since: Date)?
        var stopFailedAt: Date?
        var syncBroken: (detail: String, since: Date)?
        var dismissed = false
        var actionStartedAt: Date?

        static func == (left: Record, right: Record) -> Bool {
            left.isRunning == right.isRunning
                && left.lastRunningAt == right.lastRunningAt
                && left.stopRequested == right.stopRequested
                && left.stopped?.at == right.stopped?.at
                && left.startFailure?.line == right.startFailure?.line
                && left.startFailure?.at == right.startFailure?.at
                && left.notAnswering?.detail == right.notAnswering?.detail
                && left.notAnswering?.since == right.notAnswering?.since
                && left.stopFailedAt == right.stopFailedAt
                && left.syncBroken?.detail == right.syncBroken?.detail
                && left.dismissed == right.dismissed
                && left.actionStartedAt == right.actionStartedAt
        }
    }

    private var records: [String: Record] = [:]

    public init() {}

    /// A button on the card was pressed. Whatever it leads to is the person's own doing, so the
    /// old problems go and the dismissal with them.
    public mutating func noteAction(_ id: String, isStop: Bool, at date: Date) {
        var record = records[id] ?? Record()
        record.stopRequested = isStop
        record.stopped = nil
        record.startFailure = nil
        record.stopFailedAt = nil
        record.notAnswering = nil
        record.dismissed = false
        record.actionStartedAt = date
        records[id] = record
    }

    /// The start command failed or the project never came up.
    public mutating func noteStartFailed(_ id: String, line: String, at date: Date) {
        var record = records[id] ?? Record()
        let tookLong = record.actionStartedAt.map { date.timeIntervalSince($0) >= Self.startFailedBannerAfter } ?? false
        record.startFailure = (line, date, tookLong)
        record.isRunning = false
        record.dismissed = false
        records[id] = record
    }

    /// Stop returned and the project still answers.
    public mutating func noteStopDidNotTakeEffect(_ id: String, at date: Date) {
        var record = records[id] ?? Record()
        record.stopFailedAt = date
        record.isRunning = true
        record.lastRunningAt = date
        record.dismissed = false
        records[id] = record
    }

    /// A settled observation: from a poll `StateSettler` let through, or from the end of a
    /// command.
    ///
    /// - Parameters:
    ///   - notAnswering: what the card says when the project's process is up and its health
    ///     check is silent or answering an error; nil when it is not in that state.
    ///   - syncBroken: the file sync's own complaint, nil when it is fine.
    ///   - dockerDown: Docker is not running, so a project that stops now went down with it.
    public mutating func observe(
        _ id: String,
        running: Bool,
        notAnswering: String? = nil,
        syncBroken: String? = nil,
        dockerDown: Bool = false,
        at date: Date
    ) {
        var record = records[id] ?? Record()

        if running {
            record.isRunning = true
            record.lastRunningAt = date
            record.stopped = nil
            record.startFailure = nil
            // A stop that did not take is still the person's stop: when it finally lands, the
            // project did not stop on its own.
            if record.stopFailedAt == nil { record.stopRequested = false }
        } else {
            if record.isRunning == true, !record.stopRequested {
                record.stopped = (date, record.lastRunningAt ?? date, dockerDown)
                record.dismissed = false
            }
            record.stopFailedAt = nil
            record.isRunning = false
        }

        if let notAnswering {
            record.notAnswering = (notAnswering, record.notAnswering?.since ?? date)
        } else {
            record.notAnswering = nil
        }

        if let syncBroken, running {
            record.syncBroken = (syncBroken, record.syncBroken?.since ?? date)
        } else {
            record.syncBroken = nil
        }
        records[id] = record
    }

    /// ⌥ on the menu row. Lasts until something new happens to the project.
    public mutating func dismiss(_ id: String) {
        records[id]?.dismissed = true
    }

    /// Forgets projects that are no longer on the deck.
    public mutating func keep(only ids: Set<String>) {
        records = records.filter { ids.contains($0.key) }
    }

    public func problems(for id: String, now: Date) -> [Problem] {
        guard let record = records[id] else { return [] }
        var problems: [Problem] = []
        // What is dismissed is what was reported; a live fault like a broken sync or a silent
        // health check is still true and stays.
        if !record.dismissed {
            if let stopped = record.stopped {
                problems.append(.stoppedOnItsOwn(wasRunningAt: stopped.wasRunningAt, at: stopped.at, withDocker: stopped.withDocker))
            }
            if let failure = record.startFailure {
                problems.append(.startFailed(line: failure.line, at: failure.at, tookLong: failure.tookLong))
            }
            if let stopFailedAt = record.stopFailedAt {
                problems.append(.stopDidNotTakeEffect(at: stopFailedAt))
            }
        }
        if let silent = record.notAnswering, now.timeIntervalSince(silent.since) >= Self.notAnsweringAfter {
            problems.append(.notAnswering(detail: silent.detail, since: silent.since))
        }
        if let sync = record.syncBroken {
            problems.append(.syncBroken(detail: sync.detail, since: sync.since))
        }
        return problems
    }
}

/// A project on the deck, as the attention rows need to name it.
public struct WatchedProject: Sendable, Equatable {
    public let id: String
    public let cardID: CardID
    public let title: String
    /// `Arc XP`, `DDEV`, `bun · next + nest`.
    public let kind: String
    public let mark: AttentionMark
    public let needsDocker: Bool

    public init(id: String, cardID: CardID, title: String, kind: String, mark: AttentionMark, needsDocker: Bool) {
        self.id = id
        self.cardID = cardID
        self.title = title
        self.kind = kind
        self.mark = mark
        self.needsDocker = needsDocker
    }
}

/// Rows and banners for the projects on this Mac and the Docker they sit on.
public enum ProjectAttention {
    public static func items(
        projects: [WatchedProject],
        watch: ProjectWatch,
        docker: DockerStatus,
        dockerDownSince: Date?,
        now: Date
    ) -> [AttentionItem] {
        var items: [AttentionItem] = []
        let dockerIsDown = docker.state == .notRunning || docker.state == .notInstalled
        var wentDownWithDocker: [WatchedProject] = []

        for project in projects {
            for problem in watch.problems(for: project.id, now: now) {
                switch problem {
                case .stoppedOnItsOwn(let wasRunningAt, let at, let withDocker):
                    // One cause, one row: while Docker is down the projects that fell with it are
                    // named under "Start Docker" rather than each saying it stopped.
                    if withDocker, dockerIsDown {
                        wentDownWithDocker.append(project)
                        continue
                    }
                    items.append(AttentionItem(
                        id: "project:\(project.id):stopped",
                        tier: .needsFixing,
                        mark: project.mark,
                        title: "\(project.title) stopped on its own",
                        subtitle: withDocker
                            ? "\(project.kind) · stopped when Docker quit"
                            : "\(project.kind) · was running at \(AttentionDigest.clock(wasRunningAt)) · nobody pressed Stop",
                        since: at,
                        action: .showCard(project.cardID),
                        isDismissible: true
                    ))
                case .startFailed(let line, let at, _):
                    items.append(AttentionItem(
                        id: "project:\(project.id):start",
                        tier: .needsFixing,
                        mark: project.mark,
                        title: "\(project.title) didn't start",
                        subtitle: line,
                        since: at,
                        action: .showCard(project.cardID),
                        isDismissible: true
                    ))
                case .notAnswering(let detail, let since):
                    items.append(AttentionItem(
                        id: "project:\(project.id):silent",
                        tier: .needsFixing,
                        mark: project.mark,
                        title: "\(project.title) is up but not answering",
                        subtitle: detail,
                        since: since,
                        action: .showCard(project.cardID)
                    ))
                case .stopDidNotTakeEffect(let at):
                    items.append(AttentionItem(
                        id: "project:\(project.id):stop",
                        tier: .needsFixing,
                        mark: project.mark,
                        title: "\(project.title) is still running",
                        subtitle: "Stop didn't take effect, it still answers",
                        since: at,
                        action: .showCard(project.cardID),
                        isDismissible: true
                    ))
                case .syncBroken(let detail, let since):
                    items.append(AttentionItem(
                        id: "project:\(project.id):sync",
                        tier: .needsFixing,
                        mark: project.mark,
                        title: "File sync broken: \(project.title)",
                        subtitle: "\(detail) · saved files may not reach the site",
                        since: since,
                        action: .showCard(project.cardID)
                    ))
                }
            }
        }

        guard dockerIsDown else { return items }
        let canStart = docker.state == .notRunning
        if !wentDownWithDocker.isEmpty {
            items.append(AttentionItem(
                id: "docker:quit",
                tier: .needsFixing,
                mark: .docker,
                title: canStart ? "Start Docker" : "Docker is gone",
                subtitle: "Docker quit · \(AttentionWords.list(wentDownWithDocker.map(\.title))) went down",
                since: dockerDownSince,
                action: canStart ? .startDocker : .none
            ))
        } else {
            let needing = projects.filter(\.needsDocker).map(\.title)
            if !needing.isEmpty {
                items.append(AttentionItem(
                    id: "docker:off",
                    tier: .goodToKnow,
                    mark: .docker,
                    title: canStart ? "Docker is not running" : "Docker is not installed",
                    subtitle: "\(AttentionWords.list(needing)) \(needing.count == 1 ? "needs" : "need") it",
                    since: dockerDownSince,
                    action: canStart ? .startDocker : .none,
                    isEnabled: canStart
                ))
            }
        }
        return items
    }

    /// The banners worth raising for the same problems. Kept to what happened while you were
    /// not looking: a stop that did not take and a start that failed in front of you are already
    /// on the card you are looking at.
    public static func alerts(
        projects: [WatchedProject],
        watch: ProjectWatch,
        docker: DockerStatus,
        dockerDownSince: Date?,
        source: (WatchedProject) -> DeckAlert.Source,
        now: Date
    ) -> [DeckAlert] {
        var alerts: [DeckAlert] = []
        let dockerIsDown = docker.state == .notRunning || docker.state == .notInstalled
        var wentDownWithDocker: [WatchedProject] = []

        for project in projects {
            for problem in watch.problems(for: project.id, now: now) {
                switch problem {
                case .stoppedOnItsOwn(let wasRunningAt, let at, let withDocker):
                    if withDocker, dockerIsDown {
                        wentDownWithDocker.append(project)
                        continue
                    }
                    alerts.append(DeckAlert(
                        id: "down:\(project.id):\(Int(at.timeIntervalSince1970))",
                        kind: .wentDown,
                        source: source(project),
                        title: "\(project.title) stopped on its own",
                        subtitle: project.kind,
                        body: "It was running at \(AttentionDigest.clock(wasRunningAt)) and nobody pressed Stop. Click to see the log.",
                        subject: project.title,
                        target: .card(project.cardID),
                        isQuiet: true
                    ))
                case .startFailed(let line, let at, let tookLong):
                    guard tookLong else { continue }
                    alerts.append(DeckAlert(
                        id: "start:\(project.id):\(Int(at.timeIntervalSince1970))",
                        kind: .startFailed,
                        source: source(project),
                        title: "\(project.title) didn't start",
                        subtitle: project.kind,
                        body: "\(line). Click to see the log.",
                        subject: project.title,
                        target: .card(project.cardID),
                        isQuiet: true
                    ))
                case .notAnswering(let detail, let since):
                    alerts.append(DeckAlert(
                        id: "silent:\(project.id):\(Int(since.timeIntervalSince1970))",
                        kind: .wentDown,
                        source: source(project),
                        title: "\(project.title) stopped answering",
                        subtitle: project.kind,
                        body: "\(detail). Click to see the log.",
                        subject: project.title,
                        target: .card(project.cardID),
                        isQuiet: true
                    ))
                case .syncBroken(_, let since):
                    alerts.append(DeckAlert(
                        id: "sync:\(project.id):\(Int(since.timeIntervalSince1970))",
                        kind: .wentDown,
                        source: source(project),
                        title: "File sync broke on \(project.title)",
                        subtitle: project.kind,
                        body: "Saved files may not reach the site. Click for the card.",
                        subject: project.title,
                        target: .card(project.cardID),
                        isQuiet: true
                    ))
                case .stopDidNotTakeEffect:
                    continue
                }
            }
        }

        if dockerIsDown, !wentDownWithDocker.isEmpty, let first = wentDownWithDocker.first {
            let names = AttentionWords.list(wentDownWithDocker.map(\.title))
            alerts.append(DeckAlert(
                id: "docker:quit:\(Int((dockerDownSince ?? now).timeIntervalSince1970))",
                kind: .wentDown,
                source: .docker,
                title: "Docker stopped",
                subtitle: names,
                body: "\(names) went down with it. Click to see \(first.title).",
                subject: "Docker",
                target: .card(first.cardID),
                isQuiet: true
            ))
        }
        return alerts
    }
}
