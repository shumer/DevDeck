import DevDeckCore
import Foundation
import GitHubKit
import TestHarness

func runInboxTests(_ run: TestRun) async {
    run.section("GitHub — inbox")

    let http = FakeHTTPClient([
        .success(.json(Fixtures.notifications, headers: ["X-Poll-Interval": "90", "ETag": "\"n1\""])),
    ])
    let client = GitHubClient(
        transport: APITransport(client: http, retryPolicy: .none, sleeper: RecordingSleeper()),
        tokenStore: InMemoryTokenStore(tokens: [.github: "test-token"])
    )
    let snapshot = try? await NotificationsService(client: client).fetch()

    await run.test("notifications decode into the inbox snapshot") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        try expectEqual(snapshot.items.count, 4)
        try expectEqual(snapshot.unreadCount, 3, "the read one is not counted")
        try expectEqual(snapshot.repositoryCount, 3)
        try expectEqual(snapshot.serverPollInterval, 90, "X-Poll-Interval reaches the refresh loop")
    }

    await run.test("the request is a conditional GET for unread notifications") {
        let request = try expectNotNil(await http.request(at: 0), "request")
        try expectEqual(request.method, .get)
        try expect(request.url.absoluteString.contains("/notifications"))
        try expect(request.url.absoluteString.contains("all=false"))
        try expectEqual(request.cacheKey, "github.notifications", "polling relies on the ETag")
        try expectEqual(request.headers["X-GitHub-Api-Version"], "2022-11-28")
    }

    await run.test("reasons map, and an unknown one is kept rather than dropped") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        let byID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        try expectEqual(byID["1"]?.reason, .reviewRequested)
        try expectEqual(byID["2"]?.reason, .ciActivity)
        try expectEqual(byID["3"]?.reason, .mention)
        try expectEqual(byID["4"]?.reason, .other, "an unrecognised reason still shows up")
    }

    await run.test("actionable counts only what is waiting on me") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        try expectEqual(snapshot.actionableCount, 2, "review request and mention, not the CI note")
    }

    await run.test("rows are unread first, then by how loud the reason is") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        try expectEqual(snapshot.prioritized().map(\.id), ["1", "3", "2", "4"])
        try expectEqual(snapshot.prioritized(limit: 2).map(\.id), ["1", "3"])
    }

    run.section("GitHub — notification links")

    await run.test("a pull request subject becomes a page a human can open") {
        let url = InboxItem.webURL(fromSubject: URL(string: "https://api.github.com/repos/editoria/ledwall/pulls/412"))
        try expectEqual(url?.absoluteString, "https://github.com/editoria/ledwall/pull/412")
    }

    await run.test("issue subjects need no rewrite beyond the host") {
        let url = InboxItem.webURL(fromSubject: URL(string: "https://api.github.com/repos/editoria/ledwall/issues/77"))
        try expectEqual(url?.absoluteString, "https://github.com/editoria/ledwall/issues/77")
    }

    await run.test("a subject without a URL stays without one") {
        try expectNil(InboxItem.webURL(fromSubject: nil))
    }

    await run.test("an unexpected host is left alone rather than mangled") {
        let original = URL(string: "https://github.enterprise.local/api/v3/repos/a/b/pulls/1")
        try expectEqual(InboxItem.webURL(fromSubject: original), original)
    }

    run.section("GitHub — inbox failures")

    await run.test("a 304 replays the previous payload") {
        let http = FakeHTTPClient([
            .success(.json(Fixtures.notifications, headers: ["ETag": "\"n1\""])),
            .success(.status(304, headers: ["ETag": "\"n1\""])),
        ])
        let client = GitHubClient(
            transport: APITransport(client: http, retryPolicy: .none, sleeper: RecordingSleeper()),
            tokenStore: InMemoryTokenStore(tokens: [.github: "test-token"])
        )
        let service = NotificationsService(client: client)
        let first = try await service.fetch()
        let second = try await service.fetch()
        try expectEqual(first.unreadCount, second.unreadCount, "an unchanged inbox still renders")
        try expectEqual(await http.requestCount, 2)
    }

    await run.test("a rejected token surfaces on the card") {
        let http = FakeHTTPClient([.success(.status(401))])
        let client = GitHubClient(
            transport: APITransport(client: http, retryPolicy: .none, sleeper: RecordingSleeper()),
            tokenStore: InMemoryTokenStore(tokens: [.github: "bad"])
        )
        let error = try await expectThrows {
            _ = try await NotificationsService(client: client).fetch()
        }
        try expectEqual(error as? APIError, .unauthorized)
    }
}
