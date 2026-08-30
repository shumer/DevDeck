import DevDeckCore
import SwiftUI

/// Every checkout at once: what is uncommitted, what is unpushed, what has fallen behind.
///
/// The one card that shows something no other card can. A project card answers "is it running";
/// this answers "what did I leave in the middle of", which is the question that costs an hour on
/// a Monday. It is derived entirely from git, so it needs no token and no network, and it says
/// nothing at all when every checkout is clean, which most days it is not.
public struct WorkInFlightCard: View {
    public nonisolated static let baseHeight: Double = 96

    private let states: [CheckoutState]
    private let checkedAt: Date?
    private let isExpanded: Bool
    private let isCollapsed: Bool
    private let onOpen: (CheckoutState) -> Void
    private let onToggleExpand: () -> Void

    public init(
        states: [CheckoutState],
        checkedAt: Date? = nil,
        isExpanded: Bool = false,
        isCollapsed: Bool = false,
        onOpen: @escaping (CheckoutState) -> Void = { _ in },
        onToggleExpand: @escaping () -> Void = {}
    ) {
        self.states = states
        self.checkedAt = checkedAt
        self.isExpanded = isExpanded
        self.isCollapsed = isCollapsed
        self.onOpen = onOpen
        self.onToggleExpand = onToggleExpand
    }

    public nonisolated static func size(
        for states: [CheckoutState],
        isExpanded: Bool,
        isCollapsed: Bool = false
    ) -> CGSize {
        guard !isCollapsed else {
            return CGSize(width: CardMetrics.width, height: CollapsedCardMetrics.height)
        }
        return CGSize(
            width: CardMetrics.width,
            height: CardMetrics.height(
                base: baseHeight,
                total: WorkInFlight.rows(from: states).count,
                isExpanded: isExpanded
            )
        )
    }

    public var body: some View {
        if isCollapsed {
            collapsed
        } else {
            full
        }
    }

    private var rows: [CheckoutState] { WorkInFlight.rows(from: states) }

    private var collapsed: some View {
        CardCollapsedRow(
            glyph: nil,
            title: "Work in flight",
            note: note,
            tone: rows.contains(where: \.isUrgent) ? .alert : (rows.isEmpty ? .good : .neutral),
            color: rows.contains(where: \.isUrgent) ? DeckTheme.amber : DeckTheme.green,
            help: note ?? "Work in flight"
        )
    }

    private var note: String? {
        guard !rows.isEmpty else { return "all clean" }
        let unpushed = rows.filter { $0.ahead > 0 }.count
        if unpushed > 0 { return "\(unpushed) unpushed · \(rows.count) in flight" }
        return "\(rows.count) in flight"
    }

    private var full: some View {
        CardChrome(
            title: "Work in flight",
            glyph: nil,
            timestamp: ProjectCardMetrics.timestamp(checkedAt)
        ) {
            let visible = CardMetrics.rowCount(total: rows.count, isExpanded: isExpanded)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(rows.count)")
                    .font(.system(size: 26, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(DeckTheme.value.opacity(0.85))
                Text(rows.isEmpty ? "clean" : "in flight")
                    .font(.system(size: 12))
                    .foregroundStyle(DeckTheme.label)
                Spacer(minLength: 6)
                if let unpushed = unpushedSummary {
                    StatusPill(unpushed, color: DeckTheme.amber)
                }
            }
            .frame(height: 30)
            .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(rows.prefix(visible)) { state in
                    row(state)
                }
            }
            .padding(.top, 6)

            if CardMetrics.showsExpander(total: rows.count) {
                CardExpander(
                    hidden: rows.count - CardMetrics.collapsedRows,
                    isExpanded: isExpanded,
                    onToggle: onToggleExpand
                )
            }

            Spacer(minLength: 4)
            CardFooter(leading: footer)
        }
    }

    private var unpushedSummary: String? {
        let unpushed = rows.filter { $0.ahead > 0 }.count
        return unpushed > 0 ? "\(unpushed) unpushed" : nil
    }

    private var footer: String {
        let checkouts = states.count
        return "\(checkouts) checkout\(checkouts == 1 ? "" : "s") watched"
    }

    private func row(_ state: CheckoutState) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(state.isUrgent ? DeckTheme.amber : DeckTheme.label.opacity(0.6))
                .frame(width: 6, height: 6)
            Text(state.title)
                .font(.system(size: 11.5))
                .foregroundStyle(DeckTheme.value.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(state.branch)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(DeckTheme.value.opacity(0.45))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(state.summary)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(state.isUrgent ? DeckTheme.amber : DeckTheme.value.opacity(0.58))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: CardMetrics.rowHeight - 1)
        .overlay(alignment: .top) { Rectangle().fill(DeckTheme.faint).frame(height: 1) }
        .contentShape(Rectangle())
        .clickable()
        .onTapGesture { onOpen(state) }
        .help("\(state.title) on \(state.branch): \(state.summary)")
    }
}
