import DevDeckCore
import Foundation
import GitHubKit
import TestHarness

private func makeClient(
    responses: [Result<HTTPResponse, Error>],
    token: String? = "test-token"
) -> (GitHubClient, FakeHTTPClient) {
    let http = FakeHTTPClient(responses)
    let tokens = InMemoryTokenStore(tokens: token.map { [TokenKey.github: $0] } ?? [:])
    let client = GitHubClient(
        transport: APITransport(client: http, retryPolicy: .none, sleeper: RecordingSleeper()),
        tokenStore: tokens
    )
    return (client, http)
}

func runGitHubTests(_ run: TestRun) async {
    run.section("GitHub — search query")

    await run.test("the default query asks for my open pull requests") {
        let query = PullRequestsService.searchQuery(settings: .default)
        try expect(query.contains("is:open"))
        try expect(query.contains("is:pr"))
        try expect(query.contains("author:@me"))
        try expect(query.contains("archived:false"))
        try expect(!query.contains("draft:false"), "drafts are included by default")
    }

    await run.test("settings narrow the query") {
        let settings = GitHubSettings(includeDrafts: false, organizations: ["editoria", "shumer"])
        let query = PullRequestsService.searchQuery(settings: settings)
        try expect(query.contains("draft:false"))
        try expect(query.contains("org:editoria"))
        try expect(query.contains("org:shumer"))
    }

    run.section("GitHub — pull request decoding")

    let (client, http) = makeClient(responses: [.success(.json(Fixtures.pullRequestSearch))])
    let snapshot = try? await PullRequestsService(client: client).fetch()

    await run.test("the response decodes into a snapshot") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        try expectEqual(snapshot.totalCount, 8,
                        "seven of mine reported by the server, plus the one waiting on my review")
        try expectEqual(snapshot.pullRequests.count, 5, "the non-pull-request node is dropped")
        try expectEqual(snapshot.repositoryCount, 3)
        try expectEqual(snapshot.organizationCount, 2)
    }

    await run.test("the request is a POST to /graphql with a bearer token") {
        let request = try expectNotNil(await http.request(at: 0), "request")
        try expectEqual(request.method, .post)
        try expectEqual(request.url.absoluteString, "https://api.github.com/graphql")
        try expectEqual(request.headers["Authorization"], "bearer test-token")
        try expectNil(request.cacheKey, "a GraphQL POST must not carry an ETag")
    }

    await run.test("health is derived from checks, review and threads") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        let byID = Dictionary(uniqueKeysWithValues: snapshot.pullRequests.map { ($0.id, $0) })

        let failing = try expectNotNil(byID["PR_failing"], "failing PR")
        try expectEqual(failing.checks, .failure)
        try expectEqual(failing.unresolvedThreads, 2, "resolved threads do not count")
        try expectEqual(failing.health, .blocked)
        try expectEqual(failing.statusLine, "checks failed")
        try expectEqual(failing.statusCode, "CF")

        let changes = try expectNotNil(byID["PR_changes"], "changes-requested PR")
        try expectEqual(changes.reviewDecision, .changesRequested)
        try expectEqual(changes.health, .blocked, "green checks do not rescue a rejected review")
        try expectEqual(changes.statusLine, "changes requested")

        let ready = try expectNotNil(byID["PR_ready"], "ready PR")
        try expectEqual(ready.health, .ready)
        try expectEqual(ready.statusLine, "approved")
        try expectEqual(ready.shortLabel, "tools #5")

        let draft = try expectNotNil(byID["PR_draft"], "draft PR")
        try expectEqual(draft.checks, .none, "a commit with no rollup has no check state")
        try expectEqual(draft.health, .attention)
        try expectEqual(draft.statusLine, "draft")
    }

    await run.test("a review someone is waiting on is carried, and marked as theirs") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        let review = try expectNotNil(
            snapshot.pullRequests.first { $0.isReviewRequest }, "the review request"
        )
        try expectEqual(review.id, "PR_review")
        try expectEqual(review.statusCode, "RV")
        try expectEqual(review.statusLine, "waiting for your review")
        try expectEqual(review.health, .attention, "approved and green, but you still owe it")
        try expectEqual(snapshot.reviewRequestCount, 1)
        try expectEqual(review.ticket.key, "IW-164", "the ticket key is split out as on any row")
    }

    await run.test("rows are ordered worst first, and a review owed outranks my own work") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        try expectEqual(snapshot.prioritized().map(\.id),
                        ["PR_failing", "PR_changes", "PR_review", "PR_draft", "PR_ready"])
        try expectEqual(snapshot.prioritized(limit: 2).map(\.id), ["PR_failing", "PR_changes"])
        try expectEqual(snapshot.blockedCount, 2)
        try expectEqual(snapshot.readyCount, 1)
    }

    await run.test("the two searches go out together, and both are asked for") {
        let request = try expectNotNil(await http.request(at: 0), "request")
        let body = String(decoding: request.body ?? Data(), as: UTF8.self)
        try expect(body.contains("author:@me"), "mine")
        try expect(body.contains("review-requested:@me"), "and what is waiting on me")
        try expectEqual(await http.requestCount, 1, "one round trip, not two")
    }

    await run.test("a pull request answering both searches is counted once, as mine") {
        let (client, _) = makeClient(responses: [.success(.json(Fixtures.pullRequestOverlap))])
        let snapshot = try expectNotNil(try? await PullRequestsService(client: client).fetch(), "snapshot")
        try expectEqual(snapshot.pullRequests.count, 1)
        try expect(!snapshot.pullRequests[0].isReviewRequest, "yours wins the tie")
        try expectEqual(snapshot.totalCount, 1)
    }

    await run.test("switching review requests off stops asking for them") {
        var settings = GitHubSettings.default
        settings.includesReviewRequests = false
        let query = PullRequestsService.reviewQuery(settings: settings)
        try expect(!query.contains("review-requested"), "nothing is asked for")
        try expect(!query.isEmpty, "and the query is still valid — GitHub rejects an empty one")
    }

    run.section("GitHub — API mapping")

    await run.test("status codes mirror the wording they abbreviate") {
        func make(
            draft: Bool = false,
            review: ReviewDecision = .none,
            checks: CheckState = .success,
            threads: Int = 0
        ) -> PullRequestSummary {
            PullRequestSummary(
                id: "x", number: 1, title: "x", repository: "o/r", organization: "o",
                url: URL(string: "https://github.com/o/r/pull/1")!,
                isDraft: draft, updatedAt: Date(timeIntervalSince1970: 0),
                reviewDecision: review, checks: checks, unresolvedThreads: threads
            )
        }

        try expectEqual(make(checks: .failure).statusCode, "CF")
        try expectEqual(make(review: .changesRequested).statusCode, "CR")
        try expectEqual(make(draft: true).statusCode, "DR")
        try expectEqual(make(checks: .pending).statusCode, "CP")
        try expectEqual(make(threads: 3).statusCode, "T3")
        try expectEqual(make(threads: 40).statusCode, "T9", "the code stays two characters wide")
        try expectEqual(make(review: .approved).statusCode, "AP")
        try expectEqual(make().statusCode, "WR")

        // A code that disagrees with the tooltip beside it is worse than either alone.
        try expectEqual(make(checks: .failure).statusLine, "checks failed")
        try expectEqual(make(threads: 3).statusLine, "3 unresolved threads")
        try expectEqual(make().statusLine, "waiting for review")
    }

    await run.test("check states collapse ERROR into failure") {
        try expectEqual(CheckState(apiValue: "ERROR"), .failure)
        try expectEqual(CheckState(apiValue: "EXPECTED"), .pending)
        try expectEqual(CheckState(apiValue: nil), .none)
        try expectEqual(ReviewDecision(apiValue: "REVIEW_REQUIRED"), .reviewRequired)
        try expectEqual(ReviewDecision(apiValue: "something new"), .none)
    }

    await run.test("GraphQL errors surface instead of an empty card") {
        let (client, _) = makeClient(responses: [.success(.json(Fixtures.graphQLErrors))])
        let error = try await expectThrows {
            _ = try await PullRequestsService(client: client).fetch()
        }
        guard case .graphQL(let messages)? = error as? APIError else {
            throw TestFailure(message: "expected a graphQL error, got \(error)", file: #filePath, line: #line)
        }
        try expect(messages.first?.contains("OIDC access restrictions") == true)
    }

    await run.test("a missing token is reported before any request is sent") {
        let (client, http) = makeClient(responses: [], token: nil)
        let error = try await expectThrows {
            _ = try await PullRequestsService(client: client).fetch()
        }
        try expectEqual(error as? APIError, .missingToken("GitHub"))
        try expectEqual(await http.requestCount, 0)
    }

    await run.test("an unauthorized token maps to a readable message") {
        let (client, _) = makeClient(responses: [.success(.status(401))])
        let error = try await expectThrows {
            _ = try await PullRequestsService(client: client).fetch()
        }
        try expectEqual(error as? APIError, .unauthorized)
        try expectEqual((error as? APIError)?.displayMessage, "Token rejected")
    }
}
