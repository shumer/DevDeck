import DevDeckCore
import GitHubKit
import SwiftUI

/// "GitHub inbox": what is waiting on me, loudest first.
public struct InboxCard: View {
    public nonisolated static let baseHeight: Double = 119

    private let state: CardState<InboxSnapshot>
    private let now: Date
    private let accountLabels: [String: String]
    private let isExpanded: Bool
    private let isCollapsed: Bool
    private let onOpen: (URL, String) -> Void
    private let onToggleExpand: () -> Void
    private let onOpenDashboard: () -> Void
    private let onMarkRead: (InboxItem) -> Void
    /// Reads everything not addressed to you, and everything, for the footer's link.
    private let onMarkRestRead: (() -> Void)?
    private let onMarkAllRead: (() -> Void)?
    /// Where a mark-as-read that is under way has got to, shown in the footer in place of the
    /// link until it is over.
    private let progress: Progress?

    public init(
        state: CardState<InboxSnapshot>,
        now: Date = Date(),
        accountLabels: [String: String] = [:],
        isExpanded: Bool = false,
        isCollapsed: Bool = false,
        onOpen: @escaping (URL, String) -> Void = { _, _ in },
        onToggleExpand: @escaping () -> Void = {},
        onOpenDashboard: @escaping () -> Void = {},
        onMarkRead: @escaping (InboxItem) -> Void = { _ in },
        onMarkRestRead: (() -> Void)? = nil,
        onMarkAllRead: (() -> Void)? = nil,
        progress: Progress? = nil
    ) {
        self.state = state
        self.now = now
        self.accountLabels = accountLabels
        self.isExpanded = isExpanded
        self.isCollapsed = isCollapsed
        self.onOpen = onOpen
        self.onToggleExpand = onToggleExpand
        self.onOpenDashboard = onOpenDashboard
        self.onMarkRead = onMarkRead
        self.onMarkRestRead = onMarkRestRead
        self.onMarkAllRead = onMarkAllRead
        self.progress = progress
    }

    /// A mark-as-read in flight. Without this the card said nothing for the minute a few hundred
    /// threads take, and a second press started the same work again.
    public enum Progress: Equatable, Sendable {
        /// Paging through the box for what has to be marked.
        case gathering
        /// So many of so many.
        case marking(done: Int, total: Int)
        /// One request for the whole box, nothing to count.
        case markingAll
        /// Over: how many were marked, or nil when GitHub was asked for everything at once.
        case finished(Int?)
        /// GitHub refused, with its reason.
        case failed(String)

        public var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }

