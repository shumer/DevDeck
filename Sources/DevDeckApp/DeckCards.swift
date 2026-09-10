import DevDeckCore

/// The cards this deck can show, and which of them it is showing.
///
/// The built-in cards plus whatever the modules add, one per configured project, in the order
/// the modules are given, which is the order the deck is laid out in. Read fresh every time,
/// so a project added in settings is in the list the moment it is asked for.
@MainActor
final class DeckCards {
    private let preferences: Preferences
    private let modules: [CardModule]

    init(preferences: Preferences, modules: [CardModule]) {
        self.preferences = preferences
        self.modules = modules
    }

    var catalog: [CardDescriptor] {
        CardCatalog.all(including: modules.flatMap { $0.descriptors() })
    }

    /// Every card with its switch, in deck order.
    var resolved: [ResolvedCard] {
        preferences.cardLayout.resolved(catalog: catalog)
    }

    /// The cards that should be on screen, in deck order.
    var visible: [CardID] {
        preferences.cardLayout.visibleCards(catalog: catalog).map(\.id)
    }

    /// The menu group a card goes under, so a menu can keep project kinds apart. Nil for a
    /// built-in card.
    func menuGroup(of card: CardID) -> String? {
        modules.first { $0.owns(card) }?.menuGroup
    }

    /// The groups, in deck order, for a menu to offer in the same order.
    var menuGroups: [String] {
        modules.compactMap(\.menuGroup)
    }

    func setEnabled(_ isEnabled: Bool, for card: CardID) {
        var layout = preferences.cardLayout
        layout.setEnabled(isEnabled, for: card)
        preferences.cardLayout = layout
    }

    func isEnabled(_ card: CardID) -> Bool {
        preferences.cardLayout.isEnabled(card, catalog: catalog)
    }
}
