import AzureKit
import DevDeckCore
import Foundation
import TestHarness

private let account = AzureAccount(id: "work", label: "Work", organization: "acme")

private func makeClient(
    responses: [Result<HTTPResponse, Error>],
    token: String? = "pat-test"
) -> (AzureClient, FakeHTTPClient) {
    let http = FakeHTTPClient(responses)
    let tokens = InMemoryTokenStore(tokens: token.map { [account.tokenKey: $0] } ?? [:])
    let client = AzureClient(
        transport: APITransport(client: http, retryPolicy: .none, sleeper: RecordingSleeper()),
        tokenStore: tokens,
        account: account
    )
    return (client, http)
}

private let identity = #"{"authenticatedUser":{"id":"me","providerDisplayName":"Me"}}"#

/// Mine: a conflict, a rejection, a draft, one waiting on a required vote, one approved, and a
/// node with nothing in it.
private let mine = """
{"value":[
 {"pullRequestId":41,"title":"PROJ-6257 - Drop the legacy poller","creationDate":"2026-08-30T09:12:44.1234567Z","isDraft":false,"mergeStatus":"conflicts",
  "createdBy":{"id":"me","displayName":"Me"},"repository":{"id":"r1","name":"web","project":{"name":"Shop"}},
  "reviewers":[{"id":"anna","vote":10,"isRequired":true}]},
 {"pullRequestId":42,"title":"Rebase onto main","creationDate":"2026-08-30T08:00:00Z","isDraft":false,"mergeStatus":"succeeded",
  "createdBy":{"id":"me","displayName":"Me"},"repository":{"id":"r1","name":"web","project":{"name":"Shop"}},
  "reviewers":[{"id":"anna","vote":-10,"isRequired":true},{"id":"team","vote":0,"isRequired":true,"isContainer":true}]},
 {"pullRequestId":43,"title":"WIP search facets","creationDate":"2026-08-29T08:00:00Z","isDraft":true,"mergeStatus":"succeeded",
  "createdBy":{"id":"me","displayName":"Me"},"repository":{"id":"r2","name":"search","project":{"name":"Shop"}},
  "reviewers":[]},
 {"pullRequestId":44,"title":"Cache the index","creationDate":"2026-08-28T08:00:00Z","isDraft":false,"mergeStatus":"succeeded",
  "createdBy":{"id":"me","displayName":"Me"},"repository":{"id":"r3","name":"infra","project":{"name":"Platform"}},
  "reviewers":[{"id":"anna","vote":10,"isRequired":false},{"id":"bob","vote":0,"isRequired":true}]},
 {"pullRequestId":45,"title":"Bump the runtime","creationDate":"2026-08-27T08:00:00Z","isDraft":false,"mergeStatus":"succeeded",
  "createdBy":{"id":"me","displayName":"Me"},"repository":{"id":"r3","name":"infra","project":{"name":"Platform"}},
  "reviewers":[{"id":"anna","vote":5,"isRequired":true}]},
 {"pullRequestId":46,"title":"No repository on this one","creationDate":"2026-08-27T08:00:00Z"}
],"count":6}
"""

/// Asked of me: one still owed, one I already approved, one that is mine anyway.
private let reviewing = """
{"value":[
 {"pullRequestId":50,"title":"Split the parser","creationDate":"2026-08-30T07:00:00Z","isDraft":false,"mergeStatus":"queued",
  "createdBy":{"id":"marta","displayName":"Marta"},"repository":{"id":"r1","name":"web","project":{"name":"Shop"}},
  "reviewers":[{"id":"me","vote":0,"isRequired":true}]},
 {"pullRequestId":51,"title":"Already looked at","creationDate":"2026-08-30T06:00:00Z","isDraft":false,"mergeStatus":"succeeded",
  "createdBy":{"id":"marta","displayName":"Marta"},"repository":{"id":"r1","name":"web","project":{"name":"Shop"}},
  "reviewers":[{"id":"me","vote":10,"isRequired":true}]},
 {"pullRequestId":44,"title":"Cache the index","creationDate":"2026-08-28T08:00:00Z","isDraft":false,"mergeStatus":"succeeded",
  "createdBy":{"id":"me","displayName":"Me"},"repository":{"id":"r3","name":"infra","project":{"name":"Platform"}},
  "reviewers":[{"id":"me","vote":0,"isRequired":true}]}
],"count":3}
"""

