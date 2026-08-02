import DevDeckCore
import Foundation
import TestHarness

func runNetworkingTests(_ run: TestRun) async {
    run.section("Networking — headers and rate limits")

    await run.test("header lookup ignores case") {
        let response = HTTPResponse(statusCode: 200, headers: ["ETag": "\"abc\""], body: Data())
        try expectEqual(response.header("etag"), "\"abc\"")
        try expectEqual(response.header("ETAG"), "\"abc\"")
        try expectNil(response.header("x-missing"))
    }

    await run.test("rate limit parses the GitHub headers") {
        let response = HTTPResponse(
            statusCode: 200,
            headers: [
                "x-ratelimit-limit": "5000",
                "x-ratelimit-remaining": "4990",
                "x-ratelimit-used": "10",
                "x-ratelimit-reset": "1700000000",
            ],
            body: Data()
        )
        let limit = try expectNotNil(RateLimit.parse(response), "rate limit")
        try expectEqual(limit.limit, 5000)
        try expectEqual(limit.remaining, 4990)
        try expectEqual(limit.used, 10)
        try expectEqual(limit.resetAt, Date(timeIntervalSince1970: 1_700_000_000))
        try expect(!limit.isExhausted)
    }

    await run.test("rate limit is nil when no headers are present") {
        try expectNil(RateLimit.parse(HTTPResponse(statusCode: 200)))
    }

    await run.test("retry-after and poll interval are read as seconds") {
        let response = HTTPResponse(
            statusCode: 429,
            headers: ["Retry-After": "30", "X-Poll-Interval": "60"],
            body: Data()
        )
        try expectEqual(response.retryAfterSeconds, 30)
        try expectEqual(response.pollIntervalSeconds, 60)
    }

    run.section("Networking — retry policy")

    await run.test("backoff grows and is capped") {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1, multiplier: 3, maxDelay: 10)
        try expectEqual(policy.delay(beforeAttempt: 1), 0, "first attempt never waits")
        try expectEqual(policy.delay(beforeAttempt: 2), 1)
        try expectEqual(policy.delay(beforeAttempt: 3), 3)
        try expectEqual(policy.delay(beforeAttempt: 4), 9)
        try expectEqual(policy.delay(beforeAttempt: 5), 10, "capped at maxDelay")
    }

    await run.test("only transient failures are retried") {
        let policy = RetryPolicy(maxAttempts: 3)
        try expect(policy.shouldRetry(.server(status: 502, message: nil), afterAttempt: 1))
        try expect(policy.shouldRetry(.transport("offline"), afterAttempt: 2))
        try expect(!policy.shouldRetry(.server(status: 502, message: nil), afterAttempt: 3),
                   "attempts are exhausted")
        try expect(!policy.shouldRetry(.unauthorized, afterAttempt: 1))
        try expect(!policy.shouldRetry(.rateLimited(resetAt: nil), afterAttempt: 1))
    }

    run.section("Networking — conditional cache")

    await run.test("a response without validators is not cached") {
        let cache = HTTPCache()
        await cache.store(HTTPResponse.json("{}"), for: "prs")
        try expectNil(await cache.entry(for: "prs"))
    }

    await run.test("validators are stored and replayed on the next request") {
        let cache = HTTPCache()
        await cache.store(
            HTTPResponse.json("[1]", headers: ["ETag": "\"v1\"", "Last-Modified": "Wed, 21 Oct 2026 07:28:00 GMT"]),
            for: "inbox"
        )
        let prepared = await cache.conditionalRequest(
            from: HTTPRequest(url: URL(string: "https://api.github.com/notifications")!, cacheKey: "inbox")
        )
        try expectEqual(prepared.headers["If-None-Match"], "\"v1\"")
        try expectEqual(prepared.headers["If-Modified-Since"], "Wed, 21 Oct 2026 07:28:00 GMT")
    }

    await run.test("requests without a cache key are left alone") {
        let cache = HTTPCache()
        await cache.store(HTTPResponse.json("[]", headers: ["ETag": "\"v1\""]), for: "inbox")
        let request = HTTPRequest(url: URL(string: "https://api.github.com/graphql")!)
        let prepared = await cache.conditionalRequest(from: request)
        try expectEqual(prepared, request)
    }

    run.section("Networking — transport")

    let url = URL(string: "https://api.github.com/notifications")!

    await run.test("a 304 is answered from the cache") {
        let client = FakeHTTPClient([
            .success(.json("[{\"id\":\"1\"}]", headers: ["ETag": "\"v1\""])),
            .success(.status(304, headers: ["ETag": "\"v1\""])),
        ])
        let transport = APITransport(client: client, sleeper: RecordingSleeper())
        let request = HTTPRequest(url: url, cacheKey: "inbox")

        let first = try await transport.perform(request)
        try expect(!first.wasNotModified)
        try expectEqual(String(decoding: first.body, as: UTF8.self), "[{\"id\":\"1\"}]")

        let second = try await transport.perform(request)
        try expect(second.wasNotModified, "second call should be served from cache")
        try expectEqual(String(decoding: second.body, as: UTF8.self), "[{\"id\":\"1\"}]")

        let replayed = await client.request(at: 1)
        try expectEqual(replayed?.headers["If-None-Match"], "\"v1\"")
    }

    await run.test("a 304 with an empty cache is treated as a fault") {
        let client = FakeHTTPClient([.success(.status(304))])
        let transport = APITransport(client: client, retryPolicy: .none, sleeper: RecordingSleeper())
        let error = try await expectThrows {
            _ = try await transport.perform(HTTPRequest(url: url, cacheKey: "inbox"))
        }
        try expectEqual(error as? APIError, .transport("304 with no cached body"))
    }

    await run.test("401 maps to unauthorized") {
        let client = FakeHTTPClient([.success(.status(401))])
        let transport = APITransport(client: client, retryPolicy: .none, sleeper: RecordingSleeper())
        let error = try await expectThrows {
            _ = try await transport.perform(HTTPRequest(url: url))
        }
        try expectEqual(error as? APIError, .unauthorized)
    }

    await run.test("403 with an exhausted budget maps to rate limited") {
        let client = FakeHTTPClient([
            .success(.status(403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1700000000"])),
        ])
        let transport = APITransport(client: client, retryPolicy: .none, sleeper: RecordingSleeper())
        let error = try await expectThrows {
            _ = try await transport.perform(HTTPRequest(url: url))
        }
        try expectEqual(error as? APIError, .rateLimited(resetAt: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    await run.test("403 without rate-limit headers keeps the server message") {
        let body = "{\"message\":\"Resource protected by organization SAML enforcement\"}"
        let client = FakeHTTPClient([.success(.json(body, status: 403))])
        let transport = APITransport(client: client, retryPolicy: .none, sleeper: RecordingSleeper())
        let error = try await expectThrows {
            _ = try await transport.perform(HTTPRequest(url: url))
        }
        try expectEqual(
            error as? APIError,
            .forbidden("Resource protected by organization SAML enforcement")
        )
    }

    await run.test("429 uses Retry-After against the injected clock") {
        let clock = MutableDateProvider(now: Date(timeIntervalSince1970: 1_000))
        let client = FakeHTTPClient([.success(.status(429, headers: ["Retry-After": "60"]))])
        let transport = APITransport(
            client: client,
            retryPolicy: .none,
            sleeper: RecordingSleeper(),
            clock: clock
        )
        let error = try await expectThrows {
            _ = try await transport.perform(HTTPRequest(url: url))
        }
        try expectEqual(error as? APIError, .rateLimited(resetAt: Date(timeIntervalSince1970: 1_060)))
    }

    await run.test("a 502 is retried and the recovery is returned") {
        let sleeper = RecordingSleeper()
        let client = FakeHTTPClient([
            .success(.status(502)),
            .success(.json("{\"ok\":true}")),
        ])
        let transport = APITransport(
            client: client,
            retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 2, multiplier: 2),
            sleeper: sleeper
        )
        let response = try await transport.perform(HTTPRequest(url: url))
        try expectEqual(String(decoding: response.body, as: UTF8.self), "{\"ok\":true}")
        try expectEqual(await client.requestCount, 2)
        try expectEqual(await sleeper.delays, [2], "one backoff before the second attempt")
    }

    await run.test("retries give up after maxAttempts") {
        let client = FakeHTTPClient([
            .success(.status(500)), .success(.status(500)), .success(.status(500)),
        ])
        let transport = APITransport(
            client: client,
            retryPolicy: RetryPolicy(maxAttempts: 3),
            sleeper: RecordingSleeper()
        )
        let error = try await expectThrows {
            _ = try await transport.perform(HTTPRequest(url: url))
        }
        try expectEqual(error as? APIError, .server(status: 500, message: nil))
        try expectEqual(await client.requestCount, 3)
    }
}
