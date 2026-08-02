import DevDeckCore
import Foundation
import GitHubKit
import TestHarness

private func makeActionsClient(
    routes: [(String, Result<HTTPResponse, Error>)]
) -> (GitHubClient, FakeHTTPClient) {
    let http = FakeHTTPClient(routes: routes)
    let client = GitHubClient(
        transport: APITransport(client: http, retryPolicy: .none, sleeper: RecordingSleeper()),
        tokenStore: InMemoryTokenStore(tokens: [.github: "test-token"])
    )
    return (client, http)
}

func runActionsTests(_ run: TestRun) async {
    run.section("GitHub — actions")

    let settings = GitHubSettings(actionsRepositories: ["editoria/ledwall", "shumer/tools"])
    let (client, http) = makeActionsClient(routes: [
        ("editoria/ledwall", .success(.json(Fixtures.workflowRunsPrimary))),
        ("shumer/tools", .success(.json(Fixtures.workflowRunsSecondary))),
    ])
    let clock = MutableDateProvider(now: Date(timeIntervalSince1970: 1_785_000_000))
    let snapshot = try? await ActionsService(client: client, settings: settings, clock: clock).fetch()

    await run.test("runs from every repository land in one snapshot") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        try expectEqual(snapshot.runs.count, 5)
        try expectEqual(snapshot.repositories.count, 2)
        try expectEqual(snapshot.windowDays, 7)
    }

    await run.test("each repository is asked for separately and cached separately") {
        let request = try expectNotNil(await http.request(matching: "editoria/ledwall"), "request")
        try expect(request.url.absoluteString.contains("/repos/editoria/ledwall/actions/runs"))
        try expect(request.url.absoluteString.contains("per_page=50"))
        try expect(request.url.absoluteString.contains("created="))
        try expectEqual(request.cacheKey, "github.actions.default.editoria/ledwall")
    }

    await run.test("statuses and conclusions map to what the card draws") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        let byID = Dictionary(uniqueKeysWithValues: snapshot.runs.map { ($0.id, $0) })
        try expectEqual(byID[2]?.conclusion, .failure, "timed_out is a failure")
        try expectEqual(byID[3]?.conclusion, .cancelled)
        try expectEqual(byID[4]?.status, .inProgress)
        try expectEqual(byID[4]?.conclusion, RunConclusion.none)
        try expectNil(byID[4]?.durationSeconds, "an unfinished run has no duration")
        try expectEqual(byID[1]?.durationSeconds, 360)
    }

    await run.test("a run without run_started_at falls back to created_at") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        let running = try expectNotNil(snapshot.runs.first { $0.id == 4 }, "running run")
        try expectEqual(running.startedAt, ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z"))
    }

    await run.test("success rate ignores runs that decided nothing") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        // Decisive: two successes and one failure. Cancelled and in-progress are excluded.
        let rate = try expectNotNil(snapshot.successRate, "success rate")
        try expectEqual((rate * 100).rounded(), 67)
        try expectEqual(snapshot.failedCount, 1)
        try expectEqual(snapshot.runningCount, 1)
    }

    await run.test("no decisive runs means no rate rather than zero percent") {
        let empty = ActionsSnapshot(
            runs: [],
            windowDays: 7,
            repositories: ["editoria/ledwall"]
        )
        try expectNil(empty.successRate, "an idle week is not a failing week")
        try expectNil(empty.averageDurationSeconds)
    }

    await run.test("failures come first and newest first") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        try expectEqual(snapshot.recentFailures().map(\.id), [2])
        try expectEqual(snapshot.active().map(\.id), [4])
    }

    await run.test("average duration is measured over finished runs only") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        // 360s, 600s, 60s, 240s — the in-progress run contributes nothing.
        try expectEqual(snapshot.averageDurationSeconds, 315)
    }

    run.section("GitHub — actions failure handling")

    await run.test("one unreachable repository does not blank the card") {
        let (client, _) = makeActionsClient(routes: [
            ("editoria/ledwall", .success(.json(Fixtures.workflowRunsPrimary))),
            ("shumer/gone", .failure(APIError.notFound)),
        ])
        let settings = GitHubSettings(actionsRepositories: ["editoria/ledwall", "shumer/gone"])
        let snapshot = try await ActionsService(client: client, settings: settings).fetch()
        try expectEqual(snapshot.runs.count, 4, "the healthy repository still reports")
    }

    await run.test("when every repository fails the error surfaces") {
        let (client, _) = makeActionsClient(routes: [
            ("editoria", .failure(APIError.forbidden("SAML"))),
            ("shumer", .failure(APIError.forbidden("SAML"))),
        ])
        let settings = GitHubSettings(actionsRepositories: ["editoria/ledwall", "shumer/tools"])
        let error = try await expectThrows {
            _ = try await ActionsService(client: client, settings: settings).fetch()
        }
        try expectEqual(error as? APIError, .forbidden("SAML"))
    }

    await run.test("no repositories means no requests at all") {
        let (client, http) = makeActionsClient(routes: [])
        let snapshot = try await ActionsService(client: client, settings: GitHubSettings()).fetch()
        try expect(snapshot.repositories.isEmpty)
        try expectEqual(await http.requestCount, 0, "an unconfigured card must not poll")
    }

    await run.test("the window start is a plain UTC date") {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        try expectEqual(ActionsService.windowStart(from: now, days: 7), "2026-07-18")
        try expectEqual(ActionsService.windowStart(from: now, days: 1), "2026-07-24")
    }
}
