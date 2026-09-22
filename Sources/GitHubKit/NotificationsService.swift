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
            serverPollInterval: result.pollIntervalSeconds,
            // A full page means there may be more behind it: the card says "50+" rather than
            // presenting the size of one page as the size of the box.
            cappedAccounts: result.value.count >= settings.maxNotifications ? [accountID] : []
        )
    }

    /// Every unread thread, page after page, for an action that has to reach past what the card
    /// loaded. Stops at the first short page, and at `maxPages` whatever happens, so a box of
    /// thousands costs a bounded number of requests rather than an hour of them.
    public func unreadThreads(maxPages: Int = 10) async throws -> [InboxItem] {
        var items: [InboxItem] = []
        for page in 1...max(1, maxPages) {
            let result: RESTResult<[NotificationPayload]> = try await client.get(
                path: "notifications",
                query: [
                    URLQueryItem(name: "all", value: "false"),
                    URLQueryItem(name: "per_page", value: String(Self.pageSize)),
                    URLQueryItem(name: "page", value: String(page)),
                ]
            )
            items += result.value.map { Self.item(from: $0, accountID: accountID) }
            if result.value.count < Self.pageSize { break }
        }
        return items
    }

    /// The largest page the endpoint serves.
    static let pageSize = 50

    /// Marks many threads read, a few at a time, and says which ones GitHub refused.
    ///
    /// One by one, three hundred threads took minutes, long enough for the card to be polled in
    /// between and look as if nothing had happened. Six at a time is quick without looking like
    /// a burst to the API. `progress` is told how many are done after each one, from whichever
    /// task finished it.
    public func markRead(
        _ ids: [String],
        concurrency: Int = 6,
        progress: @escaping @Sendable (Int) async -> Void = { _ in }
    ) async -> [String: APIError] {
        var failures: [String: APIError] = [:]
        var done = 0
        await withTaskGroup(of: (String, APIError?).self) { group in
            var queue = ids.makeIterator()
            func next() -> Bool {
                guard let id = queue.next() else { return false }
                group.addTask {
                    do {
                        try await markRead(id)
                        return (id, nil)
                    } catch {
                        return (id, APIError.wrapping(error))
                    }
                }
                return true
            }
            for _ in 0..<max(1, concurrency) {
                if !next() { break }
            }
            for await (id, failure) in group {
                if let failure { failures[id] = failure }
                done += 1
                await progress(done)
                _ = next()
            }
        }
        return failures
    }

    /// Marks everything read up to a moment, in one request.
    ///
    /// The moment is the newest notification the card has shown, not now: anything that arrives
    /// between the card drawing and the click stays unread, rather than being cleared by a
    /// button pressed about something else.
    public func markAllRead(upTo lastReadAt: Date) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let body = try JSONSerialization.data(withJSONObject: [
            "last_read_at": formatter.string(from: lastReadAt),
            "read": true,
        ])
        try await client.send(method: .put, path: "notifications", body: body)
    }

    /// Marks one thread read, which is what the notification's own id addresses.
    ///
    /// The card drops the row itself rather than waiting for the next poll: the endpoint
    /// supports conditional requests and answers 304 for a while after a change, so waiting
    /// would leave a row on screen that is already dealt with.
    public func markRead(_ id: String) async throws {
        try await client.send(method: .patch, path: "notifications/threads/\(id)")
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
