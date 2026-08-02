import DevDeckCore
import Foundation

/// The closest thing GitHub has to a todo list: review requests, mentions, CI failures and
/// state changes, in one endpoint that supports conditional requests.
public struct NotificationsService: Sendable {
    private let client: GitHubClient
    private let settings: GitHubSettings

    /// Cache identity for the conditional request. One endpoint, one key.
    static let cacheKey = "github.notifications"

    public init(client: GitHubClient, settings: GitHubSettings = .default) {
        self.client = client
        self.settings = settings
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
            cacheKey: Self.cacheKey
        )

        return InboxSnapshot(
            items: result.value.map(Self.item(from:)),
            serverPollInterval: result.pollIntervalSeconds
        )
    }

    static func item(from payload: NotificationPayload) -> InboxItem {
        InboxItem(
            id: payload.id,
            reason: NotificationReason(apiValue: payload.reason),
            title: payload.subject.title,
            repository: payload.repository.fullName,
            updatedAt: payload.updatedAt,
            isUnread: payload.unread,
            url: InboxItem.webURL(fromSubject: payload.subject.url)
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
