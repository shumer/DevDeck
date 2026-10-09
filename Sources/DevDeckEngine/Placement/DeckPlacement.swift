#if canImport(CoreGraphics)
import CoreGraphics
#endif
import DevDeckCore
import Foundation

/// The screens as placement needs to see them: every display with an identity, the main one, and
/// where a card goes when its own display is not connected.
public struct DeckDisplays: Sendable, Equatable {
    public let screens: [DisplayFrame]
    public let main: DisplayFrame?
    public let fallback: DisplayFrame?

    public init(screens: [DisplayFrame], main: DisplayFrame?, fallback: DisplayFrame?) {
        self.screens = screens
        self.main = main
        self.fallback = fallback
    }
}

/// One thing the shell does to its panels, in the order given.
public enum DeckPanelChange: Sendable, Equatable {
    /// Close this card's panel.
    case close(CardID)
    /// Open a panel for this card at this frame.
    case open(CardID, CGRect)
    /// Move or resize this card's panel to this frame.
    case place(CardID, CGRect)
}

/// Where every panel is, and every decision about where it goes.
///
/// It keeps a frame per panel, in the Mac's coordinates (points, y growing upward), which the
/// shell keeps true by reporting the moves it did not make. Each operation answers with the
/// changes to apply; the shell applies them without telling this about them again. The two rules
/// it exists to keep: a position is written down only when a person chose it, and the deck
/// settling into its data is not a layout event. See docs/adr/0029-placement-in-the-engine.md.
@MainActor
public final class DeckPlacement {
    private unowned let runtime: DeckRuntime
    private let preferences: Preferences
    /// A card's size as drawn right now. The shell measures: it is the one with the fonts.
    private let measure: (CardID) -> CGSize
    private let displays: () -> DeckDisplays
    private let gap = CGFloat(CardMetrics.panelGap)

    /// Every open panel's frame.
    public private(set) var frames: [CardID: CGRect] = [:]
    /// Moves that have not been believed yet, see `PendingMoves`.
    private var pendingMoves = PendingMoves()
    /// What this call has decided so far, handed back when it ends.
    private var changes: [DeckPanelChange] = []

    /// How long after the screens change before the deck is put back. A display that has just
    /// woken reports its old frame for a moment, and the Dock follows the main display in a
    /// second notification a few hundred milliseconds later.
    public static let screensSettle: TimeInterval = 0.6

    public init(
        runtime: DeckRuntime,
        preferences: Preferences,
        measure: @escaping (CardID) -> CGSize,
        displays: @escaping () -> DeckDisplays
    ) {
        self.runtime = runtime
        self.preferences = preferences
        self.measure = measure
        self.displays = displays
    }

    // MARK: Which panels

    /// Brings the panels in line with the cards that are on, and tells the runtime which cards
    /// are worth fetching.
    public func sync() -> [DeckPanelChange] {
        let wanted = runtime.cards.visible

        for (card, vacated) in frames where !wanted.contains(card) {
            frames[card] = nil
            changes.append(.close(card))
            shiftColumn(below: vacated, by: vacated.height + gap)
        }

        // Before the panels, not after. This is where the runtime reads which cards are
        // collapsed, and a panel built while that is still unknown opens at the wrong size and
        // then corrects itself, which moves everything under it twice.
        runtime.setActiveCards(Set(wanted))

        // A card that has never been placed is put down after the whole deck is on screen, not
        // while it is still being built: it would otherwise pick its spot from the two panels
        // that happened to exist at that moment and land on top of a card whose saved position
        // had not been restored yet.
        var unplaced: [CardID] = []
        var opened: [CardID] = []
        for card in wanted where frames[card] == nil {
            if preferences.placement(for: card) == nil { unplaced.append(card) }
            var size = measure(card)
            // Open at the height this card last settled at. Computing it now would use empty data
            // and produce a short panel that grows a moment later, pushing the rest of the column
            // down, which is how the deck crept apart across launches.
            if let remembered = preferences.height(for: card) {
                size.height = remembered
            }
            let origin = origin(for: card, size: size)
            let frame = CGRect(origin: origin, size: size)
            frames[card] = frame
            changes.append(.open(card, frame))
            opened.append(card)
        }
        for card in unplaced { settle(card) }
        // Two cards remembered at the same spot, which happens when both were hidden and the deck
        // was tidied over the place one of them had, would open on top of each other. The one
        // that opened second joins the deck instead.
        for card in opened where !unplaced.contains(card) && isDoubled(card) { settle(card) }
        // Home or parked, from the placements, so a card whose display is absent opens folded in
        // the parked column with the rest, and hiding a parked card closes the column up.
        placeAll()
        return take()
    }

