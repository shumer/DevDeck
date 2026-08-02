import Foundation

/// Everything the inbox card renders.
public struct InboxSnapshot: Sendable, Equatable, Codable {
    public let items: [InboxItem]
    /// What the server asked for through `X-Poll-Interval`, if anything.
    public let serverPollInterval: TimeInterval?

    public init(items: [InboxItem], serverPollInterval: TimeInterval? = nil) {
        self.items = items
        self.serverPollInterval = serverPollInterval
    }

    public static let empty = InboxSnapshot(items: [], serverPollInterval: nil)

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