        public var isRunning: Bool {
            switch self {
            case .gathering, .marking, .markingAll: return true
            case .finished, .failed: return false
            }
        }
    }

    /// The footer's words for a mark-as-read in progress or just over.
    public nonisolated static func progressText(_ progress: Progress) -> String {
        switch progress {
        case .gathering: return L("card.inbox.progress.gathering")
        case .marking(let done, let total): return L("card.inbox.progress.marking", done, total)
        case .markingAll: return L("card.inbox.progress.markingAll")
        case .finished(let count?): return LN("card.inbox.progress.finished", count)
        case .finished(nil): return L("card.inbox.progress.finishedAll")
        case .failed(let reason): return L("card.inbox.progress.failed", reason)
        }
    }

    /// What the footer's link does.
    public enum Clearing: Equatable, Sendable {
        /// Everything not addressed to you: the safe one, and the default whenever something is.
        case rest
        /// The whole box, up to the newest notification shown.
        case all
    }

    /// The link the footer offers, or nil when there is nothing to read.
    ///
    /// With a mix, it reads what is not addressed to you and ⌥ turns it into all. With only one
    /// kind left it reads all of it, with the count. It used to offer nothing when everything
    /// unread was addressed to you, to keep it from being cleared by accident, and that left a
    /// card saying "33 unread" with no way to act on it; the number on the link is the guard.
    public nonisolated static func clearing(for snapshot: InboxSnapshot, optionDown: Bool) -> (action: Clearing, title: String)? {
        guard snapshot.unreadCount > 0 else { return nil }
        let all = snapshot.isCapped ? L("card.inbox.readAll.capped") : LN("card.inbox.readAll", snapshot.unreadCount)
        if optionDown || snapshot.actionableCount == 0 { return (.all, all) }
        guard snapshot.isCapped || !snapshot.unreadNotForYou.isEmpty else { return (.all, all) }
        // Named by what stays rather than by what goes: "the rest" read as "all but the three
        // rows on the card", which is not what it does.
        return (.rest, LN("card.inbox.readRest", snapshot.actionableCount))
    }

    /// The count, with a plus when the box did not fit in what the card loaded.
    public nonisolated static func unreadText(for snapshot: InboxSnapshot) -> String {
        snapshot.isCapped ? "\(snapshot.unreadCount)+" : "\(snapshot.unreadCount)"
    }

    public nonisolated static func size(for state: CardState<InboxSnapshot>, isExpanded: Bool, isCollapsed: Bool = false) -> CGSize {
        guard !isCollapsed else {
            return CGSize(width: CardMetrics.width, height: CollapsedCardMetrics.height)
        }
        let total = state.value?.items.count ?? 0
        return CGSize(
            width: CardMetrics.width,
            height: CardMetrics.height(base: baseHeight, total: total, isExpanded: isExpanded)
        )
    }

    public var body: some View {
        if isCollapsed {
            collapsed
        } else {
            full
        }
    }

    /// One row: the mark, a dot for how loud the card is, its name and the count. A list card
    /// has no lifecycle to offer, so its single action is the one thing it can do - open the
    /// same list on the web.
    private var collapsed: some View {
        CardCollapsedRow(
            glyph: CardGlyph.github,
            title: L("card.title.inbox"),
            note: collapsedNote,
            tone: collapsedTone.tone,
            color: collapsedTone.color,
            actions: [CardAction(L("card.action.openInBrowser"), systemImage: "arrow.up.forward", action: onOpenDashboard)],
            help: collapsedNote ?? L("card.title.inbox")
        )
    }

    /// Unread is the number, and what is waiting on you is the part worth colour.
    private var collapsedNote: String? {
        guard let snapshot = state.value else { return state.failure?.displayMessage ?? L("card.pill.loading") }
        if snapshot.actionableCount > 0 { return L("card.inbox.forYouUnread", snapshot.actionableCount, snapshot.unreadCount) }
        return snapshot.unreadCount == 0 ? L("card.pill.clear") : L("card.inbox.unread", snapshot.unreadCount)
    }

    private var collapsedTone: (tone: CardStateTone, color: Color) {
        guard let snapshot = state.value else { return (.neutral, DeckTheme.label) }
        if snapshot.actionableCount > 0 { return (.alert, DeckTheme.amber) }
        return snapshot.unreadCount == 0 ? (.good, DeckTheme.green) : (.neutral, DeckTheme.label)
    }

    private var full: some View {
        CardChrome(title: L("card.chrome.inbox"), pill: pill) {
            if let snapshot = state.value {
                content(snapshot)
            } else {
                CardPlaceholder(state: state)
            }
        }
    }

    private var pill: (text: String, color: Color)? {
        if let failure = state.failure, state.value == nil {
            return (failure.displayMessage, DeckTheme.red)
        }
        guard let snapshot = state.value else { return nil }
        if snapshot.actionableCount > 0 {
            return (L("card.inbox.forYou", snapshot.actionableCount), DeckTheme.violet)
        }
        return snapshot.unreadCount == 0 ? (L("card.pill.clear"), DeckTheme.green) : (L("card.inbox.nothingForYou"), DeckTheme.label)
    }

    @ViewBuilder
    private func content(_ snapshot: InboxSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Self.unreadText(for: snapshot))
                .font(.system(size: 42, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(snapshot.actionableCount > 0 ? DeckTheme.violet : DeckTheme.green)
            Text(L("card.inbox.unread.word"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DeckTheme.label)
        }
        .padding(.top, 2)

        let total = snapshot.items.count
        let rows = CardMetrics.rowCount(total: total, isExpanded: isExpanded)

        VStack(spacing: 0) {
            ForEach(snapshot.prioritized(limit: rows)) { item in
                row(item)
            }
        }
        .padding(.top, 6)

        if CardMetrics.showsExpander(total: total) {
            CardExpander(
                hidden: total - CardMetrics.collapsedRows,
                isExpanded: isExpanded,
                onToggle: onToggleExpand
            )
        }

        Spacer(minLength: 4)

        let isStale = state.failure != nil
            || !snapshot.failures.isEmpty
            || state.isStale(now: now, maxAge: 600)
        if let progress {
            HStack {
                Text(Self.progressText(progress))
                    .foregroundStyle(progress.isFailure ? DeckTheme.amber : DeckTheme.label)
                    .truncationMode(.tail)
                    .help(Self.progressText(progress))
                Spacer(minLength: 6)
                Text(CardFreshness.text(for: state))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isStale ? DeckTheme.amber : DeckTheme.label)
                    .fixedSize()
            }
            .font(.system(size: 10.5))
            .lineLimit(1)
            .frame(height: CardFooter.height)
        } else if snapshot.failures.isEmpty, let onMarkRestRead, let onMarkAllRead, snapshot.unreadCount > 0 {
            // The link takes the place of the repository count, which said little.
            HStack {
                InboxClearLink(snapshot: snapshot, onRest: onMarkRestRead, onAll: onMarkAllRead)
                Spacer(minLength: 6)
                Text(CardFreshness.text(for: state))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isStale ? DeckTheme.amber : DeckTheme.label)
                    .fixedSize()
            }
            .font(.system(size: 10.5))
            .lineLimit(1)
            .frame(height: CardFooter.height)
        } else {
            CardFooter(
                leading: snapshot.failures.summary ?? (snapshot.items.isEmpty
                    ? L("card.inbox.empty")
                    : LN("card.repos", snapshot.repositoryCount)),
                trailing: CardFreshness.text(for: state),
                isStale: isStale
            )
        }
    }

    private func row(_ item: InboxItem) -> some View {
        HStack(spacing: 8) {
            Text(item.reason.chip)
                .font(.system(size: 10))
                .foregroundStyle(DeckTheme.label)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            if accountLabels.count > 1, let label = accountLabels[item.accountID] {
                AccountChip(label)
            }
            Text(item.title)
                .font(.system(size: 12.5))
                .foregroundStyle(item.isUnread ? DeckTheme.value : DeckTheme.label)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(RelativeTime.short(from: item.updatedAt, to: now))
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.label)
                .fixedSize()
        }
        .frame(height: CardMetrics.rowHeight - 1)
        .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
        .contentShape(Rectangle())
        .clickable(isEnabled: item.url != nil)
        .onTapGesture { if let url = item.url { onOpen(url, item.accountID) } }
        // Right-click rather than a button on the row: the row is 28 points tall and already
        // carries a chip, a repository and a title, and this is not something you do to every
        // one of them.
        .contextMenu {
            Button(L("card.inbox.markRead")) { onMarkRead(item) }
            if let url = item.url {
                Button(L("card.inbox.openOnGitHub")) { onOpen(url, item.accountID) }
            }
        }
        .help(L("attention.row.colon", item.shortRepository, item.title))
    }
}

