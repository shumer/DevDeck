import CoreGraphics
import Foundation

/// Where the deck goes while the display it belongs to is unplugged.
///
/// One layout for the deck rather than one clamp per card. Parking used to apply each card's own
/// offset to the borrowed screen and pull it back inside, which on a smaller screen sends every
/// card that sat lower than the screen is tall to the same spot on the bottom edge, in a pile.
/// The window server does the same on its own, to the top edge, for windows it finds off every
/// screen. Eleven cards arranged on a 27-inch display are not eleven independent decisions about
/// a 14-inch one.
///
/// So the parked deck is one column of folded rows. The cards keep the order the deck reads in,
/// home's columns left to right and top to bottom within each, and stand at the side of the
/// borrowed screen the deck stood on at home, wrapping into a second column only when the rows
/// do not fit. Folding is the caller's business, this only needs the folded sizes. Nothing here
/// writes a placement, which is what takes the deck home unchanged.
public enum DeckParking {
    /// A card on the deck: where it lives, and how big it is in the state it is laid out in.
    public struct Card: Equatable, Sendable {
        public let id: CardID
        public let placement: PanelPlacement
        public let size: CGSize

        public init(id: CardID, placement: PanelPlacement, size: CGSize) {
            self.id = id
            self.placement = placement
            self.size = size
        }
    }

    /// Where every card goes: home when its display is here, into the parked column on the
    /// fallback display when it is not. Top-left corners, in global coordinates.
    public struct Plan: Equatable, Sendable {
        public var home: [CardID: CGPoint] = [:]
        public var parked: [CardID: CGPoint] = [:]

        public init() {}
    }

    public static func plan(
        _ cards: [Card],
        displays: [DisplayFrame],
        fallback: DisplayFrame?,
        gap: CGFloat
    ) -> Plan {
        var plan = Plan()
        var away: [Card] = []
        for card in cards {
            if let point = card.placement.topLeft(on: displays) {
                plan.home[card.id] = point
            } else {
                away.append(card)
            }
        }
        if let fallback, !away.isEmpty {
            plan.parked = layout(away, on: fallback, gap: gap)
        }
        return plan
    }

    /// The parked column for cards whose display is absent.
    public static func layout(_ cards: [Card], on display: DisplayFrame, gap: CGFloat) -> [CardID: CGPoint] {
        guard !cards.isEmpty else { return [:] }
        let ordered = readingOrder(cards)
        let frame = display.visibleFrame
        let widest = ordered.map(\.size.width).max() ?? 0
        let tallest = ordered.map(\.size.height).max() ?? 0

        // The deck stands where it stood: the same distance in from the left, or against the
        // right edge when that distance does not exist on this screen, and the same distance
        // down from the top.
        let left = ordered.map(\.placement.offset.x).min() ?? 0
        let top = ordered.map(\.placement.offset.y).min() ?? 0
        let x = min(max(frame.minX + left, frame.minX), max(frame.maxX - widest, frame.minX))
        let y = min(max(frame.maxY - top, frame.minY + tallest), frame.maxY)

        let points = DeckLayout.tidy(
            sizes: ordered.map(\.size),
            anchorTopLeft: CGPoint(x: x, y: y),
            screen: frame,
            gap: gap
        )
        var result: [CardID: CGPoint] = [:]
        for (card, point) in zip(ordered, points) {
            result[card.id] = point
        }
        return result
    }

    /// Home's columns left to right, and top to bottom within each: the order the deck reads in.
    ///
    /// Columns are read from the offsets, since that is all a placement remembers: two cards
    /// whose left edges are within half a card of each other are one column, the same rule
    /// `DeckLayout.isSameColumn` applies to frames.
    static func readingOrder(_ cards: [Card]) -> [Card] {
        var columns: [[Card]] = []
        for card in cards.sorted(by: { $0.placement.offset.x < $1.placement.offset.x }) {
            let index = columns.firstIndex { column in
                let width = min(column[0].size.width, card.size.width)
                return abs(column[0].placement.offset.x - card.placement.offset.x) < width / 2
            }
            if let index {
                columns[index].append(card)
            } else {
                columns.append([card])
            }
        }
        return columns.flatMap { column in
            column.sorted { $0.placement.offset.y < $1.placement.offset.y }
        }
    }
}
