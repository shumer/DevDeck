import DevDeckCore
import Foundation
import GitLabKit
import TestHarness

private let account = GitLabAccount(id: "work", label: "Work", host: URL(string: "https://git.acme.io")!)

private func makeClient(
    responses: [Result<HTTPResponse, Error>],
    token: String? = "glpat-test"
) -> (GitLabClient, FakeHTTPClient) {
    let http = FakeHTTPClient(responses)
    let tokens = InMemoryTokenStore(tokens: token.map { [account.tokenKey: $0] } ?? [:])
    let client = GitLabClient(
        transport: APITransport(client: http, retryPolicy: .none, sleeper: RecordingSleeper()),
        tokenStore: tokens,
        account: account
    )
    return (client, http)
}

/// One answer covering every row the card can draw: a failing pipeline, a conflict, a draft,
/// one that needs approvals, one that is ready, and one waiting on my review.
private let payload = """
{
  "data": {
    "currentUser": {
      "mine": {
        "count": 9,
        "nodes": [
          {
            "id": "gid://gitlab/MergeRequest/1",
            "iid": "41",
            "title": "IR-6257 - Drop the legacy poller",
            "webUrl": "https://git.acme.io/acme/web/-/merge_requests/41",
            "draft": false,
            "conflicts": false,
            "updatedAt": "2026-08-30T09:12:44.123Z",
            "approvalsLeft": 0,
            "project": { "fullPath": "acme/web" },
            "headPipeline": { "status": "FAILED" },
            "discussions": { "nodes": [
              { "resolvable": true, "resolved": false },
              { "resolvable": true, "resolved": true },
              { "resolvable": false, "resolved": null }
            ] }
          },
          {
            "id": "gid://gitlab/MergeRequest/2",
            "iid": "42",
            "title": "Rebase onto main",
            "webUrl": "https://git.acme.io/acme/web/-/merge_requests/42",
            "draft": false,
            "conflicts": true,
            "updatedAt": "2026-08-30T08:00:00Z",
            "approvalsLeft": 1,
            "project": { "fullPath": "acme/web" },
            "headPipeline": { "status": "SUCCESS" },
            "discussions": { "nodes": [] }
          },
          {
            "id": "gid://gitlab/MergeRequest/3",
            "iid": "7",
            "title": "Spike: new importer",
            "webUrl": "https://git.acme.io/acme/tools/-/merge_requests/7",
            "draft": true,
            "conflicts": false,
            "updatedAt": "2026-08-29T17:30:00Z",
            "approvalsLeft": 0,
            "project": { "fullPath": "acme/tools" },
            "headPipeline": { "status": "RUNNING" },
            "discussions": { "nodes": [] }
          },
          {
            "id": "gid://gitlab/MergeRequest/4",
            "iid": "8",
            "title": "Cache the site index",
            "webUrl": "https://git.acme.io/acme/tools/-/merge_requests/8",
            "draft": false,
            "conflicts": false,
            "updatedAt": "2026-08-29T12:00:00Z",
            "approvalsLeft": 0,
            "project": { "fullPath": "acme/tools" },
            "headPipeline": { "status": "SUCCESS" },
            "discussions": { "nodes": [] }
          },
          {
            "id": "gid://gitlab/MergeRequest/5",
            "iid": "9",
            "title": "Missing everything"
          }
        ]
      },
      "reviewing": {
        "count": 1,
        "nodes": [
          {
            "id": "gid://gitlab/MergeRequest/6",
            "iid": "12",
            "title": "Bump the base image",
            "webUrl": "https://other.example/infra/images/-/merge_requests/12",
            "draft": false,
            "conflicts": false,
            "updatedAt": "2026-08-30T10:00:00Z",
            "approvalsLeft": 2,
            "project": { "fullPath": "infra/images" },
            "headPipeline": { "status": "SUCCESS" },
            "discussions": { "nodes": [] }
          }
        ]
      }
    }
  }
}
"""

