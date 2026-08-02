import Foundation

/// GitHub's rate-limit accounting, parsed from response headers.
///
/// Worth surfacing: the REST and GraphQL budgets are separate, and a card that quietly
/// stops updating because the hour's budget is gone is indistinguishable from a broken one.
public struct RateLimit: Sendable, Equatable {
    public let limit: Int?
    public let remaining: Int?
    public let used: Int?
    public let resetAt: Date?

    public init(limit: Int?, remaining: Int?, used: Int?, resetAt: Date?) {
        self.limit = limit
        self.remaining = remaining
        self.used = used
        self.resetAt = resetAt
    }

    public var isExhausted: Bool { (remaining ?? 1) <= 0 }

    /// Returns nil when the response carried no rate-limit headers at all.
    public static func parse(_ response: HTTPResponse) -> RateLimit? {
        let limit = response.header("x-ratelimit-limit").flatMap(Int.init)
        let remaining = response.header("x-ratelimit-remaining").flatMap(Int.init)
        let used = response.header("x-ratelimit-used").flatMap(Int.init)
        let reset = response.header("x-ratelimit-reset")
            .flatMap(TimeInterval.init)
            .map { Date(timeIntervalSince1970: $0) }

        if limit == nil, remaining == nil, used == nil, reset == nil { return nil }
        return RateLimit(limit: limit, remaining: remaining, used: used, resetAt: reset)
    }
}

public extension HTTPResponse {
    /// `Retry-After` is either seconds or an HTTP date; only the seconds form is used in
    /// practice by GitHub, and an unparseable value must not be treated as "retry now".
    var retryAfterSeconds: TimeInterval? {
        guard let raw = header("retry-after")?.trimmingCharacters(in: .whitespaces) else { return nil }
        return TimeInterval(raw)
    }

    /// GitHub tells notification clients how often they may poll. Ignoring it is the fastest
    /// way to get the token throttled.
    var pollIntervalSeconds: TimeInterval? {
        header("x-poll-interval").flatMap(TimeInterval.init)
    }
}
