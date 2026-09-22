import AppKit
import DevDeckCore
import DevDeckUI
import SwiftUI

/// Hands a drag on a card to the window server, the way a title bar would.
@MainActor
enum PanelDrag {
    /// How far the mouse travels before a press on a card is a drag rather than a click.
    static let threshold: CGFloat = 3

    /// The mouse-down a drag has already been handed off for. The gesture keeps reporting while
    /// the window server moves the panel, and one press is one drag.
    private static var handedOff: Int?

    static func begin() {
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDragged,
              event.eventNumber != handedOff,
              let window = event.window,
              // The lock lives on the window: `isMovableByWindowBackground` is what Lock
              // positions turns off, so a locked panel stays where it is either way.
              window.isMovableByWindowBackground
        else { return }
        handedOff = event.eventNumber
        window.performDrag(with: event)
    }
}

/// Maps a card identifier onto its view and its panel size.
///
/// The one place that asks the modules "whose card is this", so adding a card means one
/// module and one descriptor in `CardCatalog`. Observes the controller so the module's view
/// is rebuilt whenever the data it reads changes.
struct CardHostView: View {
    @ObservedObject var controller: DeckController
    let card: CardID

    /// The modules, in deck order. Set once at launch; a view cannot carry a reference to the
    /// app's objects any other way, and a card is never drawn before they exist.
    @MainActor static var modules: [CardModule] = []

    @MainActor
    static func module(for card: CardID) -> CardModule? {
        modules.first { $0.owns(card) }
    }

    var body: some View {
        Group {
            if let module = Self.module(for: card) {
                module.view(for: card)
            } else {
                unimplemented
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard let url = Self.dashboardURL(for: card) else { return }
            // The dashboard belongs to whichever account is first; there is no row to ask.
            LinkOpener.open(url, using: controller.browser(for: controller.accountLabels.keys.sorted().first ?? ""))
        }
        // Moving the panel is asked for here, explicitly, rather than left to the window's
        // "movable by background". That one is decided by AppKit before SwiftUI sees the click,
        // and on a binary built against a current SDK SwiftUI claims the click for the card's
        // own gestures first: the window never heard about the drag, and no card could be moved.
        // Simultaneous, so the double click on the card and the taps on its buttons still win
        // whenever the mouse does not travel.
        .simultaneousGesture(
            DragGesture(minimumDistance: PanelDrag.threshold, coordinateSpace: .global)
                .onChanged { _ in PanelDrag.begin() }
        )
    }

    private var unimplemented: some View {
        CardChrome(title: CardCatalog.descriptor(for: card)?.title ?? card.rawValue) {
            Spacer()
            Text(L("card.notBuilt"))
                .font(.system(size: 13))
                .foregroundStyle(DeckTheme.label)
            Spacer()
        }
    }

    @MainActor
    static func size(for card: CardID) -> NSSize {
        module(for: card)?.size(for: card) ?? NSSize(width: CardMetrics.width, height: 150)
    }

    /// Where a double-click on the panel background goes: the same data, on the web.
    @MainActor
    static func dashboardURL(for card: CardID) -> URL? {
        module(for: card)?.dashboardURL(for: card)
    }
}
