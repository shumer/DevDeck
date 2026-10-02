import DevDeckCore
import DevDeckWorkerProtocol
import Foundation
import TestHarness

/// Portable-only old producer regression fixtures. Every HTTP request is intercepted by the
/// owned actor below; no URLSession, provider, socket, user token or persistent credential is used.
/// The current action contract stays Void/throws: no per-thread receipt is inferred from RPC.
func runWorkerRemoteCompletenessTests(_ run: TestRun) async {
    run.section("WSL remote completeness")

    await run.test("actual rest producer admits six held PATCHs and attempts every eligible thread once") {
        let result = try await remoteCompletenessScenario(refusedID: nil)
        try expectEqual(result.outcome, .succeeded, "all-success current action outcome")
        try expectEqual(Set(result.final.patchIDs), Set(remoteCompletenessEligibleIDs), "exact eligible target set")
        try expect(result.final.patchCounts.values.allSatisfy { $0 == 1 }, "each eligible thread must be attempted exactly once")
        try expectEqual(result.final.statuses.count, 9, "every fake PATCH completed")
        try expect(result.final.statuses.values.allSatisfy { $0 == 205 }, "all-success fake responses stay successful")
        try expectEqual(result.progress, ["gathering"] + (1...9).map { "marking:\($0):9" }, "all-success completion progress")
        print("  premises: admitted owned account; fetch rows13/personal3/read1; GET2; PATCH9 exact; success9; old held=\(result.held.active)")
        try expectEqual(result.held.active, 6, "original six-concurrent rest invariant")
        try expectEqual(result.held.held, 6, "exact six owned held PATCH continuations")
        try expectEqual(result.final.peak, 6, "bounded six-request ceiling")
    }

    await run.test("actual rest producer collects first403 and still attempts later205 threads through total progress") {
        let result = try await remoteCompletenessScenario(refusedID: "1")
        // Keep the existing sanitized Void/error boundary. The fake actor, not an invented RPC
        // result, independently knows which HTTP calls were refused or completed successfully.
        try expectEqual(result.outcome, .remoteFailure("remoteActionFailed"), "sanitized partial-read action error")
        try expectEqual(result.final.statuses["1"], 403, "the earliest eligible fake thread was refused")
        print("  premises: admitted owned account; fetch rows13/personal3/read1; GET2; earliest403 completed; PATCH attempts=\(result.final.patchIDs.count)")
        try expectEqual(Set(result.final.patchIDs), Set(remoteCompletenessEligibleIDs), "first refusal must not skip later eligible threads")
        try expect(result.final.patchCounts.values.allSatisfy { $0 == 1 }, "partial refusal must not retry any owned thread")
        try expectEqual(result.final.statuses.count, 9, "all nine attempted fake replies were collected")
        try expectEqual(result.final.statuses.filter { $0.key != "1" && $0.value == 205 }.count, 8, "later eligible threads still complete")
        try expectEqual(result.progress, ["gathering"] + (1...9).map { "marking:\($0):9" }, "partial-refusal completion progress reaches total")
        try expectEqual(result.held.active, 6, "partial-refusal batch also admits exactly six")
        try expectEqual(result.final.peak, 6, "partial-refusal batch remains bounded to six")
    }

    await run.test("actual rest cancellation admits no later delegated HTTP and reaps its held wave") {
        try await remoteCompletenessCancellationScenario()
    }
}

private let remoteCompletenessEligibleIDs = (1...9).map(String.init)
private let remoteCompletenessPersonalIDs: Set<String> = ["101", "102", "103"]
private let remoteCompletenessToken = "owned-synthetic-not-a-provider-token"

private enum RemoteCompletenessOutcome: Sendable, Equatable {
    case succeeded
    case remoteFailure(String)
    case unexpectedFailure
}

private struct RemoteCompletenessCapture: Sendable {
    let active: Int
    let peak: Int
    let held: Int
    let gets: Int
    let patchIDs: [String]
    let patchCounts: [String: Int]
    let statuses: [String: Int]
    let routesValid: Bool
}

private struct RemoteCompletenessResult: Sendable {
    let held: RemoteCompletenessCapture
    let final: RemoteCompletenessCapture
    let outcome: RemoteCompletenessOutcome
    let progress: [String]
}

