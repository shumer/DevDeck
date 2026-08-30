import DevDeckCore
import Foundation

/// Everything the inbox card renders.
public struct InboxSnapshot: Sendable, Equatable, Codable {
    public let items: [InboxItem]
    /// What the server asked for through `X-Poll-Interval`, if anything.
    public let serverPollInterval: TimeInterval?
    public let failures: [AccountFailure]

    public init(
        items: [InboxItem],
        serverPollInterval: TimeInterval? = nil,
        failures: [AccountFailure] = []
    ) {
        self.items = items
        self.serverPollInterval = serverPollInterval
        self.failures = failures
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
            failures: failures + snapshots.flatMap(\.failures)
        )
    }

    public var unreadCount: Int {
        items.filter(\.isUnread).count
    }

    /// Notifications that are waiting on the user personally, as opposed to things they are
    /// merely subscribed to.
    public var actionableCount: Int {
        items.filter { $0.isUnread && $0.reason.priority <= 3 }.count
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
