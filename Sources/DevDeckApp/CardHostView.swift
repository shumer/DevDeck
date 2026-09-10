import AppKit
import DevDeckCore
import DevDeckUI
import SwiftUI

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
    }

    private var unimplemented: some View {
        CardChrome(title: CardCatalog.descriptor(for: card)?.title ?? card.rawValue) {
            Spacer()
            Text("Not built yet")
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
