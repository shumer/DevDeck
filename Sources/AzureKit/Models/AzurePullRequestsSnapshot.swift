import DevDeckCore
import Foundation

/// Everything the Azure DevOps card renders, computed once so the view stays dumb.
public struct AzurePullRequestsSnapshot: Sendable, Equatable, Codable {
    /// Open pull requests the organization reported, which can exceed `pullRequests.count`
    /// when the fetch limit truncates the list.
    public let totalCount: Int
    public let pullRequests: [AzurePullRequestSummary]
    /// Accounts that failed while this snapshot was assembled.
    public let failures: [AccountFailure]

    public init(
        totalCount: Int,
        pullRequests: [AzurePullRequestSummary],
        failures: [AccountFailure] = []
    ) {
        self.totalCount = totalCount
        self.pullRequests = pullRequests
        self.failures = failures
    }

    public static let empty = AzurePullRequestsSnapshot(totalCount: 0, pullRequests: [])

    /// Combines one snapshot per account into the single list the card draws.
    ///
    /// Deduplicated by id, which carries the repository, so two accounts on the same
    /// organization with access to the same repository show a shared pull request once.
    public static func merging(
        _ snapshots: [AzurePullRequestsSnapshot],
        failures: [AccountFailure] = []
    ) -> AzurePullRequestsSnapshot {
        var seen = Set<String>()
        var merged: [AzurePullRequestSummary] = []
        var total = 0

        for snapshot in snapshots {
            total += snapshot.totalCount
            for request in snapshot.pullRequests where seen.insert(request.id).inserted {
                merged.append(request)
            }
        }

        let duplicates = snapshots.reduce(0) { $0 + $1.pullRequests.count } - merged.count
        return AzurePullRequestsSnapshot(
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
        Set(pullRequests.map { "\($0.project)/\($0.repository)" }).count
    }

    public var projectCount: Int {
        Set(pullRequests.map(\.project)).count
    }

    /// How many of the rows are somebody waiting on you rather than you waiting on somebody.
    public var reviewRequestCount: Int {
        pullRequests.filter(\.isReviewRequest).count
    }

    /// Rows for the card body: worst first, then newest. The same order as the GitHub card,
    /// for the same reason: the pull request worth finding is the stuck one.
    public func prioritized(limit: Int? = nil) -> [AzurePullRequestSummary] {
        func rank(_ request: AzurePullRequestSummary) -> Int {
            if request.health == .blocked { return 0 }
            if request.isReviewRequest { return 1 }
            return request.health == .attention ? 2 : 3
        }
        let sorted = pullRequests.sorted { left, right in
            let leftRank = rank(left)
            let rightRank = rank(right)
            if leftRank != rightRank { return leftRank < rightRank }
            return left.createdAt > right.createdAt
        }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }
}
