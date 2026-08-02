import Foundation

/// Everything the "my pull requests" card renders, computed once so the view stays dumb.
public struct PullRequestsSnapshot: Sendable, Equatable, Codable {
    /// Total open pull requests reported by the search, which can exceed `pullRequests.count`
    /// when the fetch limit truncates the list.
    public let totalCount: Int
    public let pullRequests: [PullRequestSummary]
    /// Accounts that failed while this snapshot was assembled.
    public let failures: [AccountFailure]

    public init(
        totalCount: Int,
        pullRequests: [PullRequestSummary],
        failures: [AccountFailure] = []
    ) {
        self.totalCount = totalCount
        self.pullRequests = pullRequests
        self.failures = failures
    }

    public static let empty = PullRequestsSnapshot(totalCount: 0, pullRequests: [])

    /// Combines one snapshot per account into the single list the card draws.
    ///
    /// Deduplicated by pull request id: two accounts with access to the same repository would
    /// otherwise show every shared pull request twice.
    public static func merging(
        _ snapshots: [PullRequestsSnapshot],
        failures: [AccountFailure] = []
    ) -> PullRequestsSnapshot {
        var seen = Set<String>()
        var merged: [PullRequestSummary] = []
        var total = 0

        for snapshot in snapshots {
            total += snapshot.totalCount
            for pullRequest in snapshot.pullRequests where seen.insert(pullRequest.id).inserted {
                merged.append(pullRequest)
            }
        }

        // The per-account totals double-count anything deduplicated above, so trim the total
        // by exactly what was dropped rather than reporting a number the list cannot back up.
        let duplicates = snapshots.reduce(0) { $0 + $1.pullRequests.count } - merged.count
        return PullRequestsSnapshot(
            totalCount: max(0, total - duplicates),
            pullRequests: merged,
            failures: failures + snapshots.flatMap(\.failures)
        )
    }

    public var blockedCount: Int {
        pullRequests.filter { $0.health == .blocked }.count
    }

    public var readyCount: Int {
        pullRequests.filter { $0.health == .ready }.count
    }

    public var repositoryCount: Int {
        Set(pullRequests.map(\.repository)).count
    }

    public var organizationCount: Int {
        Set(pullRequests.map(\.organization)).count
    }

    /// Rows for the card body: worst first, then most recently touched.
    ///
    /// Sorting by health rather than by date is deliberate — the reason to look at the card
    /// is to find the PR that is stuck, and that one is rarely the newest.
    public func prioritized(limit: Int? = nil) -> [PullRequestSummary] {
        let order: [PullRequestHealth: Int] = [.blocked: 0, .attention: 1, .ready: 2]
        let sorted = pullRequests.sorted { left, right in
            let leftRank = order[left.health] ?? 3
            let rightRank = order[right.health] ?? 3
            if leftRank != rightRank { return leftRank < rightRank }
            return left.updatedAt > right.updatedAt
        }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }
}
