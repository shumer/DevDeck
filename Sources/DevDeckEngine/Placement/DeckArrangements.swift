import DevDeckCore
import Foundation

// Saved decks: which cards are on, which are folded, and where each one sits. The arithmetic of
// comparing and storing them is `DeckArrangement` in Core; this is the part that offers them,
// saves the deck under a name and puts one back.

/// A question with a typed answer, asked before a command goes ahead.
public struct DeckPrompt: Sendable, Equatable, Codable {
    public let title: String
    public let detail: String
    public let placeholder: String
    public let confirm: String
    public let cancel: String
}

extension DeckRuntime {
    /// The deck as it is right now, in the form an arrangement is stored in.
    private func currentArrangement() -> [DeckArrangement.Placed] {
        let showing = placement?.frames ?? [:]
        return cards.catalog.map { descriptor in
            DeckArrangement.Placed(
                card: descriptor.id.rawValue,
                isVisible: showing[descriptor.id] != nil,
                isCollapsed: isCollapsedByChoice(descriptor.id),
                placement: savedPlacement(for: descriptor.id)?.storage
            )
        }
    }

    /// Every saved arrangement, ticked when it is the one on screen, and a way to save the
    /// current one. ⌥ forgets one, which is where macOS puts the destructive twin of a menu item
    /// and saves the submenu from being twice as long.
    func arrangementEntries() -> [DeckMenuEntry] {
        var entries: [DeckMenuEntry] = []
        let current = currentArrangement()
        let saved = savedArrangements
        for arrangement in saved {
            var item = DeckMenuItem(arrangement.name, command: .applyArrangement(name: arrangement.name))
            item.isOn = arrangement.matches(current)
            item.alternate = .init(title: L("arrangements.forget", arrangement.name), command: .forgetArrangement(name: arrangement.name))
            entries.append(.item(item))
        }
        if !saved.isEmpty { entries.append(.separator) }
        var save = DeckMenuItem(L("arrangements.save"), command: .saveArrangement(name: ""))
        save.prompt = DeckPrompt(
            title: L("arrangements.save.title"),
            detail: L("arrangements.save.detail"),
            placeholder: L("arrangements.name.placeholder"),
            confirm: L("button.save"),
            cancel: L("button.cancel")
        )
        entries.append(.item(save))
        return entries
    }

    /// Saves the deck as it is under a name, replacing one of the same name. A name of nothing
    /// but spaces saves nothing.
    func saveArrangement(named name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        savedArrangements = DeckArrangements.adding(DeckArrangement(name: name, cards: currentArrangement()), to: savedArrangements)
    }

    func forgetArrangement(named name: String) {
        savedArrangements = DeckArrangements.removing(name, from: savedArrangements)
    }

    /// Puts a saved arrangement back: the card list first, then the folds, then the positions.
    ///
    /// In that order on purpose. A card has to exist before it can be folded, and it has to be
    /// the right size before it is put anywhere, or the panel lands somewhere and then changes
    /// shape under itself. The shell then opens the panels and places them.
    func applyArrangement(named name: String) {
        guard let arrangement = savedArrangements.first(where: { $0.name == name }) else { return }
        let list = cards
        for placed in arrangement.cards {
            let card = CardID(rawValue: placed.card)
            list.setEnabled(placed.isVisible, for: card)
            if let storage = placed.placement, let placement = PanelPlacement(storage: storage) {
                savePlacement(placement, for: card)
            }
            if isCollapsedByChoice(card) != placed.isCollapsed {
                toggleCollapsed(card)
            }
        }
        effect(.arrangementApplied)
    }
}