func runAzureTests(_ run: TestRun) async {
    run.section("Azure DevOps - pull request decoding")

    let (client, http) = makeClient(responses: [.success(.json(identity)), .success(.json(mine)), .success(.json(reviewing))])
    let snapshot = try? await AzurePullRequestsService(client: client, account: account).fetch()

    await run.test("the response decodes into a snapshot") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        try expectEqual(snapshot.pullRequests.count, 6, "five of mine plus the one vote I owe; the node with nothing in it is dropped")
        try expectEqual(snapshot.totalCount, 6)
        try expectEqual(snapshot.reviewRequestCount, 1, "a vote already cast and my own pull request are not requests")
        try expectEqual(snapshot.repositoryCount, 3)
        try expectEqual(snapshot.projectCount, 2, "Shop and Platform")
        let review = try expectNotNil(snapshot.pullRequests.first { $0.isReviewRequest }, "review")
        try expectEqual(review.number, 50)
        try expectEqual(review.author, "Marta")
        try expectEqual(review.url.absoluteString, "https://dev.azure.com/acme/Shop/_git/web/pullrequest/50",
                        "the list endpoint knows no web address, so the row builds its own")
    }

    await run.test("three GETs with a Basic credential, versioned except for who-am-I") {
        let who = try expectNotNil(await http.request(at: 0), "connectionData")
        try expectEqual(who.url.absoluteString, "https://dev.azure.com/acme/_apis/connectionData")
        try expectEqual(who.headers["Authorization"], "Basic \(Data(":pat-test".utf8).base64EncodedString())",
                        "a PAT is the password of a credential with no user name")
        let list = try expectNotNil(await http.request(at: 1), "mine")
        try expectEqual(list.method, .get)
        try expect(list.url.absoluteString.hasPrefix("https://dev.azure.com/acme/_apis/git/pullrequests?"))
        try expect(list.url.absoluteString.contains("searchCriteria.creatorId=me"))
        try expect(list.url.absoluteString.contains("api-version=7.1"))
        _ = try expectNotNil(list.cacheKey, "a GET the same every refresh may carry an ETag")
        let asked = try expectNotNil(await http.request(at: 2), "reviewing")
        try expect(asked.url.absoluteString.contains("searchCriteria.reviewerId=me"))
    }

    await run.test("health is derived from the merge state, the votes and the draft flag") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        func row(_ number: Int) throws -> AzurePullRequestSummary {
            try expectNotNil(snapshot.pullRequests.first { $0.number == number }, "#\(number)")
        }
        try expectEqual(try row(41).health, .blocked)
        try expectEqual(try row(41).statusCode, "MC", "a conflict before anything a reviewer said")
        try expectEqual(try row(42).health, .blocked)
        try expectEqual(try row(42).statusCode, "CR", "a rejection is changes requested; the group row is not a vote")
        try expectEqual(try row(43).statusCode, "DR")
        try expectEqual(try row(43).health, .attention)
        try expectEqual(try row(44).statusCode, "A1", "one required vote still owed")
        try expectEqual(try row(44).health, .attention)
        try expectEqual(try row(45).statusCode, "AP", "approved with suggestions is approved")
        try expectEqual(try row(45).health, .ready)
        try expectEqual(try row(50).statusCode, "RV")
        try expectEqual(try row(50).health, .attention, "somebody else's queued merge is not my stuck work")
        try expectEqual(try row(50).statusLine, "waiting for your vote")
        try expectEqual(try row(41).ticket.key, "PROJ-6257")
        try expectEqual(try row(41).ticket.subject, "Drop the legacy poller")
        try expectEqual(try row(41).shortLabel, "Shop/web#41")
    }

    await run.test("rows are ordered worst first, with a review request just under them") {
        let snapshot = try expectNotNil(snapshot, "snapshot")
        try expectEqual(snapshot.prioritized().map(\.number), [41, 42, 50, 43, 44, 45],
                        "blocked newest first, then the vote owed, then attention, then ready")
        try expectEqual(snapshot.prioritized(limit: 2).map(\.number), [41, 42])
    }

    await run.test("a timestamp is read with seven fractional digits, three, or none") {
        let seven = try expectNotNil(AzureClient.parseDate("2026-08-30T09:12:44.1234567Z"), "seven")
        let three = try expectNotNil(AzureClient.parseDate("2026-08-30T09:12:44.123Z"), "three")
        let none = try expectNotNil(AzureClient.parseDate("2026-08-30T09:12:44Z"), "none")
        try expect(abs(seven.timeIntervalSince(three)) < 0.001)
        try expect(abs(three.timeIntervalSince(none) - 0.123) < 0.001, "the fraction survives the cut")
        try expectNil(AzureClient.parseDate("yesterday"))
    }

    await run.test("an organization is taken however it is typed, and a typo is not one") {
        try expectEqual(AzureAccount.normalizedOrganization("acme"), "acme")
        try expectEqual(AzureAccount.normalizedOrganization(" https://dev.azure.com/acme/ "), "acme")
        try expectEqual(AzureAccount.normalizedOrganization("https://dev.azure.com/acme/Shop/_git/web/pullrequest/41"), "acme")
        try expectEqual(AzureAccount.normalizedOrganization("dev.azure.com/acme"), "acme")
        try expectEqual(AzureAccount.normalizedOrganization("acme.visualstudio.com"), "acme", "the legacy host names it too")
        try expectNil(AzureAccount.normalizedOrganization(""))
        try expectNil(AzureAccount.normalizedOrganization("not an org"))
        try expectNil(AzureAccount.normalizedOrganization("https://dev.azure.com/"))
    }

    await run.test("an organization keeps its own token key and its own addresses") {
        try expectEqual(AzureAccount(id: AzureAccount.defaultID, label: "Azure DevOps").tokenKey.account, "azure")
        try expectEqual(account.tokenKey.account, "azure.work")
        try expectEqual(account.organizationURL.absoluteString, "https://dev.azure.com/acme")
        try expectEqual(account.displayOrganization, "acme")
        try expectEqual(AzureAccount(id: "new", label: "New").displayOrganization, "dev.azure.com", "nothing typed yet still says where it points")
        try expectEqual(AzurePullRequestsService.webURL(organization: "acme", project: "My Shop", repository: "web", number: 7).absoluteString,
                        "https://dev.azure.com/acme/My%20Shop/_git/web/pullrequest/7")
    }

    await run.test("nothing configured means no Azure DevOps at all") {
        let store = AzureAccountsStore(backend: InMemoryPreferences())
        try expect(store.accounts().isEmpty, "opt-in, like GitLab")
        store.save([account, AzureAccount(id: "off", label: "Old", isEnabled: false)])
        try expectEqual(store.accounts().count, 2)
        try expectEqual(store.enabledAccounts().map(\.id), ["work"])
        let workspace = AzureWorkspace(accounts: [], tokenStore: InMemoryTokenStore())
        do {
            _ = try await workspace.pullRequests()
            throw TestFailure(message: "no accounts should read as no token", file: #filePath, line: #line)
        } catch let error as APIError {
            try expectEqual(error, .missingToken("Azure DevOps"))
        }
    }

    await run.test("a rejected token comes back as a sign-in page, which is read as unauthorized") {
        let (client, _) = makeClient(responses: [.success(HTTPResponse(statusCode: 203, body: Data("<!DOCTYPE html><html><head><title>Sign in</title></head></html>".utf8)))])
        do {
            _ = try await AzurePullRequestsService(client: client, account: account).fetch()
            throw TestFailure(message: "a sign-in page is not a payload", file: #filePath, line: #line)
        } catch let error as APIError {
            try expectEqual(error, .unauthorized)
        }
        let (bare, _) = makeClient(responses: [], token: nil)
        do {
            _ = try await AzurePullRequestsService(client: bare, account: account).fetch()
            throw TestFailure(message: "no token should fail before any request", file: #filePath, line: #line)
        } catch let error as APIError {
            try expectEqual(error, .missingToken("Azure DevOps"))
        }
    }

    await run.test("two organizations are merged into one card, and one failing does not empty it") {
        let merged = AzurePullRequestsSnapshot.merging(
            [
                AzurePullRequestsSnapshot(totalCount: 2, pullRequests: [sample(id: "a"), sample(id: "b")]),
                AzurePullRequestsSnapshot(totalCount: 1, pullRequests: [sample(id: "b")]),
            ],
            failures: [AccountFailure(account: "Old", message: "token expired")]
        )
        try expectEqual(merged.pullRequests.count, 2, "the same pull request from two accounts is one row")
        try expectEqual(merged.totalCount, 2, "and the total is trimmed by exactly what was dropped")
        try expectEqual(merged.failures.summary, "Old: token expired")
    }

    await run.test("what Azure DevOps wants from a person, in the GitHub card's words") {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let review = AzurePullRequestSummary(
            id: "r1/50", number: 50, title: "Split the parser", project: "Shop", repository: "web",
            url: URL(string: "https://dev.azure.com/acme/Shop/_git/web/pullrequest/50")!, isDraft: false, merge: .pending,
            createdAt: now, approvals: 0, hasChangesRequested: false, requiredVotesMissing: 1,
            accountID: "work", isReviewRequest: true, author: "Marta"
        )
        let stuck = AzurePullRequestSummary(
            id: "r1/41", number: 41, title: "Drop the poller", project: "Shop", repository: "web",
            url: URL(string: "https://dev.azure.com/acme/Shop/_git/web/pullrequest/41")!, isDraft: false, merge: .conflicts,
            createdAt: now, approvals: 1, hasChangesRequested: false, requiredVotesMissing: 0, accountID: "work"
        )
        let rows = AzureAttention.items(pullRequests: AzurePullRequestsSnapshot(totalCount: 2, pullRequests: [review, stuck]), labels: [:])
        try expectEqual(rows.map(\.tier), [.waiting, .stuck])
        try expectEqual(rows[0].title, "Review: Split the parser")
        try expectEqual(rows[0].subtitle, "Shop/web #50 · from Marta")
        try expectEqual(rows[0].action, .open(review.url, service: .azure, account: "work"))
        try expectEqual(rows[1].title, "Merge conflict: Drop the poller")
        try expectEqual(rows[1].subtitle, "Shop/web #41 · your pull request")
        let alerts = AzureAttention.alerts(pullRequests: AzurePullRequestsSnapshot(totalCount: 2, pullRequests: [review, stuck]), labels: ["work": "Work", "other": "Other"])
        try expectEqual(alerts.map(\.title), ["Marta asked for your review", "Your pull request has a merge conflict"])
        try expectEqual(alerts[0].subtitle, "Shop/web #50 · Work")
        try expectEqual(alerts.map(\.source), [.azure, .azure])
        try expectEqual(alerts.map(\.isQuiet), [false, true])
    }
}

private func sample(id: String) -> AzurePullRequestSummary {
    AzurePullRequestSummary(
        id: id, number: 1, title: "One", project: "Shop", repository: "web",
        url: URL(string: "https://dev.azure.com/acme/Shop/_git/web/pullrequest/1")!,
        isDraft: false, merge: .succeeded, createdAt: Date(timeIntervalSince1970: 0),
        approvals: 1, hasChangesRequested: false, requiredVotesMissing: 0
    )
}