func runGitLabTests(_ run: TestRun) async {
    run.section("GitLab - merge request decoding")

    let (client, http) = makeClient(responses: [.success(.json(payload))])
    let snapshot = try? await MergeRequestsService(client: client, accountID: account.id).fetch()

    await run.test("the response decodes into a snapshot") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        try expectEqual(snapshot.totalCount, 10, "nine of mine reported by the server, plus one to review")
        try expectEqual(snapshot.mergeRequests.count, 5, "the node with nothing in it is dropped")
        try expectEqual(snapshot.projectCount, 3)
        try expectEqual(snapshot.groupCount, 2, "acme and infra")
        try expectEqual(snapshot.reviewRequestCount, 1)
    }

    await run.test("the request is a POST to the instance's own graphql endpoint") {
        let request = try expectNotNil(await http.request(at: 0), "request")
        try expectEqual(request.method, .post)
        try expectEqual(request.url.absoluteString, "https://git.acme.io/api/graphql",
                        "the host is per account, because GitLab is routinely self-hosted")
        try expectEqual(request.headers["Authorization"], "Bearer glpat-test")
        try expectNil(request.cacheKey, "a GraphQL POST must not carry an ETag")
    }

    await run.test("health is derived from the pipeline, conflicts and approvals") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        let byID = Dictionary(uniqueKeysWithValues: snapshot.mergeRequests.map { ($0.id, $0) })

        let failing = try expectNotNil(byID["gid://gitlab/MergeRequest/1"], "failing")
        try expectEqual(failing.pipeline, .failed)
        try expectEqual(failing.unresolvedThreads, 1,
                        "resolved threads do not count, and neither do unresolvable ones")
        try expectEqual(failing.health, .blocked)
        try expectEqual(failing.statusCode, "CI")
        try expectEqual(failing.ticket.key, "IR-6257", "the ticket key gets its own column")

        let conflicted = try expectNotNil(byID["gid://gitlab/MergeRequest/2"], "conflicted")
        try expectEqual(conflicted.health, .blocked, "a green pipeline does not rescue a conflict")
        try expectEqual(conflicted.statusCode, "CF")

        let draft = try expectNotNil(byID["gid://gitlab/MergeRequest/3"], "draft")
        try expectEqual(draft.health, .attention, "a draft is unfinished, not stuck")
        try expectEqual(draft.statusCode, "DR")

        let ready = try expectNotNil(byID["gid://gitlab/MergeRequest/4"], "ready")
        try expectEqual(ready.health, .ready)
        try expectEqual(ready.statusCode, "ok")
        try expectEqual(ready.shortLabel, "acme/tools!8", "GitLab writes it with a bang")

        let reviewing = try expectNotNil(byID["gid://gitlab/MergeRequest/6"], "review request")
        try expect(reviewing.isReviewRequest)
        try expectEqual(reviewing.statusCode, "2ap")
        try expectEqual(reviewing.statusLine, "pipeline passed, 2 approvals left")
    }

    await run.test("rows are ordered worst first, with a review request just under them") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        let order = snapshot.prioritized().map(\.iid)
        try expectEqual(Array(order.prefix(2)), [41, 42], "the two blocked ones lead")
        try expectEqual(order[2], 12, "then the one somebody is waiting on you for")
        try expectEqual(order.last, 8, "and the one that is ready needs you least")
    }

    await run.test("a timestamp is read whether or not it carries fractional seconds") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        let withFraction = snapshot.mergeRequests.first { $0.iid == 41 }
        let without = snapshot.mergeRequests.first { $0.iid == 42 }
        _ = try expectNotNil(withFraction, "fractional")
        _ = try expectNotNil(without, "plain")
        try expect(
            (withFraction?.updatedAt ?? .distantPast) > (without?.updatedAt ?? .distantFuture),
            "both shapes appear across GitLab versions, and both have to parse"
        )
    }

    run.section("GitLab - accounts")

    await run.test("an instance keeps its own token key and its own endpoint") {
        try expectEqual(GitLabAccount.default.tokenKey.account, "gitlab")
        try expectEqual(account.tokenKey.account, "gitlab.work")
        try expectEqual(account.graphQLURL.absoluteString, "https://git.acme.io/api/graphql")
        try expectEqual(account.displayHost, "git.acme.io")
    }

    await run.test("nothing configured means no GitLab at all") {
        let store = GitLabAccountsStore(backend: InMemoryPreferences())
        try expect(store.accounts().isEmpty,
                   "unlike GitHub's, which always answers with a default: GitLab is opt-in")

        store.save([account, GitLabAccount(id: "off", label: "Old", isEnabled: false)])
        try expectEqual(store.accounts().count, 2)
        try expectEqual(store.enabledAccounts().map(\.id), ["work"])
    }

    await run.test("two instances are merged into one card, and one failing does not empty it") {
        let merged = MergeRequestsSnapshot.merging(
            [
                MergeRequestsSnapshot(totalCount: 2, mergeRequests: [sample(id: "a"), sample(id: "b")]),
                MergeRequestsSnapshot(totalCount: 1, mergeRequests: [sample(id: "b")]),
            ],
            failures: [AccountFailure(account: "Old", message: "token expired")]
        )
        try expectEqual(merged.mergeRequests.count, 2, "the same merge request from two accounts is one row")
        try expectEqual(merged.totalCount, 2, "and the total is trimmed by exactly what was dropped")
        try expectEqual(merged.failures.summary, "Old: token expired")
    }
}

private func sample(id: String) -> MergeRequestSummary {
    MergeRequestSummary(
        id: id,
        iid: 1,
        title: "One",
        project: "acme/web",
        url: URL(string: "https://git.acme.io/acme/web/-/merge_requests/1")!,
        isDraft: false,
        hasConflicts: false,
        updatedAt: Date(timeIntervalSince1970: 0),
        pipeline: .success,
        approvalsLeft: 0,
        unresolvedThreads: 0
    )
}
