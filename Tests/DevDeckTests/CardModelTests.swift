import DevDeckCore
import DevDeckEngine
import Foundation
import GitHubKit
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
) -> PullRequestsCardModel {
    PullRequestsCardModel.build(state: state, accountLabels: labels, isExpanded: isExpanded, isCollapsed: isCollapsed, now: cardNow)
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
}
