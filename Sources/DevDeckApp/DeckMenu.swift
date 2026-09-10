import AppKit
import DevDeckCore
import DevDeckUI

/// The menu-bar item and every menu in the app.
///
/// Every menu here is repopulated as it opens, so a checkmark can never show state from
/// whenever the menu happened to be created: a menu built once keeps the checkmarks it had at
/// creation, which is how the lock toggle looked stuck on. The status item's icon and tooltip
/// come from `DeckStatusSummary`; this only draws them.
@MainActor
final class DeckMenu: NSObject, NSMenuDelegate {
    private let controller: DeckController
    private let cards: DeckCards
    private let panels: PanelCoordinator
    private let arrangements: ArrangementsController
    private let openSettings: () -> Void
    private let quit: () -> Void

    private var statusItem: NSStatusItem!
    /// Which panel a context menu belongs to, so a right-click can offer something about *this*
    /// card rather than only about the deck.
    private var menuOwners: [ObjectIdentifier: CardID] = [:]

    init(
        controller: DeckController,
        cards: DeckCards,
        panels: PanelCoordinator,
        arrangements: ArrangementsController,
        openSettings: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.controller = controller
        self.cards = cards
        self.panels = panels
        self.arrangements = arrangements
        self.openSettings = openSettings
        self.quit = quit
    }

    /// Puts the item in the menu bar. Separate from `init` because the coordinator needs this
    /// object before the status item exists, and the status item needs nothing back.
    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "DevDeck, open pull requests"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
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
    /// "deck", the letters say whose. Numbers go in the tooltip: a bare "8" in the menu bar
    /// belongs to nothing in particular.
    func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let summary = controller.statusSummary

