import DevDeckCore
import DevDeckUI
import Foundation
import GitHubKit
import GitLabKit
import TestHarness

private let now = Date(timeIntervalSince1970: 1_790_000_000)

private func item(_ id: String, _ tier: AttentionTier, minutesAgo: Double? = nil, title: String? = nil) -> AttentionItem {
    AttentionItem(
        id: id,
        tier: tier,
        mark: .github,
        title: title ?? id,
        subtitle: "",
        since: minutesAgo.map { now.addingTimeInterval(-$0 * 60) },
        action: .none
    )
}

private func pullRequest(
    id: String,
    title: String = "IR-1 - Fix the feed",
    checks: CheckState = .success,
    review: ReviewDecision = .none,
    isReviewRequest: Bool = false,
    requestedBy: String? = nil,
    hasConflicts: Bool = false,
    account: String = "work"
) -> PullRequestSummary {
    PullRequestSummary(
        id: id, number: 7, title: title, repository: "acme/web", organization: "acme",
        url: URL(string: "https://github.com/acme/web/pull/\(id)")!, isDraft: false,
        updatedAt: now.addingTimeInterval(-3600), reviewDecision: review, checks: checks,
        unresolvedThreads: 0, accountID: account, isReviewRequest: isReviewRequest,
        requestedBy: requestedBy, hasConflicts: hasConflicts
    )
}

private func workflowRun(
    _ id: Int, name: String = "Deploy", branch: String = "main", conclusion: RunConclusion,
    minutesAgo: Double, onMain: Bool = true
) -> WorkflowRun {
    WorkflowRun(
        id: id, name: name, repository: "acme/site", branch: branch, status: .completed,
        conclusion: conclusion, startedAt: now.addingTimeInterval(-minutesAgo * 60),
        updatedAt: now.addingTimeInterval(-minutesAgo * 60 + 60),
        url: URL(string: "https://github.com/acme/site/actions/runs/\(id)"), accountID: "work",
        isOnDefaultBranch: onMain
    )
}

private let arc = WatchedProject(id: "news", cardID: CardID(rawValue: "arc.news"), title: "ACME News", kind: "Arc XP", mark: .arc, needsDocker: true)
private let shop = WatchedProject(id: "shop", cardID: CardID(rawValue: "ddev.shop"), title: "ACME Shop", kind: "DDEV", mark: .ddev, needsDocker: true)

