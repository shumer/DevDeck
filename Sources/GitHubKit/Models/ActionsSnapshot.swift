import Foundation

/// Everything the Actions card renders, over one time window across several repositories.
public struct ActionsSnapshot: Sendable, Equatable, Codable {
    public let runs: [WorkflowRun]
    public let windowDays: Int
    /// Repositories that were asked for, including ones that returned nothing.
    public let repositories: [String]

    public init(runs: [WorkflowRun], windowDays: Int, repositories: [String]) {
        self.runs = runs
        self.windowDays = windowDays
        self.repositories = repositories
    }

    public static let empty = ActionsSnapshot(runs: [], windowDays: 7, repositories: [])

    /// Share of decisive runs that passed, 0…1. Nil when nothing decisive ran in the window —
    /// which is different from 0% and must not be drawn as a red zero.
    public var successRate: Double? {
        let decisive = runs.filter { $0.conclusion.countsTowardSuccessRate }
        guard !decisive.isEmpty else { return nil }
        let passed = decisive.filter { $0.conclusion == .success }.count
        return Double(passed) / Double(decisive.count)
    }

    public var runningCount: Int {
        runs.filter { $0.status.isActive }.count
    }

    public var failedCount: Int {
        runs.filter { $0.conclusion == .failure }.count
    }

    public var averageDurationSeconds: TimeInterval? {
        let durations = runs.compactMap(\.durationSeconds)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    /// Failures newest first — the rows worth putting on the card.
    public func recentFailures(limit: Int? = nil) -> [WorkflowRun] {
        let failures = runs
            .filter { $0.conclusion == .failure }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard let limit else { return failures }
        return Array(failures.prefix(limit))
    }

    /// Runs in flight, newest first.
    public func active(limit: Int? = nil) -> [WorkflowRun] {
        let active = runs
            .filter { $0.status.isActive }
            .sorted { $0.startedAt > $1.startedAt }
        guard let limit else { return active }
        return Array(active.prefix(limit))
    }
}
