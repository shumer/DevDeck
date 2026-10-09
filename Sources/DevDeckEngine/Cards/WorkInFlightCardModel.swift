import DevDeckCore
import Foundation

/// Every checkout at once: what is uncommitted, what is unpushed, what has fallen behind.
///
/// The one card that shows something no other card can. A project card answers "is it running";
/// this answers "what did I leave in the middle of", which is the question that costs an hour on
/// a Monday. It is derived entirely from git, so it needs no token and no network.
public struct WorkInFlightCardModel: Sendable, Equatable, Codable {
    public struct Row: Sendable, Equatable, Codable, Identifiable {
        public let id: String
        /// Attention for work that exists only here; neutral for the rest.
        public let tone: DeckTone
        public let title: String
        public let branch: String
        public let summary: String
        public let help: String
        public let command: DeckCommand
    }

    public let title: String
    public let timestamp: String
    public let count: Int
    public let unit: String
    public let pill: DeckPillModel?
    public let rows: [Row]
    public let expander: DeckExpanderModel?
    public let footer: DeckFooterModel
    public let collapsed: DeckCollapsedModel
    public let isCollapsed: Bool
    public let isExpanded: Bool
    /// Every checkout worth a row, shown or not.
    public let total: Int

    public static func build(
        states: [CheckoutState],
        checkedAt: Date?,
        isExpanded: Bool,
        isCollapsed: Bool
    ) -> WorkInFlightCardModel {
        let card = CardID.workInFlight
        let all = WorkInFlight.rows(from: states)
        let unpushed = all.filter { $0.ahead > 0 }.count
        let visible = all.prefix(CardMetrics.rowCount(total: all.count, isExpanded: isExpanded))

        let note: String
        if all.isEmpty {
            note = L("card.wif.allClean")
        } else if unpushed > 0 {
            note = L("card.wif.unpushedInFlight", unpushed, all.count)
        } else {
            note = L("card.wif.inFlight", all.count)
        }
        let collapsedTone: DeckTone = all.contains(where: \.isUrgent) ? .attention : (all.isEmpty ? .good : .neutral)

        return WorkInFlightCardModel(
            title: L("card.title.workInFlight"),
            timestamp: DeckCardTime.checked(checkedAt),
            count: all.count,
            unit: all.isEmpty ? L("card.wif.clean") : L("card.wif.inFlight.word"),
            pill: unpushed > 0 ? DeckPillModel(L("card.wif.unpushed", unpushed), tone: .attention) : nil,
            rows: visible.map { state in
                Row(
                    id: state.id,
                    tone: state.isUrgent ? .attention : .neutral,
                    title: state.title,
                    branch: state.branch,
                    summary: state.summary,
                    help: L("attention.row.colon", "\(state.title) · \(state.branch)", state.summary),
                    command: .openCheckout(id: state.id)
                )
            },
            expander: CardMetrics.showsExpander(total: all.count)
                ? DeckExpanderModel(
                    label: isExpanded ? L("card.showLess") : L("card.showMore", all.count - CardMetrics.collapsedRows),
                    isExpanded: isExpanded,
                    command: .toggleExpanded(card)
                )
                : nil,
            footer: DeckFooterModel(leading: LN("card.wif.watched", states.count), trailing: nil, isStale: false),
            collapsed: DeckCollapsedModel(
                mark: nil,
                title: L("card.title.workInFlight"),
                note: note,
                tone: collapsedTone,
                actions: [],
                help: note
            ),
            isCollapsed: isCollapsed,
            isExpanded: isExpanded,
            total: all.count
        )
    }
}
