import AppKit
import DevDeckCore

/// Saved decks: which cards are on, which are folded, and where each one sits.
///
/// The arithmetic of comparing and storing them is `DeckArrangement` in Core; this is the
/// part that asks for a name, applies one to the live deck and offers them in a menu.
@MainActor
final class ArrangementsController: NSObject {
    private let preferences: Preferences
    private let controller: DeckController
    private let cards: DeckCards
    private let panels: PanelCoordinator

    init(preferences: Preferences, controller: DeckController, cards: DeckCards, panels: PanelCoordinator) {
        self.preferences = preferences
        self.controller = controller
        self.cards = cards
        self.panels = panels
    }

    /// The deck as it is right now, in the form an arrangement is stored in.
    private func current() -> [DeckArrangement.Placed] {
        cards.catalog.map { descriptor in
            DeckArrangement.Placed(
                card: descriptor.id.rawValue,
                isVisible: panels.isShowing(descriptor.id),
                isCollapsed: controller.isCollapsed(descriptor.id),
                placement: preferences.placement(for: descriptor.id)?.storage
            )
        }
    }

    /// The submenu: every saved arrangement, ticked when it is the one on screen, and a way to
    /// save the current one.
    func submenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = current()
        for saved in preferences.arrangements {
            let item = NSMenuItem(title: saved.name, action: #selector(apply(_:)), keyEquivalent: "")
            item.state = saved.matches(current) ? .on : .off
            item.representedObject = saved.name
            item.target = self
            // Alt-click forgets it, which is where macOS puts the destructive twin of a menu
            // item and saves the submenu from being twice as long.
            let forget = NSMenuItem(title: "Forget \(saved.name)", action: #selector(forget(_:)), keyEquivalent: "")
            forget.representedObject = saved.name
            forget.target = self
            forget.isAlternate = true
            forget.keyEquivalentModifierMask = .option
            submenu.addItem(item)
            submenu.addItem(forget)
        }
        if !preferences.arrangements.isEmpty { submenu.addItem(.separator()) }
        let save = NSMenuItem(title: "Save this one…", action: #selector(save), keyEquivalent: "")
        save.target = self
        submenu.addItem(save)
        return submenu
    }

    @objc private func save() {
        let alert = NSAlert()
        alert.messageText = "Save this arrangement"
        alert.informativeText = "Which cards are on the deck, which are folded to a row, and where "
            + "each one sits. Saving over a name replaces it."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Il Tempo day"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        preferences.arrangements = DeckArrangements.adding(
            DeckArrangement(name: name, cards: current()),
            to: preferences.arrangements
        )
    }

    /// Puts a saved arrangement back: the card list first, then the sizes, then the positions.
    ///
    /// In that order on purpose. A card has to exist before it can be folded, and it has to be
    /// the right size before it is put anywhere, or the panel lands somewhere and then changes
    /// shape under itself.
    @objc private func apply(_ item: NSMenuItem) {
        guard let name = item.representedObject as? String,
              let arrangement = preferences.arrangements.first(where: { $0.name == name })
        else { return }

        for placed in arrangement.cards {
            let card = CardID(rawValue: placed.card)
            cards.setEnabled(placed.isVisible, for: card)
            if let storage = placed.placement, let placement = PanelPlacement(storage: storage) {
                preferences.setPlacement(placement, for: card)
            }
            if controller.isCollapsed(card) != placed.isCollapsed {
                controller.toggleCollapsed(card)
            }
        }

        panels.syncPanels()
        panels.replaceAll()
    }

    @objc private func forget(_ item: NSMenuItem) {
        guard let name = item.representedObject as? String else { return }
        preferences.arrangements = DeckArrangements.removing(name, from: preferences.arrangements)
    }
}