/// Owns every route and releases its first wave only when the fixture asks. Nine eligible
/// threads make both the first-six ceiling and replenishment after completion observable.
private actor RemoteCompletenessHTTP: HTTPClient {
    private let body: Data
    private let refusedID: String?
    private var released = false
    private var active = 0
    private var peak = 0
    private var gets = 0
    private var patchIDs: [String] = []
    private var patchCounts: [String: Int] = [:]
    private var statuses: [String: Int] = [:]
    private var routesValid = true
    private var held: [String: CheckedContinuation<Void, any Error>] = [:]

    init(body: Data, refusedID: String?) {
        self.body = body
        self.refusedID = refusedID
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try Task.checkCancellation()
        let originMatches = request.url.scheme == "https" && request.url.host == "api.github.com"
            && request.url.port == nil && request.url.user == nil && request.url.password == nil
        let credentialMatches = request.headers["Authorization"] == "bearer " + remoteCompletenessToken
        routesValid = routesValid && originMatches && credentialMatches
        if request.method == .get && request.url.path == "/notifications" {
            gets += 1
            let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let all = query.first { $0.name == "all" }?.value
            let perPage = query.first { $0.name == "per_page" }?.value
            let page = query.first { $0.name == "page" }?.value
            routesValid = routesValid && all == "false" && perPage == "50"
                && (gets == 1 ? page == nil : page == "1")
                && gets <= 2 && request.body == nil
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
        }
        guard request.method == .patch && request.url.path.hasPrefix("/notifications/threads/") else {
            routesValid = false
            throw APIError.notFound
        }
        let id = String(request.url.path.dropFirst("/notifications/threads/".count))
        routesValid = routesValid && remoteCompletenessEligibleIDs.contains(id)
            && request.url.query == nil && request.url.fragment == nil && request.body == nil
        patchIDs.append(id)
        patchCounts[id, default: 0] += 1
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        if !released {
            try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    held[id] = continuation
                }
            }, onCancel: {
                Task { await self.cancel(id) }
            })
        }
        try Task.checkCancellation()
        let status = id == refusedID ? 403 : 205
        statuses[id] = status
        return HTTPResponse(statusCode: status, headers: ["Content-Type": "application/json"],
            body: status == 403 ? Data(#"{"message":"Owned notification permission refusal"}"#.utf8) : Data())
    }

    private func cancel(_ id: String) {
        held.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    func releaseAll() {
        released = true
        let current = Array(held.values)
        held.removeAll()
        for continuation in current { continuation.resume() }
    }

    func close() {
        released = true
        let current = Array(held.values)
        held.removeAll()
        for continuation in current { continuation.resume(throwing: CancellationError()) }
    }

    func capture() -> RemoteCompletenessCapture {
        RemoteCompletenessCapture(active: active, peak: peak, held: held.count, gets: gets,
            patchIDs: patchIDs, patchCounts: patchCounts, statuses: statuses, routesValid: routesValid)
    }
}

private func remoteCompletenessBody() throws -> Data {
    func row(_ id: String, reason: String, unread: Bool = true) -> [String: Any] {
        ["id": id, "unread": unread, "reason": reason, "updated_at": "2026-08-01T10:00:00Z",
         "subject": ["title": "Owned synthetic notification", "url": NSNull(), "type": "CheckSuite"],
         "repository": ["full_name": "owned/repository"]]
    }
    let rows = remoteCompletenessEligibleIDs.map { row($0, reason: "ci_activity") } + [
        row("101", reason: "mention"), row("102", reason: "review_requested"),
        row("103", reason: "security_alert"), row("104", reason: "ci_activity", unread: false),
    ]
    return try JSONSerialization.data(withJSONObject: rows)
}

private func remoteCompletenessScenario(refusedID: String?) async throws -> RemoteCompletenessResult {
    let http = RemoteCompletenessHTTP(body: try remoteCompletenessBody(), refusedID: refusedID)
    let service = WorkerRemoteService(http: http)
    let account = WorkerRemoteAccount(id: "owned", label: "Owned synthetic account",
        endpoint: "https://api.github.com", token: remoteCompletenessToken,
        cacheScope: String(repeating: "A", count: 64))
    let request = WorkerRemoteRequest(cardID: "owned.inbox.completeness", kind: .inbox, accounts: [account])
    let admitted = try await service.fetch(request)
    // These are before the action: the actual old producer has already validated and decoded
    // the supplied account/token/request through this fake HTTP client. No future API needed.
    try expectEqual(admitted.rows.count, 13, "positive decoded fixture rows")
    try expectEqual(admitted.total, 12, "positive unread count")
    try expectEqual(admitted.actionableCount, 3, "positive personal reason count")
    try expectEqual(Set(admitted.rows.filter { $0.isUnread && $0.health == "ready" }.map(\.id)),
        Set(remoteCompletenessEligibleIDs), "positive exact rest eligibility")
    try expectEqual(Set(admitted.rows.filter { $0.isUnread && $0.health == "attention" }.map(\.id)),
        remoteCompletenessPersonalIDs, "positive excluded personal reasons")
    try expectEqual(admitted.rows.filter { !$0.isUnread }.map(\.id), ["104"], "positive excluded already-read row")
    try expect(admitted.failures.isEmpty && admitted.kind == .inbox && admitted.cardID == request.cardID,
        "positive action card/account admission")
    let initial = await http.capture()
    try expect(initial.gets == 1 && initial.patchIDs.isEmpty && initial.routesValid,
        "positive exact fake GET/account authentication before any mark")

    let progress = Box<[String]>([])
    let completion = Box<RemoteCompletenessOutcome?>(nil)
    let task = Task {
        do {
            try await service.markRead(request, rest: true, onProgress: { value in
                progress.mutate { $0.append(value) }
            })
            completion.mutate { $0 = .succeeded }
        } catch let error as WorkerRemoteError {
            completion.mutate { $0 = .remoteFailure(error.code) }
        } catch {
            completion.mutate { $0 = .unexpectedFailure }
        }
    }
    do {
        try expect(await remoteCompletenessWait(for: .seconds(2)) { (await http.capture()).held >= 1 },
            "positive actual rest producer never reached its first held PATCH")
        let first = await http.capture()
        try expect(first.gets == 2 && first.routesValid && first.active >= 1 && first.held >= 1
            && completion.value == nil && progress.value == ["gathering"],
            "positive admitted gathering/held action must precede concurrency/refusal assertions")
        // Old sequential source reaches exactly one, then stays admitted/held. Returning false
        // here is data for the acceptance assertion, not an unbounded wait or timeout-red.
        _ = await remoteCompletenessWait(for: .milliseconds(750)) { (await http.capture()).held >= 6 }
        let held = await http.capture()
        try expect(held.active >= 1 && held.held >= 1 && held.routesValid && completion.value == nil,
            "positive fake held requests must survive until explicit release")
        await http.releaseAll()
        try expect(await remoteCompletenessWait(for: .seconds(2)) { completion.value != nil },
            "owned rest action did not complete after every held fake response was released")
        await task.value
        let final = await http.capture()
        try expect(final.gets == 2 && final.routesValid && final.active == 0 && final.held == 0,
            "owned action completion changed fake routes or leaked held requests")
        let outcome = try expectNotNil(completion.value, "owned action outcome")
        await http.close()
        return RemoteCompletenessResult(held: held, final: final, outcome: outcome, progress: progress.value)
    } catch {
        task.cancel()
        await http.close()
        if await remoteCompletenessWait(for: .seconds(2), { completion.value != nil }) {
            await task.value
        }
        throw error
    }
}

/// Fixture-only bounded coordination. This never invokes API retry Sleeper or real network.
/// Deadline expiration while collecting the first-six wave is observed metadata, not a
/// process timeout or an intended exception from the helper itself.
private func remoteCompletenessWait(for duration: Duration,
    _ predicate: @escaping @Sendable () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: duration)
    while clock.now < deadline {
        if await predicate() { return true }
        do { try await Task.sleep(for: .milliseconds(2)) }
        catch { return false }
    }
    return await predicate()
}