func runAttentionTests(_ run: TestRun) async {
    run.section("Attention - the digest")

    await run.test("tiers come in the order they are read, and a person waiting longest leads") {
        let digest = AttentionDigest(items: [
            item("stuck-old", .stuck, minutesAgo: 300),
            item("news", .goodToKnow, minutesAgo: 1),
            item("waiting-new", .waiting, minutesAgo: 5),
            item("fix", .needsFixing, minutesAgo: 10),
            item("waiting-old", .waiting, minutesAgo: 90),
            item("stuck-new", .stuck, minutesAgo: 3),
        ])
        try expectEqual(digest.items.map(\.id), ["waiting-old", "waiting-new", "fix", "stuck-new", "stuck-old", "news"],
                        "somebody who has waited longest first; everything else newest first")
    }

    await run.test("one thing is counted once, however many sources report it") {
        let digest = AttentionDigest(items: [item("review:1", .waiting), item("review:1", .waiting)])
        try expectEqual(digest.count(.waiting), 1)
        try expectEqual(digest.summary, "1 waiting on you")
    }

    await run.test("the icon takes the most urgent tier, and good to know never lights it") {
        try expectEqual(AttentionDigest(items: [item("a", .stuck), item("b", .needsFixing)]).iconTier, .needsFixing)
        try expectEqual(AttentionDigest(items: [item("a", .stuck), item("b", .waiting)]).iconTier, .waiting)
        try expectNil(AttentionDigest(items: [item("update", .goodToKnow)]).iconTier)
        try expectNil(AttentionDigest(items: []).iconTier)
    }

    await run.test("a section shows three rows and folds the rest, but never folds just one") {
        let five = AttentionDigest(items: (1...5).map { item("s\($0)", .stuck, minutesAgo: Double($0)) })
        let section = try expectNotNil(five.sections.first, "section")
        try expectEqual(section.visible.count, 3)
        try expectEqual(section.overflow.count, 2)
        try expectEqual(section.overflowTitle, "2 more stuck")

        let four = AttentionDigest(items: (1...4).map { item("s\($0)", .stuck) })
        try expectEqual(four.sections.first?.visible.count, 4, "a submenu holding one row costs the same line")
        try expectNil(four.sections.first?.overflowTitle)
    }

    await run.test("the tooltip counts by tier, and says so when nothing needs you") {
        let digest = AttentionDigest(items: [item("a", .waiting), item("b", .waiting), item("c", .needsFixing), item("d", .stuck), item("e", .goodToKnow)])
        try expectEqual(digest.summary, "2 waiting on you, 1 to fix, 1 stuck")
        try expectEqual(DeckStatusSummary(digest: digest).tooltip, "DevDeck: 2 waiting on you, 1 to fix, 1 stuck")
        try expectEqual(AttentionDigest(items: []).summary, "nothing needs you")
    }

    await run.test("ages are short and times are the deck's own format") {
        try expectEqual(AttentionDigest.age(since: now.addingTimeInterval(-30), now: now), "now")
        try expectEqual(AttentionDigest.age(since: now.addingTimeInterval(-12 * 60), now: now), "12m")
        try expectEqual(AttentionDigest.age(since: now.addingTimeInterval(-5 * 3600), now: now), "5h")
        try expectEqual(AttentionDigest.age(since: now.addingTimeInterval(-3 * 86_400), now: now), "3d")
        try expectNil(AttentionDigest.age(since: nil, now: now))
    }

    await run.test("names are listed the way a sentence lists them") {
        try expectEqual(AttentionWords.list(["A"]), "A")
        try expectEqual(AttentionWords.list(["A", "B"]), "A and B")
        try expectEqual(AttentionWords.list(["A", "B", "C", "D"]), "A, B and 2 more")
        try expectEqual(AttentionWords.withAccount(["acme/web #7", "anna asked"], label: nil), "acme/web #7 · anna asked")
        try expectEqual(AttentionWords.withAccount(["acme/web #7"], label: "Work"), "acme/web #7 · Work")
        let long = AttentionWords.trimmed("A very long pull request title that goes on and on well past the width")
        try expect(long.count <= 48 && long.hasSuffix("…"), long)
    }

    run.section("Attention - GitHub")

    await run.test("a review names what, where and who asked, and opens the pull request") {
        let request = pullRequest(id: "1", isReviewRequest: true, requestedBy: "anna")
        let row = try expectNotNil(GitHubAttention.items(
            pullRequests: PullRequestsSnapshot(totalCount: 1, pullRequests: [request]), inbox: nil, actions: nil, labels: [:]
        ).first, "row")
        try expectEqual(row.tier, .waiting)
        try expectEqual(row.title, "Review: Fix the feed", "the ticket key is not the subject")
        try expectEqual(row.subtitle, "acme/web #7 · anna asked")
        try expectEqual(row.action, .open(request.url, service: .github, account: "work"))

        let withLabels = GitHubAttention.items(
            pullRequests: PullRequestsSnapshot(totalCount: 1, pullRequests: [request]), inbox: nil, actions: nil,
            labels: ["work": "Work", "home": "Home"]
        )
        try expectEqual(withLabels.first?.subtitle, "acme/web #7 · anna asked · Work", "the account only when there are several")
    }

    await run.test("your stuck pull requests say what is in the way, conflict first") {
        let rows = GitHubAttention.items(
            pullRequests: PullRequestsSnapshot(totalCount: 3, pullRequests: [
                pullRequest(id: "1", checks: .failure),
                pullRequest(id: "2", checks: .failure, hasConflicts: true),
                pullRequest(id: "3", review: .changesRequested),
                pullRequest(id: "4"),
            ]),
            inbox: nil, actions: nil, labels: [:]
        )
        try expectEqual(rows.map(\.title), ["Checks failed: Fix the feed", "Merge conflict: Fix the feed", "Changes requested: Fix the feed"])
        try expect(rows.allSatisfy { $0.tier == .stuck && $0.subtitle.contains("your pull request") })
    }

    await run.test("the inbox adds what asks for you, once, and leaves the chatter out") {
        let request = pullRequest(id: "1", isReviewRequest: true)
        let inbox = InboxSnapshot(items: [
            InboxItem(id: "t1", reason: .reviewRequested, title: "Fix the feed", repository: "acme/web", updatedAt: now, isUnread: true, url: request.url, accountID: "work"),
            InboxItem(id: "t2", reason: .mention, title: "Deploy checklist", repository: "acme/ops", updatedAt: now, isUnread: true, url: URL(string: "https://github.com/acme/ops/issues/3"), accountID: "work"),
            InboxItem(id: "t3", reason: .comment, title: "Somebody said a thing", repository: "acme/ops", updatedAt: now, isUnread: true, url: nil, accountID: "work"),
            InboxItem(id: "t4", reason: .assigned, title: "Already read", repository: "acme/ops", updatedAt: now, isUnread: false, url: nil, accountID: "work"),
        ])
        let rows = GitHubAttention.items(
            pullRequests: PullRequestsSnapshot(totalCount: 1, pullRequests: [request]), inbox: inbox, actions: nil, labels: [:]
        )
        try expectEqual(rows.map(\.id), ["review:1", "inbox:t2"], "the review's own notification is the same review")
        try expectEqual(rows[1].title, "Mentioned: Deploy checklist")
        try expectEqual(rows[1].inboxThreadID, "t2", "so ⌥ can mark it read")
    }

    await run.test("a workflow counts only while its latest run on the main branch is red") {
        let failing = ActionsSnapshot(runs: [
            workflowRun(3, conclusion: .failure, minutesAgo: 10),
            workflowRun(2, conclusion: .failure, minutesAgo: 60),
            workflowRun(1, conclusion: .success, minutesAgo: 120),
            workflowRun(9, name: "Lint", branch: "feature/x", conclusion: .failure, minutesAgo: 5, onMain: false),
        ], windowDays: 7, repositories: ["acme/site"])
        let rows = GitHubAttention.items(pullRequests: nil, inbox: nil, actions: failing, labels: [:])
        try expectEqual(rows.count, 1, "a red run on a feature branch belongs to its pull request")
        try expectEqual(rows.first?.title, "Deploy failing on main")
        try expectEqual(rows.first?.subtitle, "acme/site · failed 2 times in a row")
        try expectEqual(rows.first?.since, now.addingTimeInterval(-3600), "since the first failure of the streak")

        let fixed = ActionsSnapshot(runs: [
            workflowRun(4, conclusion: .success, minutesAgo: 2),
            workflowRun(3, conclusion: .failure, minutesAgo: 10),
        ], windowDays: 7, repositories: ["acme/site"])
        try expect(GitHubAttention.items(pullRequests: nil, inbox: nil, actions: fixed, labels: [:]).isEmpty,
                   "the next run passed, so it is not news any more")

        let alerts = GitHubAttention.alerts(actions: failing, labels: [:])
        try expectEqual(alerts.first?.id, "run:acme/site:Deploy:main:2", "the streak's first failure is the identity")
        try expect(alerts.first?.isQuiet == true)
    }

    await run.test("banners say what happened in the title and what a click does in the body") {
        let alerts = GitHubAttention.alerts(pullRequests: PullRequestsSnapshot(totalCount: 2, pullRequests: [
            pullRequest(id: "1", isReviewRequest: true, requestedBy: "anna"),
            pullRequest(id: "2", checks: .failure),
        ]), labels: [:])
        try expectEqual(alerts.map(\.title), ["anna asked for your review", "Checks failed on your pull request"])
        try expectEqual(alerts[0].subtitle, "acme/web #7")
        try expectEqual(alerts[0].body, "IR-1 Fix the feed. Click to open it.", "the ticket key is kept in a banner")
        try expectEqual(alerts.map(\.isQuiet), [false, true])
    }

    run.section("Attention - GitLab")

    await run.test("a review somebody waits on is never your stuck work, whatever its pipeline") {
        let review = MergeRequestSummary(
            id: "r", iid: 41, title: "Drop the poller", project: "acme/web", url: URL(string: "https://git.acme.io/r")!,
            isDraft: false, hasConflicts: false, updatedAt: now, pipeline: .failed, approvalsLeft: 1,
            unresolvedThreads: 0, accountID: "gl", isReviewRequest: true, author: "marta"
        )
        let mine = MergeRequestSummary(
            id: "m", iid: 42, title: "Toolbar spacing", project: "cms/editor", url: URL(string: "https://git.acme.io/m")!,
            isDraft: false, hasConflicts: true, updatedAt: now, pipeline: .failed, approvalsLeft: 0,
            unresolvedThreads: 0, accountID: "gl"
        )
        try expectEqual(review.health, .attention)
        let rows = GitLabAttention.items(mergeRequests: MergeRequestsSnapshot(totalCount: 2, mergeRequests: [review, mine]), labels: [:])
        try expectEqual(rows.map(\.tier), [.waiting, .stuck])
        try expectEqual(rows[0].subtitle, "acme/web !41 · from marta")
        try expectEqual(rows[1].title, "Merge conflict: Toolbar spacing")
    }

    run.section("Attention - accounts")

    await run.test("a rejected token is something to fix, with its form one click away") {
        let failure = AccountFailure(account: "Work", accountID: "work", error: APIError.unauthorized)
        try expectEqual(failure.kind, .rejected)
        let row = try expectNotNil(AccountAttention.items(failures: [failure], service: .github, now: now, failingSince: [:]).first, "row")
        try expectEqual(row.tier, .needsFixing)
        try expectEqual(row.title, "Replace GitHub token (Work)")
        try expectEqual(row.action, .accountSettings(service: .github, account: "work"))

        let missing = AccountFailure(account: "GitHub", message: "No GitHub token yet", kind: .rejected)
        try expectEqual(AccountAttention.items(failures: [missing], service: .github, now: now, failingSince: [:]).first?.title,
                        "Add a GitHub token")
    }

    await run.test("a network blip is only good to know, until it has lasted") {
        let failure = AccountFailure(account: "Customer", accountID: "gl", error: APIError.transport("offline"))
        try expectEqual(failure.kind, .unreachable)
        let fresh = AccountAttention.items(failures: [failure], service: .gitlab, now: now, failingSince: ["gl": now.addingTimeInterval(-120)])
        try expectEqual(fresh.first?.tier, .goodToKnow)
        let long = AccountAttention.items(failures: [failure], service: .gitlab, now: now, failingSince: ["gl": now.addingTimeInterval(-20 * 60)])
        try expectEqual(long.first?.tier, .needsFixing)
        try expectEqual(long.first?.title, "Can't reach GitLab (Customer)")

        let refused = AccountFailure(account: "Work", accountID: "work", error: APIError.graphQL(["Your token has not been granted the required scopes"]))
        let refusedRow = AccountAttention.items(failures: [refused], service: .github, now: now, failingSince: [:]).first
        try expectEqual(refusedRow?.title, "GitHub refused the request (Work)", "an answer that says no is not a network problem")
        try expectEqual(refusedRow?.tier, .needsFixing)

        let limited = AccountFailure(account: "Work", accountID: "work", error: APIError.rateLimited(resetAt: now))
        try expectEqual(AccountAttention.items(failures: [limited], service: .github, now: now, failingSince: [:]).first?.tier, .goodToKnow)
    }

    await run.test("only a rejected token is announced, once per time it stops working") {
        let rejected = AccountFailure(account: "Work", accountID: "work", error: APIError.unauthorized)
        let first = try expectNotNil(AccountAttention.alert(for: rejected, service: .github, since: now), "alert")
        try expectEqual(first.title, "DevDeck can't check Work on GitHub")
        try expectEqual(first.target, .accountSettings(service: "github", account: "work"))
        let again = AccountAttention.alert(for: rejected, service: .github, since: now.addingTimeInterval(3600))
        try expect(first.id != again?.id, "a second episode is news again")
        try expectNil(AccountAttention.alert(
            for: AccountFailure(account: "Work", accountID: "work", error: APIError.transport("x")), service: .github, since: now
        ))
    }

    run.section("Attention - projects on this Mac")

    await run.test("a project that was already stopped at launch did not stop on its own") {
        var watch = ProjectWatch()
        watch.observe("news", running: false, at: now)
        try expect(watch.problems(for: "news", now: now).isEmpty)
    }

    await run.test("running and then not, with nobody pressing Stop, is worth saying") {
        var watch = ProjectWatch()
        watch.observe("news", running: true, at: now.addingTimeInterval(-600))
        watch.observe("news", running: false, at: now)
        try expectEqual(watch.problems(for: "news", now: now), [.stoppedOnItsOwn(wasRunningAt: now.addingTimeInterval(-600), at: now, withDocker: false)])

        let rows = ProjectAttention.items(projects: [arc], watch: watch, docker: DockerStatus(state: .running), dockerDownSince: nil, now: now)
        try expectEqual(rows.first?.title, "ACME News stopped on its own")
        try expect(rows.first?.isDismissible == true)

        var stopped = ProjectWatch()
        stopped.observe("news", running: true, at: now.addingTimeInterval(-600))
        stopped.noteAction("news", isStop: true, at: now.addingTimeInterval(-10))
        stopped.observe("news", running: false, at: now)
        try expect(stopped.problems(for: "news", now: now).isEmpty, "a stop you pressed is not news")
    }

    await run.test("a stop that did not take, landing later, is still your stop") {
        var watch = ProjectWatch()
        watch.observe("news", running: true, at: now.addingTimeInterval(-600))
        watch.noteAction("news", isStop: true, at: now.addingTimeInterval(-60))
        watch.noteStopDidNotTakeEffect("news", at: now.addingTimeInterval(-30))
        try expectEqual(watch.problems(for: "news", now: now), [.stopDidNotTakeEffect(at: now.addingTimeInterval(-30))])
        watch.observe("news", running: true, at: now.addingTimeInterval(-20))
        watch.observe("news", running: false, at: now)
        try expect(watch.problems(for: "news", now: now).isEmpty)
    }

    await run.test("a failed start is kept until the next press or until it runs") {
        var watch = ProjectWatch()
        watch.noteAction("news", isStop: false, at: now.addingTimeInterval(-60))
        watch.noteStartFailed("news", line: "port 8080 is already in use", at: now)
        try expectEqual(watch.problems(for: "news", now: now), [.startFailed(line: "port 8080 is already in use", at: now, tookLong: true)])
        watch.observe("news", running: false, at: now.addingTimeInterval(10))
        try expectEqual(watch.problems(for: "news", now: now.addingTimeInterval(10)).count, 1, "a poll does not wipe the reason")
        watch.observe("news", running: true, at: now.addingTimeInterval(20))
        try expect(watch.problems(for: "news", now: now.addingTimeInterval(20)).isEmpty)
    }

    await run.test("up but silent is only said after it has lasted two minutes") {
        var watch = ProjectWatch()
        watch.observe("news", running: true, notAnswering: "health check answered 500", at: now)
        try expect(watch.problems(for: "news", now: now.addingTimeInterval(60)).isEmpty, "compiling, probably")
        try expectEqual(watch.problems(for: "news", now: now.addingTimeInterval(130)),
                        [.notAnswering(detail: "health check answered 500", since: now)])
    }

    await run.test("dismissing hides what happened, not what is still wrong") {
        var watch = ProjectWatch()
        watch.observe("shop", running: true, syncBroken: "mutagen failed", at: now.addingTimeInterval(-600))
        watch.observe("shop", running: false, at: now.addingTimeInterval(-300))
        watch.observe("shop", running: true, syncBroken: "mutagen failed", at: now.addingTimeInterval(-200))
        watch.observe("shop", running: false, at: now)
        watch.dismiss("shop")
        try expect(watch.problems(for: "shop", now: now).isEmpty)
        watch.observe("shop", running: true, syncBroken: "mutagen failed", at: now.addingTimeInterval(10))
        try expectEqual(watch.problems(for: "shop", now: now.addingTimeInterval(10)),
                        [.syncBroken(detail: "mutagen failed", since: now.addingTimeInterval(10))],
                        "a broken sync is still broken")
    }

    await run.test("projects that fell with Docker are one row about Docker") {
        var watch = ProjectWatch()
        for project in ["news", "shop"] {
            watch.observe(project, running: true, at: now.addingTimeInterval(-600))
            watch.observe(project, running: false, dockerDown: true, at: now)
        }
        let down = DockerStatus(state: .notRunning)
        let rows = ProjectAttention.items(projects: [arc, shop], watch: watch, docker: down, dockerDownSince: now, now: now)
        try expectEqual(rows.map(\.title), ["Start Docker"])
        try expectEqual(rows.first?.subtitle, "Docker quit · ACME News and ACME Shop went down")
        try expectEqual(rows.first?.action, .startDocker)

        let alerts = ProjectAttention.alerts(projects: [arc, shop], watch: watch, docker: down, dockerDownSince: now, source: { _ in .project }, now: now)
        try expectEqual(alerts.map(\.title), ["Docker stopped"], "one banner for one cause")

        let back = ProjectAttention.items(projects: [arc, shop], watch: watch, docker: DockerStatus(state: .running), dockerDownSince: nil, now: now)
        try expectEqual(back.first?.subtitle, "Arc XP · stopped when Docker quit", "once Docker is back, each project says what happened to it")
    }

    await run.test("Docker merely off is good to know, and only when a project needs it") {
        let rows = ProjectAttention.items(projects: [arc], watch: ProjectWatch(), docker: DockerStatus(state: .notRunning), dockerDownSince: now, now: now)
        try expectEqual(rows.map(\.tier), [.goodToKnow])
        try expectEqual(rows.first?.subtitle, "ACME News needs it")
        let none = ProjectAttention.items(projects: [], watch: ProjectWatch(), docker: DockerStatus(state: .notRunning), dockerDownSince: now, now: now)
        try expect(none.isEmpty)
    }

    run.section("Attention - work only on this Mac")

    await run.test("local commits are counted and dated from one git command") {
        let parsed = WorkInFlight.parseLocalCommits("1789990000\n1789000000\n\n")
        try expectEqual(parsed.count, 2)
        try expectEqual(parsed.oldest, Date(timeIntervalSince1970: 1_789_000_000))
    }

    await run.test("only work older than three days is worth a row, and never a badge") {
        let old = CheckoutState(id: "w", title: "widgets", branch: "feat/x", dirtyFiles: 0, ahead: 4, behind: 0, hasUpstream: true,
                                localCommits: 4, oldestLocalCommitAt: now.addingTimeInterval(-5 * 86_400))
        let fresh = CheckoutState(id: "f", title: "fresh", branch: "feat/y", dirtyFiles: 0, ahead: 1, behind: 0, hasUpstream: true,
                                  localCommits: 1, oldestLocalCommitAt: now.addingTimeInterval(-3600))
        let orphan = CheckoutState(id: "o", title: "spike", branch: "spike/cache", dirtyFiles: 0, ahead: 0, behind: 0, hasUpstream: false,
                                   localCommits: 2, oldestLocalCommitAt: now.addingTimeInterval(-9 * 86_400))
        let rows = CheckoutAttention.items(checkouts: [old, fresh, orphan], folders: ["w": URL(fileURLWithPath: "/tmp/w")], now: now)
        try expectEqual(rows.map(\.title), ["4 commits only on this Mac: widgets", "Branch not on any remote: spike"])
        try expect(rows.allSatisfy { $0.tier == .goodToKnow })
        try expectEqual(rows.first?.action, .openTerminal(URL(fileURLWithPath: "/tmp/w")))
    }

    run.section("Attention - the whole deck")

    await run.test("GitLab counts, a hidden card does not, and a rejected token is not calm") {
        let review = MergeRequestSummary(
            id: "r", iid: 41, title: "Drop the poller", project: "acme/web", url: URL(string: "https://git.acme.io/r")!,
            isDraft: false, hasConflicts: false, updatedAt: now, pipeline: .success, approvalsLeft: 0,
            unresolvedThreads: 0, accountID: "gl", isReviewRequest: true
        )
        var input = DeckAttention.Input(
            activeCards: [.gitlabMergeRequests],
            mergeRequests: CardState(value: MergeRequestsSnapshot(totalCount: 1, mergeRequests: [review]), updatedAt: now)
        )
        try expectEqual(DeckAttention.digest(input, now: now).iconTier, .waiting, "a GitLab review lights the icon")

        input.activeCards = []
        try expect(DeckAttention.digest(input, now: now).isEmpty, "what a hidden card fetched before is not news")

        var rejected = DeckAttention.Input(activeCards: [.githubPullRequests])
        rejected.pullRequests.fail(.accounts([AccountFailure(account: "Work", accountID: "work", error: APIError.unauthorized)]))
        let digest = DeckAttention.digest(rejected, now: now)
        try expectEqual(digest.iconTier, .needsFixing)
        try expectEqual(digest.items.first?.title, "Replace GitHub token (Work)")
    }

    await run.test("an update row is good to know, and only clickable when there is something to click") {
        try expectEqual(UpdateAttention.item(version: "0.15", phase: .available).action, .installUpdate)
        let waiting = UpdateAttention.item(version: "0.15", phase: .waiting(card: "ACME News"))
        try expectEqual(waiting.title, "Update to 0.15 waits for ACME News")
        try expect(!waiting.isEnabled)
        try expectEqual(UpdateAttention.item(version: "0.15", phase: .failed(reason: "offline")).title, "Update to 0.15 failed, click to retry")
    }
}
