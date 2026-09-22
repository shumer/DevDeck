import DevDeckCore
import Foundation
import DevDeckUI
import GitHubKit
import TestHarness

func runInboxTests(_ run: TestRun) async {
    run.section("GitHub - inbox")

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
        try expectEqual(request.cacheKey, "github.notifications.default",
                        "polling relies on the ETag, and each account has its own")
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

    run.section("GitHub - clearing the inbox")

    /// A page of `count` unread notifications, ids from `first` up, every other one a comment
    /// and the rest CI chatter, none of it addressed to anyone.
    func page(_ count: Int, from first: Int = 1) -> String {
        let items = (0..<count).map { offset in
            """
            {"id": "\(first + offset)", "unread": true, "reason": "\(offset % 2 == 0 ? "comment" : "ci_activity")",
             "updated_at": "2026-08-01T10:00:00Z",
             "subject": {"title": "t", "url": null, "type": "Issue"},
             "repository": {"full_name": "editoria/ledwall"}}
            """
        }
        return "[" + items.joined(separator: ",") + "]"
    }

    func inboxClient(_ http: FakeHTTPClient) -> GitHubClient {
        GitHubClient(
            transport: APITransport(client: http, retryPolicy: .none, sleeper: RecordingSleeper()),
            tokenStore: InMemoryTokenStore(tokens: [.github: "test-token"])
        )
    }

    await run.test("a full page means the count is a floor, and the card says 50+") {
        let full = FakeHTTPClient([.success(.json(page(4)))])
        let capped = try await NotificationsService(client: inboxClient(full), settings: GitHubSettings(maxNotifications: 4)).fetch()
        try expect(capped.isCapped, "four asked for, four came back: there may be more")
        try expectEqual(InboxCard.unreadText(for: capped), "4+")

        let short = FakeHTTPClient([.success(.json(page(3)))])
        let whole = try await NotificationsService(client: inboxClient(short), settings: GitHubSettings(maxNotifications: 4)).fetch()
        try expect(!whole.isCapped, "a short page is the whole box")
        try expectEqual(InboxCard.unreadText(for: whole), "3")

        let merged = InboxSnapshot.merging([capped, whole])
        try expect(merged.isCapped, "one capped account makes the merged count a floor too")
    }

    await run.test("the rest of the box is read page by page, and stops at the first short one") {
        let http = FakeHTTPClient([.success(.json(page(50))), .success(.json(page(7, from: 51)))])
        let threads = try await NotificationsService(client: inboxClient(http)).unreadThreads()
        try expectEqual(threads.count, 57)
        try expectEqual(await http.requestCount, 2, "no third request after a short page")
        let second = try expectNotNil(await http.request(at: 1), "second request")
        try expect(second.url.absoluteString.contains("page=2"))
        try expect(second.url.absoluteString.contains("all=false"), "only what is unread")
        try expectNil(second.cacheKey, "an action must see the box as it is, not a 304")
    }

    await run.test("paging is bounded, whatever the size of the box") {
        let http = FakeHTTPClient(Array(repeating: .success(.json(page(50))), count: 5))
        let threads = try await NotificationsService(client: inboxClient(http)).unreadThreads(maxPages: 3)
        try expectEqual(threads.count, 150)
        try expectEqual(await http.requestCount, 3)
    }

    await run.test("mark all as read is one PUT, up to the newest thing the card showed") {
        let http = FakeHTTPClient([.success(.status(205))])
        let moment = Date(timeIntervalSince1970: 1_785_000_000)
        try await NotificationsService(client: inboxClient(http)).markAllRead(upTo: moment)
        let request = try expectNotNil(await http.request(at: 0), "request")
        try expectEqual(request.method, .put)
        try expect(request.url.absoluteString.hasSuffix("/notifications"))
        try expectEqual(request.headers["Content-Type"], "application/json")
        let body = try expectNotNil(request.body, "body")
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        try expectEqual(json?["last_read_at"] as? String, "2026-07-25T17:20:00Z",
                        "whatever arrived after this stays unread")
        try expectEqual(json?["read"] as? Bool, true)
    }

    await run.test("the rest is what is not addressed to you, and the newest is per account") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        try expectEqual(snapshot.unreadNotForYou.map(\.id), ["2"],
                        "the CI note goes; the review request and the mention stay")
        try expectEqual(snapshot.newestByAccount[GitHubAccount.defaultID],
                        snapshot.items.map(\.updatedAt).max())
        try expectEqual(snapshot.removing(["2"]).unreadCount, 2)
    }

    await run.test("the footer's link reads the rest when something is for you, all when nothing is") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        let rest = try expectNotNil(InboxCard.clearing(for: snapshot, optionDown: false), "link")
        try expectEqual(rest.action, .rest)
        // Named by what stays: "the rest" read as "everything but the rows on the card".
        try expectEqual(rest.title, "Mark as read, except the 2 for you")

        let option = try expectNotNil(InboxCard.clearing(for: snapshot, optionDown: true), "⌥ link")
        try expectEqual(option.action, .all, "⌥ is the whole box")
        try expectEqual(option.title, "Mark all 3 as read")

        let noise = InboxSnapshot(items: snapshot.unreadNotForYou)
        try expectEqual(InboxCard.clearing(for: noise, optionDown: false)?.action, .all,
                        "nothing is for you, so all is safe")
        try expectEqual(InboxCard.clearing(for: noise, optionDown: false)?.title, "Mark 1 as read")

        // Everything unread is addressed to you. There used to be no link at all, and a card
        // saying "33 unread" with nothing to press; the count on the link is the guard instead.
        let forYouOnly = snapshot.removing(["2"])
        let only = try expectNotNil(InboxCard.clearing(for: forYouOnly, optionDown: false), "link")
        try expectEqual(only.action, .all)
        try expectEqual(only.title, "Mark all 2 as read")

        try expectNil(InboxCard.clearing(for: .empty, optionDown: false), "nothing to read")
    }

    await run.test("many threads are marked a few at a time, and a refusal is reported by thread") {
        var responses: [Result<HTTPResponse, Error>] = Array(repeating: .success(.status(205)), count: 9)
        responses[4] = .success(.status(403))
        let http = FakeHTTPClient(responses)
        let ids = (1...9).map(String.init)
        let counter = Counter()
        let refused = await NotificationsService(client: inboxClient(http)).markRead(ids, concurrency: 3) { done in
            await counter.record(done)
        }
        try expectEqual(await http.requestCount, 9, "every thread is asked for, once")
        try expectEqual(refused.count, 1, "one refusal, and it is named")
        try expectEqual(await counter.last, 9, "progress reaches the end")
        try expect(await counter.values == Array(1...9), "and counts up one at a time")
        let methods = await (0..<9).asyncMap { await http.request(at: $0)?.method }
        try expect(methods.allSatisfy { $0 == .patch }, "each one is the thread's own PATCH")
    }

    await run.test("the footer says how far a mark-as-read has got, and how it ended") {
        try expectEqual(InboxCard.progressText(.marking(done: 120, total: 340)), "Marking as read… 120 of 340")
        try expectEqual(InboxCard.progressText(.finished(340)), "Done, 340 marked as read")
        try expectEqual(InboxCard.progressText(.failed("Not allowed")), "GitHub refused: Not allowed")
        try expect(InboxCard.Progress.gathering.isRunning && !InboxCard.Progress.finished(1).isRunning,
                   "a second press is refused only while one is running")

        Strings.use(.russian, lookingIn: localisationRoot)
        try expectEqual(InboxCard.progressText(.marking(done: 3, total: 40)), "Отмечаю прочитанными… 3 из 40")
        try expectEqual(LN("card.inbox.readRest", 24), "Отметить прочитанным, кроме 24 для вас")
        try expectEqual(LN("card.inbox.readAll", 12), "Отметить все 12 прочитанными")
        try expectEqual(LN("card.inbox.readAll", 1), "Отметить 1 прочитанным")
        Strings.use(.english, lookingIn: localisationRoot)
    }

    await run.test("a box bigger than the card loaded is never promised a number") {
        let capped = InboxSnapshot(items: snapshot?.items ?? [], cappedAccounts: [GitHubAccount.defaultID])
        try expectEqual(InboxCard.clearing(for: capped, optionDown: true)?.title, "Mark all as read")
    }

    run.section("GitHub - notification links")

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

    run.section("GitHub - inbox failures")

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

/// Records what a progress callback was told, in order.
private actor Counter {
    private(set) var values: [Int] = []
    var last: Int? { values.last }
    func record(_ value: Int) { values.append(value) }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var result: [T] = []
        for element in self { result.append(await transform(element)) }
        return result
    }
}
