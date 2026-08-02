import Foundation

/// What a card knows right now: the last good value, when it arrived, and whether the
/// most recent refresh failed.
///
/// The last good value is kept across failures on purpose — a panel showing yesterday's
/// number with a visible "stale" marker is more useful than one that blanks itself the
/// moment the network hiccups.
public struct CardState<Value: Sendable & Equatable>: Sendable, Equatable {
    public var value: Value?
    public var updatedAt: Date?
    public var isRefreshing: Bool
    public var failure: APIError?

    public init(
        value: Value? = nil,
        updatedAt: Date? = nil,
        isRefreshing: Bool = false,
        failure: APIError? = nil
    ) {
        self.value = value
        self.updatedAt = updatedAt
        self.isRefreshing = isRefreshing
        self.failure = failure
    }

    public var hasValue: Bool { value != nil }

    public mutating func beginRefresh() {
        isRefreshing = true
    }

    public mutating func succeed(_ value: Value, at date: Date) {
        self.value = value
        self.updatedAt = date
        self.isRefreshing = false
        self.failure = nil
    }

    public mutating func fail(_ error: APIError) {
        self.isRefreshing = false
        self.failure = error
    }

    /// True when the value is older than `maxAge`, or when there is no value at all.
    public func isStale(now: Date, maxAge: TimeInterval) -> Bool {
        guard let updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) > maxAge
    }
}
