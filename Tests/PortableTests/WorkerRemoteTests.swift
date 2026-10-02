import DevDeckCore
import DevDeckWorkerProtocol
import Foundation
import TestHarness

func runWorkerRemoteTests(_ run: TestRun) async {
    run.section("WSL remote cards")
    let encoder = JSONEncoder()
    let account = WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://api.github.com", token: "offline-secret")
    func request(_ kind: WorkerRemoteRequest.Kind = .pullRequests, accounts: [WorkerRemoteAccount]? = nil) -> WorkerRemoteRequest {
        WorkerRemoteRequest(cardID: "github.pr", kind: kind, accounts: accounts ?? [account])
    }
    await run.test("scoped remote polling reuses validators and a 304 preserves the shared inbox snapshot") {
        let http = FakeHTTPClient([.success(.json(Fixtures.notifications, headers: ["ETag": "fixture-v1", "X-Poll-Interval": "120"])), .success(.status(304, headers: ["X-Poll-Interval": "120"]))])
        let account = WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://api.github.com", token: "offline-secret", cacheScope: String(repeating: "A", count: 64))
        let service = WorkerRemoteService(http: http)
        let first = try await service.fetch(request(.inbox, accounts: [account]))
        let second = try await service.fetch(request(.inbox, accounts: [account]))
        try expectEqual(first.rows.map(\.id), second.rows.map(\.id))
        try expectEqual(second.pollIntervalSeconds, 120)
        try expectEqual((await http.request(at: 1))?.headers["If-None-Match"], "fixture-v1")
    }
    await run.test("credential rotation and host change isolate cached validators") {
        let http = FakeHTTPClient(Array(repeating: .success(.json(Fixtures.notifications, headers: ["ETag": "fixture-v1"])), count: 3))
        let service = WorkerRemoteService(http: http)
        let first = WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://api.github.com", token: "offline-secret", cacheScope: String(repeating: "A", count: 64))
        let rotated = WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://api.github.com", token: "other-offline-secret", cacheScope: String(repeating: "B", count: 64))
        let host = WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://enterprise.example.com/api", token: "offline-secret", cacheScope: String(repeating: "A", count: 64))
        for account in [first, rotated, host] { _ = try await service.fetch(request(.inbox, accounts: [account])) }
        for index in [1, 2] { try expectEqual((await http.request(at: index))?.headers["If-None-Match"], nil) }
        try expectEqual((await http.request(at: 1))?.headers["Authorization"], "bearer other-offline-secret")
    }
    await run.test("mark-read invalidates the account's cached inbox before refreshing") {
        let http = FakeHTTPClient([.success(.json(Fixtures.notifications, headers: ["ETag": "fixture-v1"])), .success(.status(205)), .success(.json("[]"))])
        let account = WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://api.github.com", token: "offline-secret", cacheScope: String(repeating: "A", count: 64))
        let service = WorkerRemoteService(http: http)
        _ = try await service.fetch(request(.inbox, accounts: [account]))
        try await service.markRead(WorkerRemoteRequest(cardID: "github.inbox", kind: .inbox, accounts: [account], threadIDs: ["42"]), rest: false)
        let refreshed = try await service.fetch(request(.inbox, accounts: [account]))
        try expectEqual(refreshed.rows.count, 0)
        try expectEqual((await http.request(at: 2))?.headers["If-None-Match"], nil)
    }
    await run.test("remote PR snapshot reuses shared health and preserves account identity") {
        let http = FakeHTTPClient([.success(.json(Fixtures.pullRequestSearch))])
        let value = try await WorkerRemoteService(http: http).fetch(request())
        try expectEqual(value.total, 8)
        try expectEqual(value.rows.count, 5)
        try expectEqual(value.blocked, 2)
        try expect(value.rows.allSatisfy { $0.accountID == "work" })
        try expect(value.rows.contains { $0.needsReview })
        try expectEqual(value.rows.map(\.statusCode), ["CF", "CR", "RV", "DR", "AP"])
        try expectEqual(value.repositoryCount, 3)
        try expectEqual(value.namespaceCount, 2)
        try expectEqual(value.reviewCount, 1)
        try expectEqual(value.rows[2].ticketKey, "IW-164")
        try expectEqual(value.rows[2].subject, "Approvers resource for the proofing API")
        try expect(value.capped)
        try expect(!String(decoding: encoder.encode(value), as: UTF8.self).contains("offline-secret"))
    }
    await run.test("one missing token preserves another account's rows and reports a sanitized failure") {
        let http = FakeHTTPClient([.success(.json(Fixtures.pullRequestSearch))])
        let missing = WorkerRemoteAccount(id: "missing", label: "Missing", endpoint: "https://api.github.com")
        let value = try await WorkerRemoteService(http: http).fetch(request(accounts: [account, missing]))
        try expectEqual(value.rows.count, 5)
        try expectEqual(value.failures.count, 1)
        try expectEqual(value.failures.first?.accountID, "missing")
        try expectEqual(value.failures.first?.kind, "rejected")
    }
    await run.test("all missing credentials fail without consulting environment tokens or the network") {
        let http = FakeHTTPClient([])
        let missing = WorkerRemoteAccount(id: "missing", label: "Missing", endpoint: "https://api.github.com")
        do { _ = try await WorkerRemoteService(http: http).fetch(request(accounts: [missing])); throw TestFailure(message: "Expected rejection", file: #filePath, line: #line) }
        catch let error as WorkerRemoteError { try expectEqual(error.code, "credentialsRejected") }
        try expectEqual(await http.requestCount, 0)
    }
    await run.test("worker rejects unsafe credential endpoints and duplicate account IDs before HTTP") {
        let http = FakeHTTPClient([])
        for endpoint in ["http://api.github.com", "https://user:secret@example.com", "https://example.com?token=secret", "https://example.com#secret"] {
            do {
                _ = try await WorkerRemoteService(http: http).fetch(request(accounts: [WorkerRemoteAccount(id: "a", label: "A", endpoint: endpoint, token: "offline-secret")]))
                throw TestFailure(message: "Expected invalid endpoint", file: #filePath, line: #line)
            } catch let error as WorkerRemoteError { try expectEqual(error.code, "invalidRemote") }
        }
        do { _ = try await WorkerRemoteService(http: http).fetch(request(accounts: [account, account])); throw TestFailure(message: "Expected duplicate rejection", file: #filePath, line: #line) }
        catch let error as WorkerRemoteError { try expectEqual(error.code, "invalidRemote") }
        try expectEqual(await http.requestCount, 0)
    }
    await run.test("remote upstream error text and credentials are never echoed in worker failures") {
        let http = FakeHTTPClient([.success(.json("{\"errors\":[{\"message\":\"offline-secret\"}]}"))])
        let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: http))
        let value = await worker.handle(try encoder.encode(WorkerRequest(id: "remote", operation: "remote.snapshot", remote: request())))
        try expectEqual(value.error?.code, "remoteUnavailable")
        try expect(!String(decoding: encoder.encode(value), as: UTF8.self).contains("offline-secret"))
    }
    await run.test("inbox rows preserve review and mention attention semantics") {
        let http = FakeHTTPClient([.success(.json(Fixtures.notifications))])
        let value = try await WorkerRemoteService(http: http).fetch(request(.inbox))
        try expect(!value.rows.isEmpty)
        try expect(value.rows.contains { $0.needsReview && $0.health == "attention" })
        try expectEqual(value.total, 3)
        try expectEqual(value.rows.map(\.id), ["1", "3", "2", "4"])
        try expectEqual(value.actionableCount, 2)
        try expectEqual(value.repositoryCount, 3)
        try expectEqual(value.rows.last?.isUnread, false)
        try expect(value.rows.allSatisfy { $0.updatedAt != nil })
    }
    await run.test("Actions uses explicit per-account repositories and shared success-rate rules") {
        let http = FakeHTTPClient(routes: [
            ("actions/runs", .success(.json(Fixtures.workflowRunsPrimary))),
            ("/repos/example/web", .success(.json("{\"default_branch\":\"main\"}")))
        ])
        let configured = WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://api.github.com", repositories: ["example/web"], token: "offline-secret")
        let value = try await WorkerRemoteService(http: http).fetch(request(.actions, accounts: [configured]))
        try expectEqual(value.rows.count, 4)
        try expectEqual(value.blocked, 1)
        try expectEqual(value.successRate, 0.5)
        try expectEqual(value.repositoryCount, 1)
        try expectEqual(value.watchedRepositories, ["example/web"])
        try expectEqual(value.runningCount, 1)
        try expectEqual(value.windowDays, 7)
        try expect(value.averageDurationSeconds != nil && !value.followsPullRequests)
    }
    await run.test("GitLab remote response shares merge-request rules and endpoint") {
        let http = FakeHTTPClient([.success(.json("""
        {"data":{"currentUser":{"mine":{"count":1,"nodes":[{"id":"gid://gitlab/MergeRequest/1","iid":"1","title":"Synthetic merge request","webUrl":"https://git.example.com/a/web/-/merge_requests/1","draft":false,"conflicts":false,"updatedAt":"2026-08-30T09:12:00Z","approvalsLeft":0,"project":{"fullPath":"a/web"},"headPipeline":{"status":"FAILED"},"discussions":{"nodes":[]}}]},"reviewing":{"count":0,"nodes":[]}}}}
        """))])
        let configured = WorkerRemoteAccount(id: "lab", label: "Lab", endpoint: "https://git.example.com", token: "offline-secret")
        let value = try await WorkerRemoteService(http: http).fetch(request(.mergeRequests, accounts: [configured]))
        try expectEqual(value.total, 1)
        try expectEqual(value.blocked, 1)
        try expectEqual(value.rows.first?.accountID, "lab")
        try expectEqual(value.rows.first?.statusCode, "CF")
        try expectEqual(value.repositoryCount, 1)
        try expectEqual(value.namespaceCount, 1)
        try expectEqual((await http.request(matching: "graphql"))?.url.absoluteString, "https://git.example.com/api/graphql")
    }
    await run.test("GitLab adapter preserves every short state conflict precedence review order and ticket metadata") {
        let codes = ["MC", "CF", "DR", "CP", "A2", "T3", "AP"]
        var nodes: [[String: Any]] = []
        for (index, code) in codes.enumerated() {
            nodes.append(["id": "gid://gitlab/MergeRequest/\(index + 1)", "iid": "\(index + 1)", "title": "IR-6258 - Synthetic merge \(index)",
                          "webUrl": "https://git.example.com/a/web/-/merge_requests/\(index + 1)", "draft": code == "DR", "conflicts": code == "MC",
                          "updatedAt": "2026-08-30T09:12:00Z", "approvalsLeft": code == "A2" ? 2 : 0, "project": ["fullPath": "a/web"],
                          "headPipeline": ["status": code == "MC" || code == "CF" ? "FAILED" : code == "CP" ? "RUNNING" : "SUCCESS"],
                          "discussions": ["nodes": code == "T3" ? Array(repeating: ["resolvable": true, "resolved": false], count: 3) : []]])
        }
        var review = nodes[0]; review["id"] = "gid://gitlab/MergeRequest/8"; review["iid"] = "8"
        let body: [String: Any] = ["data": ["currentUser": ["mine": ["count": 7, "nodes": nodes], "reviewing": ["count": 1, "nodes": [review]]]]]
        let http = FakeHTTPClient([.success(.json(String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)))])
        let lab = WorkerRemoteAccount(id: "lab", label: "Lab", endpoint: "https://git.example.com", token: "offline-secret")
        let value = try await WorkerRemoteService(http: http).fetch(request(.mergeRequests, accounts: [lab]))
        try expectEqual(Set(value.rows.compactMap(\.statusCode)), Set(codes + ["RV"]))
        try expectEqual(Set(value.rows.prefix(2).compactMap(\.statusCode)), Set(["MC", "CF"]))
        try expectEqual(value.rows[2].statusCode, "RV")
        try expectEqual(value.blocked, 2); try expectEqual(value.reviewCount, 1)
        try expect(value.rows.allSatisfy { $0.ticketKey == "IR-6258" && $0.updatedAt != nil })
    }
    await run.test("GitHub conflict code wins over failed checks while a requested review remains RV") {
        let body = Fixtures.pullRequestSearch.replacingOccurrences(of: "\"number\": 412,", with: "\"number\": 412, \"mergeable\": \"CONFLICTING\",")
        let http = FakeHTTPClient([.success(.json(body))])
        let value = try await WorkerRemoteService(http: http).fetch(request())
        try expectEqual(value.rows.first?.statusCode, "MC")
        try expectEqual(value.rows.first(where: \.needsReview)?.statusCode, "RV")
    }
    await run.test("token verification asks only identity and returns no secret or identity fields") {
        let http = FakeHTTPClient([.success(.json("{\"data\":{\"viewer\":{\"login\":\"synthetic\"}}}"))])
        let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: http))
        let value = await worker.handle(try encoder.encode(WorkerRequest(id: "verify", operation: "remote.verify", remote: request())))
        try expect(value.error == nil && value.remote == nil)
        let sent = try expectNotNil(await http.request(at: 0), "identity request")
        let query = String(decoding: sent.body ?? Data(), as: UTF8.self)
        try expect(query.contains("viewer { login }"))
        try expect(!query.contains("search"))
        try expect(!String(decoding: encoder.encode(value), as: UTF8.self).contains("synthetic"))
    }
    await run.test("GitLab verification fails closed on anonymous identity and sanitizes error bodies") {
        let http = FakeHTTPClient([.success(.json("{\"data\":{\"currentUser\":null},\"errors\":[{\"message\":\"offline-secret\"}]}"))])
        let configured = WorkerRemoteAccount(id: "lab", label: "Lab", endpoint: "https://git.example.com", token: "offline-secret")
        let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: http))
        let value = await worker.handle(try encoder.encode(WorkerRequest(id: "verify", operation: "remote.verify", remote: request(.mergeRequests, accounts: [configured]))))
        try expectEqual(value.error?.code, "credentialsRejected")
        try expect(!String(decoding: encoder.encode(value), as: UTF8.self).contains("offline-secret"))
    }
    await run.test("Actions explicit account survives another account's missing fallback token") {
        let http = FakeHTTPClient(routes: [
            ("actions/runs", .success(.json(Fixtures.workflowRunsPrimary))),
            ("/repos/example/web", .success(.json("{\"default_branch\":\"main\"}")))
        ])
        let configured = WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://api.github.com", repositories: ["example/web"], token: "offline-secret")
        let missing = WorkerRemoteAccount(id: "missing", label: "Missing", endpoint: "https://api.github.com")
        let value = try await WorkerRemoteService(http: http).fetch(request(.actions, accounts: [configured, missing]))
        try expectEqual(value.rows.count, 4)
        try expectEqual(value.failures.first?.accountID, "missing")
    }
    await run.test("remote attention uses shared PR policy and review keys deduplicate with inbox") {
        let http = FakeHTTPClient([.success(.json(Fixtures.pullRequestSearch))])
        let value = try await WorkerRemoteService(http: http).fetch(request())
        try expectEqual(value.attention.filter { $0.kind == "review" }.count, 1)
        try expectEqual(value.attention.filter { $0.kind == "blocked" }.count, 2)
        try expect(value.attention.allSatisfy { $0.accountID == "work" })
        try expect(value.attention.first(where: { $0.kind == "review" })?.key.hasPrefix("github:review:https://") == true)
    }
    await run.test("mark-read patches only a validated thread for its supplied account") {
        let http = FakeHTTPClient([.success(HTTPResponse(statusCode: 205))])
        let remote = WorkerRemoteRequest(cardID: "github.inbox", kind: .inbox, accounts: [account], threadIDs: ["42"])
        try await WorkerRemoteService(http: http).markRead(remote, rest: false)
        let sent = try expectNotNil(await http.request(at: 0), "mark request")
        try expectEqual(sent.method.rawValue, "PATCH")
        try expectEqual(sent.url.absoluteString, "https://api.github.com/notifications/threads/42")
    }
    await run.test("mark-rest keeps mentions and review requests unread and skips already read rows") {
        let http = FakeHTTPClient([.success(.json(Fixtures.notifications)), .success(HTTPResponse(statusCode: 205))])
        let remote = WorkerRemoteRequest(cardID: "github.inbox", kind: .inbox, accounts: [account])
        try await WorkerRemoteService(http: http).markRead(remote, rest: true)
        try expectEqual(await http.requestCount, 2)
        try expectEqual((await http.request(at: 1))?.url.absoluteString, "https://api.github.com/notifications/threads/2")
    }
    await run.test("invalid notification IDs cannot redirect a mutation request") {
        let http = FakeHTTPClient([])
        let remote = WorkerRemoteRequest(cardID: "github.inbox", kind: .inbox, accounts: [account], threadIDs: ["../../other"])
        do { try await WorkerRemoteService(http: http).markRead(remote, rest: false); throw TestFailure(message: "Expected rejection", file: #filePath, line: #line) }
        catch let error as WorkerRemoteError { try expectEqual(error.code, "invalidRemote") }
        try expectEqual(await http.requestCount, 0)
    }
    await run.test("mark-all uses the shown timestamp on the selected account and invalidates cached inbox") {
        let cutoff = ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")!.timeIntervalSince1970
        let scoped = WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://api.github.com", token: "offline-secret", cacheScope: String(repeating: "A", count: 64))
        let http = FakeHTTPClient([.success(.json(Fixtures.notifications, headers: ["ETag": "before-read"])), .success(.status(205)), .success(.json("[]"))])
        let service = WorkerRemoteService(http: http)
        _ = try await service.fetch(request(.inbox, accounts: [scoped]))
        try await service.markAllRead(WorkerRemoteRequest(cardID: "github.inbox", kind: .inbox, accounts: [scoped], lastReadAt: cutoff))
        let sent = try expectNotNil(await http.request(at: 1), "mark all")
        try expectEqual(sent.method.rawValue, "PUT")
        try expectEqual(sent.url.absoluteString, "https://api.github.com/notifications")
        let body = try JSONSerialization.jsonObject(with: sent.body!) as! [String: Any]
        try expectEqual(body["last_read_at"] as? String, "2026-08-01T10:00:00Z")
        try expectEqual(body["read"] as? Bool, true)
        _ = try await service.fetch(request(.inbox, accounts: [scoped]))
        try expectEqual((await http.request(at: 2))?.headers["If-None-Match"], nil)
    }
    await run.test("mark-all rejects absent future negative cutoffs and ambiguous account scope before HTTP") {
        let http = FakeHTTPClient([]); let service = WorkerRemoteService(http: http)
        let cutoffs: [TimeInterval?] = [nil, -1, 0, Date().timeIntervalSince1970 + 3600]
        for cutoff in cutoffs {
            do { try await service.markAllRead(WorkerRemoteRequest(cardID: "github.inbox", kind: .inbox, accounts: [account], lastReadAt: cutoff)); throw TestFailure(message: "Expected invalid cutoff", file: #filePath, line: #line) }
            catch let error as WorkerRemoteError { try expectEqual(error.code, "invalidRemote") }
        }
        do { try await service.markAllRead(WorkerRemoteRequest(cardID: "github.inbox", kind: .inbox, accounts: [account, WorkerRemoteAccount(id: "second", label: "Second", endpoint: "https://api.github.com", token: "offline-secret")], lastReadAt: 1000)); throw TestFailure(message: "Expected ambiguous scope rejection", file: #filePath, line: #line) }
        catch let error as WorkerRemoteError { try expectEqual(error.code, "invalidRemote") }
        try expectEqual(await http.requestCount, 0)
    }
    await run.test("mark-all errors are sanitized and worker dispatch advertises the operation") {
        let http = FakeHTTPClient([.success(.json("offline-secret", status: 403))])
        let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: http))
        let response = await worker.handle(try encoder.encode(WorkerRequest(id: "read-all", operation: "remote.markAll", remote: WorkerRemoteRequest(cardID: "github.inbox", kind: .inbox, accounts: [account], lastReadAt: 1000))))
        try expectEqual(response.error?.code, "remoteActionFailed")
        try expect(!String(decoding: encoder.encode(response), as: UTF8.self).contains("offline-secret"))
        try expect(WorkerProtocol.capabilities.contains("remote.markAll"))
    }
}
