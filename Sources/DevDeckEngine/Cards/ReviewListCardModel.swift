import DevDeckCore
import Foundation
import GitHubKit
import GitLabKit

/// The pull requests card and the merge requests card, which are one card with the nouns changed.
///
/// Same layout, same order, same vocabulary for the three states: two cards on one desktop that
/// answer the same question in two shapes would be two things to learn instead of one. Both
/// show yours plus the ones waiting on a review from you; a review someone is waiting on sits
/// just under the blocked ones and carries an eye rather than the code of its own state, because
/// what matters about it is not whether its checks pass but that it is not yours.
public struct ReviewListCardModel: Sendable, Equatable, Codable {
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

    /// One share of the health bar: how many open requests are in one state.
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
    /// Every open request, shown or not, which is what the card's height follows.
    public let total: Int

    /// The GitHub card. `accountLabels`: label by account id; with more than one, rows carry
    /// their account.
    public static func pullRequests(
        state: CardState<PullRequestsSnapshot>,
        accountLabels: [String: String],
        isExpanded: Bool,
        isCollapsed: Bool,
        now: Date
    ) -> ReviewListCardModel {
        let snapshot = state.value
        let input = snapshot.map { snapshot in
            Input(
                totalCount: snapshot.totalCount,
                blockedCount: snapshot.blockedCount,
                reviewRequestCount: snapshot.reviewRequestCount,
                healths: snapshot.pullRequests.map { tone(of: $0.health) },
                rows: snapshot.prioritized(limit: CardMetrics.rowCount(total: snapshot.pullRequests.count, isExpanded: isExpanded)).map {
                    InputRow(
                        id: $0.id, tone: tone(of: $0.health), accountID: $0.accountID, isReviewRequest: $0.isReviewRequest,
                        key: $0.ticket.key, subject: $0.ticket.subject, trailing: $0.statusCode,
                        help: L("attention.row.colon", $0.shortLabel, $0.statusLine), url: $0.url
                    )
                },
                failures: snapshot.failures,
                covers: L("card.footer.pair", LN("card.repos", snapshot.repositoryCount), LN("card.orgs", snapshot.organizationCount))
            )
        }
        return build(
            card: .githubPullRequests, title: L("card.chrome.pulls"), collapsedTitle: L("card.title.pulls"),
            mark: .github, service: .github, state: state, input: input,
            accountLabels: accountLabels, isExpanded: isExpanded, isCollapsed: isCollapsed, now: now
        )
    }

    /// The GitLab card.
    public static func mergeRequests(
        state: CardState<MergeRequestsSnapshot>,
        accountLabels: [String: String],
        isExpanded: Bool,
        isCollapsed: Bool,
        now: Date
    ) -> ReviewListCardModel {
        let snapshot = state.value
        let input = snapshot.map { snapshot in
            Input(
                totalCount: snapshot.totalCount,
                blockedCount: snapshot.blockedCount,
                reviewRequestCount: snapshot.reviewRequestCount,
                healths: snapshot.mergeRequests.map { tone(of: $0.health) },
                rows: snapshot.prioritized(limit: CardMetrics.rowCount(total: snapshot.mergeRequests.count, isExpanded: isExpanded)).map {
                    InputRow(
                        id: $0.id, tone: tone(of: $0.health), accountID: $0.accountID, isReviewRequest: $0.isReviewRequest,
                        key: $0.ticket.key, subject: $0.ticket.subject, trailing: $0.statusCode,
                        help: L("attention.row.colon", $0.shortLabel, $0.statusLine), url: $0.url
                    )
                },
                failures: snapshot.failures,
                covers: L("card.footer.pair", LN("card.projects", snapshot.projectCount), LN("card.groups", snapshot.groupCount))
            )
        }
        return build(
            card: .gitlabMergeRequests, title: L("card.chrome.merges"), collapsedTitle: L("card.title.merges"),
            mark: .gitlab, service: .gitlab, state: state, input: input,
            accountLabels: accountLabels, isExpanded: isExpanded, isCollapsed: isCollapsed, now: now
        )
    }

    // MARK: Shared by both

    /// What either snapshot comes down to, once its own nouns are spent.
    private struct Input {
        let totalCount: Int
        let blockedCount: Int
        let reviewRequestCount: Int
        /// Every request's state, shown or not, for the bar.
        let healths: [DeckTone]
        let rows: [InputRow]
        let failures: [AccountFailure]
        /// What the card covers: repositories and organisations, or projects and groups.
        let covers: String
    }

    private struct InputRow {
        let id: String
        let tone: DeckTone
        let accountID: String
        let isReviewRequest: Bool
        let key: String?
        let subject: String
        let trailing: String
        let help: String
        let url: URL
    }

