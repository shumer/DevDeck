import DevDeckCore
import Foundation

/// The closest thing GitHub has to a todo list: review requests, mentions, CI failures and
/// state changes, in one endpoint that supports conditional requests.
public struct NotificationsService: Sendable {
    private let client: GitHubClient
    private let settings: GitHubSettings
    private let accountID: String

    /// Cache identity for the conditional request. Per account, because two accounts poll the
    /// same endpoint with different tokens and would otherwise share one ETag.
    var cacheKey: String { "github.notifications.\(accountID)" }

    public init(
        client: GitHubClient,
        settings: GitHubSettings = .default,
        accountID: String = GitHubAccount.defaultID
    ) {
        self.client = client
        self.settings = settings
        self.accountID = accountID
    }

    public func fetch() async throws -> InboxSnapshot {
        let result: RESTResult<[NotificationPayload]> = try await client.get(
            path: "notifications",
            query: [
                // `all=false` is unread only, which is what the card counts. Read items would
                // only pad the list with things already dealt with.
                URLQueryItem(name: "all", value: "false"),
                URLQueryItem(name: "per_page", value: String(settings.maxNotifications)),
            ],
            cacheKey: cacheKey
        )

        return InboxSnapshot(
            items: result.value.map { Self.item(from: $0, accountID: accountID) },
            serverPollInterval: result.pollIntervalSeconds
        )
    }

    static func item(
        from payload: NotificationPayload,
        accountID: String = GitHubAccount.defaultID
    ) -> InboxItem {
        InboxItem(
            id: payload.id,
            reason: NotificationReason(apiValue: payload.reason),
            title: payload.subject.title,
            repository: payload.repository.fullName,
            updatedAt: payload.updatedAt,
            isUnread: payload.unread,
            url: InboxItem.webURL(fromSubject: payload.subject.url),
            accountID: accountID
        )
    }
}

// MARK: - Wire format

public struct NotificationPayload: Decodable, Sendable {
    let id: String
    let unread: Bool
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: Repository

    struct Subject: Decodable, Sendable {
        let title: String
        let url: URL?
        let type: String
    }

    struct Repository: Decodable, Sendable {
        let fullName: String

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, unread, reason, subject, repository
        case updatedAt = "updated_at"
    }
}