/// The footer's link on the inbox card: "Mark the rest as read", or with ⌥ held, all of it.
///
/// ⌥ is read while the pointer is over the link, a few times a second, so the words change
/// the moment the key goes down rather than on the next mouse move. Nothing is watched while
/// the pointer is elsewhere, and no keyboard monitor is needed for it.
struct InboxClearLink: View {
    let snapshot: InboxSnapshot
    let onRest: () -> Void
    let onAll: () -> Void

    // Written out rather than as `@State`: see `ClickableHighlight`.
    private var _isOptionDown = State(initialValue: false)
    private var isOptionDown: Bool {
        get { _isOptionDown.wrappedValue }
        nonmutating set { _isOptionDown.wrappedValue = newValue }
    }
    private var _watch = State(initialValue: OptionWatch())

    init(snapshot: InboxSnapshot, onRest: @escaping () -> Void, onAll: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onRest = onRest
        self.onAll = onAll
    }

    var body: some View {
        if let clearing = InboxCard.clearing(for: snapshot, optionDown: isOptionDown) {
            Text(clearing.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(DeckTheme.blue)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .contentShape(Rectangle())
                .clickable(cornerRadius: 4)
                .onHover { hovering in
                    let flag = _isOptionDown
                    _watch.wrappedValue.follow(hovering) { flag.wrappedValue = $0 }
                }
                .onTapGesture {
                    // The key is read again at the click: the last poll may be a tenth of a
                    // second old, and the click is what counts.
                    let option = NSEvent.modifierFlags.contains(.option)
                    let action = InboxCard.clearing(for: snapshot, optionDown: option)?.action ?? clearing.action
                    action == .all ? onAll() : onRest()
                }
                .help(clearing.action == .rest ? L("card.inbox.readRest.help") : clearing.title)
                .padding(.leading, -3)
        } else {
            Text(LN("card.repos", snapshot.repositoryCount))
                .foregroundStyle(DeckTheme.label)
        }
    }
}

/// Polls ⌥ while the pointer is over something that cares, and stops when it leaves.
@MainActor
final class OptionWatch {
    private var timer: Timer?

    func follow(_ hovering: Bool, report: @escaping (Bool) -> Void) {
        timer?.invalidate()
        timer = nil
        guard hovering else {
            report(false)
            return
        }
        report(NSEvent.modifierFlags.contains(.option))
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            report(NSEvent.modifierFlags.contains(.option))
        }
    }
}