    // MARK: Sizes

    /// Grows and shrinks panels as their contents change, keeping the top edge where it is and
    /// pushing the rest of the column out of the way.
    public func syncSizes() -> [DeckPanelChange] {
        // Once per pass, because it is a hand-over and not a query.
        let userChanged = runtime.takeUserResizes()

        for card in Array(frames.keys) {
            guard let old = frames[card] else { continue }
            // A parked card is folded by the deck rather than by its data, and `placeAll` is what
            // sizes it. Its height is not remembered either.
            guard !runtime.isParked(card) else { continue }
            // A card that has never had data computes the height of an empty card. It opens at
            // the height it last settled at and waits.
            guard runtime.hasLoaded(card) || preferences.height(for: card) == nil else { continue }

            let size = measure(card)
            guard abs(old.height - size.height) > 0.5 || abs(old.width - size.width) > 0.5 else { continue }

            let frame = CGRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
            frames[card] = frame
            changes.append(.place(card, frame))
            preferences.setHeight(size.height, for: card)
            // The position is deliberately not saved here. A resize keeps the top edge, so there
            // is nothing new to record, and the one thing saving here did record was a card that
            // a neighbour's resize had displaced a moment earlier.

            if preferences.packsColumns {
                packColumn(containing: card)
            } else if userChanged.contains(card) {
                // Only for a change somebody asked for. Selection uses the old frame: those are
                // the panels that were below before the resize, and they have to make room.
                shiftColumn(below: old, by: old.height - size.height)
            }
        }
        return take()
    }

    // MARK: Arranging

    /// Closes up every column. Turning packing on is a decision, so it takes effect now rather
    /// than the next time a card happens to change height.
    public func packAllColumns() -> [DeckPanelChange] {
        for card in Array(frames.keys) { packColumn(containing: card) }
        return take()
    }

    /// Closes up the deck while keeping it where the user put it: anchor on the topmost panel and
    /// stack the rest beneath it, starting a new column whenever the next card would hang below
    /// the screen. It deliberately does not reset to a corner.
    public func tidy() -> [DeckPanelChange] {
        let ordered = runtime.cards.visible.compactMap { card in frames[card].map { (card, $0) } }
        guard let anchor = ordered.max(by: { $0.1.maxY < $1.1.maxY })?.1 else { return take() }
        let screens = displays()
        let screen = screens.screens.first { $0.visibleFrame.intersects(anchor) }?.visibleFrame
            ?? screens.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        let placements = DeckLayout.tidy(
            sizes: ordered.map(\.1.size),
            anchorTopLeft: CGPoint(x: anchor.minX, y: anchor.maxY),
            screen: screen,
            gap: gap
        )
        for (index, (card, frame)) in ordered.enumerated() {
            let topLeft = placements[index]
            move(card, to: CGPoint(x: topLeft.x, y: topLeft.y - frame.height))
        }
        // Tidying is an arrangement somebody asked for, so it is saved against the display the
        // cards are actually on, even when that is a display they were only parked on.
        for (card, _) in ordered { persistPosition(of: card, userMoved: true) }
        return take()
    }

    // MARK: Moves the shell did not make

    /// A panel moved, by a person or by the window server, which announce it the same way. Not
    /// written down yet: the window server's moves come a few milliseconds before it says the
    /// screens changed. Returns when to call `settleMoves(at:)`.
    public func moved(_ card: CardID, to frame: CGRect, at time: TimeInterval) -> TimeInterval? {
        frames[card] = frame
        pendingMoves.moved(card, at: time)
        return pendingMoves.nextDue
    }

    /// Writes down the moves the screens have kept quiet after: those were the user's. Returns
    /// when to call again, if anything is still waiting.
    public func settleMoves(at time: TimeInterval) -> TimeInterval? {
        for card in pendingMoves.settled(at: time) {
            persistPosition(of: card, userMoved: true)
        }
        return pendingMoves.nextDue
    }

    /// The screens changed: whatever moves were waiting were the window server's, not the user's.
    /// The shell calls `placeAfterScreensChanged()` once they have settled; see `screensSettle`.
    public func screensChanged() {
        _ = pendingMoves.screensChanged()
    }