    private static func build<Value: Sendable & Equatable>(
        card: CardID,
        title: String,
        collapsedTitle: String,
        mark: DeckMark,
        service: DeckLinkService,
        state: CardState<Value>,
        input: Input?,
        accountLabels: [String: String],
        isExpanded: Bool,
        isCollapsed: Bool,
        now: Date
    ) -> ReviewListCardModel {
        ReviewListCardModel(
            title: title,
            mark: mark,
            timestamp: DeckCardTime.header(for: state),
            content: input.map { content($0, card: card, service: service, state: state, accountLabels: accountLabels, isExpanded: isExpanded, now: now) },
            placeholder: DeckPlaceholderModel(state),
            collapsed: collapsed(input, state: state, card: card, title: collapsedTitle, mark: mark),
            isCollapsed: isCollapsed,
            isExpanded: isExpanded,
            total: input?.healths.count ?? 0
        )
    }

    private static func content<Value: Sendable & Equatable>(
        _ input: Input,
        card: CardID,
        service: DeckLinkService,
        state: CardState<Value>,
        accountLabels: [String: String],
        isExpanded: Bool,
        now: Date
    ) -> Content {
        let total = input.healths.count
        let shares = [DeckTone.alert, .attention, .good]
            .map { tone in Share(tone: tone, count: input.healths.filter { $0 == tone }.count) }
            .filter { $0.count > 0 }
        let rows = input.rows.map { request in
            Row(
                id: request.id,
                tone: request.tone,
                account: accountLabels.count > 1 ? accountLabels[request.accountID] : nil,
                // Not mine: the row is here because somebody is waiting, and the eye needs to
                // know that before it reads the title.
                icon: request.isReviewRequest ? DeckIconModel(.review, tone: .attention, help: L("card.waitingReview")) : nil,
                key: request.key,
                title: request.subject,
                trailing: request.trailing,
                help: request.help,
                command: .openLink(request.url, account: request.accountID, service: service)
            )
        }
        let expander = CardMetrics.showsExpander(total: total)
            ? DeckExpanderModel(
                label: isExpanded ? L("card.showLess") : L("card.showMore", total - CardMetrics.collapsedRows),
                isExpanded: isExpanded,
                command: .toggleExpanded(card)
            )
            : nil
        var covers = input.covers
        // Only the rows beyond the expanded ceiling are worth mentioning; the ones the expander
        // would reveal are its own business.
        let beyondCeiling = CardMetrics.hiddenWhenExpanded(total: total)
        if isExpanded, beyondCeiling > 0 { covers += L("card.notShown", beyondCeiling) }
        return Content(
            count: input.totalCount,
            unit: L("card.open"),
            pill: pill(input),
            shares: shares,
            rows: rows,
            expander: expander,
            // The clock is in the header, so the footer says what the header cannot: which
            // accounts came back empty, and whether what is on screen is still fresh.
            footer: DeckFooterModel(
                leading: input.failures.summary ?? covers,
                trailing: state.isStale(now: now, maxAge: 600) ? DeckCardTime.asOf(state) : nil,
                isStale: state.failure != nil || !input.failures.isEmpty
            )
        )
    }

    private static func pill(_ input: Input) -> DeckPillModel {
        if input.blockedCount > 0 {
            return DeckPillModel(L("card.pill.blocked", input.blockedCount), tone: .alert)
        }
        // Someone waiting on you outranks anything of yours that is merely in progress.
        if input.reviewRequestCount > 0 {
            return DeckPillModel(L("card.pill.toReview", input.reviewRequestCount), tone: .attention)
        }
        if input.totalCount == 0 {
            return DeckPillModel(L("card.pill.clear"), tone: .good)
        }
        return DeckPillModel(L("card.pill.onTrack"), tone: .good)
    }

    /// One row, for a card folded down: a list card has no lifecycle to offer, so its single
    /// action is the one thing it can do, open the same list on the web.
    private static func collapsed<Value: Sendable & Equatable>(
        _ input: Input?,
        state: CardState<Value>,
        card: CardID,
        title: String,
        mark: DeckMark
    ) -> DeckCollapsedModel {
        let note: String
        let tone: DeckTone
        if let input {
            if input.blockedCount > 0 {
                note = L("card.pill.blockedOpen", input.blockedCount, input.totalCount)
                tone = .alert
            } else if input.reviewRequestCount > 0 {
                note = L("card.pill.toReviewOpen", input.reviewRequestCount, input.totalCount)
                tone = .attention
            } else {
                note = input.totalCount == 0 ? L("card.pill.clear") : L("card.pill.open", input.totalCount)
                tone = .good
            }
        } else {
            note = state.failure?.displayMessage ?? L("card.pill.loading")
            tone = .neutral
        }
        return DeckCollapsedModel(
            mark: mark,
            title: title,
            note: note,
            tone: tone,
            actions: [DeckActionModel(L("card.action.openInBrowser"), glyph: .openExternal, command: .openDashboard(card))],
            help: note
        )
    }

    private static func tone(of health: PullRequestHealth) -> DeckTone {
        switch health {
        case .blocked: return .alert
        case .attention: return .attention
        case .ready: return .good
        }
    }

    private static func tone(of health: MergeRequestHealth) -> DeckTone {
        switch health {
        case .blocked: return .alert
        case .attention: return .attention
        case .ready: return .good
        }
    }
}
