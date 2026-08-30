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

    public init(
        state: CardState<InboxSnapshot>,
        now: Date = Date(),
        accountLabels: [String: String] = [:],
        isExpanded: Bool = false,
        isCollapsed: Bool = false,
        onOpen: @escaping (URL, String) -> Void = { _, _ in },
        onToggleExpand: @escaping () -> Void = {},
        onOpenDashboard: @escaping () -> Void = {}
    ) {
        self.state = state
        self.now = now
        self.accountLabels = accountLabels
        self.isExpanded = isExpanded
        self.isCollapsed = isCollapsed
        self.onOpen = onOpen
        self.onToggleExpand = onToggleExpand
        self.onOpenDashboard = onOpenDashboard
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
            title: "GitHub inbox",
            note: collapsedNote,
            tone: collapsedTone.tone,
            color: collapsedTone.color,
            action: CardAction("Open in browser", systemImage: "arrow.up.forward", action: onOpenDashboard),
            help: collapsedNote ?? "GitHub inbox"
        )
    }

    /// Unread is the number, and what is waiting on you is the part worth colour.
    private var collapsedNote: String? {
        guard let snapshot = state.value else { return state.failure?.displayMessage ?? "loading" }
        if snapshot.actionableCount > 0 { return "\(snapshot.actionableCount) on you · \(snapshot.unreadCount) unread" }
        return snapshot.unreadCount == 0 ? "clear" : "\(snapshot.unreadCount) unread"
    }

    private var collapsedTone: (tone: CardStateTone, color: Color) {
        guard let snapshot = state.value else { return (.neutral, DeckTheme.label) }
        if snapshot.actionableCount > 0 { return (.alert, DeckTheme.amber) }
        return snapshot.unreadCount == 0 ? (.good, DeckTheme.green) : (.neutral, DeckTheme.label)
    }

    private var full: some View {
        CardChrome(title: "GitHub · inbox", pill: pill) {
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
            return ("\(snapshot.actionableCount) for me", DeckTheme.violet)
        }
        return snapshot.unreadCount == 0 ? ("clear", DeckTheme.green) : ("fyi", DeckTheme.label)
    }

    @ViewBuilder
    private func content(_ snapshot: InboxSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(snapshot.unreadCount)")
                .font(.system(size: 42, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(snapshot.actionableCount > 0 ? DeckTheme.violet : DeckTheme.green)
            Text("unread")
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

        CardFooter(
            leading: snapshot.failures.summary ?? (snapshot.items.isEmpty
                ? "nothing waiting"
                : "\(snapshot.repositoryCount) repo\(snapshot.repositoryCount == 1 ? "" : "s")"),
            trailing: CardFreshness.text(for: state),
            isStale: state.failure != nil
                || !snapshot.failures.isEmpty
                || state.isStale(now: now, maxAge: 600)
        )
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
        .help("\(item.shortRepository): \(item.title)")
    }
}