    /// Reads every placement again and puts the deck where it says: home when the display is
    /// here, folded into the parked column on the main display when it is not.
    ///
    /// macOS lays all the screens out in one coordinate space and re-lays it on every change, so
    /// unplugging the external display that happens to be the main one shifts the laptop's screen
    /// underneath the cards. Because a placement names its display rather than a global point,
    /// putting things back is just reading it again.
    public func placeAfterScreensChanged() -> [DeckPanelChange] {
        placeAll()
        return take()
    }

    // MARK: Inside

    private func take() -> [DeckPanelChange] {
        defer { changes = [] }
        return changes
    }

    private func move(_ card: CardID, to origin: CGPoint) {
        guard let frame = frames[card] else { return }
        let moved = CGRect(origin: origin, size: frame.size)
        frames[card] = moved
        changes.append(.place(card, moved))
    }

    private func placeAll() {
        let screens = displays()
        let cards = frames.compactMap { card, frame -> DeckParking.Card? in
            guard let placement = preferences.placement(for: card) else { return nil }
            return DeckParking.Card(
                id: card,
                placement: placement,
                size: CGSize(width: frame.width, height: CollapsedCardMetrics.height)
            )
        }
        let plan = DeckParking.plan(cards, displays: screens.screens, fallback: screens.fallback, gap: gap)
        // Folded before anything is measured: a parked card measures as a folded one.
        let wasParked = runtime.parkedCards
        runtime.setParked(Set(plan.parked.keys))

        for (card, topLeft) in plan.home {
            guard let frame = frames[card] else { continue }
            // A card that has just come home stands up again; one that never left keeps the size
            // its data gave it, so this is not a resize `syncSizes` misses.
            let size = wasParked.contains(card) ? standingSize(for: card) : frame.size
            place(card, topLeft: topLeft, size: size)
        }
        for (card, topLeft) in plan.parked {
            guard let frame = frames[card] else { continue }
            place(card, topLeft: topLeft, size: CGSize(width: frame.width, height: CollapsedCardMetrics.height))
        }
    }

    /// Moves and sizes one panel, when that changes anything.
    private func place(_ card: CardID, topLeft: CGPoint, size: CGSize) {
        guard let current = frames[card] else { return }
        let frame = CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        guard abs(frame.minX - current.minX) > 0.5 || abs(frame.minY - current.minY) > 0.5
            || abs(frame.width - current.width) > 0.5 || abs(frame.height - current.height) > 0.5
        else { return }
        frames[card] = frame
        changes.append(.place(card, frame))
    }

    /// The height a card stands at: measured from its data once it has some, remembered until
    /// then, the same rule `syncSizes` follows.
    private func standingSize(for card: CardID) -> CGSize {
        var size = measure(card)
        if !runtime.hasLoaded(card), let remembered = preferences.height(for: card) {
            size.height = remembered
        }
        return size
    }

    /// Whether another panel already sits exactly where this one is.
    private func isDoubled(_ card: CardID) -> Bool {
        guard let frame = frames[card] else { return false }
        return frames.contains { other, otherFrame in
            other != card && abs(otherFrame.minX - frame.minX) < 2 && abs(otherFrame.maxY - frame.maxY) < 2
        }
    }

    /// Closes up the column this card is in, keeping the order that is on screen.
    ///
    /// Runs by itself, so it is deliberately the timid version of tidying: same column, same
    /// order, anchored on whichever card is already at the top. Cards are never moved to another
    /// column and never re-sorted, because a card that jumps sideways or swaps places on its own
    /// is worse than the gap it was closing.
    private func packColumn(containing card: CardID) {
        guard let anchor = frames[card], !runtime.isParked(card) else { return }
        let members = frames
            .filter { !runtime.isParked($0.key) && DeckLayout.isSameColumn($0.value, anchor) }
            .sorted { $0.value.maxY > $1.value.maxY }
        guard members.count > 1, let top = members.first?.value else { return }

        let screens = displays()
        guard let screen = screens.screens.first(where: { $0.visibleFrame.intersects(top) })?.visibleFrame
            ?? screens.main?.visibleFrame
        else { return }

        let placements = DeckLayout.pack(
            sizes: members.map(\.value.size),
            anchorTopLeft: CGPoint(x: top.minX, y: top.maxY),
            screen: screen,
            gap: gap
        )
        for (index, member) in members.enumerated() {
            let point = placements[index]
            move(member.key, to: CGPoint(x: point.x, y: point.y - member.value.height))
        }
        // Saved, because this is where the cards now live. Not as a user move: a panel parked on
        // a display that is unplugged keeps the placement it belongs to.
        for member in members { persistPosition(of: member.key) }
    }

