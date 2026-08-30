import DevDeckCore
import Foundation

/// Fetches the merge requests you have open and the ones waiting on your review, from one
/// GitLab instance.
public struct MergeRequestsService: Sendable {
    private let client: GitLabClient
    private let accountID: String
    private let limit: Int

    public init(client: GitLabClient, accountID: String = GitLabAccount.defaultID, limit: Int = 20) {
        self.client = client
        self.accountID = accountID
        self.limit = limit
    }

    public func fetch() async throws -> MergeRequestsSnapshot {
        let payload: Payload = try await client.graphQL(
            query: Self.query,
            variables: Variables(limit: limit)
        )
        return Self.snapshot(from: payload, accountID: accountID)
    }

    struct Variables: Encodable, Sendable {
        let limit: Int
    }

    /// One query for the whole card.
    ///
    /// `currentUser` answers both halves without a search string, which is the part GitHub
    /// cannot do: there, "mine or waiting on me" needs two searches because the qualifiers do
    /// not OR. `reviewRequestedMergeRequests` drops a merge request the moment you review it,
    /// which is exactly when it should leave the card.
    ///
    /// `approvalsLeft` and `conflicts` are asked for by name rather than taken from
    /// `detailedMergeStatus`, whose vocabulary has changed between GitLab versions and would
    /// have to be mapped again on every upgrade.
    static let query = """
    query DevDeckMergeRequests($limit: Int!) {
      currentUser {
        mine: authoredMergeRequests(state: opened, sort: UPDATED_DESC, first: $limit) {
          count
          ...mergeRequests
        }
        reviewing: reviewRequestedMergeRequests(state: opened, sort: UPDATED_DESC, first: $limit) {
          count
          ...mergeRequests
        }
      }
    }

    fragment mergeRequests on MergeRequestConnection {
      nodes {
        id
        iid
        title
        webUrl
        draft
        conflicts
        updatedAt
        approvalsLeft
        project { fullPath }
        headPipeline { status }
        discussions(first: 100) {
          nodes { resolvable resolved }
        }
      }
    }
    """

    static func snapshot(from payload: Payload, accountID: String) -> MergeRequestsSnapshot {
        guard let user = payload.currentUser else {
            return MergeRequestsSnapshot(totalCount: 0, mergeRequests: [])
        }

        let mine = user.mine.nodes.compactMap {
            summary(from: $0, accountID: accountID, isReviewRequest: false)
        }
        // Yours wins a tie. You cannot normally be asked to review your own merge request, but
        // a rule that adds a whole group as reviewers can produce one, and it is yours first.
        var seen = Set(mine.map(\.id))
        let reviewing = user.reviewing.nodes
            .compactMap { summary(from: $0, accountID: accountID, isReviewRequest: true) }
            .filter { seen.insert($0.id).inserted }

        return MergeRequestsSnapshot(
            totalCount: user.mine.count + reviewing.count,
            mergeRequests: mine + reviewing
        )
    }

    /// A node missing anything the row is built from is dropped rather than shown half-drawn.
    static func summary(
        from node: Payload.Node,
        accountID: String,
        isReviewRequest: Bool
    ) -> MergeRequestSummary? {
        guard
            let id = node.id,
            let iid = Int(node.iid ?? ""),
            let title = node.title,
            let url = node.webUrl,
            let updatedAt = node.updatedAt,
            let project = node.project?.fullPath
        else { return nil }

        return MergeRequestSummary(
            id: id,
            iid: iid,
            title: title,
            project: project,
            url: url,
            isDraft: node.draft ?? false,
            hasConflicts: node.conflicts ?? false,
            updatedAt: updatedAt,
            pipeline: PipelineState(apiValue: node.headPipeline?.status),
            approvalsLeft: node.approvalsLeft ?? 0,
            // Only resolvable threads count. GitLab calls every comment stream a discussion,
            // including the ones that are just somebody talking, and those can never be
            // resolved - counting them would leave a row permanently unresolved.
            unresolvedThreads: node.discussions?.nodes
                .filter { $0.resolvable == true && $0.resolved != true }
                .count ?? 0,
            accountID: accountID,
            isReviewRequest: isReviewRequest
        )
    }

    // MARK: Payload

    struct Payload: Decodable, Sendable {
        let currentUser: User?

        struct User: Decodable, Sendable {
            let mine: Connection
            let reviewing: Connection
        }

        struct Connection: Decodable, Sendable {
            let count: Int
            let nodes: [Node]
        }

        struct Node: Decodable, Sendable {
            let id: String?
            /// A string in GitLab's schema, an integer to everybody else.
            let iid: String?
            let title: String?
            let webUrl: URL?
            let draft: Bool?
            let conflicts: Bool?
            let updatedAt: Date?
            let approvalsLeft: Int?
            let project: Project?
            let headPipeline: Pipeline?
            let discussions: Discussions?
        }

        struct Project: Decodable, Sendable {
            let fullPath: String?
        }

        struct Pipeline: Decodable, Sendable {
            let status: String?
        }

        struct Discussions: Decodable, Sendable {
            let nodes: [Discussion]
        }

        struct Discussion: Decodable, Sendable {
            let resolvable: Bool?
            let resolved: Bool?
        }
    }
}
