import DevDeckCore
import Foundation
import GitHubKit

/// Pull requests: yours, plus the ones waiting on a review from you.
///
/// Both halves of "what do I owe today" on one card. A review someone is waiting on sits just
/// under the blocked ones and carries an eye rather than the two-letter code of its own state:
/// what matters about it is not whether its checks pass but that it is not yours.
public struct PullRequestsCardModel: Sendable, Equatable, Codable {
    public struct Row: Sendable, Equatable, Codable, Identifiable {
        public let id: String
        public let tone: DeckTone
        /// Which account the row came from, only when there is more than one to tell apart.
        public let account: String?
        /// Set when the row is here because somebody is waiting on you.
        public let icon: DeckIconModel?
        /// The ticket key, in its own column: left in the sentence it eats the width the subject
        /// needs.
        public let key: String?
        public let title: String
        public let trailing: String
        public let help: String
        public let command: DeckCommand
    }

    /// One share of the health bar: how many open pull requests are in one state.
    public struct Share: Sendable, Equatable, Codable {
        public let tone: DeckTone
        public let count: Int
    }

    public struct Content: Sendable, Equatable, Codable {
        public let count: Int
        public let unit: String
        public let pill: DeckPillModel?
        /// In the order blocked, attention, ready, leaving out the empty ones.
        public let shares: [Share]
        public let rows: [Row]
        public let expander: DeckExpanderModel?
        public let footer: DeckFooterModel
    }

    public let title: String
    public let mark: DeckMark
    public let timestamp: String
    /// Nil until the first answer; then the placeholder gives way to the content.
    public let content: Content?
    public let placeholder: DeckPlaceholderModel
    public let collapsed: DeckCollapsedModel
    public let isCollapsed: Bool
    public let isExpanded: Bool
    /// Every open pull request, shown or not, which is what the card's height follows.
    public let total: Int

    /// Everything the card shows, decided.
    ///
    /// - `accountLabels`: label by account id; with more than one, rows carry their account.
    public static func build(
        state: CardState<PullRequestsSnapshot>,
        accountLabels: [String: String],
        isExpanded: Bool,
        isCollapsed: Bool,
        now: Date
    ) -> PullRequestsCardModel {
        let card = CardID.githubPullRequests
        let snapshot = state.value
        return PullRequestsCardModel(
            title: L("card.chrome.pulls"),
            mark: .github,
            timestamp: DeckCardTime.header(for: state),
            content: snapshot.map { content($0, state: state, accountLabels: accountLabels, isExpanded: isExpanded, now: now) },
            placeholder: DeckPlaceholderModel(state),
            collapsed: collapsed(state, card: card),
            isCollapsed: isCollapsed,
            isExpanded: isExpanded,
            total: snapshot?.pullRequests.count ?? 0
        )
    }

    private static func content(
        _ snapshot: PullRequestsSnapshot,
        state: CardState<PullRequestsSnapshot>,
        accountLabels: [String: String],
        isExpanded: Bool,
        now: Date
    ) -> Content {
        let card = CardID.githubPullRequests
        let total = snapshot.pullRequests.count
        let shares = [(DeckTone.alert, PullRequestHealth.blocked), (.attention, .attention), (.good, .ready)]
            .map { tone, health in Share(tone: tone, count: snapshot.pullRequests.filter { $0.health == health }.count) }
            .filter { $0.count > 0 }
        let rows = snapshot.prioritized(limit: CardMetrics.rowCount(total: total, isExpanded: isExpanded)).map { request in
            Row(
                id: request.id,
                tone: tone(of: request.health),
                account: accountLabels.count > 1 ? accountLabels[request.accountID] : nil,
                // Not mine: the row is here because somebody is waiting, and the eye needs to
                // know that before it reads the title.
                icon: request.isReviewRequest ? DeckIconModel(.review, tone: .attention, help: L("card.waitingReview")) : nil,
                key: request.ticket.key,
                title: request.ticket.subject,
                trailing: request.statusCode,
                help: L("attention.row.colon", request.shortLabel, request.statusLine),
                command: .openLink(request.url, account: request.accountID, service: .github)
            )
        }
        let expander = CardMetrics.showsExpander(total: total)
            ? DeckExpanderModel(
                label: isExpanded ? L("card.showLess") : L("card.showMore", total - CardMetrics.collapsedRows),
                isExpanded: isExpanded,
                command: .toggleExpanded(card)
            )
            : nil
        return Content(
            count: snapshot.totalCount,
            unit: L("card.open"),
            pill: pill(snapshot, state: state),
            shares: shares,
            rows: rows,
            expander: expander,
            // The clock is in the header, so the footer says what the header cannot: which
            // accounts came back empty, and whether what is on screen is still fresh.
            footer: DeckFooterModel(
                leading: snapshot.failures.summary ?? footerLeading(snapshot, isExpanded: isExpanded),
                trailing: state.isStale(now: now, maxAge: 600) ? DeckCardTime.asOf(state) : nil,
                isStale: state.failure != nil || !snapshot.failures.isEmpty
            )
        )
    }

