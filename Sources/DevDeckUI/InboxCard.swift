import DevDeckCore
import GitHubKit
import SwiftUI

/// "GitHub inbox": what is waiting on me, loudest first.
public struct InboxCard: View {
    public static let baseHeight: Double = 119

    private let state: CardState<InboxSnapshot>
    private let now: Date
    private let accountLabels: [String: String]
    private let isExpanded: Bool
    private let onOpen: (URL, String) -> Void
    private let onToggleExpand: () -> Void

    public init(
        state: CardState<InboxSnapshot>,
        now: Date = Date(),
        accountLabels: [String: String] = [:],
        isExpanded: Bool = false,
        onOpen: @escaping (URL, String) -> Void = { _, _ in },
        onToggleExpand: @escaping () -> Void = {}
    ) {
        self.state = state
        self.now = now
        self.accountLabels = accountLabels
        self.isExpanded = isExpanded
        self.onOpen = onOpen
        self.onToggleExpand = onToggleExpand
    }

    public static func size(for state: CardState<InboxSnapshot>, isExpanded: Bool) -> CGSize {
        let total = state.value?.items.count ?? 0
        return CGSize(
            width: CardMetrics.width,
            height: CardMetrics.height(base: baseHeight, total: total, isExpanded: isExpanded)
        )
    }

    public var body: some View {
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
