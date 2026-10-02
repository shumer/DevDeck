import DevDeckCore
import DevDeckWorkerProtocol
import Foundation
import GitHubKit
import TestHarness

private func inboxNotification(id: String = "42", reason: String = "mention", unread: Bool = true,
                               title: String = "Owned notification", subjectURL: String? = "https://api.github.com/repos/example/web/issues/5") -> [String: Any] {
    ["id": id, "unread": unread, "reason": reason, "updated_at": "2026-09-28T10:00:00Z",
     "subject": ["title": title, "url": subjectURL as Any? ?? NSNull(), "type": "Issue"],
     "repository": ["full_name": "example/web"]]
}
private func inboxPayload(_ items: [[String: Any]]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: items), as: UTF8.self)
}
private func inboxWire(_ response: WorkerResponse) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as! [String: Any]
}
private func inboxResponse(account: WorkerRemoteAccount, subjectURL: String?) async throws -> (WorkerResponse, FakeHTTPClient) {
    let http = FakeHTTPClient([.success(.json(try inboxPayload([inboxNotification(subjectURL: subjectURL)])))])
    let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: http))
    let remote = WorkerRemoteRequest(cardID: "remote.inbox:owned", kind: .inbox, accounts: [account])
    let response = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "owned-inbox", operation: "remote.snapshot", remote: remote)))
    return (response, http)
}

private func inboxSnapshot(_ accounts: [WorkerRemoteAccount], http: any HTTPClient) async throws -> WorkerResponse {
    let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: http))
    return await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "source-inbox", operation: "remote.snapshot",
        remote: WorkerRemoteRequest(cardID: "remote.inbox:owned", kind: .inbox, accounts: accounts))))
}

private actor InboxMutationHTTP: HTTPClient {
    private let body: String
    private let rejectWrite: Bool
    private var readSucceeded = false
    private var gets: [String: Int] = [:]
    private var sent: [HTTPRequest] = []
    init(rejectWrite: Bool = false) throws {
        self.rejectWrite = rejectWrite
        body = try inboxPayload([inboxNotification(subjectURL: nil)])
    }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sent.append(request)
        guard let host = request.url.host, ["one.example.invalid", "two.example.invalid"].contains(host) else {
            throw APIError.transport("Synthetic request escaped its recorded origins")
        }
        if request.method == .patch {
            guard host == "two.example.invalid", request.url.path == "/api/v3/notifications/threads/42" else {
                throw APIError.transport("Synthetic mutation selected the wrong account or raw thread")
            }
            if rejectWrite { return .json("synthetic-two-secret upstream body", status: 403) }
            readSucceeded = true
            return .status(205)
        }
        guard request.method == .get, request.url.path == "/api/v3/notifications" else {
            throw APIError.transport("Unexpected synthetic notification request")
        }
        gets[host, default: 0] += 1
        let etag = host == "one.example.invalid" ? "one-inbox-before" : "two-inbox-before"
        if request.headers["If-None-Match"] == etag { return .status(304) }
        return .json(host == "two.example.invalid" && readSucceeded ? "[]" : body, headers: ["ETag": etag])
    }
    func requests() -> [HTTPRequest] { sent }
}

