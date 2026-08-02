import Foundation

/// Everything the "my pull requests" card renders, computed once so the view stays dumb.
public struct PullRequestsSnapshot: Sendable, Equatable, Codable {
    /// Total open pull requests reported by the search, which can exceed `pullRequests.count`
    /// when the fetch limit truncates the list.
    public let totalCount: Int
    public let pullRequests: [PullRequestSummary]

    public init(totalCount: Int, pullRequests: [PullRequestSummary]) {
        self.totalCount = totalCount
        self.pullRequests = pullRequests
    }

    public static let empty = PullRequestsSnapshot(totalCount: 0, pullRequests: [])

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
