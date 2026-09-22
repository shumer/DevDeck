import DevDeckCore
import Foundation

/// Everything the inbox card renders.
public struct InboxSnapshot: Sendable, Equatable, Codable {
    public let items: [InboxItem]
    /// What the server asked for through `X-Poll-Interval`, if anything.
    public let serverPollInterval: TimeInterval?
    public let failures: [AccountFailure]
    /// Accounts whose box did not fit in the page the card asks for. Their count is a floor, not
    /// a total, and an action on "everything" has to page through the rest.
    public let cappedAccounts: Set<String>

    public init(
        items: [InboxItem],
        serverPollInterval: TimeInterval? = nil,
        failures: [AccountFailure] = [],
        cappedAccounts: Set<String> = []
    ) {
        self.items = items
        self.serverPollInterval = serverPollInterval
        self.failures = failures
        self.cappedAccounts = cappedAccounts
    }

    /// Whether the unread count is only as far as the card looked.
    public var isCapped: Bool { !cappedAccounts.isEmpty }

    /// The unread threads not addressed to you: comments, CI, state changes, subscriptions,
    /// your own pull requests. What "mark the rest as read" clears.
    public var unreadNotForYou: [InboxItem] {
        items.filter { $0.isUnread && !$0.reason.isForYou }
    }

    /// The newest notification per account, which is how far "mark all as read" may reach.
    public var newestByAccount: [String: Date] {
        items.reduce(into: [:]) { result, item in
            result[item.accountID] = max(result[item.accountID] ?? item.updatedAt, item.updatedAt)
        }
    }

    /// The same box with some threads gone, for the card to redraw before the server answers.
    public func removing(_ ids: Set<String>) -> InboxSnapshot {
        InboxSnapshot(
            items: items.filter { !ids.contains($0.id) },
            serverPollInterval: serverPollInterval,
            failures: failures,
            cappedAccounts: cappedAccounts
        )
    }

    public static let empty = InboxSnapshot(items: [], serverPollInterval: nil)

    /// Combines one snapshot per account.
    ///
    /// The poll interval is the largest any server asked for: honouring the shortest would
    /// throttle the account that asked for the longest.
    public static func merging(
        _ snapshots: [InboxSnapshot],
        failures: [AccountFailure] = []
    ) -> InboxSnapshot {
        InboxSnapshot(
            items: snapshots.flatMap(\.items),
            serverPollInterval: snapshots.compactMap(\.serverPollInterval).max(),
            failures: failures + snapshots.flatMap(\.failures),
            cappedAccounts: snapshots.reduce(into: []) { $0.formUnion($1.cappedAccounts) }
        )
    }

    public var unreadCount: Int {
        items.filter(\.isUnread).count
    }

    /// Notifications that are waiting on the user personally, as opposed to things they are
    /// merely subscribed to.
    public var actionableCount: Int {
        items.filter { $0.isUnread && $0.reason.isForYou }.count
    }

    public var repositoryCount: Int {
        Set(items.map(\.repository)).count
    }

    /// Rows for the card: unread first, then by how much the reason demands attention, then
    /// newest first.
    public func prioritized(limit: Int? = nil) -> [InboxItem] {
        let sorted = items.sorted { left, right in
            if left.isUnread != right.isUnread { return left.isUnread }
            if left.reason.priority != right.reason.priority {
                return left.reason.priority < right.reason.priority
            }
            return left.updatedAt > right.updatedAt
        }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }
}
