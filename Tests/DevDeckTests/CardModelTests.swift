import DevDeckCore
import DevDeckEngine
import Foundation
import GitHubKit
import GitLabKit
import TestHarness

// What a card shows, decided in the engine and checked here without drawing anything. Every
// branch that used to sit in a SwiftUI view has a check of its own.

private let cardNow = Date(timeIntervalSince1970: 1_790_000_000)

/// A pull request in the given state, and nothing else about it worth reading.
private func pullRequest(
    _ id: String,
    _ health: PullRequestHealth,
    account: String = "work",
    review: Bool = false
) -> PullRequestSummary {
    PullRequestSummary(
        id: id,
        number: 1,
        title: "PROJ-1 \(id)",
        repository: "acme/site",
        organization: "acme",
        url: URL(string: "https://github.com/acme/site/pull/1")!,
        isDraft: false,
        updatedAt: cardNow,
        reviewDecision: health == .blocked ? .changesRequested : (health == .ready ? .approved : .reviewRequired),
        checks: health == .blocked ? .failure : .success,
        unresolvedThreads: 0,
        accountID: account,
        isReviewRequest: review
    )
}

private func pullsState(_ requests: [PullRequestSummary], failures: [AccountFailure] = [], at date: Date = cardNow) -> CardState<PullRequestsSnapshot> {
    var state = CardState<PullRequestsSnapshot>()
    state.succeed(PullRequestsSnapshot(totalCount: requests.count, pullRequests: requests, failures: failures), at: date)
    return state
}

private func pullsModel(
    _ state: CardState<PullRequestsSnapshot>,
    labels: [String: String] = ["work": "Work"],
    isExpanded: Bool = false,
    isCollapsed: Bool = false
) -> ReviewListCardModel {
    ReviewListCardModel.pullRequests(state: state, accountLabels: labels, isExpanded: isExpanded, isCollapsed: isCollapsed, now: cardNow)
}


private func thread(_ id: String, _ reason: NotificationReason, unread: Bool = true, url: Bool = true) -> InboxItem {
    InboxItem(
        id: id, reason: reason, title: "Thread \(id)", repository: "acme/site",
        updatedAt: cardNow.addingTimeInterval(-600), isUnread: unread,
        url: url ? URL(string: "https://github.com/acme/site/issues/\(id)") : nil, accountID: "work"
    )
}

private func inboxModel(
    _ items: [InboxItem],
    failures: [AccountFailure] = [],
    progress: InboxProgress? = nil
) -> InboxCardModel {
    var state = CardState<InboxSnapshot>()
    state.succeed(InboxSnapshot(items: items, failures: failures), at: cardNow)
    return InboxCardModel.build(state: state, accountLabels: ["work": "Work"], isExpanded: false, isCollapsed: false, progress: progress, now: cardNow)
}

private func workflowRun(_ id: Int, _ conclusion: RunConclusion, status: RunStatus = .completed) -> WorkflowRun {
    WorkflowRun(
        id: id, name: "CI", repository: "acme/site", branch: "main", status: status, conclusion: conclusion,
        startedAt: cardNow.addingTimeInterval(-900), updatedAt: cardNow.addingTimeInterval(-600),
        url: URL(string: "https://github.com/acme/site/actions/runs/\(id)"), accountID: "work", isOnDefaultBranch: true
    )
}

private func actionsModel(_ runs: [WorkflowRun], repositories: [String] = ["acme/site"], follows: Bool = true) -> ActionsCardModel {
    var state = CardState<ActionsSnapshot>()
    state.succeed(ActionsSnapshot(runs: runs, windowDays: 7, repositories: repositories), at: cardNow)
    return ActionsCardModel.build(state: state, followsPullRequests: follows, isCollapsed: false, now: cardNow)
}

private func checkout(_ id: String, dirty: Int = 0, ahead: Int = 0) -> CheckoutState {
    CheckoutState(id: id, title: id, branch: "main", dirtyFiles: dirty, ahead: ahead, behind: 0, hasUpstream: true)
}

