import AppKit
import DevDeckCore
import DevDeckUI

/// Owns the panels: which are on screen, how big each is, and where it sits.
///
/// Everything here is about the windows as windows. What a card shows is the controller's
/// business, and what a right-click on one offers is the menu's; this object opens, sizes,
/// places and remembers, and the two rules it exists to keep are stated once, on
/// `persistPosition` and `syncPanelSizes`: a position is written down only when a person chose
/// it, and the deck settling into its data is not a layout event.
@MainActor
final class PanelCoordinator: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let controller: DeckController
    private let cards: DeckCards
    /// Builds the context menu for one panel. Supplied by the menu object, which is the one
    /// that fills it in when it opens.
    private let makeContextMenu: (CardID) -> NSMenu

    private var panels: [CardID: PanelWindow] = [:]
    /// True while the deck is putting panels where they already belong rather than someone
    /// moving them. AppKit posts `windowDidMove` for programmatic moves too, so without this the
    /// deck saves its own repositioning as though it were an arrangement a person chose.
    private var isRepositioning = false
    /// What the panels sit at when nobody is holding the summon key.
    private var restingLevel: NSWindow.Level
    /// Whether they are currently raised over everything.
    private var isRaised = false

    init(
        preferences: Preferences,
        controller: DeckController,
        cards: DeckCards,
        makeContextMenu: @escaping (CardID) -> NSMenu
    ) {
        self.preferences = preferences
        self.controller = controller
        self.cards = cards
        self.makeContextMenu = makeContextMenu
        self.restingLevel = preferences.displayMode.windowLevel
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Whether a card has a panel right now.
    func isShowing(_ card: CardID) -> Bool {
        panels[card] != nil
    }

    // MARK: Which panels

    /// Brings the on-screen panels in line with the saved layout, and tells the controller
    /// which cards are worth fetching.
    func syncPanels() {
        let wanted = cards.visible

        for (card, window) in panels where !wanted.contains(card) {
            let vacated = window.frame
            window.orderOut(nil)
            panels[card] = nil
            shiftColumn(below: vacated, by: vacated.height + DeckTheme.panelGap)
        }

        // Before the panels, not after. This is where the controller reads which cards are
        // collapsed, and a panel built while that is still unknown opens at the wrong size and
        // then corrects itself, which moves everything under it twice.
        controller.setActiveCards(Set(wanted))

        // A card that has never been placed is put down after the whole deck is on screen, not
        // while it is still being built: a new card added at launch would otherwise pick its
        // spot from the two panels that happened to exist at that moment and land under one of
        // them, on top of a card whose saved position had not been restored yet.
        var unplaced: [CardID] = []
        for card in wanted where panels[card] == nil {
            if preferences.placement(for: card) == nil { unplaced.append(card) }
            showPanel(card)
        }
        for card in unplaced { settle(card) }
    }

    private func showPanel(_ card: CardID) {
        var size = CardHostView.size(for: card)
        // Open at the height this card last settled at. Computing it now would use empty data
        // and produce a short panel that grows a moment later, pushing the rest of the column
        // down - which is how the deck crept apart across launches.
        if let remembered = preferences.height(for: card) {
            size.height = remembered
        }
        let hosting = PanelHostingView(rootView: CardHostView(controller: controller, card: card))
        let window = PanelWindow(
            card: card,
            size: size,
            origin: origin(for: card, size: size),
            cornerRadius: cornerRadius(for: card),
            content: hosting
        )
        window.level = isRaised ? .floating : restingLevel
        window.isMovableByWindowBackground = !preferences.isLocked
        window.delegate = self
        window.contentView?.menu = makeContextMenu(card)
        reposition { window.orderFrontRegardless() }
        panels[card] = window
    }

    // MARK: Sizes

    /// Grows and shrinks panels as their contents change, keeping the top edge where it is and
    /// pushing the rest of the column out of the way.
    func syncPanelSizes() {
        // Once per pass, because it is a hand-over and not a query.
        let userChanged = controller.takeUserResizes()

        for (card, window) in panels {
            // A card that has never had data computes the height of an empty card. Letting that
            // through resized the panel to a shape nothing was ever in, and then back, and the
            // column walked up the screen and down again with a different set of neighbours each
            // way. It opens at the height it last settled at and waits.
            guard controller.hasLoaded(card) || preferences.height(for: card) == nil else { continue }

            let size = CardHostView.size(for: card)
            let old = window.frame
            guard abs(old.height - size.height) > 0.5 || abs(old.width - size.width) > 0.5 else { continue }

            let frame = NSRect(
                x: old.origin.x,
                y: old.maxY - size.height,
                width: size.width,
                height: size.height
            )
            reposition {
                window.setFrame(frame, display: true, animate: false)
            }
            // Collapsing changes the shape as well as the height.
            window.apply(cornerRadius: cornerRadius(for: card))
            window.invalidateShadow()
            preferences.setHeight(size.height, for: card)
            // The position is deliberately not saved here. A resize keeps the top edge, so there
            // is nothing new to record, and the one thing that call did record was the case it
            // should not have: a card that a neighbour's resize had displaced a moment earlier,
            // written down at the displaced position and then loaded from there at the next
            // launch.

            if preferences.packsColumns {
                packColumn(containing: card)
            } else if userChanged.contains(card) {
                // Only for a change somebody asked for. Selection uses the old frame: those are
                // the panels that were below before the resize, and they are the ones that have
                // to make room.
                shiftColumn(below: old, by: old.height - size.height)
            }
        }
    }

    /// A collapsed panel is a different shape, not just a shorter one.
    private func cornerRadius(for card: CardID) -> CGFloat {
        controller.isCollapsed(card) ? CollapsedCardMetrics.cornerRadius : DeckTheme.cornerRadius
    }

    // MARK: Positions

    /// Closes up the column this card is in, keeping the order that is on screen.
    ///
    /// Runs by itself, so it is deliberately the timid version of tidying: same column, same
    /// order, anchored on whichever card is already at the top. Cards are never moved to another
    /// column and never re-sorted, because a card that jumps sideways or swaps places on its own
    /// is worse than the gap it was closing. The menu's Tidy is still the one that does both.
    private func packColumn(containing card: CardID) {
        guard let anchor = panels[card] else { return }
        let members = panels
            .filter { DeckLayout.isSameColumn($0.value.frame, anchor.frame) }
            .sorted { $0.value.frame.maxY > $1.value.frame.maxY }
        guard members.count > 1, let top = members.first?.value.frame else { return }

        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(top) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let screen else { return }

        let placements = DeckLayout.pack(
            sizes: members.map(\.value.frame.size),
            anchorTopLeft: CGPoint(x: top.minX, y: top.maxY),
            screen: screen,
            gap: DeckTheme.panelGap
        )

        reposition {
            for (index, member) in members.enumerated() {
                let point = placements[index]
                member.value.setFrameOrigin(NSPoint(x: point.x, y: point.y - member.value.frame.height))
            }
        }
        // Saved, because this is where the cards now live. Not as a user move: a panel parked on
        // a display that is unplugged keeps the placement it belongs to.
        for member in members { persistPosition(of: member.key) }
    }

    /// Closes up every column. Turning packing on is a decision, so it takes effect now rather
    /// than the next time a card happens to change height.
    func packAllColumns() {
        for card in panels.keys { packColumn(containing: card) }
    }

    /// Closes up the deck while keeping it where the user put it: anchor on the topmost panel
    /// and stack the rest beneath it, starting a new column whenever the next card would hang
    /// below the screen. It deliberately does not reset to a corner.
    ///
    /// The wrapping is not a nicety. Six cards are over a thousand points tall, and a single
    /// column pushed the last of them under the bottom edge - where nothing can grab it, and
    /// the position was saved.
    func tidy() {
        let ordered = cards.visible.compactMap { card in panels[card].map { (card, $0) } }
        guard let anchor = ordered.max(by: { $0.1.frame.maxY < $1.1.frame.maxY })?.1 else { return }

        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(anchor.frame) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let placements = DeckLayout.tidy(
            sizes: ordered.map(\.1.frame.size),
            anchorTopLeft: CGPoint(x: anchor.frame.minX, y: anchor.frame.maxY),
            screen: screen,
            gap: DeckTheme.panelGap
        )

        reposition {
            for (index, (_, window)) in ordered.enumerated() {
                let topLeft = placements[index]
                window.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - window.frame.height))
            }
        }
        // Tidying is an arrangement somebody asked for, so it is saved against the display the
        // cards are actually on - even when that is a display they were only parked on.
        for (card, _) in ordered { persistPosition(of: card, userMoved: true) }
    }

    /// Records which display a panel is on and where on it, which is what positions are
    /// restored from.
    ///
    /// A panel sitting on a display that is not currently connected keeps the placement it
    /// already had: it is only parked somewhere visible, and parking is not a decision the user
    /// made. Overwriting it is how a deck moves house permanently every time a monitor is
    /// unplugged for an hour.
    ///
    /// `userMoved` is the exception, and it is the whole difference between the deck arranging
    /// itself and someone arranging it. Dragging a parked card, or tidying the deck while the
    /// monitor it belongs to is unplugged, is a decision, and it has to outrank the placement it
    /// replaces - otherwise the arrangement is silently dropped and the next screen change
    /// hauls every card back to where it was parked. Which is exactly what it did.
    private func persistPosition(of card: CardID, userMoved: Bool = false) {
        guard let window = panels[card] else { return }
        guard PanelPlacement.shouldRecord(
            existing: preferences.placement(for: card),
            userMoved: userMoved,
            displays: Displays.current()
        ) else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        guard let placement = PanelPlacement.from(
            topLeft: topLeft,
            size: window.frame.size,
            displays: Displays.current()
        ) else { return }
        preferences.setPlacement(placement, for: card)
    }

    /// Saved position when there is a usable one, otherwise the next slot in a column down
    /// the right edge.
    private func origin(for card: CardID, size: NSSize) -> NSPoint {
        if let placement = preferences.placement(for: card) {
            // Its own display, when that display is here.
            if let top = placement.topLeft(on: Displays.current()) {
                return NSPoint(x: top.x, y: top.y - size.height)
            }
            // Otherwise borrow whichever display is main, keeping the placement itself intact
            // so the card goes home when its own display comes back.
            if let fallback = Displays.fallback() {
                let top = placement.topLeft(borrowing: fallback, size: size)
                return NSPoint(x: top.x, y: top.y - size.height)
            }
        }

        // A card with no placement joins the deck. It used to land on whichever display happened
        // to be main, which for a deck kept on the laptop meant a new card appearing alone on an
        // external monitor, where the answer to "where is my card" is "on another screen".
        if let spot = originBesideTheDeck(size: size) { return spot }

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var y = screen.maxY - 28
        for candidate in cards.visible {
            let candidateSize = CardHostView.size(for: candidate)
            if candidate == card {
                return NSPoint(x: screen.maxX - candidateSize.width - 28, y: y - candidateSize.height)
            }
            if panels[candidate] != nil { y -= candidateSize.height + DeckTheme.panelGap }
        }
        return NSPoint(x: screen.maxX - size.width - 28, y: y - size.height)
    }

    /// Puts a card that has never had a position into the deck, and writes it down.
    ///
    /// Saved immediately rather than at the next move, so the card comes back to the same place
    /// tomorrow instead of being re-derived from whatever the deck looks like then.
    private func settle(_ card: CardID) {
        guard let window = panels[card],
              let point = originBesideTheDeck(size: window.frame.size, ignoring: card)
        else { return }
        reposition { window.setFrameOrigin(point) }
        persistPosition(of: card)
    }

    /// Where a card with no position of its own goes: into the deck, not onto whatever display
    /// happens to be main. The arithmetic is `DeckLayout.nextSpot`; this only supplies the deck.
    private func originBesideTheDeck(size: NSSize, ignoring card: CardID? = nil) -> NSPoint? {
        let frames = panels.filter { $0.key != card }.values.map(\.frame)
        guard let first = frames.first,
              let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(first) })?.visibleFrame,
              let spot = DeckLayout.nextSpot(
                  size: size,
                  among: frames,
                  screen: screen,
                  gap: DeckTheme.panelGap
              )
        else { return nil }
        return NSPoint(x: spot.x, y: spot.y)
    }

    /// Moves every panel sitting under `frame` in the same column by `dy` - positive is up,
    /// since AppKit's y grows upward.
    ///
    /// This is what stops a hidden card leaving a card-shaped hole, and what makes room when a
    /// card is expanded. Only panels that overlap horizontally are touched, so a deliberately
    /// scattered layout is left alone. Every move it makes is part of the layout: it runs when
    /// a card is hidden, or when the user changed a card's height themselves. The deck settling
    /// into its data does not come through here any more, which is what it used to do and then
    /// save.
    private func shiftColumn(below frame: NSRect, by dy: CGFloat) {
        guard dy != 0 else { return }
        var moved: [CardID] = []
        reposition {
            for (card, window) in panels {
                let current = window.frame
                guard current.maxY <= frame.minY + 1 else { continue }
                guard current.maxX > frame.minX, current.minX < frame.maxX else { continue }
                window.setFrameOrigin(NSPoint(x: current.origin.x, y: current.origin.y + dy))
                moved.append(card)
            }
        }
        for card in moved { persistPosition(of: card) }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isRepositioning, let window = notification.object as? PanelWindow else { return }
        persistPosition(of: window.card, userMoved: true)
    }

    /// Runs a move the deck decided on rather than the user, so `windowDidMove` stays quiet.
    private func reposition(_ body: () -> Void) {
        isRepositioning = true
        body()
        isRepositioning = false
    }

    /// Puts every panel back where it belongs after a display comes or goes.
    ///
    /// macOS lays all the screens out in one coordinate space and re-lays it on every change,
    /// so unplugging the external display that happens to be the main one shifts the laptop's
    /// screen underneath the cards - and the deck scatters, sometimes off-screen entirely.
    /// Because a placement names its display rather than a global point, putting things back is
    /// just reading it again: home if that display is here, parked on the main one if it is
    /// not, and home again the moment it returns.
    @objc private func screensChanged() {
        // The arrangement is still settling when the notification arrives - a display that has
        // just woken reports its old frame for a moment - so this runs after a beat.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(replaceAll), object: nil)
        perform(#selector(replaceAll), with: nil, afterDelay: 0.6)
    }

    /// Reads every placement again and moves whatever is not where it says.
    @objc func replaceAll() {
        reposition {
            for (card, window) in panels {
                let size = window.frame.size
                let point = origin(for: card, size: size)
                guard abs(point.x - window.frame.minX) > 0.5 || abs(point.y - window.frame.minY) > 0.5
                else { continue }
                window.setFrameOrigin(point)
                window.invalidateShadow()
            }
        }
    }

    // MARK: Levels

    /// Raises the panels over everything, or puts them back down. The same panels, the same
    /// frames and the same pixels at a different window level: summoning is not a mode.
    func setRaised(_ raised: Bool) {
        isRaised = raised
        let level = raised ? NSWindow.Level.floating : restingLevel
        for window in panels.values {
            window.level = level
            if raised { window.orderFrontRegardless() }
        }
    }

    /// Applies the settings a panel carries on itself: where it sits in the window order at
    /// rest, and whether it can be dragged.
    func applyPreferences() {
        restingLevel = preferences.displayMode.windowLevel
        let level = isRaised ? NSWindow.Level.floating : restingLevel
        for window in panels.values {
            window.level = level
            window.isMovableByWindowBackground = !preferences.isLocked
        }
    }
}