func runWorkerInboxAttentionTests(_ run: TestRun) async {
    run.section("Inbox attention alternate targets")
    await run.test("actual hello advertises the additive Inbox read-target producer") {
        let http = FakeHTTPClient([])
        let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: http))
        let response = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "inbox-target-hello", operation: "hello")))
        try expect(response.capabilities?.contains("attention.inboxReadTarget") == true)
        try expectEqual(await http.requestCount, 0)
    }
    for (name, subjectURL) in [("URL personal row", Optional("https://api.github.com/repos/example/web/issues/5")),
                               ("URL-less personal row", Optional<String>.none)] {
        await run.test("actual fake-HTTP Inbox producer retains an exact read target for " + name) {
            let account = WorkerRemoteAccount(id: "owned:δ", label: "Owned", endpoint: "https://api.github.com", token: "synthetic-inbox-secret")
            let (response, http) = try await inboxResponse(account: account, subjectURL: subjectURL)
            try expectNil(response.error)
            try expectEqual(response.remote?.rows.count, 1)
            try expectEqual(response.remote?.rows.first?.accountID, account.id)
            let wire = try inboxWire(response)
            let remote = try expectNotNil(wire["remote"] as? [String: Any], "remote snapshot")
            let nested = try expectNotNil(remote["signals"] as? [String: Any], "nested signals")
            let top = try expectNotNil(wire["attention"] as? [String: Any], "top signals")
            for snapshot in [top, nested] {
                let rows = try expectNotNil(snapshot["items"] as? [[String: Any]], "signal items")
                try expectEqual(rows.count, 1)
                let target = try expectNotNil(rows[0]["inboxRead"] as? [String: String], "exact source-based read target")
                try expectEqual(target, ["cardID": "remote.inbox:owned", "accountID": account.id, "threadID": "42", "endpoint": account.endpoint])
                try expectEqual((rows[0]["action"] as? [String: Any])?["kind"] as? String, subjectURL == nil ? "none" : "open")
            }
            try expectEqual(await http.requestCount, 1)
            try expect(!String(decoding: JSONEncoder().encode(response), as: UTF8.self).contains("synthetic-inbox-secret"))
        }
    }
    await run.test("URL-less colliding raw threads retain two exact account origins before shared digest deduplication") {
        let one = WorkerRemoteAccount(id: "a:δ", label: "One", endpoint: "https://one.example.invalid/api/v3", token: "synthetic-one-secret")
        let two = WorkerRemoteAccount(id: "4:a:δ", label: "Two", endpoint: "https://two.example.invalid/api/v3", token: "synthetic-two-secret")
        let http = FakeHTTPClient(routes: [
            ("one.example.invalid", .success(.json(try inboxPayload([inboxNotification(title: "First source", subjectURL: nil)])))),
            ("two.example.invalid", .success(.json(try inboxPayload([inboxNotification(title: "Second source", subjectURL: nil)]))))
        ])
        let response = try await inboxSnapshot([one, two], http: http)
        try expectNil(response.error)
        try expectEqual(response.remote?.rows.count, 2)
        let signals = try expectNotNil(response.remote?.signals, "source-bound signals")
        try expectEqual(signals.items.count, 2)
        try expectEqual(Set(signals.items.map(\.id)).count, 2)
        for account in [one, two] {
            let item = try expectNotNil(signals.items.first { $0.inboxRead?.accountID == account.id }, "own exact account")
            let expectedID = "inbox:\(account.id.utf8.count):\(account.id):2:42"
            try expectEqual(item.id, expectedID); try expectEqual(item.key, expectedID)
            try expectEqual(item.inboxRead, .init(cardID: "remote.inbox:owned", accountID: account.id, threadID: "42", endpoint: account.endpoint))
            try expectEqual(item.action.kind, "none")
            try expectEqual(response.remote?.attention.first { $0.id == expectedID }?.accountID, account.id)
            try expect(item.subtitle.contains(account.label))
        }
        try expectEqual(Set(response.attention?.items.map(\.id) ?? []), Set(signals.items.map(\.id)))
    }
    await run.test("a review thread cannot lend its URL key or read target to another account's colliding mention") {
        let one = WorkerRemoteAccount(id: "reviewer", label: "Reviewer", endpoint: "https://one.example.invalid", token: "synthetic-one-secret")
        let two = WorkerRemoteAccount(id: "mentioned", label: "Mentioned", endpoint: "https://two.example.invalid", token: "synthetic-two-secret")
        let url = "https://github.com/example/web/pull/5"
        let http = FakeHTTPClient(routes: [
            ("one.example.invalid", .success(.json(try inboxPayload([inboxNotification(reason: "review_requested", subjectURL: url)])))),
            ("two.example.invalid", .success(.json(try inboxPayload([inboxNotification(reason: "mention", subjectURL: url)]))))
        ])
        let response = try await inboxSnapshot([one, two], http: http)
        let items = try expectNotNil(response.remote?.signals?.items, "original personal policy")
        let review = try expectNotNil(items.first { $0.inboxRead?.accountID == one.id }, "review source")
        let mention = try expectNotNil(items.first { $0.inboxRead?.accountID == two.id }, "mention source")
        try expectEqual(review.key, "github:review:" + url)
        try expectEqual(mention.key, mention.id)
        try expect(review.key != mention.key)
        try expectEqual(review.action.accountID, one.id); try expectEqual(mention.action.accountID, two.id)
        try expectEqual(review.inboxRead?.endpoint, one.endpoint); try expectEqual(mention.inboxRead?.endpoint, two.endpoint)
    }
    await run.test("all Inbox personal eligibility wording and ages still come from the unchanged original builder") {
        let reasons = ["security_alert", "review_requested", "mention", "team_mention", "assign", "ci_activity",
                       "state_change", "comment", "author", "subscribed", "future_reason"]
        let account = WorkerRemoteAccount(id: "policy", label: "Policy", endpoint: "https://api.github.com", token: "synthetic-policy-secret")
        var payload: [[String: Any]] = []
        var originalItems: [InboxItem] = []
        let date = ISO8601DateFormatter().date(from: "2026-09-28T10:00:00Z")!
        for (index, reason) in reasons.enumerated() {
            let id = String(index + 1), title = "Original policy " + reason
            payload.append(inboxNotification(id: id, reason: reason, title: title))
            originalItems.append(InboxItem(id: id, reason: .init(apiValue: reason), title: title, repository: "example/web",
                updatedAt: date, isUnread: true, url: URL(string: "https://github.com/example/web/issues/5"), accountID: account.id))
        }
        payload.append(inboxNotification(id: "30", reason: "mention", unread: false))
        let response = try await inboxSnapshot([account], http: FakeHTTPClient([.success(.json(try inboxPayload(payload)))]))
        let original = GitHubAttention.items(pullRequests: nil, inbox: InboxSnapshot(items: originalItems), actions: nil, labels: [account.id: account.label])
        let actual = try expectNotNil(response.remote?.signals?.items, "source policy signals")
        try expectEqual(actual.count, original.count)
        try expectEqual(actual.count, 5)
        for source in original {
            let actualItem = try expectNotNil(actual.first { $0.inboxRead?.threadID == source.inboxThreadID }, "original personal source")
            try expectEqual(actualItem.title, source.title); try expectEqual(actualItem.subtitle, source.subtitle)
            try expectEqual(actualItem.since, source.since?.timeIntervalSince1970)
            try expectEqual(actualItem.tier, "waiting"); try expectEqual(actualItem.mark, "github")
            try expectEqual(actualItem.enabled, source.isEnabled); try expectEqual(actualItem.dismissible, source.isDismissible)
        }
        try expectEqual(response.remote?.rows.count, 12)
        try expectEqual(response.remote?.total, 11)
        try expectEqual(response.remote?.actionableCount, 5)
        try expectEqual(response.remote?.signals?.alerts.count, 0)
    }
    await run.test("separate PR and Inbox review producers keep their original overlap key without grafting a write target onto PR") {
        let account = WorkerRemoteAccount(id: "review", label: "Review", endpoint: "https://api.github.com", token: "synthetic-review-secret")
        let http = FakeHTTPClient([.success(.json(Fixtures.pullRequestSearch))])
        let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: http))
        let pr = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "review-pr", operation: "remote.snapshot",
            remote: WorkerRemoteRequest(cardID: "remote.pr", kind: .pullRequests, accounts: [account]))))
        let prItem = try expectNotNil(pr.remote?.signals?.items.first { $0.id.hasPrefix("review:") }, "original PR review")
        let url = try expectNotNil(prItem.action.url, "original review address")
        let inboxHTTP = FakeHTTPClient([.success(.json(try inboxPayload([inboxNotification(reason: "review_requested", subjectURL: url)])))])
        let inbox = try await inboxSnapshot([account], http: inboxHTTP)
        let inboxItem = try expectNotNil(inbox.remote?.signals?.items.first, "original Inbox review")
        try expectEqual(prItem.key, inboxItem.key)
        try expectNil(prItem.inboxRead)
        try expect(pr.remote?.signals?.items.allSatisfy { $0.inboxRead == nil } == true)
        try expectEqual(inboxItem.inboxRead?.threadID, "42")
        try expectEqual(inboxItem.inboxRead?.cardID, "remote.inbox:owned")
    }
    await run.test("invalid or ambiguous raw notification IDs retain their primary facts without admitting a read target") {
        let account = WorkerRemoteAccount(id: "bounded", label: "Bounded", endpoint: "https://api.github.com", token: "synthetic-bounds-secret")
        for id in ["not-a-thread", "42/../other", String(repeating: "1", count: 33)] {
            let response = try await inboxSnapshot([account], http: FakeHTTPClient([.success(.json(try inboxPayload([inboxNotification(id: id)])))]))
            try expectNil(response.error)
            try expectEqual(response.remote?.rows.first?.id, id)
            try expectEqual(response.remote?.signals?.items.count, 1)
            try expectNil(response.remote?.signals?.items.first?.inboxRead)
            try expectEqual(response.remote?.signals?.items.first?.action.kind, "open")
        }
        let duplicates = [inboxNotification(title: "First same tuple"), inboxNotification(title: "Second same tuple")]
        let response = try await inboxSnapshot([account], http: FakeHTTPClient([.success(.json(try inboxPayload(duplicates)))]))
        try expectEqual(response.remote?.rows.count, 2)
        try expectEqual(response.remote?.signals?.items.count, 1)
        try expectNil(response.remote?.signals?.items.first?.inboxRead)
        try expect(response.remote?.signals?.items.first?.title.contains("First same tuple") == true)
    }
    await run.test("account failure rows never gain Inbox targets and top-level successful targets exactly match nested sources") {
        let one = WorkerRemoteAccount(id: "good", label: "Good", endpoint: "https://api.github.com", token: "synthetic-good-secret")
        let missing = WorkerRemoteAccount(id: "missing", label: "Missing", endpoint: "https://api.github.com")
        let response = try await inboxSnapshot([one, missing], http: FakeHTTPClient([.success(.json(try inboxPayload([inboxNotification()])))]))
        try expectNil(response.error)
        try expectEqual(response.remote?.failures.first?.accountID, missing.id)
        let nested = try expectNotNil(response.remote?.signals?.items.first, "healthy nested source")
        let top = try expectNotNil(response.attention?.items.first { $0.id == nested.id }, "same exact top source")
        try expectEqual(top.inboxRead, nested.inboxRead)
        let failed = try expectNotNil(response.attention?.items.first { $0.action.kind == "accountSettings" }, "own failed account")
        try expectNil(failed.inboxRead)
        try expectEqual(failed.action.accountID, missing.id)
        try expectEqual(response.remote?.signals?.items.count, 1)
        try expectEqual(response.attention?.items.count, 2)
    }
    await run.test("legacy attention JSON omits the new optional target and unrelated Actions producer cannot manufacture it") {
        let legacy = """
        {"id":"legacy","key":"legacy","tier":"waiting","mark":"github","title":"Legacy","subtitle":"Original","action":{"kind":"none"},"enabled":true,"dismissible":false}
        """
        let item = try JSONDecoder().decode(WorkerAttentionItem.self, from: Data(legacy.utf8))
        try expectNil(item.inboxRead)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
        try expectNil(encoded["inboxRead"])
        try expectEqual(WorkerProtocol.version, 1)
        try expect(WorkerProtocol.capabilities.contains("remote.markRead"))
        let account = WorkerRemoteAccount(id: "actions", label: "Actions", endpoint: "https://api.github.com", repositories: ["example/web"], token: "synthetic-actions-secret")
        let http = FakeHTTPClient(routes: [("actions/runs", .success(.json(Fixtures.workflowRunsPrimary))),
            ("/repos/example/web", .success(.json("{\"default_branch\":\"main\"}")))])
        let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: http))
        let response = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "actions-no-inbox-target", operation: "remote.snapshot",
            remote: WorkerRemoteRequest(cardID: "remote.actions", kind: .actions, accounts: [account]))))
        try expectNil(response.error)
        try expect(response.remote?.signals?.items.allSatisfy { $0.inboxRead == nil } == true)
        try expect(response.attention?.items.allSatisfy { $0.inboxRead == nil } == true)
    }
    await run.test("captured colliding Inbox source patches only its exact account origin and invalidates only its own cache") {
        let one = WorkerRemoteAccount(id: "one", label: "One", endpoint: "https://one.example.invalid/api/v3", token: "synthetic-one-secret", cacheScope: String(repeating: "A", count: 64))
        let two = WorkerRemoteAccount(id: "two", label: "Two", endpoint: "https://two.example.invalid/api/v3", token: "synthetic-two-secret", cacheScope: String(repeating: "B", count: 64))
        let http = try InboxMutationHTTP()
        let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: http))
        let inbox = WorkerRemoteRequest(cardID: "remote.inbox:owned", kind: .inbox, accounts: [one, two])
        let first = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "before-own-read", operation: "remote.snapshot", remote: inbox)))
        let target = try expectNotNil(first.remote?.signals?.items.first { $0.inboxRead?.accountID == two.id }?.inboxRead, "exact selected source")
        let marked = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "read-own-thread", operation: "remote.markRead",
            remote: WorkerRemoteRequest(cardID: target.cardID, kind: .inbox, accounts: [two], threadIDs: [target.threadID]))))
        try expectNil(marked.error); try expectNil(marked.attention); try expectNil(marked.remote)
        let fresh = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "after-own-read", operation: "remote.snapshot", remote: inbox)))
        try expectEqual(fresh.remote?.rows.count, 1); try expectEqual(fresh.remote?.rows.first?.accountID, one.id)
        let requests = await http.requests()
        let patch = requests.filter { $0.method == .patch }
        try expectEqual(patch.count, 1)
        try expectEqual(patch[0].url.absoluteString, target.endpoint + "/notifications/threads/42")
        try expectEqual(patch[0].headers["Authorization"], "bearer synthetic-two-secret")
        let lastOne = try expectNotNil(requests.last { $0.method == .get && $0.url.host == "one.example.invalid" }, "untouched sibling cache")
        let lastTwo = try expectNotNil(requests.last { $0.method == .get && $0.url.host == "two.example.invalid" }, "invalidated owner cache")
        try expectEqual(lastOne.headers["If-None-Match"], "one-inbox-before")
        try expectNil(lastTwo.headers["If-None-Match"])
    }
    await run.test("a failed captured-thread PATCH stays sanitized and its fresh owner response can still be unread") {
        let one = WorkerRemoteAccount(id: "one", label: "One", endpoint: "https://one.example.invalid/api/v3", token: "synthetic-one-secret", cacheScope: String(repeating: "A", count: 64))
        let two = WorkerRemoteAccount(id: "two", label: "Two", endpoint: "https://two.example.invalid/api/v3", token: "synthetic-two-secret", cacheScope: String(repeating: "B", count: 64))
        let http = try InboxMutationHTTP(rejectWrite: true)
        let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: http))
        let inbox = WorkerRemoteRequest(cardID: "remote.inbox:owned", kind: .inbox, accounts: [one, two])
        let first = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "before-refused-read", operation: "remote.snapshot", remote: inbox)))
        let target = try expectNotNil(first.remote?.signals?.items.first { $0.inboxRead?.accountID == two.id }?.inboxRead, "selected refused source")
        let marked = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "refused-read", operation: "remote.markRead",
            remote: WorkerRemoteRequest(cardID: target.cardID, kind: .inbox, accounts: [two], threadIDs: [target.threadID]))))
        try expectEqual(marked.error?.code, "remoteActionFailed")
        try expectNil(marked.attention); try expectNil(marked.remote)
        let wire = String(decoding: try JSONEncoder().encode(marked), as: UTF8.self)
        try expect(!wire.contains("synthetic-two-secret") && !wire.contains("upstream body"))
        let fresh = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "after-refused-read", operation: "remote.snapshot", remote: inbox)))
        try expectEqual(fresh.remote?.rows.count, 2)
        try expect(fresh.remote?.rows.contains { $0.accountID == two.id && $0.id == target.threadID && $0.isUnread } == true)
        let requests = await http.requests()
        try expectEqual(requests.filter { $0.method == .patch }.count, 1)
        try expectNil(requests.last { $0.method == .get && $0.url.host == "two.example.invalid" }?.headers["If-None-Match"])
        try expectEqual(requests.last { $0.method == .get && $0.url.host == "one.example.invalid" }?.headers["If-None-Match"], "one-inbox-before")
    }
}
