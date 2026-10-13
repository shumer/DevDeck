import Foundation

/// How long each project has been up, as the local loop saw it, kept across launches.
///
/// One session per stretch of running: opened when a project is first seen up, closed when it
/// is seen down. While it is open, every observation moves `lastSeen`, so a session cut short
/// by the app quitting ends where the app last looked rather than running on for a night.
/// Two weeks are kept; the questions asked of it are today and the last seven days.
public struct ProjectRunLog: Sendable, Equatable, Codable {
    public struct Session: Sendable, Equatable, Codable {
        public var start: Date
        public var end: Date?
        public var lastSeen: Date

        public init(start: Date, end: Date? = nil, lastSeen: Date) {
            self.start = start
            self.end = end
            self.lastSeen = lastSeen
        }
    }

    /// Sessions by project id, oldest first.
    public private(set) var sessions: [String: [Session]]
    public static let keeps: TimeInterval = 14 * 86_400

    public init(sessions: [String: [Session]] = [:]) {
        self.sessions = sessions
    }

    /// A settled observation. Returns whether anything other than `lastSeen` changed, which
    /// is when the log is worth writing out at once.
    @discardableResult
    public mutating func observe(_ id: String, running: Bool, at date: Date) -> Bool {
        var list = sessions[id] ?? []
        if running {
            if let index = list.indices.last, list[index].end == nil {
                list[index].lastSeen = max(list[index].lastSeen, date)
                sessions[id] = list
                return false
            }
            list.append(Session(start: date, lastSeen: date))
        } else {
            guard let index = list.indices.last, list[index].end == nil else { return false }
            // Never before the last time it was seen up: a clock that went backwards is not a
            // session that ended before it ran.
            list[index].end = max(date, list[index].lastSeen)
        }
        sessions[id] = list
        return true
    }

    /// At launch: a session left open by the last run ended when that run last looked. A
    /// project still up is seen again within seconds and opens a new one.
    public mutating func closeOpenSessions() {
        for (id, list) in sessions {
            var closed = list
            for index in closed.indices where closed[index].end == nil {
                closed[index].end = closed[index].lastSeen
            }
            sessions[id] = closed
        }
    }

    /// Drops what is older than `keeps`, and projects with nothing left.
    public mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.keeps)
        sessions = sessions.compactMapValues { list in
            let kept = list.filter { ($0.end ?? now) >= cutoff }
            return kept.isEmpty ? nil : kept
        }
    }

    /// Seconds the project was up between two moments. An open session runs to `now`.
    public func total(for id: String, from: Date, to now: Date) -> TimeInterval {
        (sessions[id] ?? []).reduce(0) { sum, session in
            let end = session.end ?? now
            let overlap = min(end, now).timeIntervalSince(max(session.start, from))
            return sum + max(0, overlap)
        }
    }
}

/// One project's time, as the menu and an agent are told it.
public struct ProjectRunTotal: Sendable, Equatable, Codable {
    public let id: String
    public let cardID: CardID
    public let title: String
    public let today: TimeInterval
    public let week: TimeInterval

    public init(id: String, cardID: CardID, title: String, today: TimeInterval, week: TimeInterval) {
        self.id = id
        self.cardID = cardID
        self.title = title
        self.today = today
        self.week = week
    }

    /// Today and the last seven days, for every project named, in the order given.
    public static func totals(of projects: [WatchedProject], in log: ProjectRunLog, now: Date, calendar: Calendar = .current) -> [ProjectRunTotal] {
        let startOfDay = calendar.startOfDay(for: now)
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        return projects.map { project in
            ProjectRunTotal(
                id: project.id, cardID: project.cardID, title: project.title,
                today: log.total(for: project.id, from: startOfDay, to: now),
                week: log.total(for: project.id, from: weekAgo, to: now)
            )
        }
    }
}

public extension AttentionWords {
    /// `3h 20m`, `45m`. Under a minute is `0m`: a project that ran for seconds ran for no time
    /// anyone bills.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 { return L("attention.duration.hoursMinutes", minutes / 60, minutes % 60) }
        return L("attention.duration.minutes", minutes)
    }
}

public extension ProjectAttention {
    /// One row for the day: how long projects ran, and which. Nothing when nothing ran.
    static func timeItems(_ totals: [ProjectRunTotal]) -> [AttentionItem] {
        let ran = totals.filter { $0.today >= 60 }.sorted { $0.today > $1.today }
        guard !ran.isEmpty else { return [] }
        let sum = ran.reduce(0) { $0 + $1.today }
        return [AttentionItem(
            id: "time:today",
            tier: .goodToKnow,
            mark: .project("project"),
            title: L("attention.time.today.title", AttentionWords.duration(sum)),
            subtitle: AttentionWords.list(ran.map { L("attention.time.item", $0.title, AttentionWords.duration($0.today)) }, limit: 3),
            action: .none,
            isEnabled: false
        )]
    }
}
