import DevDeckCore
import Foundation
import GitHubKit

/// "GitHub inbox": what is waiting on me, loudest first.
public struct InboxCardModel: Sendable, Equatable, Codable {
    public struct Row: Sendable, Equatable, Codable, Identifiable {
        public let id: String
        /// Why the thread is here: review, mention, CI and so on.
        public let chip: String
        public let account: String?
        public let title: String
        /// A thread already read is drawn quieter than one that is not.
        public let isRead: Bool
        public let age: String
        public let help: String
        /// Nil for a thread with nowhere to go, such as a CI run with no page.
        public let command: DeckCommand?
        /// Right-click rather than a button on the row: the row is 28 points tall and already
        /// carries a chip, a repository and a title, and this is not something you do to every
        /// one of them.
        public let menu: [DeckActionModel]
    }

    /// The footer: a mark-as-read under way, the link that starts one, or the plain line.
    public struct Footer: Sendable, Equatable, Codable {
        /// Where a mark-as-read has got to, in place of the link until it is over.
        public let progress: String?
        public let progressFailed: Bool
        /// The link, and what it turns into while ⌥ is held. The shell only reads the key.
        public let clearing: DeckLinkModel?
        public let clearingWithOption: DeckLinkModel?
        /// What the footer says when there is neither.
        public let leading: String
        /// The clock, since this card's header carries the pill instead.
        public let clock: String
        public let isStale: Bool
    }

    public struct Content: Sendable, Equatable, Codable {
        public let count: String
        /// Violet when something is addressed to you, green when nothing is.
        public let countTone: DeckTone
        public let unit: String
        public let rows: [Row]
        public let expander: DeckExpanderModel?
        public let footer: Footer
    }

    public let title: String
    public let pill: DeckPillModel?
    public let content: Content?
    public let placeholder: DeckPlaceholderModel
    public let collapsed: DeckCollapsedModel
    public let isCollapsed: Bool
    public let isExpanded: Bool
    public let total: Int

    /// What the footer's link does.
    public enum Clearing: Equatable, Sendable {
        /// Everything not addressed to you: the safe one, and the default whenever something is.
        case rest
        /// The whole box, up to the newest notification shown.
        case all
    }

    public static func build(
        state: CardState<InboxSnapshot>,
        accountLabels: [String: String],
        isExpanded: Bool,
        isCollapsed: Bool,
        progress: InboxProgress?,
        now: Date
    ) -> InboxCardModel {
        let snapshot = state.value
        return InboxCardModel(
            title: L("card.chrome.inbox"),
            pill: pill(state),
            content: snapshot.map { content($0, state: state, accountLabels: accountLabels, isExpanded: isExpanded, progress: progress, now: now) },
            placeholder: DeckPlaceholderModel(state),
            collapsed: collapsed(state),
            isCollapsed: isCollapsed,
            isExpanded: isExpanded,
            total: snapshot?.items.count ?? 0
        )
    }

    /// The link the footer offers, or nil when there is nothing to read.
    ///
    /// With a mix, it reads what is not addressed to you and ⌥ turns it into all. With only one
    /// kind left it reads all of it, with the count. It used to offer nothing when everything
    /// unread was addressed to you, to keep it from being cleared by accident, and that left a
    /// card saying "33 unread" with no way to act on it; the number on the link is the guard.
    public static func clearing(for snapshot: InboxSnapshot, optionDown: Bool) -> (action: Clearing, title: String)? {
        guard snapshot.unreadCount > 0 else { return nil }
        let all = snapshot.isCapped ? L("card.inbox.readAll.capped") : LN("card.inbox.readAll", snapshot.unreadCount)
        if optionDown || snapshot.actionableCount == 0 { return (.all, all) }
        guard snapshot.isCapped || !snapshot.unreadNotForYou.isEmpty else { return (.all, all) }
        // Named by what stays rather than by what goes: "the rest" read as "all but the three
        // rows on the card", which is not what it does.
        return (.rest, LN("card.inbox.readRest", snapshot.actionableCount))
    }

    /// The count, with a plus when the box did not fit in what the card loaded.
    public static func unreadText(for snapshot: InboxSnapshot) -> String {
        snapshot.isCapped ? "\(snapshot.unreadCount)+" : "\(snapshot.unreadCount)"
    }

    /// The footer's words for a mark-as-read in progress or just over.
    public static func progressText(_ progress: InboxProgress) -> String {
        switch progress {
        case .gathering: return L("card.inbox.progress.gathering")
        case .marking(let done, let total): return L("card.inbox.progress.marking", done, total)
        case .markingAll: return L("card.inbox.progress.markingAll")
        case .finished(let count?): return LN("card.inbox.progress.finished", count)
        case .finished(nil): return L("card.inbox.progress.finishedAll")
        case .failed(let reason): return L("card.inbox.progress.failed", reason)
        }
    }

