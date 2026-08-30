import DevDeckCore
import Foundation

/// Everything the merge requests card renders, computed once so the view stays dumb.
public struct MergeRequestsSnapshot: Sendable, Equatable, Codable {
    /// Total open merge requests the instance reported, which can exceed
    /// `mergeRequests.count` when the fetch limit truncates the list.
    public let totalCount: Int
    public let mergeRequests: [MergeRequestSummary]
    /// Accounts that failed while this snapshot was assembled.
    public let failures: [AccountFailure]

    public init(
        totalCount: Int,
        mergeRequests: [MergeRequestSummary],
        failures: [AccountFailure] = []
    ) {
        self.totalCount = totalCount
        self.mergeRequests = mergeRequests
        self.failures = failures
    }

    public static let empty = MergeRequestsSnapshot(totalCount: 0, mergeRequests: [])

    /// Combines one snapshot per account into the single list the card draws.
    ///
    /// Deduplicated by id, which is global on a GitLab instance. Two accounts on the *same*
    /// instance with access to the same project would otherwise show every shared merge request
    /// twice; two accounts on different instances never collide.
    public static func merging(
        _ snapshots: [MergeRequestsSnapshot],
        failures: [AccountFailure] = []
    ) -> MergeRequestsSnapshot {
        var seen = Set<String>()
        var merged: [MergeRequestSummary] = []
        var total = 0

        for snapshot in snapshots {
            total += snapshot.totalCount
            for request in snapshot.mergeRequests where seen.insert(request.id).inserted {
                merged.append(request)
            }
        }

        let duplicates = snapshots.reduce(0) { $0 + $1.mergeRequests.count } - merged.count
        return MergeRequestsSnapshot(
            totalCount: max(0, total - duplicates),
            mergeRequests: merged,
            failures: failures + snapshots.flatMap(\.failures)
        )
    }

    public var blockedCount: Int {
        mergeRequests.filter { $0.health == .blocked }.count
    }

    public var readyCount: Int {
        mergeRequests.filter { $0.health == .ready }.count
    }

    public var projectCount: Int {
        Set(mergeRequests.map(\.project)).count
    }

    public var groupCount: Int {
        Set(mergeRequests.map(\.group)).count
    }

    /// How many of the rows are somebody waiting on you rather than you waiting on somebody.
    public var reviewRequestCount: Int {
        mergeRequests.filter(\.isReviewRequest).count
    }

    /// The rows worth interrupting somebody for.
    ///
    /// A review request is somebody waiting on you, which is the whole reason to be told at all.
    /// A blocked one of yours is the other, and it is optional because a red build on a branch
    /// you are actively pushing to is not news.
    public func alerts(includeBlocked: Bool) -> [DeckAlert] {
        mergeRequests.compactMap { request in
            if request.isReviewRequest {
                return DeckAlert(
                    id: "review:\(request.id)",
                    kind: .reviewRequest,
                    title: "Review requested",
                    body: "\(request.shortLabel) \(request.ticket.subject)",
                    url: request.url,
                    accountID: request.accountID
                )
            }
            guard includeBlocked, request.health == .blocked else { return nil }
            return DeckAlert(
                // The state is part of the identity: something announced as blocked, fixed, and
                // broken again is worth saying twice.
                id: "blocked:\(request.id):\(request.statusCode)",
                kind: .blocked,
                title: request.statusLine.prefix(1).uppercased() + request.statusLine.dropFirst(),
                body: "\(request.shortLabel) \(request.ticket.subject)",
                url: request.url,
                accountID: request.accountID
            )
        }
    }

    /// Rows for the card body: worst first, then most recently touched. The same order as the
    /// GitHub card, for the same reason - the merge request worth finding is the stuck one, and
    /// it is rarely the newest.
    public func prioritized(limit: Int? = nil) -> [MergeRequestSummary] {
        func rank(_ request: MergeRequestSummary) -> Int {
            if request.health == .blocked { return 0 }
            if request.isReviewRequest { return 1 }
            return request.health == .attention ? 2 : 3
        }
        let sorted = mergeRequests.sorted { left, right in
            let leftRank = rank(left)
            let rightRank = rank(right)
            if leftRank != rightRank { return leftRank < rightRank }
            return left.updatedAt > right.updatedAt
        }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }
}