/// Count delegation before the inner fake checks cancellation. Without worker admission,
/// cancelled bulk children would still reach this seam even though the inner fake refuses them.
private actor RemoteCompletenessDelegationHTTP: HTTPClient {
    let base: RemoteCompletenessHTTP
    private var delegated: [String] = []

    init(base: RemoteCompletenessHTTP) { self.base = base }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        delegated.append(request.method.rawValue + " " + request.url.absoluteString)
        return try await base.send(request)
    }

    func capture() -> [String] { delegated }
}

private func remoteCompletenessCancellationScenario() async throws {
    let http = RemoteCompletenessHTTP(body: try remoteCompletenessBody(), refusedID: nil)
    let delegated = RemoteCompletenessDelegationHTTP(base: http)
    let service = WorkerRemoteService(http: delegated)
    let account = WorkerRemoteAccount(id: "owned", label: "Owned synthetic account",
        endpoint: "https://api.github.com", token: remoteCompletenessToken,
        cacheScope: String(repeating: "A", count: 64))
    let request = WorkerRemoteRequest(cardID: "owned.inbox.completeness.cancel", kind: .inbox, accounts: [account])
    let admitted = try await service.fetch(request)
    try expect(admitted.rows.count == 13 && admitted.total == 12 && admitted.actionableCount == 3
        && admitted.failures.isEmpty && admitted.cardID == request.cardID && admitted.kind == .inbox,
        "cancellation fixture must first admit its actual account/token/inbox through fake HTTP")
    try expectEqual(Set(admitted.rows.filter { $0.isUnread && $0.health == "ready" }.map(\.id)),
        Set(remoteCompletenessEligibleIDs), "cancellation exact eligible rest targets")
    try expectEqual(Set(admitted.rows.filter { $0.isUnread && $0.health == "attention" }.map(\.id)),
        remoteCompletenessPersonalIDs, "cancellation excludes personal threads")
    try expectEqual(admitted.rows.filter { !$0.isUnread }.map(\.id), ["104"], "cancellation excludes read threads")
    let progress = Box<[String]>([])
    let completion = Box<RemoteCompletenessOutcome?>(nil)
    let task = Task {
        do {
            try await service.markRead(request, rest: true, onProgress: { value in
                progress.mutate { $0.append(value) }
            })
            completion.mutate { $0 = .succeeded }
        } catch let error as WorkerRemoteError {
            completion.mutate { $0 = .remoteFailure(error.code) }
        } catch {
            completion.mutate { $0 = .unexpectedFailure }
        }
    }
    do {
        try expect(await remoteCompletenessWait(for: .seconds(2)) { (await http.capture()).held >= 1 },
            "cancellation must positively hold an actual admitted PATCH before cancelling")
        // Old serial and new bulk implementations both have a positively held initial wave.
        // Its exact size belongs to the other regression tests, not the cancellation contract.
        _ = await remoteCompletenessWait(for: .milliseconds(750)) { (await http.capture()).held >= 6 }
        let held = await http.capture()
        let before = await delegated.capture()
        try expect(held.gets == 2 && held.routesValid && held.active >= 1 && held.active <= 6
            && held.held == held.active && held.patchIDs.count == held.active && held.statuses.isEmpty
            && completion.value == nil && progress.value == ["gathering"]
            && before.count == held.patchIDs.count + 2,
            "cancellation requires exact GET/filter/auth plus pending owned PATCH delegation premises")
        task.cancel()
        try expect(await remoteCompletenessWait(for: .seconds(2)) { completion.value != nil },
            "cancelled owned action did not finish and reap its held responses")
        await task.value
        let final = await http.capture()
        let after = await delegated.capture()
        try expectEqual(completion.value, .remoteFailure("remoteActionFailed"), "cancelled service keeps sanitized Void/error boundary")
        try expectEqual(after, before, "cancellation must not delegate any later HTTP request")
        try expectEqual(final.patchIDs, held.patchIDs, "cancellation must not admit later eligible PATCHs")
        try expect(final.gets == 2 && final.routesValid && final.active == 0 && final.held == 0
            && final.statuses.isEmpty && final.patchCounts.values.allSatisfy { $0 == 1 },
            "cancellation must reap all held continuations without completing or retrying a fake PATCH")
        await http.close()
    } catch {
        task.cancel()
        await http.close()
        if await remoteCompletenessWait(for: .seconds(2), { completion.value != nil }) {
            await task.value
        }
        throw error
    }
}
