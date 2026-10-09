import AppKit
import DevDeckCore
import DevDeckEngine
import DevDeckUI

/// Owns the panels as windows: opens, sizes, moves and closes them as `DeckPlacement` decides.
///
/// Where a panel goes, when a position is written down, what is parked and how a column closes
/// up are the engine's; see `DeckPlacement`. This reports what only the Mac sees (a panel moved,
/// the screens changed, how big a card draws) and applies the changes it gets back, at window
/// levels the summon key and the display mode set.
@MainActor
final class PanelCoordinator: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let controller: DeckController
    /// Builds the context menu for one panel. Supplied by the menu object, which is the one
    /// that fills it in when it opens.
    private let makeContextMenu: (CardID) -> NSMenu
    private var placement: DeckPlacement!

    private var panels: [CardID: PanelWindow] = [:]
    /// True while the deck is applying its own decisions. AppKit posts `windowDidMove` for
    /// programmatic moves too, and those are not news to the engine.
    private var isRepositioning = false
    /// What the panels sit at when nobody is holding the summon key.
    private var restingLevel: NSWindow.Level
    /// Whether they are currently raised over everything.
    private var isRaised = false

    init(
        preferences: Preferences,
        controller: DeckController,
        makeContextMenu: @escaping (CardID) -> NSMenu
    ) {
        self.preferences = preferences
        self.controller = controller
        self.makeContextMenu = makeContextMenu
        self.restingLevel = preferences.displayMode.windowLevel
        super.init()
        placement = controller.runtime.placePanels(
            measure: { CardHostView.size(for: $0) },
            displays: { Displays.deck() }
        )
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

    // MARK: Asking the engine

    /// Brings the on-screen panels in line with the cards that are on.
    func syncPanels() {
        apply(placement.sync())
    }

    /// Grows and shrinks panels as their contents change.
    func syncPanelSizes() {
        apply(placement.syncSizes())
    }

    /// Closes up every column, when packing has just been turned on.
    func packAllColumns() {
        apply(placement.packAllColumns())
    }

    /// Closes up the deck while keeping it where the user put it.
    func tidy() {
        apply(placement.tidy())
    }

    /// Puts every panel where its placement says, home or parked.
    @objc func replaceAll() {
        apply(placement.placeAfterScreensChanged())
    }

    // MARK: Applying

    private func apply(_ changes: [DeckPanelChange]) {
        isRepositioning = true
        defer { isRepositioning = false }
        for change in changes {
            switch change {
            case .close(let card):
                panels[card]?.orderOut(nil)
                panels[card] = nil
            case .open(let card, let frame):
                open(card, frame: frame)
            case .place(let card, let frame):
                guard let window = panels[card] else { continue }
                let current = window.frame
                if abs(current.width - frame.width) > 0.5 || abs(current.height - frame.height) > 0.5 {
                    window.setFrame(frame, display: true, animate: false)
                    // Collapsing changes the shape as well as the height.
                    window.apply(cornerRadius: cornerRadius(for: card))
                    window.invalidateShadow()
                } else {
                    window.setFrameOrigin(frame.origin)
                }
            }
        }
    }

    private func open(_ card: CardID, frame: NSRect) {
        let hosting = PanelHostingView(rootView: CardHostView(controller: controller, card: card))
        let window = PanelWindow(
            card: card,
            size: frame.size,
            origin: frame.origin,
            cornerRadius: cornerRadius(for: card),
            content: hosting
        )
        window.level = isRaised ? .floating : restingLevel
        window.isMovableByWindowBackground = !preferences.isLocked
        window.delegate = self
        window.contentView?.menu = makeContextMenu(card)
        window.orderFrontRegardless()
        panels[card] = window
    }

    /// A collapsed panel is a different shape, not just a shorter one.
    private func cornerRadius(for card: CardID) -> CGFloat {
        controller.isCollapsed(card) ? CollapsedCardMetrics.cornerRadius : DeckTheme.cornerRadius
    }

    // MARK: What only the Mac sees

    func windowDidMove(_ notification: Notification) {
        guard !isRepositioning, let window = notification.object as? PanelWindow else { return }
        let due = placement.moved(window.card, to: window.frame, at: Date().timeIntervalSinceReferenceDate)
        schedule(due)
    }

    private func schedule(_ due: TimeInterval?) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(settleMoves), object: nil)
        guard let due else { return }
        let delay = max(due - Date().timeIntervalSinceReferenceDate, 0) + 0.01
        perform(#selector(settleMoves), with: nil, afterDelay: delay)
    }

    @objc private func settleMoves() {
        schedule(placement.settleMoves(at: Date().timeIntervalSinceReferenceDate))
    }

    @objc private func screensChanged() {
        placement.screensChanged()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(settleMoves), object: nil)
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(replaceAll), object: nil)
        perform(#selector(replaceAll), with: nil, afterDelay: DeckPlacement.screensSettle)
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
