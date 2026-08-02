import Foundation

public struct TransportResponse: Sendable, Equatable {
    public let body: Data
    /// True when the server answered 304 and the body came from the cache.
    public let wasNotModified: Bool
    public let rateLimit: RateLimit?
    public let pollIntervalSeconds: TimeInterval?

    public init(
        body: Data,
        wasNotModified: Bool,
        rateLimit: RateLimit? = nil,
        pollIntervalSeconds: TimeInterval? = nil
    ) {
        self.body = body
        self.wasNotModified = wasNotModified
        self.rateLimit = rateLimit
        self.pollIntervalSeconds = pollIntervalSeconds
    }
}

/// Conditional requests, status mapping and backoff in one place, so every integration
/// gets the same behaviour and no client hand-rolls its own retry loop.
public actor APITransport {
    private let client: any HTTPClient
    private let cache: HTTPCache
    private let retryPolicy: RetryPolicy
    private let sleeper: any Sleeper
    private let clock: any DateProvider

    public init(
        client: any HTTPClient,
        cache: HTTPCache = HTTPCache(),
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleeper: any Sleeper = TaskSleeper(),
        clock: any DateProvider = SystemDateProvider()
    ) {
        self.client = client
        self.cache = cache
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
        self.clock = clock
    }

    public func perform(_ request: HTTPRequest) async throws -> TransportResponse {
        var attempt = 0

        while true {
            attempt += 1
            let delay = retryPolicy.delay(beforeAttempt: attempt)
            if delay > 0 { try await sleeper.sleep(seconds: delay) }

            let prepared = await cache.conditionalRequest(from: request)

            do {
                let response = try await client.send(prepared)
                return try await handle(response, for: request)
            } catch let error as APIError {
                guard retryPolicy.shouldRetry(error, afterAttempt: attempt) else { throw error }
                Log.network.debug("Retrying after \(error.displayMessage, privacy: .public)")
            }
        }
    }

    private func handle(_ response: HTTPResponse, for request: HTTPRequest) async throws -> TransportResponse {
        let rateLimit = RateLimit.parse(response)
        let poll = response.pollIntervalSeconds

        switch response.statusCode {
        case 200..<300:
            if let key = request.cacheKey {
                await cache.store(response, for: key)
            }
            return TransportResponse(
                body: response.body,
                wasNotModified: false,
                rateLimit: rateLimit,
                pollIntervalSeconds: poll
            )

        case 304:
            guard let key = request.cacheKey, let entry = await cache.entry(for: key) else {
                // A 304 without anything cached means the validator came from somewhere else;
                // treat it as a transport fault so the caller retries rather than rendering
                // an empty card.
                throw APIError.transport("304 with no cached body")
            }
            return TransportResponse(
                body: entry.body,
                wasNotModified: true,
                rateLimit: rateLimit,
                pollIntervalSeconds: poll
            )

        case 401:
            throw APIError.unauthorized

        case 403:
            // GitHub uses 403 both for "no permission" and for a spent rate limit;
            // the remaining counter is the only way to tell them apart.
            if let rateLimit, rateLimit.isExhausted {
                throw APIError.rateLimited(resetAt: rateLimit.resetAt)
            }
            throw APIError.forbidden(Self.message(from: response.body))

        case 404:
            throw APIError.notFound

        case 429:
            let resetAt = response.retryAfterSeconds.map { clock.now.addingTimeInterval($0) }
                ?? rateLimit?.resetAt
            throw APIError.rateLimited(resetAt: resetAt)

        default:
            throw APIError.server(status: response.statusCode, message: Self.message(from: response.body))
        }
    }

    /// GitHub error bodies are `{"message": "...", "documentation_url": "..."}`.
    private static func message(from body: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let message = object["message"] as? String,
            !message.isEmpty
        else { return nil }
        return message
    }
}