func runCardModelTests(_ run: TestRun) async {
    run.section("Card models - pull requests")

    await run.test("the pill names the loudest thing: blocked, then reviews, then empty, then on track") {
        let blocked = pullsModel(pullsState([pullRequest("a", .blocked), pullRequest("b", .attention, review: true)]))
        try expectEqual(blocked.content?.pill, DeckPillModel("1 blocked", tone: .alert))

        let review = pullsModel(pullsState([pullRequest("a", .ready), pullRequest("b", .attention, review: true)]))
        try expectEqual(review.content?.pill, DeckPillModel("1 to review", tone: .attention))

        let empty = pullsModel(pullsState([]))
        try expectEqual(empty.content?.pill?.tone, .good)
        try expectEqual(empty.content?.pill?.text, L("card.pill.clear"))

        let fine = pullsModel(pullsState([pullRequest("a", .ready), pullRequest("b", .attention)]))
        try expectEqual(fine.content?.pill, DeckPillModel(L("card.pill.onTrack"), tone: .good))
    }

    await run.test("folded, the card says the same thing in one line") {
        let blocked = pullsModel(pullsState([pullRequest("a", .blocked), pullRequest("b", .ready)]), isCollapsed: true)
        try expectEqual(blocked.collapsed.note, L("card.pill.blockedOpen", 1, 2))
        try expectEqual(blocked.collapsed.tone, .alert)
        try expect(blocked.isCollapsed)

        let review = pullsModel(pullsState([pullRequest("b", .attention, review: true)]))
        try expectEqual(review.collapsed.tone, .attention)

        let loading = pullsModel(CardState<PullRequestsSnapshot>())
        try expectEqual(loading.collapsed.note, L("card.pill.loading"))
        try expectEqual(loading.collapsed.tone, .neutral)
        try expectEqual(loading.collapsed.actions.map(\.command), [.openDashboard(.githubPullRequests)])
    }

    await run.test("before the first answer there is a placeholder, and the failure when there is one") {
        let waiting = pullsModel(CardState<PullRequestsSnapshot>())
        try expectNil(waiting.content)
        try expect(!waiting.placeholder.isFailure)

        var refused = CardState<PullRequestsSnapshot>()
        refused.fail(.missingToken("GitHub"))
        let model = pullsModel(refused)
        try expect(model.placeholder.isFailure)
        try expectEqual(model.placeholder.hint, L("card.addToken", "GitHub"))
        try expectEqual(model.timestamp, model.placeholder.message, "the header says what broke instead of a clock")
    }

    await run.test("rows name their account only when there is more than one") {
        let state = pullsState([pullRequest("a", .blocked, account: "work"), pullRequest("b", .ready, account: "home")])
        try expect(pullsModel(state).content?.rows.allSatisfy { $0.account == nil } == true)
        let two = pullsModel(state, labels: ["work": "Work", "home": "Home"])
        try expectEqual(two.content?.rows.map(\.account), ["Work", "Home"])
    }

    await run.test("a review request wears the eye, and every row opens in its own account") {
        let model = pullsModel(pullsState([pullRequest("a", .attention, account: "home", review: true)]))
        let row = try expectNotNil(model.content?.rows.first, "row")
        try expectEqual(row.icon, DeckIconModel(.review, tone: .attention, help: L("card.waitingReview")))
        try expectEqual(row.command, .openLink(URL(string: "https://github.com/acme/site/pull/1")!, account: "home", service: .github))
    }

    await run.test("blocked rows come first, and the bar counts every state that has any") {
        let model = pullsModel(pullsState([pullRequest("r", .ready), pullRequest("b", .blocked), pullRequest("r2", .ready)]))
        try expectEqual(model.content?.rows.first?.id, "b")
        try expectEqual(model.content?.rows.first?.tone, .alert)
        try expectEqual(model.content?.shares.map(\.tone), [.alert, .good])
        try expectEqual(model.content?.shares.map(\.count), [1, 2])
    }

    await run.test("the expander is there only when it hides something, and says how much") {
        let three = pullsModel(pullsState((1...3).map { pullRequest("p\($0)", .ready) }))
        try expectNil(three.content?.expander)

        let five = (1...5).map { pullRequest("p\($0)", .ready) }
        let folded = pullsModel(pullsState(five))
        try expectEqual(folded.content?.expander?.label, L("card.showMore", 2))
        try expectEqual(folded.content?.rows.count, 3)
        let open = pullsModel(pullsState(five), isExpanded: true)
        try expectEqual(open.content?.expander?.label, L("card.showLess"))
        try expectEqual(open.content?.rows.count, 5)
        try expectEqual(open.content?.expander?.command, .toggleExpanded(.githubPullRequests))
    }

    await run.test("the footer counts what the card covers, or names the accounts that failed") {
        let fine = pullsModel(pullsState([pullRequest("a", .ready)]))
        try expectEqual(fine.content?.footer.leading, L("card.footer.pair", LN("card.repos", 1), LN("card.orgs", 1)))
        try expectEqual(fine.content?.footer.isStale, false)

        let failure = AccountFailure(account: "Home", message: "token rejected", kind: .rejected)
        let partial = pullsModel(pullsState([pullRequest("a", .ready)], failures: [failure]))
        try expectEqual(partial.content?.footer.leading, [failure].summary)
        try expectEqual(partial.content?.footer.isStale, true)

        let many = pullsModel(pullsState((1...14).map { pullRequest("p\($0)", .ready) }), isExpanded: true)
        try expect(many.content?.footer.leading.hasSuffix(L("card.notShown", 2)) == true, "rows beyond the ceiling are owned up to")
    }

    await run.test("data that stopped moving says since when, after ten minutes") {
        let fresh = pullsModel(pullsState([pullRequest("a", .ready)], at: cardNow.addingTimeInterval(-300)))
        try expectNil(fresh.content?.footer.trailing)
        let old = pullsModel(pullsState([pullRequest("a", .ready)], at: cardNow.addingTimeInterval(-900)))
        try expect(old.content?.footer.trailing?.isEmpty == false)
    }

    await run.test("the card speaks the reader's language") {
        Strings.use(.russian, lookingIn: localisationRoot)
        let model = pullsModel(pullsState([pullRequest("a", .blocked)]))
        Strings.use(.english, lookingIn: localisationRoot)
        try expectEqual(model.content?.unit, "открыто")
        try expect(model.content?.pill?.text.contains("заблок") == true, "got \(model.content?.pill?.text ?? "nil")")
    }

    run.section("Card models - merge requests")

    await run.test("the GitLab card is the pull requests card with GitLab's nouns and links") {
        let request = MergeRequestSummary(
            id: "mr1", iid: 7, title: "PROJ-2 Tidy", project: "acme/site", url: URL(string: "https://gitlab.com/acme/site/-/merge_requests/7")!,
            isDraft: false, hasConflicts: false, updatedAt: cardNow, pipeline: .failed, approvalsLeft: 0, unresolvedThreads: 0, accountID: "lab"
        )
        var state = CardState<MergeRequestsSnapshot>()
        state.succeed(MergeRequestsSnapshot(totalCount: 1, mergeRequests: [request]), at: cardNow)
        let model = ReviewListCardModel.mergeRequests(state: state, accountLabels: ["lab": "Lab"], isExpanded: false, isCollapsed: false, now: cardNow)
        try expectEqual(model.mark, .gitlab)
        try expectEqual(model.title, L("card.chrome.merges"))
        try expectEqual(model.content?.rows.first?.command, .openLink(request.url, account: "lab", service: .gitlab))
        try expectEqual(model.content?.footer.leading, L("card.footer.pair", LN("card.projects", 1), LN("card.groups", 1)))
        try expectEqual(model.collapsed.actions.first?.command, .openDashboard(.gitlabMergeRequests))
    }

    run.section("Card models - inbox")

    await run.test("the pill is violet for what is addressed to you, quiet for the rest, green for none") {
        try expectEqual(inboxModel([thread("1", .mention), thread("2", .ciActivity)]).pill?.tone, .personal)
        try expectEqual(inboxModel([thread("2", .ciActivity)]).pill, DeckPillModel(L("card.inbox.nothingForYou"), tone: .neutral))
        try expectEqual(inboxModel([]).pill, DeckPillModel(L("card.pill.clear"), tone: .good))
        try expectEqual(inboxModel([thread("1", .mention)]).content?.countTone, .personal)
        try expectEqual(inboxModel([thread("2", .ciActivity)]).content?.countTone, .good)
    }

    await run.test("the footer offers the rest, ⌥ turns it into all, and a run in progress replaces both") {
        let mixed = inboxModel([thread("1", .mention), thread("2", .ciActivity)])
        try expectEqual(mixed.content?.footer.clearing?.command, .markRestRead)
        try expectEqual(mixed.content?.footer.clearingWithOption?.command, .markAllRead)
        try expectEqual(mixed.content?.footer.clearing?.help, L("card.inbox.readRest.help"))

        let mine = inboxModel([thread("1", .mention)])
        try expectEqual(mine.content?.footer.clearing?.command, .markAllRead, "only one kind left reads all of it")

        let running = inboxModel([thread("1", .mention)], progress: .marking(done: 1, total: 4))
        try expectEqual(running.content?.footer.progress, InboxCardModel.progressText(.marking(done: 1, total: 4)))
        try expect(running.content?.footer.progressFailed == false)

        let failure = AccountFailure(account: "Home", message: "token rejected", kind: .rejected)
        let broken = inboxModel([thread("1", .mention)], failures: [failure])
        try expectNil(broken.content?.footer.clearing, "no link while an account is failing")
        try expectEqual(broken.content?.footer.leading, [failure].summary)
    }

    await run.test("a row with no page cannot be clicked, but can still be marked read") {
        let model = inboxModel([thread("9", .ciActivity, unread: false, url: false)])
        let row = try expectNotNil(model.content?.rows.first, "row")
        try expectNil(row.command)
        try expect(row.isRead)
        try expectEqual(row.menu.map(\.command), [.markRead(threadID: "9")])

        let linked = try expectNotNil(inboxModel([thread("3", .mention)]).content?.rows.first, "row")
        try expectEqual(linked.menu.count, 2)
        try expectEqual(linked.command, .openLink(URL(string: "https://github.com/acme/site/issues/3")!, account: "work", service: .github))
    }

    await run.test("folded, what is waiting on you is amber and nothing unread is green") {
        try expectEqual(inboxModel([thread("1", .mention)]).collapsed.tone, .attention)
        try expectEqual(inboxModel([]).collapsed.tone, .good)
        try expectEqual(inboxModel([thread("2", .ciActivity)]).collapsed.tone, .neutral)
    }

    run.section("Card models - actions")

    await run.test("with nothing to watch the card says why, and points at the setting") {
        let model = actionsModel([], repositories: [])
        try expectEqual(model.pill, DeckPillModel(L("card.actions.noOpenPRs"), tone: .neutral))
        guard case .unconfigured(let notice)? = model.content else {
            throw TestFailure(message: "expected the unconfigured notice", file: #filePath, line: #line)
        }
        try expectEqual(notice.link?.command, .openSetting(.actionsRepositories))
    }

    await run.test("repositories with no runs are a quiet card, not a broken one") {
        guard case .quiet(let notice, _)? = actionsModel([]).content else {
            throw TestFailure(message: "expected the quiet notice", file: #filePath, line: #line)
        }
        try expectEqual(notice.title, LN("card.actions.quiet.title", 7))
        try expectNil(notice.link)
    }

    await run.test("the rate is the headline, coloured by how good it is, and failures are the rows") {
        guard case .runs(let headline, let tone, _, let rows, _)? = actionsModel([workflowRun(1, .success), workflowRun(2, .success), workflowRun(3, .success), workflowRun(4, .failure)]).content else {
            throw TestFailure(message: "expected runs", file: #filePath, line: #line)
        }
        try expectEqual(headline, "75")
        try expectEqual(tone, .alert)
        try expectEqual(rows.map(\.id), [4])
        try expectEqual(rows.first?.tone, .alert)

        guard case .runs(_, let goodTone, _, let active, _)? = actionsModel([workflowRun(1, .success), workflowRun(5, .none, status: .inProgress)]).content else {
            throw TestFailure(message: "expected runs", file: #filePath, line: #line)
        }
        try expectEqual(goodTone, .good)
        try expectEqual(active.first?.tone, .attention, "with no failures, what is running")
        try expectEqual(active.first?.trailing, L("card.state.running"))
    }

    run.section("Card models - work in flight")

    await run.test("unpushed work is the loud part, and a row opens a terminal in its checkout") {
        let model = WorkInFlightCardModel.build(
            states: [checkout("site", ahead: 2), checkout("api", dirty: 3), checkout("clean")],
            checkedAt: cardNow, isExpanded: false, isCollapsed: false
        )
        try expectEqual(model.count, 2)
        try expectEqual(model.pill, DeckPillModel(L("card.wif.unpushed", 1), tone: .attention))
        try expectEqual(model.rows.map(\.tone), [.attention, .neutral])
        try expectEqual(model.rows.first?.command, .openCheckout(id: "site"))
        try expectEqual(model.collapsed.tone, .attention)
        try expectEqual(model.footer.leading, LN("card.wif.watched", 3))
    }

    await run.test("a clean deck says so, folded too, in the reader's language") {
        Strings.use(.russian, lookingIn: localisationRoot)
        let model = WorkInFlightCardModel.build(states: [checkout("clean")], checkedAt: nil, isExpanded: false, isCollapsed: true)
        let title = L("card.title.workInFlight")
        Strings.use(.english, lookingIn: localisationRoot)
        try expectEqual(model.collapsed.title, title, "the folded title was English in every language")
        try expectEqual(model.collapsed.tone, .good)
        try expectNil(model.pill)
    }
}
