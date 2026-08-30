import Foundation

/// A named arrangement of the deck: which cards are on it, which are folded to a row, and where
/// each one sits.
///
/// The idea only became small enough to build once a card could be one row. Before that a saved
/// arrangement could move panels around, which dragging and Tidy already do; what makes "Il Tempo
/// day" different from "Morning triage" is that one card is whole and five are rows.
public struct DeckArrangement: Sendable, Equatable, Codable, Identifiable {
    /// One card, as an arrangement remembers it.
    public struct Placed: Sendable, Equatable, Codable {
        public let card: String
        public let isVisible: Bool
        public let isCollapsed: Bool
        /// `PanelPlacement.storage`, or nil for a card that had never been placed.
        public let placement: String?

        public init(card: String, isVisible: Bool, isCollapsed: Bool, placement: String?) {
            self.card = card
            self.isVisible = isVisible
            self.isCollapsed = isCollapsed
            self.placement = placement
        }
    }

    public let name: String
    public let cards: [Placed]

    public init(name: String, cards: [Placed]) {
        self.name = name
        self.cards = cards
    }

    public var id: String { name }

    /// Whether this arrangement is what is on screen now.
    ///
    /// Compared rather than remembered, so the menu's checkmark cannot claim an arrangement the
    /// deck has since been dragged out of.
    public func matches(_ current: [Placed]) -> Bool {
        let now = Dictionary(current.map { ($0.card, $0) }, uniquingKeysWith: { first, _ in first })
        guard now.count == cards.count else { return false }
        return cards.allSatisfy { saved in
            guard let card = now[saved.card] else { return false }
            return card.isVisible == saved.isVisible
                && card.isCollapsed == saved.isCollapsed
                && card.placement == saved.placement
        }
    }
}

/// The saved arrangements, in the order they were made.
public enum DeckArrangements {
    /// Enough to be useful, few enough that the menu stays a menu.
    public static let limit = 8

    public static func adding(_ arrangement: DeckArrangement, to existing: [DeckArrangement]) -> [DeckArrangement] {
        // A name is the identity, so saving over one replaces it in place rather than growing a
        // second entry with the same title.
        var result = existing
        if let index = result.firstIndex(where: { $0.name == arrangement.name }) {
            result[index] = arrangement
            return result
        }
        result.append(arrangement)
        return Array(result.suffix(limit))
    }

    public static func removing(_ name: String, from existing: [DeckArrangement]) -> [DeckArrangement] {
        existing.filter { $0.name != name }
    }
}
