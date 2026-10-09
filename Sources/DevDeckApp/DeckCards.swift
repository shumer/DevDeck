import DevDeckCore
import DevDeckEngine

/// The cards this deck can show, and which of them it is showing: the runtime's list, for the
/// parts of the shell that place panels and save arrangements.
@MainActor
final class DeckCards {
    private let controller: DeckController

    init(controller: DeckController) {
        self.controller = controller
    }

    var catalog: [CardDescriptor] { controller.runtime.cards.catalog }

    /// Every card with its switch, in deck order.
    var resolved: [ResolvedCard] { controller.runtime.cards.resolved }

    /// The cards that should be on screen, in deck order.
    var visible: [CardID] { controller.runtime.cards.visible }

    func setEnabled(_ isEnabled: Bool, for card: CardID) {
        controller.runtime.cards.setEnabled(isEnabled, for: card)
    }

    func isEnabled(_ card: CardID) -> Bool {
        controller.runtime.cards.isEnabled(card)
    }
}
