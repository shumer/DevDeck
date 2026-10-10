#if canImport(CoreGraphics)
import CoreGraphics
#endif
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
    /// A card on the deck, with sizes in its home and fallback display coordinates.
    public struct Card: Equatable, Sendable {
        public let id: CardID
        public let placement: PanelPlacement
        public let homeSize: CGSize
        public let parkedSize: CGSize

        public init(id: CardID, placement: PanelPlacement, size: CGSize) {
            self.init(id: id, placement: placement, homeSize: size, parkedSize: size)
        }

        public init(
            id: CardID,
            placement: PanelPlacement,
            homeSize: CGSize,
            parkedSize: CGSize
        ) {
            self.id = id
            self.placement = placement
            self.homeSize = homeSize
            self.parkedSize = parkedSize
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
        var occupied: [CGRect] = []
        for card in cards {
            if let point = card.placement.topLeft(on: displays) {
                plan.home[card.id] = point
                occupied.append(CGRect(
                    x: point.x,
                    y: point.y - card.homeSize.height,
                    width: card.homeSize.width,
                    height: card.homeSize.height
                ))
            } else {
                away.append(card)
            }
        }
        if let fallback, !away.isEmpty {
            plan.parked = layout(away, on: fallback, gap: gap, avoiding: occupied)
        }
        return plan
    }

    /// The parked column for cards whose display is absent.
    public static func layout(
        _ cards: [Card],
        on display: DisplayFrame,
        gap: CGFloat,
        avoiding occupied: [CGRect] = []
    ) -> [CardID: CGPoint] {
        guard !cards.isEmpty else { return [:] }
        let ordered = readingOrder(cards)
        let frame = display.visibleFrame
        let widest = ordered.map(\.parkedSize.width).max() ?? 0
        let tallest = ordered.map(\.parkedSize.height).max() ?? 0

        // The deck stands where it stood: the same distance in from the left, or against the
        // right edge when that distance does not exist on this screen, and the same distance
        // down from the top.
        let left = ordered.map(\.placement.offset.x).min() ?? 0
        let top = ordered.map(\.placement.offset.y).min() ?? 0
        let x = min(max(frame.minX + left, frame.minX), max(frame.maxX - widest, frame.minX))
        let y = min(max(frame.maxY - top, frame.minY + tallest), frame.maxY)

        let points = DeckLayout.tidy(
            sizes: ordered.map(\.parkedSize),
            anchorTopLeft: CGPoint(x: x, y: y),
            screen: frame,
            gap: gap
        )
        var result: [CardID: CGPoint] = [:]
        for (card, point) in zip(ordered, points) {
            result[card.id] = point
        }
        return shiftedToFreeColumn(result, cards: ordered, on: frame, gap: gap, avoiding: occupied)
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
                let width = min(column[0].homeSize.width, card.homeSize.width)
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

    private static func shiftedToFreeColumn(
        _ points: [CardID: CGPoint],
        cards: [Card],
        on screen: CGRect,
        gap: CGFloat,
        avoiding occupied: [CGRect]
    ) -> [CardID: CGPoint] {
        guard !occupied.isEmpty else { return points }
        let sizes = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.parkedSize) })
        let frames = points.compactMap { card, point -> CGRect? in
            guard let size = sizes[card] else { return nil }
            return CGRect(x: point.x, y: point.y - size.height, width: size.width, height: size.height)
        }
        guard let bounds = frames.reduce(nil as CGRect?, { partial, frame in
            partial.map { $0.union(frame) } ?? frame
        }) else { return points }
        if frames.allSatisfy({ candidate in !occupied.contains(where: { candidate.intersects($0) }) }) {
            return points
        }

        let minimum = screen.minX
        let maximum = screen.maxX - bounds.width
        let suggested = occupied.flatMap { frame in
            [frame.maxX + gap, frame.minX - bounds.width - gap]
        } + [minimum, maximum]
        let candidates = Array(Set(suggested.map { min(max($0, minimum), maximum) }))
            .sorted { abs($0 - bounds.minX) < abs($1 - bounds.minX) }
        for x in candidates {
            let shift = x - bounds.minX
            let moved = frames.map { $0.offsetBy(dx: shift, dy: 0) }
            guard moved.allSatisfy(screen.contains),
                  moved.allSatisfy({ candidate in !occupied.contains(where: { candidate.intersects($0) }) })
            else { continue }
            return points.mapValues { CGPoint(x: $0.x + shift, y: $0.y) }
        }
        return points
    }
}