        // Calm and blocked are templates, so they follow the menu bar's own light and dark
        // appearance; only the one that means a person is waiting on you opts out, because there
        // red is the message.
        button.image = DeckIcon.statusItemImage(summary.state)
        button.contentTintColor = nil
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = summary.tooltip
    }

    // MARK: Filling the menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // A right-click on a panel is a question about *that* card. It used to answer with the
        // whole deck's menu, card list and all, which is the same as not answering.
        if let card = menuOwners[ObjectIdentifier(menu)] {
            populateCard(menu, card: card)
            return
        }
        populate(menu)
    }

    /// The short menu: this card, then the two things you might want next.
    private func populateCard(_ menu: NSMenu, card: CardID) {
        menu.autoenablesItems = false

        let header = NSMenuItem(title: CardCatalog.descriptor(for: card)?.title ?? card.rawValue, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let collapse = NSMenuItem(
            title: controller.isCollapsed(card) ? "Show the whole card" : "Collapse to one row",
            action: #selector(toggleCollapsed(_:)),
            keyEquivalent: ""
        )
        collapse.target = self
        collapse.representedObject = card.rawValue
        menu.addItem(collapse)

        if controller.hasLogSource(card) {
            let logs = NSMenuItem(
                title: controller.isExpanded(card) ? "Hide the log" : "Show the log",
                action: #selector(toggleLogs(_:)),
                keyEquivalent: ""
            )
            logs.target = self
            logs.representedObject = card.rawValue
            logs.isEnabled = !controller.isCollapsed(card)
            menu.addItem(logs)
        }

        let hide = NSMenuItem(title: "Hide this card", action: #selector(toggleCard(_:)), keyEquivalent: "")
        hide.target = self
        hide.representedObject = card.rawValue
        menu.addItem(hide)

        menu.addItem(.separator())
        for (title, selector) in [
            ("Tidy panels into columns", #selector(tidy)),
            ("Refresh now", #selector(refreshNow)),
            ("All cards and settings…", #selector(showSettings)),
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
    }

    private func populate(_ menu: NSMenu) {
        // AppKit re-enables any item whose target responds to the action unless automatic
        // enabling is off - without this the not-built-yet cards become clickable again.
        menu.autoenablesItems = false

        // Why the badge is lit, in words, before anything else. The icon can carry two states
        // and no more; the sentence is what makes them mean something.
        if let reason = controller.statusSummary.reason {
            let item = NSMenuItem(title: reason, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let header = NSMenuItem(title: "Cards", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let resolved = cards.resolved
        for card in resolved where cards.menuGroup(of: card.id) == nil {
            menu.addItem(cardItem(card))
        }

        // Projects get their own groups: with several of them the built-in cards would
        // otherwise be lost in the middle of a list of site names.
        for group in cards.menuGroups {
            addGroup(group, cards: resolved.filter { cards.menuGroup(of: $0.id) == group }, to: menu)
        }

        // The one item that is about a kind rather than a card. It stays here rather than in
        // the module, because it is the only one and a protocol for it would be a protocol
        // with one conformer.
        let hasDDEV = resolved.contains { cards.menuGroup(of: $0.id) == "DDEV projects" }
        if hasDDEV {
            let powerOff = NSMenuItem(
                title: "Power off all DDEV",
                action: #selector(powerOffDDEV),
                keyEquivalent: ""
            )
            powerOff.target = self
            powerOff.toolTip = "ddev poweroff: stops every project and the router"
            menu.addItem(powerOff)
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open pull requests in browser", action: #selector(openDashboard), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        // Everything below is something you *do*. What the deck *is* - where the panels sit,
        // whether they are locked, whether ⌥Space raises them, whether the app starts at login -
        // lives in Settings. A menu that mixes the two grows until the thing you actually came
        // for is somewhere in the middle of it.
        menu.addItem(.separator())
        let arrangementsItem = NSMenuItem(title: "Arrangements", action: nil, keyEquivalent: "")
        arrangementsItem.submenu = arrangements.submenu()
        menu.addItem(arrangementsItem)

        for (title, selector) in [
            ("Tidy panels into columns", #selector(tidy)),
            ("Refresh now", #selector(refreshNow)),
            ("Settings…", #selector(showSettings)),
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit DevDeck", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// A submenu rather than a run of items with a heading above them.
    ///
    /// Ten projects made thirteen lines of a menu whose other five are the things you actually
    /// opened it for. The count in the title says how many are on the deck without opening it.
    private func addGroup(_ title: String, cards: [ResolvedCard], to menu: NSMenu) {
        guard !cards.isEmpty else { return }
        let shown = cards.filter(\.isEnabled).count
        let item = NSMenuItem(title: "\(title)  (\(shown)/\(cards.count))", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for card in cards {
            submenu.addItem(cardItem(card, indented: false))
        }
        item.submenu = submenu
        menu.addItem(item)
    }

    private func cardItem(_ card: ResolvedCard, indented: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(
            title: (indented ? "   " : "") + card.descriptor.title,
            action: #selector(toggleCard(_:)),
            keyEquivalent: ""
        )
        item.state = card.isEnabled ? .on : .off
        item.representedObject = card.id.rawValue
        item.target = self
        if !card.descriptor.isImplemented {
            item.isEnabled = false
            item.toolTip = "Not built yet"
        }
        return item
    }

    // MARK: Actions

    @objc private func toggleLogs(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String else { return }
        controller.toggleLogs(for: CardID(rawValue: raw))
    }

    @objc private func toggleCollapsed(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String else { return }
        controller.toggleCollapsed(CardID(rawValue: raw))
    }

    @objc private func toggleCard(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String else { return }
        let card = CardID(rawValue: raw)
        cards.setEnabled(!cards.isEnabled(card), for: card)
        panels.syncPanels()
    }

    @objc private func powerOffDDEV() {
        // The one item in this menu that stops everything at once, and it sits a line away from
        // Refresh now.
        let alert = NSAlert()
        alert.messageText = "Power off every DDEV project?"
        alert.informativeText = "ddev poweroff stops every project on this machine and the router "
            + "with them, whether or not it is on the deck."
        alert.addButton(withTitle: "Power off")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        controller.powerOffDDEV()
    }

    @objc private func tidy() {
        panels.tidy()
    }

    @objc private func refreshNow() {
        controller.refreshNow()
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func openDashboard() {
        guard let url = CardHostView.dashboardURL(for: .githubPullRequests) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() {
        quit()
    }
}
