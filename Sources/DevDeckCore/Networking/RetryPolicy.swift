import Foundation

/// Exponential backoff for transient failures.
///
/// Deliberately short and shallow: a desktop panel that is one refresh behind is fine,
/// while a long retry chain would stack up against the next scheduled refresh.
public struct RetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var baseDelay: TimeInterval
    public var multiplier: Double
    public var maxDelay: TimeInterval

    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1,
        multiplier: Double = 3,
        maxDelay: TimeInterval = 20
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
    }

    public static let none = RetryPolicy(maxAttempts: 1)

    /// Delay before the given 1-based attempt number. Attempt 1 never waits.
    public func delay(beforeAttempt attempt: Int) -> TimeInterval {
        guard attempt > 1 else { return 0 }
        let exponent = Double(attempt - 2)
        return min(baseDelay * pow(multiplier, exponent), maxDelay)
    }

    public func shouldRetry(_ error: APIError, afterAttempt attempt: Int) -> Bool {
        attempt < maxAttempts && error.isRetryable
    }
}