    /// Records which display a panel is on and where on it, which is what positions are restored
    /// from.
    ///
    /// A panel sitting on a display that is not connected keeps the placement it already had: it
    /// is only parked somewhere visible, and parking is not a decision the user made.
    /// Overwriting it is how a deck moves house every time a monitor is unplugged for an hour.
    /// `userMoved` is the exception: dragging a parked card, or tidying while the monitor it
    /// belongs to is unplugged, is a decision, and it has to outrank the placement it replaces.
    private func persistPosition(of card: CardID, userMoved: Bool = false) {
        guard let frame = frames[card] else { return }
        let screens = displays().screens
        guard PanelPlacement.shouldRecord(
            existing: preferences.placement(for: card),
            userMoved: userMoved,
            displays: screens
        ) else { return }
        guard let placement = PanelPlacement.from(
            topLeft: CGPoint(x: frame.minX, y: frame.maxY),
            size: frame.size,
            displays: screens
        ) else { return }
        preferences.setPlacement(placement, for: card)
    }

    /// Saved position when there is a usable one, otherwise beside the deck, otherwise the next
    /// slot in a column down the right edge.
    private func origin(for card: CardID, size: CGSize) -> CGPoint {
        let screens = displays()
        if let placement = preferences.placement(for: card) {
            // Its own display, when that display is here.
            if let top = placement.topLeft(on: screens.screens) {
                return CGPoint(x: top.x, y: top.y - size.height)
            }
            // Otherwise borrow the fallback display, keeping the placement itself intact so the
            // card goes home when its own display comes back.
            if let fallback = screens.fallback {
                let top = placement.topLeft(borrowing: fallback, size: size)
                return CGPoint(x: top.x, y: top.y - size.height)
            }
        }

        // A card with no placement joins the deck, rather than landing alone on whichever display
        // happens to be main.
        if let spot = originBesideTheDeck(size: size) { return spot }

        let screen = screens.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var y = screen.maxY - 28
        for candidate in runtime.cards.visible {
            let candidateSize = measure(candidate)
            if candidate == card {
                return CGPoint(x: screen.maxX - candidateSize.width - 28, y: y - candidateSize.height)
            }
            if frames[candidate] != nil { y -= candidateSize.height + gap }
        }
        return CGPoint(x: screen.maxX - size.width - 28, y: y - size.height)
    }

    /// Puts a card that has never had a position into the deck, and writes it down, so it comes
    /// back to the same place tomorrow instead of being re-derived from whatever the deck looks
    /// like then.
    private func settle(_ card: CardID) {
        guard let frame = frames[card], let point = originBesideTheDeck(size: frame.size, ignoring: card) else { return }
        move(card, to: point)
        persistPosition(of: card)
    }

    /// Where a card with no position of its own goes: into the deck, not onto whatever display
    /// happens to be main. The arithmetic is `DeckLayout.nextSpot`.
    private func originBesideTheDeck(size: CGSize, ignoring card: CardID? = nil) -> CGPoint? {
        let others = frames.filter { $0.key != card }.map(\.value)
        guard let first = others.first,
              let screen = displays().screens.first(where: { $0.visibleFrame.intersects(first) })?.visibleFrame,
              let spot = DeckLayout.nextSpot(size: size, among: others, screen: screen, gap: gap)
        else { return nil }
        return CGPoint(x: spot.x, y: spot.y)
    }

    /// Moves every panel under `frame` in the same column by `dy`, positive being up.
    ///
    /// This is what stops a hidden card leaving a card-shaped hole, and what makes room when a
    /// card is expanded. Only panels that overlap horizontally are touched, so a deliberately
    /// scattered layout is left alone.
    private func shiftColumn(below frame: CGRect, by dy: CGFloat) {
        guard dy != 0 else { return }
        var moved: [CardID] = []
        for card in Array(frames.keys) where !runtime.isParked(card) {
            guard let current = frames[card] else { continue }
            guard current.maxY <= frame.minY + 1 else { continue }
            guard current.maxX > frame.minX, current.minX < frame.maxX else { continue }
            move(card, to: CGPoint(x: current.minX, y: current.minY + dy))
            moved.append(card)
        }
        for card in moved { persistPosition(of: card) }
    }
}
