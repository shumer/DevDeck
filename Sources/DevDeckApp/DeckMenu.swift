import AppKit
import DevDeckCore
import DevDeckEngine
import DevDeckUI

/// The menu-bar item and every menu in the app, drawn from what the runtime decides.
///
/// Every menu here is repopulated as it opens, so a checkmark can never show state from
/// whenever the menu happened to be created: a menu built once keeps the checkmarks it had at
/// creation, which is how the lock toggle looked stuck on. What the menus say, which rows are on,
/// off or disabled and what each one does are `DeckRuntime.menu(samples:)` and
/// `cardMenu(for:)`; the icon and tooltip are `status()`. This turns them into AppKit and carries
/// out what only the Mac can do.
@MainActor
final class DeckMenu: NSObject, NSMenuDelegate {
    private let controller: DeckController
    private let panels: PanelCoordinator
    private let updater: Updater
    private let openSettings: () -> Void
    private let openCardSettings: (CardID) -> Void
    private let openAccountSettings: (AttentionService, String?) -> Void
    private let showCard: (CardID) -> Void
    private let quit: () -> Void
    /// Shows the sample rows instead of the deck's own, for `--menu sample`.
    var showsSamples = false

    private var statusItem: NSStatusItem!
    /// Which panel a context menu belongs to, so a right-click can offer something about *this*
    /// card rather than only about the deck.
    private var menuOwners: [ObjectIdentifier: CardID] = [:]

    init(
        controller: DeckController,
        panels: PanelCoordinator,
        updater: Updater,
        openSettings: @escaping () -> Void,
        openCardSettings: @escaping (CardID) -> Void,
        openAccountSettings: @escaping (AttentionService, String?) -> Void,
        showCard: @escaping (CardID) -> Void,
        quit: @escaping () -> Void
    ) {
        self.openAccountSettings = openAccountSettings
        self.showCard = showCard
        self.controller = controller
        self.panels = panels
        self.updater = updater
        self.openSettings = openSettings
        self.openCardSettings = openCardSettings
        self.quit = quit
    }

    /// Puts the item in the menu bar. Separate from `init` because the coordinator needs this
    /// object before the status item exists, and the status item needs nothing back.
    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = DeckStatusModel.checking.tooltip
        statusItem.button?.setAccessibilityLabel("DevDeck")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Opens the menu-bar menu, for a summary banner that promises the list.
    func open() {
        // Popped up under the item rather than clicked: a synthetic click on a status item does
        // not open its menu while the app is not the one in front, which an agent app never is.
        guard let button = statusItem?.button, let menu = statusItem?.menu else { return }
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    /// An empty menu with this object as its delegate: `menuNeedsUpdate` fills it in every
    /// time it opens.
    func contextMenu(for card: CardID) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menuOwners[ObjectIdentifier(menu)] = card
        return menu
    }

    /// A stack of cards with the app's initials cut out of the front one - the shape says
    /// "deck", the letters say whose, and the badge says which kind of attention is wanted. The
    /// counts go in the tooltip and to VoiceOver: a bare "8" in the menu bar belongs to nothing
    /// in particular.
    func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let status = controller.runtime.status()

