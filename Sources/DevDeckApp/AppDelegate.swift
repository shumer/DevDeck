import AppKit
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

    private lazy var controller = DeckController(preferences: preferences, tokenStore: tokenStore)
    private lazy var settingsController = SettingsWindowController(tokenStore: tokenStore) { [weak self] in
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

        controller.$pullRequests
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        syncPanels()
        updateStatusItem()
        controller.start()

        // No token yet means nothing can load; open the one window that fixes that.
        if ((try? tokenStore.token(for: .github)) ?? nil) == nil {
            settingsController.show()
        }

        if CommandLine.arguments.contains("--enable-login-item"), !startsAtLogin {
            toggleLoginItem()
        }
    }

    // MARK: Panels

    private var visibleCards: [CardID] {
        preferences.cardLayout.visibleCards().map(\.id)
    }

    /// Brings the on-screen panels in line with the saved layout, and tells the controller
    /// which cards are worth fetching.
    private func syncPanels() {
        let wanted = visibleCards

        for (card, window) in panels where !wanted.contains(card) {
            let vacated = window.frame
            window.orderOut(nil)
            panels[card] = nil
            closeGap(below: vacated, height: vacated.height + DeckTheme.panelGap)
        }

        for card in wanted where panels[card] == nil {
            showPanel(card)
        }

        controller.setActiveCards(Set(wanted))
    }

    private func showPanel(_ card: CardID) {
        let size = CardHostView.size(for: card)
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
            let candidateSize = CardHostView.size(for: candidate)
            if candidate == card {
                return NSPoint(x: screen.maxX - candidateSize.width - 28, y: y - candidateSize.height)
            }
            if panels[candidate] != nil { y -= candidateSize.height + DeckTheme.panelGap }
        }
        return NSPoint(x: screen.maxX - size.width - 28, y: y - size.height)
    }

    /// Moves panels below `frame` in the same column up, so hiding a card does not leave a
    /// card-shaped hole in the stack.
    private func closeGap(below frame: NSRect, height: CGFloat) {
        for (card, window) in panels {
            let current = window.frame
            guard current.maxY <= frame.minY + 1 else { continue }
            guard current.maxX > frame.minX, current.minX < frame.maxX else { continue }
            window.setFrameOrigin(NSPoint(x: current.origin.x, y: current.origin.y + height))
            preferences.setOrigin(NSStringFromPoint(window.frame.origin), for: card)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? PanelWindow else { return }
        preferences.setOrigin(NSStringFromPoint(window.frame.origin), for: window.card)
    }

    // MARK: Menu bar

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let summary = controller.statusSummary
        let color: NSColor = summary.isUnknown
            ? .secondaryLabelColor
            : (summary.isAlert ? NSColor.systemRed : NSColor.labelColor)
        button.attributedTitle = NSAttributedString(
            string: "◆ \(summary.text)",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: color,
            ]
        )
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

        let layout = preferences.cardLayout
        for card in layout.resolved() {
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
            menu.addItem(item)
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

    @objc private func toggleCard(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String else { return }
        let card = CardID(rawValue: raw)
        var layout = preferences.cardLayout
        layout.setEnabled(!layout.isEnabled(card), for: card)
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