    private static func pill(_ snapshot: PullRequestsSnapshot, state: CardState<PullRequestsSnapshot>) -> DeckPillModel? {
        if snapshot.blockedCount > 0 {
            return DeckPillModel(L("card.pill.blocked", snapshot.blockedCount), tone: .alert)
        }
        // Someone waiting on you outranks anything of yours that is merely in progress.
        if snapshot.reviewRequestCount > 0 {
            return DeckPillModel(L("card.pill.toReview", snapshot.reviewRequestCount), tone: .attention)
        }
        if snapshot.totalCount == 0 {
            return DeckPillModel(L("card.pill.clear"), tone: .good)
        }
        return DeckPillModel(L("card.pill.onTrack"), tone: .good)
    }

    /// One row, for a card folded down: a list card has no lifecycle to offer, so its single
    /// action is the one thing it can do, open the same list on the web.
    private static func collapsed(_ state: CardState<PullRequestsSnapshot>, card: CardID) -> DeckCollapsedModel {
        let note: String?
        let tone: DeckTone
        if let snapshot = state.value {
            if snapshot.blockedCount > 0 {
                note = L("card.pill.blockedOpen", snapshot.blockedCount, snapshot.totalCount)
                tone = .alert
            } else if snapshot.reviewRequestCount > 0 {
                note = L("card.pill.toReviewOpen", snapshot.reviewRequestCount, snapshot.totalCount)
                tone = .attention
            } else {
                note = snapshot.totalCount == 0 ? L("card.pill.clear") : L("card.pill.open", snapshot.totalCount)
                tone = .good
            }
        } else {
            note = state.failure?.displayMessage ?? L("card.pill.loading")
            tone = .neutral
        }
        return DeckCollapsedModel(
            mark: .github,
            title: L("card.title.pulls"),
            note: note,
            tone: tone,
            actions: [DeckActionModel(L("card.action.openInBrowser"), glyph: .openExternal, command: .openDashboard(card))],
            help: note ?? L("card.title.pulls")
        )
    }

    private static func footerLeading(_ snapshot: PullRequestsSnapshot, isExpanded: Bool) -> String {
        var text = L(
            "card.footer.pair",
            LN("card.repos", snapshot.repositoryCount),
            LN("card.orgs", snapshot.organizationCount)
        )
        // Only the rows beyond the expanded ceiling are worth mentioning here; the ones the
        // expander would reveal are its own business.
        let beyondCeiling = CardMetrics.hiddenWhenExpanded(total: snapshot.pullRequests.count)
        if isExpanded, beyondCeiling > 0 { text += L("card.notShown", beyondCeiling) }
        return text
    }

    private static func tone(of health: PullRequestHealth) -> DeckTone {
        switch health {
        case .blocked: return .alert
        case .attention: return .attention
        case .ready: return .good
        }
    }
}
