import DevDeckCore
import Foundation

/// Fetches the pull requests the signed-in user has open, across every organisation the
/// token can see.
public struct PullRequestsService: Sendable {
    private let client: GitHubClient
    private let settings: GitHubSettings
    private let accountID: String

    public init(
        client: GitHubClient,
        settings: GitHubSettings = .default,
        accountID: String = GitHubAccount.defaultID
    ) {
        self.client = client
        self.settings = settings
        self.accountID = accountID
    }

    public func fetch() async throws -> PullRequestsSnapshot {
        let payload: SearchPayload = try await client.graphQL(
            query: Self.query,
            variables: Variables(
                searchQuery: Self.searchQuery(settings: settings),
                limit: settings.maxPullRequests
            )
        )
        return Self.snapshot(from: payload, accountID: accountID)
    }

    /// The search string sent to GitHub.
    ///
    /// `archived:false` keeps read-only repositories out; `sort:updated` makes the truncated
    /// slice the most recently touched ones rather than an arbitrary page.
    public static func searchQuery(settings: GitHubSettings) -> String {
        var parts = ["is:open", "is:pr", "author:@me", "archived:false", "sort:updated"]
        if !settings.includeDrafts { parts.append("draft:false") }
        parts.append(contentsOf: settings.organizations.map { "org:\($0)" })
        return parts.joined(separator: " ")
    }

    struct Variables: Encodable, Sendable {
        let searchQuery: String
        let limit: Int

        enum CodingKeys: String, CodingKey {
            case searchQuery = "q"
            case limit
        }
    }

    /// One query for the whole card. `reviewThreads` is capped at 100 — a PR with more open
    /// conversations than that is already the most blocked thing on the card.
    static let query = """
    query DevDeckPullRequests($q: String!, $limit: Int!) {
      search(query: $q, type: ISSUE, first: $limit) {
        issueCount
        nodes {
          ... on PullRequest {
            id
            number
            title
            url
            isDraft
            updatedAt
            repository {
              nameWithOwner
              owner { login }
            }
            reviewDecision
            reviewThreads(first: 100) {
              nodes { isResolved }
            }
            commits(last: 1) {
              nodes {
                commit {
                  statusCheckRollup { state }
                }
              }
            }
          }
        }
      }
    }
    """

    static func snapshot(
        from payload: SearchPayload,
        accountID: String = GitHubAccount.defaultID
    ) -> PullRequestsSnapshot {
        let summaries = payload.search.nodes.compactMap { Self.summary(from: $0, accountID: accountID) }
        return PullRequestsSnapshot(totalCount: payload.search.issueCount, pullRequests: summaries)
    }

    /// Search returns `Issue` nodes too; those decode with every field nil and are dropped.
    static func summary(
        from node: SearchPayload.Node,
        accountID: String = GitHubAccount.defaultID
    ) -> PullRequestSummary? {
        guard
            let id = node.id,
            let number = node.number,
            let title = node.title,
            let url = node.url,
            let updatedAt = node.updatedAt,
            let repository = node.repository
        else { return nil }

        let unresolved = (node.reviewThreads?.nodes ?? []).filter { !$0.isResolved }.count
        let rollup = node.commits?.nodes.first?.commit.statusCheckRollup?.state

        return PullRequestSummary(
            id: id,
            number: number,
            title: title,
            repository: repository.nameWithOwner,
            organization: repository.owner.login,
            url: url,
            isDraft: node.isDraft ?? false,
            updatedAt: updatedAt,
            reviewDecision: ReviewDecision(apiValue: node.reviewDecision),
            checks: CheckState(apiValue: rollup),
            unresolvedThreads: unresolved,
            accountID: accountID
        )
    }
}

// MARK: - Wire format

struct SearchPayload: Decodable, Sendable {
    let search: Search

    struct Search: Decodable, Sendable {
        let issueCount: Int
        let nodes: [Node]
    }

    struct Node: Decodable, Sendable {
        let id: String?
        let number: Int?
        let title: String?
        let url: URL?
        let isDraft: Bool?
        let updatedAt: Date?
        let repository: Repository?
        let reviewDecision: String?
        let reviewThreads: ReviewThreads?
        let commits: Commits?
    }

    struct Repository: Decodable, Sendable {
        let nameWithOwner: String
        let owner: Owner

        struct Owner: Decodable, Sendable {
            let login: String
        }
    }

    struct ReviewThreads: Decodable, Sendable {
        let nodes: [Thread]

        struct Thread: Decodable, Sendable {
            let isResolved: Bool
        }
    }

    struct Commits: Decodable, Sendable {
        let nodes: [CommitNode]

        struct CommitNode: Decodable, Sendable {
            let commit: Commit
        }

        struct Commit: Decodable, Sendable {
            let statusCheckRollup: Rollup?
        }

        struct Rollup: Decodable, Sendable {
            let state: String
        }
    }
}
