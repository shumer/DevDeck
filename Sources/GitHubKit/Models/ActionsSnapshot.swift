import DevDeckCore
import Foundation

/// Everything the Actions card renders, over one time window across several repositories.
public struct ActionsSnapshot: Sendable, Equatable, Codable {
    public let runs: [WorkflowRun]
    public let windowDays: Int
    /// Repositories that were asked for, including ones that returned nothing.
    public let repositories: [String]
    public let failures: [AccountFailure]

    public init(
        runs: [WorkflowRun],
        windowDays: Int,
        repositories: [String],
        failures: [AccountFailure] = []
    ) {
        self.runs = runs
        self.windowDays = windowDays
        self.repositories = repositories
        self.failures = failures
    }

    public static let empty = ActionsSnapshot(runs: [], windowDays: 7, repositories: [])

    /// Combines one snapshot per account, newest run first.
    public static func merging(
        _ snapshots: [ActionsSnapshot],
        failures: [AccountFailure] = []
    ) -> ActionsSnapshot {
        ActionsSnapshot(
            runs: snapshots.flatMap(\.runs).sorted { $0.startedAt > $1.startedAt },
            windowDays: snapshots.first?.windowDays ?? 7,
            repositories: snapshots.flatMap(\.repositories),
            failures: failures + snapshots.flatMap(\.failures)
        )
    }

    /// Share of decisive runs that passed, 0…1. Nil when nothing decisive ran in the window -
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

    /// Failures newest first - the rows worth putting on the card.
    public func recentFailures(limit: Int? = nil) -> [WorkflowRun] {
        let failures = runs
            .filter { $0.conclusion == .failure }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard let limit else { return failures }
        return Array(failures.prefix(limit))
    }

    /// A workflow whose latest finished run on the main branch failed, with how many in a row.
    public struct Failing: Sendable, Equatable {
        /// The newest failed run, which is the one to open.
        public let latest: WorkflowRun
        /// The first failure of the current streak, which is when it started.
        public let firstFailure: WorkflowRun
        public let streak: Int
    }

    /// Workflows still red on their repository's main branch.
    ///
    /// Only the latest decisive run of each workflow counts, so a failure that the next run fixed
    /// is not reported, and a red run on a pull request branch is left to the pull request.
    public var failingOnMainBranch: [Failing] {
        let decisive = runs.filter { $0.isOnDefaultBranch && $0.status == .completed && $0.conclusion.countsTowardSuccessRate }
        let groups = Dictionary(grouping: decisive) { "\($0.accountID)|\($0.repository)|\($0.name)|\($0.branch)" }
        return groups.values.compactMap { group -> Failing? in
            let newestFirst = group.sorted { $0.startedAt > $1.startedAt }
            guard let latest = newestFirst.first, latest.conclusion == .failure else { return nil }
            let streak = newestFirst.prefix { $0.conclusion == .failure }
            return Failing(latest: latest, firstFailure: streak.last ?? latest, streak: streak.count)
        }
        .sorted { $0.latest.startedAt > $1.latest.startedAt }
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