    private static func pill(_ state: CardState<InboxSnapshot>) -> DeckPillModel? {
        if let failure = state.failure, state.value == nil {
            return DeckPillModel(failure.displayMessage, tone: .alert)
        }
        guard let snapshot = state.value else { return nil }
        if snapshot.actionableCount > 0 {
            return DeckPillModel(L("card.inbox.forYou", snapshot.actionableCount), tone: .personal)
        }
        return snapshot.unreadCount == 0
            ? DeckPillModel(L("card.pill.clear"), tone: .good)
            : DeckPillModel(L("card.inbox.nothingForYou"), tone: .neutral)
    }

    private static func content(
        _ snapshot: InboxSnapshot,
        state: CardState<InboxSnapshot>,
        accountLabels: [String: String],
        isExpanded: Bool,
        progress: InboxProgress?,
        now: Date
    ) -> Content {
        let card = CardID.githubInbox
        let total = snapshot.items.count
        let rows = snapshot.prioritized(limit: CardMetrics.rowCount(total: total, isExpanded: isExpanded)).map { item in
            let open = item.url.map { DeckCommand.openLink($0, account: item.accountID, service: .github) }
            var menu = [DeckActionModel(L("card.inbox.markRead"), command: .markRead(threadID: item.id))]
            if let open { menu.append(DeckActionModel(L("card.inbox.openOnGitHub"), command: open)) }
            return Row(
                id: item.id,
                chip: item.reason.chip,
                account: accountLabels.count > 1 ? accountLabels[item.accountID] : nil,
                title: item.title,
                isRead: !item.isUnread,
                age: DeckCardTime.age(from: item.updatedAt, to: now),
                help: L("attention.row.colon", item.shortRepository, item.title),
                command: open,
                menu: menu
            )
        }
        let expander = CardMetrics.showsExpander(total: total)
            ? DeckExpanderModel(
                label: isExpanded ? L("card.showLess") : L("card.showMore", total - CardMetrics.collapsedRows),
                isExpanded: isExpanded,
                command: .toggleExpanded(card)
            )
            : nil
        // The link takes the place of the repository count, which said little.
        let offersLink = snapshot.failures.isEmpty && snapshot.unreadCount > 0
        return Content(
            count: unreadText(for: snapshot),
            countTone: snapshot.actionableCount > 0 ? .personal : .good,
            unit: L("card.inbox.unread.word"),
            rows: rows,
            expander: expander,
            footer: Footer(
                progress: progress.map(progressText),
                progressFailed: progress?.isFailure ?? false,
                clearing: offersLink ? link(snapshot, optionDown: false) : nil,
                clearingWithOption: offersLink ? link(snapshot, optionDown: true) : nil,
                leading: snapshot.failures.summary
                    ?? (snapshot.items.isEmpty ? L("card.inbox.empty") : LN("card.repos", snapshot.repositoryCount)),
                clock: DeckCardTime.header(for: state),
                isStale: state.failure != nil || !snapshot.failures.isEmpty || state.isStale(now: now, maxAge: 600)
            )
        )
    }

    private static func link(_ snapshot: InboxSnapshot, optionDown: Bool) -> DeckLinkModel? {
        guard let clearing = clearing(for: snapshot, optionDown: optionDown) else { return nil }
        return DeckLinkModel(
            title: clearing.title,
            help: clearing.action == .rest ? L("card.inbox.readRest.help") : clearing.title,
            command: clearing.action == .all ? .markAllRead : .markRestRead
        )
    }

    /// Unread is the number, and what is waiting on you is the part worth colour.
    private static func collapsed(_ state: CardState<InboxSnapshot>) -> DeckCollapsedModel {
        let note: String
        let tone: DeckTone
        if let snapshot = state.value {
            if snapshot.actionableCount > 0 {
                note = L("card.inbox.forYouUnread", snapshot.actionableCount, snapshot.unreadCount)
                tone = .attention
            } else if snapshot.unreadCount == 0 {
                note = L("card.pill.clear")
                tone = .good
            } else {
                note = L("card.inbox.unread", snapshot.unreadCount)
                tone = .neutral
            }
        } else {
            note = state.failure?.displayMessage ?? L("card.pill.loading")
            tone = .neutral
        }
        return DeckCollapsedModel(
            mark: .github,
            title: L("card.title.inbox"),
            note: note,
            tone: tone,
            actions: [DeckActionModel(L("card.action.openInBrowser"), glyph: .openExternal, command: .openDashboard(.githubInbox))],
            help: note
        )
    }
}
