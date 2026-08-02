import AppKit
import ArcKit
import Combine
import DevDeckCore
import DevDeckUI
import GitHubKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let preferences = Preferences()
    private let tokenStore: any TokenStore = CompositeTokenStore.standard()
    private let accountsStore = GitHubAccountsStore(backend: UserDefaults.standard)
    private let projectsStore = ArcProjectsStore(backend: UserDefaults.standard)

    private lazy var controller = DeckController(
        preferences: preferences,
        tokenStore: tokenStore,
        accountsStore: accountsStore,
        projectsStore: projectsStore
    )
    private lazy var settingsController = SettingsWindowController(
        tokenStore: tokenStore,
        accountsStore: accountsStore,
        projectsStore: projectsStore,
        preferences: preferences
    ) { [weak self] in
        // A project added or removed in settings changes the card list, not just the data.
        self?.syncPanels()
        self?.controller.refreshNow()
    }

    private var panels: [CardID: PanelWindow] = [:]
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()

    private var displayMode: DisplayMode {
        get { preferences.displayMode }
        set { preferences.displayMode = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "DevDeck — open pull requests"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Panels are sized from the data, so anything that changes it can change their height.
        Publishers.Merge4(
            controller.$pullRequests.map { _ in () },
            controller.$inbox.map { _ in () },
            controller.$actions.map { _ in () },
            controller.$expandedCards.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateStatusItem()
            self?.syncPanelSizes()
        }
        .store(in: &cancellables)

        syncPanels()
        updateStatusItem()
        controller.start()

        // No token on any account means nothing can load; open the one window that fixes that.
        let hasAnyToken = accountsStore.accounts().contains { account in
            ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil
        }
        if !hasAnyToken {
            settingsController.show()
        }

        if CommandLine.arguments.contains("--enable-login-item"), !startsAtLogin {
            toggleLoginItem()
        }
    }

    // MARK: Panels

    /// The built-in cards plus one per configured Arc project.
    private var catalog: [CardDescriptor] {
        CardCatalog.all(including: projectsStore.projects().map { project in
            CardDescriptor(
                id: project.cardID,
                title: project.title,
                subtitle: "Arc · \(project.organization)",
                isImplemented: true,
                isEnabledByDefault: true
            )
        })
    }

    private var visibleCards: [CardID] {
        preferences.cardLayout.visibleCards(catalog: catalog).map(\.id)
    }

    /// Brings the on-screen panels in line with the saved layout, and tells the controller
    /// which cards are worth fetching.
    private func syncPanels() {
        let wanted = visibleCards

        for (card, window) in panels where !wanted.contains(card) {
            let vacated = window.frame
            window.orderOut(nil)
            panels[card] = nil
            shiftColumn(below: vacated, by: vacated.height + DeckTheme.panelGap)
        }

        for card in wanted where panels[card] == nil {
            showPanel(card)
        }

        controller.setActiveCards(Set(wanted))
    }

    /// Grows and shrinks panels as their contents change, keeping the top edge where it is and
    /// pushing the rest of the column out of the way.
    private func syncPanelSizes() {
        for (card, window) in panels {
            let size = CardHostView.size(for: card, controller: controller)
            let old = window.frame
            guard abs(old.height - size.height) > 0.5 || abs(old.width - size.width) > 0.5 else { continue }

            let frame = NSRect(
                x: old.origin.x,
                y: old.maxY - size.height,
                width: size.width,
                height: size.height
            )
            window.setFrame(frame, display: true, animate: false)
            window.invalidateShadow()
            preferences.setOrigin(NSStringFromPoint(frame.origin), for: card)
            // Selection uses the old frame: those are the panels that were below before the
            // resize, and they are the ones that have to make room.
            shiftColumn(below: old, by: old.height - size.height)
        }
    }

    private func showPanel(_ card: CardID) {
        let size = CardHostView.size(for: card, controller: controller)
        let hosting = NSHostingView(rootView: CardHostView(controller: controller, card: card))
        let window = PanelWindow(card: card, size: size, origin: origin(for: card, size: size), content: hosting)
        window.level = displayMode.windowLevel
        window.isMovableByWindowBackground = !preferences.isLocked
        window.delegate = self
        window.contentView?.menu = buildMenu()
        window.orderFrontRegardless()
        panels[card] = window
    }

    /// Saved position when there is a usable one, otherwise the next slot in a column down
    /// the right edge.
    private func origin(for card: CardID, size: NSSize) -> NSPoint {
        if let saved = preferences.origin(for: card), saved.contains("{") {
            let point = NSPointFromString(saved)
            let frame = NSRect(origin: point, size: size)
            // NSPointFromString yields {0,0} for anything unparseable, and a panel restored
            // 99% off-screen cannot be grabbed back, so require a real overlap.
            let usable = NSScreen.screens.contains { screen in
                let intersection = screen.visibleFrame.intersection(frame)
                return intersection.width >= 80 && intersection.height >= 40
            }
            if usable { return point }
        }

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var y = screen.maxY - 28
        for candidate in visibleCards {
            let candidateSize = CardHostView.size(for: candidate, controller: controller)
            if candidate == card {
                return NSPoint(x: screen.maxX - candidateSize.width - 28, y: y - candidateSize.height)
            }
            if panels[candidate] != nil { y -= candidateSize.height + DeckTheme.panelGap }
        }
        return NSPoint(x: screen.maxX - size.width - 28, y: y - size.height)
    }

    /// Moves every panel sitting under `frame` in the same column by `dy` — positive is up,
    /// since AppKit's y grows upward.
    ///
    /// This is what stops a hidden card leaving a card-shaped hole, and what makes room when a
    /// card is expanded. Only panels that overlap horizontally are touched, so a deliberately
    /// scattered layout is left alone.
    private func shiftColumn(below frame: NSRect, by dy: CGFloat) {
        guard dy != 0 else { return }
        for (card, window) in panels {
            let current = window.frame
            guard current.maxY <= frame.minY + 1 else { continue }
            guard current.maxX > frame.minX, current.minX < frame.maxX else { continue }
            window.setFrameOrigin(NSPoint(x: current.origin.x, y: current.origin.y + dy))
            preferences.setOrigin(NSStringFromPoint(window.frame.origin), for: card)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? PanelWindow else { return }
        preferences.setOrigin(NSStringFromPoint(window.frame.origin), for: window.card)
    }

    // MARK: Menu bar

    /// A stack of panels — the app is a deck of cards on the desktop, and the icon should say
    /// so at a glance. Numbers go in the tooltip: a bare "8" in the menu bar belongs to
    /// nothing in particular.
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let summary = controller.statusSummary

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "DevDeck")?
            .withSymbolConfiguration(configuration)

        // Template images follow the menu bar's own light and dark appearance; the alert state
        // opts out of that deliberately, because red is the message.
        image?.isTemplate = !summary.isAlert
        button.image = image
        button.contentTintColor = summary.isAlert ? .systemRed : nil
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = summary.tooltip
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    private func populate(_ menu: NSMenu) {
        // AppKit re-enables any item whose target responds to the action unless automatic
        // enabling is off — without this the not-built-yet cards become clickable again.
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Cards", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let resolved = preferences.cardLayout.resolved(catalog: catalog)
        let projectIDs = Set(projectsStore.projects().map(\.cardID))

        for card in resolved where !projectIDs.contains(card.id) {
            menu.addItem(cardItem(card))
        }

        // Projects get their own group: with several of them the built-in cards would
        // otherwise be lost in the middle of a list of site names.
        let projectCards = resolved.filter { projectIDs.contains($0.id) }
        if !projectCards.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Arc projects", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for card in projectCards {
                menu.addItem(cardItem(card))
            }
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open pull requests in browser", action: #selector(openDashboard), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Start at login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.state = startsAtLogin ? .on : .off
        login.target = self
        menu.addItem(login)

        menu.addItem(.separator())
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.menuTitle, action: #selector(setMode(_:)), keyEquivalent: "")
            item.state = displayMode == mode ? .on : .off
            item.representedObject = mode.rawValue
            item.target = self
            menu.addItem(item)
        }
        let lock = NSMenuItem(title: "Lock position (no dragging)", action: #selector(toggleLock), keyEquivalent: "")
        lock.state = preferences.isLocked ? .on : .off
        lock.target = self
        menu.addItem(lock)

        menu.addItem(.separator())
        for (title, selector) in [
            ("Tidy panels into a column", #selector(restack)),
            ("Refresh now", #selector(refreshNow)),
            ("Settings…", #selector(openSettings)),
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit DevDeck", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Actions

    private func cardItem(_ card: ResolvedCard) -> NSMenuItem {
        let item = NSMenuItem(
            title: "   " + card.descriptor.title,
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

    @objc private func toggleCard(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String else { return }
        let card = CardID(rawValue: raw)
        var layout = preferences.cardLayout
        layout.setEnabled(!layout.isEnabled(card, catalog: catalog), for: card)
        preferences.cardLayout = layout
        syncPanels()
    }

    @objc private func setMode(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let mode = DisplayMode(rawValue: raw) else { return }
        displayMode = mode
        for window in panels.values { window.level = mode.windowLevel }
    }

    @objc private func toggleLock() {
        preferences.isLocked.toggle()
        for window in panels.values {
            window.isMovableByWindowBackground = !preferences.isLocked
        }
    }

    /// Closes up the column while keeping it where the user put it: anchor on the topmost
    /// panel and stack the rest beneath it. It deliberately does not reset to a corner.
    @objc private func restack() {
        let ordered = visibleCards.compactMap { card in panels[card].map { (card, $0) } }
        guard let anchor = ordered.max(by: { $0.1.frame.maxY < $1.1.frame.maxY })?.1 else { return }

        var y = anchor.frame.maxY
        let x = anchor.frame.minX
        for (card, window) in ordered {
            y -= window.frame.height
            window.setFrameOrigin(NSPoint(x: x, y: y))
            preferences.setOrigin(NSStringFromPoint(window.frame.origin), for: card)
            y -= DeckTheme.panelGap
        }
    }

    @objc private func refreshNow() {
        controller.refreshNow()
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @objc private func openDashboard() {
        guard let url = CardHostView.dashboardURL(for: .githubPullRequests) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        controller.stop()
        NSApp.terminate(nil)
    }

    // MARK: Login item

    /// Read from the system rather than a preference, so the menu cannot drift from reality
    /// when the user turns it off in System Settings.
    private var startsAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLoginItem() {
        do {
            if startsAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change the login item"
            alert.informativeText = """
                \(error.localizedDescription)

                macOS registers the app by its location, so this usually means the app is \
                somewhere it does not consider stable. Move DevDeck.app to /Applications and \
                try again, or add it under System Settings → General → Login Items.
                """
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
