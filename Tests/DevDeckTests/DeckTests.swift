import DevDeckCore
import DevDeckUI
import Foundation
import GitHubKit
import TestHarness

private let policy = RefreshPolicy(interval: 120, minimumInterval: 60, maximumInterval: 900)
private let now = Date(timeIntervalSince1970: 1_000)

/// A source that answers as told and writes down that it was asked.
private func source(
    _ card: CardID,
    asked: Box<[CardID]>,
    hint: TimeInterval? = nil,
    failing error: APIError? = nil
) -> RefreshSource {
    RefreshSource(card: card) {
        asked.mutate { $0.append(card) }
        if let error { throw error }
        return hint
    }
}

private func pullRequest(_ number: Int, repository: String, account: String = "github") -> PullRequestSummary {
    PullRequestSummary(
        id: "pr-\(number)",
        number: number,
        title: "Change \(number)",
        repository: repository,
        organization: String(repository.split(separator: "/").first ?? ""),
        url: URL(string: "https://github.com/\(repository)/pull/\(number)")!,
        isDraft: false,
        updatedAt: now,
        reviewDecision: .none,
        checks: .success,
        unresolvedThreads: 0,
        accountID: account
    )
}

func runDeckTests(_ run: TestRun) async {
    run.section("The refresh cycle")

    await run.test("a hidden card is never asked") {
        let asked = Box<[CardID]>([])
        let cycle = RefreshCycle()
        let pass = await cycle.run(
            [source(.githubPullRequests, asked: asked), source(.githubInbox, asked: asked)],
            active: [.githubInbox],
            policy: policy,
            now: now
        )
        try expectEqual(asked.value, [.githubInbox])
        try expectEqual(pass.refreshed, [.githubInbox])
        try expectEqual(pass.delay, 120, "nothing failed, so the plain interval")
    }

    await run.test("the sources are asked in the order they are given") {
        let asked = Box<[CardID]>([])
        let cycle = RefreshCycle()
        _ = await cycle.run(
            [
                source(.githubPullRequests, asked: asked),
                source(.githubInbox, asked: asked),
                source(.gitlabMergeRequests, asked: asked),
            ],
            active: [.githubPullRequests, .githubInbox, .gitlabMergeRequests],
            policy: policy,
            now: now
        )
        try expectEqual(asked.value, [.githubPullRequests, .githubInbox, .gitlabMergeRequests],
                        "one token and one rate limit, so one request at a time")
    }

    await run.test("one failure among three backs the whole deck off") {
        let asked = Box<[CardID]>([])
        let cycle = RefreshCycle()
        let sources = [
            source(.githubPullRequests, asked: asked),
            source(.githubInbox, asked: asked, failing: .transport("offline")),
            source(.gitlabMergeRequests, asked: asked),
        ]
        let active: Set<CardID> = [.githubPullRequests, .githubInbox, .gitlabMergeRequests]

        let first = await cycle.run(sources, active: active, policy: policy, now: now)
        try expectEqual(first.refreshed, [.githubPullRequests, .gitlabMergeRequests],
                        "the others are still asked; one card being down is not the deck being down")
        try expectEqual(first.failures, [RefreshFailure(card: .githubInbox, error: .transport("offline"))])
        try expectEqual(first.delay, 240, "one failure doubles the interval")
        try expectEqual(cycle.consecutiveFailures, 1)

        let second = await cycle.run(sources, active: active, policy: policy, now: now)
        try expectEqual(second.delay, 480, "and the count carries across passes")
        try expectEqual(cycle.consecutiveFailures, 2)
    }

    await run.test("a pass with nothing wrong forgets the failures before it") {
        let asked = Box<[CardID]>([])
        let cycle = RefreshCycle()
        _ = await cycle.run(
            [source(.githubInbox, asked: asked, failing: .transport("offline"))],
            active: [.githubInbox], policy: policy, now: now
        )
        try expectEqual(cycle.consecutiveFailures, 1)

        let pass = await cycle.run(
            [source(.githubInbox, asked: asked)],
            active: [.githubInbox], policy: policy, now: now
        )
        try expectEqual(pass.delay, 120)
        try expectEqual(cycle.consecutiveFailures, 0, "back to the plain interval at once")
    }

    await run.test("the server's poll interval is honoured upwards and never downwards") {
        let asked = Box<[CardID]>([])
        let cycle = RefreshCycle()
        let slower = await cycle.run(
            [source(.githubInbox, asked: asked, hint: 300)],
            active: [.githubInbox], policy: policy, now: now
        )
        try expectEqual(slower.delay, 300, "GitHub asked for five minutes, so five minutes")

        let faster = await cycle.run(
            [source(.githubInbox, asked: asked, hint: 30)],
            active: [.githubInbox], policy: policy, now: now
        )
        try expectEqual(faster.delay, 120, "a shorter hint does not speed the deck up")
    }

    await run.test("a rate limit reset outranks the backoff") {
        let asked = Box<[CardID]>([])
        let cycle = RefreshCycle()
        let pass = await cycle.run(
            [source(.githubPullRequests, asked: asked, failing: .rateLimited(resetAt: now.addingTimeInterval(400)))],
            active: [.githubPullRequests], policy: policy, now: now
        )
        try expectEqual(pass.delay, 405, "wait out the window plus a small margin, not 240")
    }

    await run.test("whatever a source threw comes back as something a card can render") {
        struct Odd: Error {}
        let cycle = RefreshCycle()
        let pass = await cycle.run(
            [RefreshSource(card: .githubInbox) { throw Odd() }],
            active: [.githubInbox], policy: policy, now: now
        )
        guard case .transport = pass.failures.first?.error else {
            throw TestFailure(message: "expected a transport error", file: #file, line: #line)
        }
        try expectEqual(APIError.wrapping(APIError.unauthorized), .unauthorized, "an APIError passes through")
    }

    run.section("Actions - which repositories are watched")

    let work = GitHubAccount(id: "work", label: "Work", organizations: ["acme"])
    let personal = GitHubAccount(id: "github", label: "Personal")

    await run.test("a configured list is grouped by the account whose organisation owns it") {
        let grouped = ActionsWatchList.repositoriesByAccount(
            configured: ["acme/web", "shumer/devdeck", "acme/api"],
            accounts: [personal, work],
            pullRequests: nil
        )
        try expectEqual(grouped["work"], ["acme/web", "acme/api"])
        try expectEqual(grouped["github"], ["shumer/devdeck"],
                        "nobody's organisation, so the first account, which is the personal one")
    }

    await run.test("with nothing configured the open pull requests decide, five per account") {
        let snapshot = PullRequestsSnapshot(
            totalCount: 8,
            pullRequests: (1...7).map { pullRequest($0, repository: "acme/repo-\($0)", account: "work") }
                + [pullRequest(8, repository: "shumer/devdeck"), pullRequest(9, repository: "shumer/devdeck")]
        )
        let grouped = ActionsWatchList.repositoriesByAccount(
            configured: [],
            accounts: [personal, work],
            pullRequests: snapshot
        )
        try expectEqual(grouped["work"]?.count, 5, "capped, or a busy week costs a request per repository")
        try expectEqual(grouped["github"], ["shumer/devdeck"], "the same repository twice is one repository")
    }

    await run.test("nothing configured and nothing loaded watches nothing") {
        try expectEqual(
            ActionsWatchList.repositoriesByAccount(configured: [], accounts: [personal], pullRequests: nil),
            [:]
        )
    }
}
