import Foundation

/// How long to wait before the next refresh.
///
/// Three inputs decide it: the user's interval, whatever the server asked for through
/// `X-Poll-Interval`, and how many attempts in a row have failed. The server always wins
/// upwards — an interval shorter than the one GitHub asked for is how a token gets throttled.
public struct RefreshPolicy: Sendable, Equatable {
    public var interval: TimeInterval
    public var minimumInterval: TimeInterval
    public var maximumInterval: TimeInterval

    public init(
        interval: TimeInterval = 120,
        minimumInterval: TimeInterval = 60,
        maximumInterval: TimeInterval = 900
    ) {
        self.interval = interval
        self.minimumInterval = minimumInterval
        self.maximumInterval = maximumInterval
    }

    public func nextDelay(consecutiveFailures: Int, serverHint: TimeInterval? = nil) -> TimeInterval {
        let base = max(interval, minimumInterval, serverHint ?? 0)
        guard consecutiveFailures > 0 else { return min(base, maximumInterval) }
        let backoff = base * pow(2, Double(min(consecutiveFailures, 8)))
        return min(backoff, maximumInterval)
    }

    /// A rate-limit reset in the future outranks everything else: retrying before it
    /// only burns the budget further.
    public func nextDelay(after error: APIError, consecutiveFailures: Int, now: Date) -> TimeInterval {
        if case .rateLimited(let resetAt) = error, let resetAt {
            let wait = resetAt.timeIntervalSince(now) + 5
            if wait > 0 { return min(max(wait, minimumInterval), maximumInterval) }
        }
        return nextDelay(consecutiveFailures: consecutiveFailures)
    }
}
