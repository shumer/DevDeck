import DevDeckCore
import Foundation

/// Fetches the pull requests you have open and the ones waiting on your vote, from one
/// Azure DevOps organization.
public struct AzurePullRequestsService: Sendable {
    private let client: AzureClient
    private let account: AzureAccount
    private let limit: Int

    public init(client: AzureClient, account: AzureAccount, limit: Int = 20) {
        self.client = client
        self.account = account
        self.limit = limit
    }

    /// Three requests for the whole card.
    ///
    /// The list endpoint filters by a person's id rather than by "me", so who the token belongs
    /// to is asked first. Then one list of what you opened and one of what you were asked to
    /// review, both across every project in the organization: the pull request list exists at
    /// the organization root as well as under a project, and the root is the one that does not
    /// need a project list to start from.
    public func fetch() async throws -> AzurePullRequestsSnapshot {
        let connection: ConnectionData = try await client.get(path: "_apis/connectionData", apiVersion: nil)
        guard let me = connection.authenticatedUser?.id, !me.isEmpty else {
            throw APIError.decoding("Azure DevOps did not say who the token belongs to")
        }
        let mine: Page = try await client.get(path: "_apis/git/pullrequests", query: Self.query(me, by: "creatorId"))
        let reviewing: Page = try await client.get(path: "_apis/git/pullrequests", query: Self.query(me, by: "reviewerId"))
        return Self.snapshot(mine: mine, reviewing: reviewing, me: me, account: account)
    }

    private static func query(_ me: String, by criterion: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "searchCriteria.status", value: "active"),
            URLQueryItem(name: "searchCriteria.\(criterion)", value: me),
            URLQueryItem(name: "$top", value: "100"),
        ]
    }

    static func snapshot(mine: Page, reviewing: Page, me: String, account: AzureAccount) -> AzurePullRequestsSnapshot {
        let own = mine.value.compactMap { summary(from: $0, me: me, account: account, isReviewRequest: false) }
        var seen = Set(own.map(\.id))
        // A review request is a vote still owed: once you have voted, approved or not, the row
        // leaves the card the way a reviewed pull request leaves the GitHub one. Your own pull
        // requests are yours first, even when a policy lists you as a reviewer of them.
        let asked = reviewing.value
            .filter { node in
                node.createdBy?.id != me
                    && node.reviewers?.contains { $0.id == me && ($0.vote ?? 0) == 0 && $0.hasDeclined != true } == true
            }
            .compactMap { summary(from: $0, me: me, account: account, isReviewRequest: true) }
            .filter { seen.insert($0.id).inserted }
        return AzurePullRequestsSnapshot(totalCount: own.count + asked.count, pullRequests: own + asked)
    }

    /// A node missing anything the row is built from is dropped rather than shown half-drawn.
    static func summary(from node: Node, me: String, account: AzureAccount, isReviewRequest: Bool) -> AzurePullRequestSummary? {
        guard
            let number = node.pullRequestId,
            let title = node.title,
            let createdAt = node.creationDate,
            let repository = node.repository?.name,
            let repositoryID = node.repository?.id,
            let project = node.repository?.project?.name
        else { return nil }

        // Only people vote; a group listed as a reviewer is expanded into its members' votes by
        // the service itself, and counting the group as well would count every vote twice.
        let people = (node.reviewers ?? []).filter { $0.isContainer != true }
        return AzurePullRequestSummary(
            id: "\(repositoryID)/\(number)",
            number: number,
            title: title,
            project: project,
            repository: repository,
            url: webURL(organization: account.organization, project: project, repository: repository, number: number),
            isDraft: node.isDraft ?? false,
            merge: AzureMergeState(apiValue: node.mergeStatus),
            createdAt: createdAt,
            approvals: people.filter { ($0.vote ?? 0) > 0 }.count,
            hasChangesRequested: people.contains { ($0.vote ?? 0) < 0 },
            requiredVotesMissing: people.filter { $0.isRequired == true && ($0.vote ?? 0) == 0 }.count,
            accountID: account.id,
            isReviewRequest: isReviewRequest,
            author: node.createdBy?.displayName
        )
    }

    /// `https://dev.azure.com/{organization}/{project}/_git/{repository}/pullrequest/{number}`.
    /// Built here because the list endpoint only knows the API address of a pull request.
    public static func webURL(organization: String, project: String, repository: String, number: Int) -> URL {
        AzureAccount.host
            .appendingPathComponent(organization)
            .appendingPathComponent(project)
            .appendingPathComponent("_git")
            .appendingPathComponent(repository)
            .appendingPathComponent("pullrequest")
            .appendingPathComponent(String(number))
    }

    // MARK: Payload

    struct ConnectionData: Decodable, Sendable {
        let authenticatedUser: Identity?

        struct Identity: Decodable, Sendable {
            let id: String?
            let providerDisplayName: String?
        }
    }

    struct Page: Decodable, Sendable {
        let value: [Node]
    }

    struct Node: Decodable, Sendable {
        let pullRequestId: Int?
        let title: String?
        let creationDate: Date?
        let isDraft: Bool?
        /// `succeeded`, `conflicts`, `queued`, `failure`, `rejectedByPolicy`, `notSet`.
        let mergeStatus: String?
        let createdBy: Person?
        let repository: Repository?
        let reviewers: [Reviewer]?
    }

    struct Person: Decodable, Sendable {
        let id: String?
        let displayName: String?
    }

    struct Repository: Decodable, Sendable {
        let id: String?
        let name: String?
        let project: Project?
    }

    struct Project: Decodable, Sendable {
        let name: String?
    }

    struct Reviewer: Decodable, Sendable {
        let id: String?
        /// 10 approved, 5 approved with suggestions, 0 no vote, -5 waiting for author, -10 rejected.
        let vote: Int?
        let isRequired: Bool?
        let hasDeclined: Bool?
        /// A group rather than a person.
        let isContainer: Bool?
    }
}