        // Every state but one is a template, so it follows the menu bar's own light and dark
        // appearance; only the one that means a person is waiting on you opts out, because there
        // red is the message.
        button.image = DeckIcon.statusItemImage(DeckIconState(tier: status.tier))
        button.contentTintColor = nil
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = status.tooltip
        button.setAccessibilityValue(status.accessibilityValue)
    }

    // MARK: Filling the menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // AppKit re-enables any item whose target responds to the action unless automatic
        // enabling is off.
        menu.autoenablesItems = false
        if let card = menuOwners[ObjectIdentifier(menu)] {
            fill(menu, with: controller.runtime.cardMenu(for: card))
        } else {
            fill(menu, with: controller.runtime.menu(samples: showsSamples))
        }
    }

    private func fill(_ menu: NSMenu, with entries: [DeckMenuEntry]) {
        for entry in entries {
            switch entry {
            case .header(let title):
                menu.addItem(NSMenuItem.sectionHeader(title: title))
            case .separator:
                menu.addItem(.separator())
            case .item(let model):
                menu.addItem(item(model))
                if let alternate = model.alternate {
                    menu.addItem(twin(alternate, of: model))
                }
            case .submenu(let model, let children):
                let parent = item(model)
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                fill(submenu, with: children)
                parent.submenu = submenu
                menu.addItem(parent)
            }
        }
    }

    private func item(_ model: DeckMenuItem) -> NSMenuItem {
        let item = NSMenuItem(
            title: (model.isIndented ? "   " : "") + model.title,
            action: model.command == nil ? nil : #selector(choose(_:)),
            keyEquivalent: model.keyEquivalent
        )
        item.target = self
        item.representedObject = model.command.map { MenuCommand($0, confirmation: model.confirmation, prompt: model.prompt) }
        item.isEnabled = model.isEnabled
        item.state = model.isOn ? .on : .off
        item.image = model.image.flatMap(Self.image)
        item.toolTip = model.help
        if let subtitle = model.subtitle { setSubtitle(subtitle, on: item) }
        if let badge = model.badge { item.badge = NSMenuItemBadge(string: badge) }
        return item
    }

    private func twin(_ alternate: DeckMenuItem.Alternate, of model: DeckMenuItem) -> NSMenuItem {
        let twin = NSMenuItem(title: alternate.title, action: #selector(choose(_:)), keyEquivalent: "")
        twin.target = self
        twin.representedObject = MenuCommand(alternate.command, confirmation: nil, prompt: nil)
        twin.isAlternate = true
        twin.keyEquivalentModifierMask = .option
        twin.isEnabled = alternate.isEnabled
        twin.image = model.image.flatMap(Self.image)
        if let subtitle = model.subtitle { setSubtitle(subtitle, on: twin) }
        return twin
    }

    private static func image(_ image: DeckMenuItem.Image) -> NSImage? {
        switch image {
        case .attention(let mark): return AttentionImages.image(for: mark)
        case .calm: return AttentionImages.calm
        case .more: return AttentionImages.more
        }
    }

    /// The second line under a row. Before macOS 14.4 a menu item has no subtitle, and the words
    /// go into the tooltip rather than being lost.
    private func setSubtitle(_ text: String, on item: NSMenuItem) {
        if #available(macOS 14.4, *) {
            item.subtitle = text
        } else {
            item.toolTip = text
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let chosen = sender.representedObject as? MenuCommand else { return }
        if let question = chosen.confirmation {
            let alert = NSAlert()
            alert.messageText = question.title
            alert.informativeText = question.detail
            alert.addButton(withTitle: question.confirm)
            alert.addButton(withTitle: question.cancel)
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        if let prompt = chosen.prompt {
            guard let answer = ask(prompt) else { return }
            controller.perform(.saveArrangement(name: answer))
            return
        }
        controller.perform(chosen.command)
    }

    /// Asks for a typed answer, and gives it back as typed: whether it will do is the runtime's.
    private func ask(_ prompt: DeckPrompt) -> String? {
        let alert = NSAlert()
        alert.messageText = prompt.title
        alert.informativeText = prompt.detail
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = prompt.placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: prompt.confirm)
        alert.addButton(withTitle: prompt.cancel)
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    // MARK: What only the Mac can do

    /// The effects a menu row asks for that are about the app rather than a card.
    func carryOut(_ effect: DeckEffect) {
        switch effect {
        case .cardsChanged: panels.syncPanels()
        case .lockChanged: panels.applyPreferences()
        case .tidy: panels.tidy()
        case .openSettings: openSettings()
        case .openCardSettings(let card): openCardSettings(card)
        case .openAccountSettings(let service, let account): openAccountSettings(service, account)
        case .showCard(let card): showCard(card)
        case .openMenu: open()
        case .installUpdate: updater.install()
        case .quit: quit()
        case .arrangementApplied:
            panels.syncPanels()
            panels.replaceAll()
        default: break
        }
    }
}

/// A row's command, carried on the menu item until it is chosen.
private final class MenuCommand: NSObject {
    let command: DeckCommand
    let confirmation: DeckConfirmation?
    let prompt: DeckPrompt?

    init(_ command: DeckCommand, confirmation: DeckConfirmation?, prompt: DeckPrompt?) {
        self.command = command
        self.confirmation = confirmation
        self.prompt = prompt
    }
}
