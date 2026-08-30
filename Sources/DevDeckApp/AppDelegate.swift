import AppKit
import ArcKit
import DDEVKit
import Combine
import DevDeckCore
import DevDeckUI
import GitHubKit
import GitLabKit
import ProjectKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let preferences = Preferences()
    private let tokenStore: any TokenStore = CompositeTokenStore.standard()
    private let accountsStore = GitHubAccountsStore(backend: UserDefaults.standard)
    private let gitlabAccountsStore = GitLabAccountsStore(backend: UserDefaults.standard)
    private let projectsStore = ArcProjectsStore(backend: UserDefaults.standard)
    private let ddevProjectsStore = DDEVProjectsStore(backend: UserDefaults.standard)
    private let localProjectsStore = LocalProjectsStore(backend: UserDefaults.standard)

    private lazy var controller = DeckController(
        preferences: preferences,
        tokenStore: tokenStore,
        accountsStore: accountsStore,
        gitlabAccountsStore: gitlabAccountsStore,
        projectsStore: projectsStore,
        ddevProjectsStore: ddevProjectsStore,
        localProjectsStore: localProjectsStore
    )
    private lazy var settingsController = SettingsWindowController(
        tokenStore: tokenStore,
        accountsStore: accountsStore,
        gitlabAccountsStore: gitlabAccountsStore,
        projectsStore: projectsStore,
        ddevProjectsStore: ddevProjectsStore,
        localProjectsStore: localProjectsStore,
        preferences: preferences
    ) { [weak self] in
        // A project added or removed in settings changes the card list, not just the data.
        self?.syncPanels()
        self?.controller.refreshNow()
        // And any deck preference may have changed, which only counts once it is applied.
        self?.applyDeckPreferences()
    }

    private var panels: [CardID: PanelWindow] = [:]
    /// True while the deck is putting panels where they already belong rather than someone
    /// moving them. AppKit posts `windowDidMove` for programmatic moves too, so without this the
    /// deck saves its own repositioning as though it were an arrangement a person chose.
    private var isRepositioning = false
    private var menuOwners: [ObjectIdentifier: CardID] = [:]
    private var hotKey: GlobalHotKey?
    private var veils: [VeilWindow] = []
    /// Raised right now, whether by a held key or a latched tap.
    private var isSummoned = false
    /// Latched by a tap, so it stays up until the next press.
    private var isLatched = false
    private var summonedAt: Date?
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()

    /// Where the panels sit, from settings. Read-only here: the switch that changes it lives in
    /// the settings screen, and the deck finds out through `applyDeckPreferences`.
    private var displayMode: DisplayMode { preferences.displayMode }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "DevDeck, open pull requests"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Panels are sized from the data, so anything that changes it can change their height -
        // a branch line appearing on a project card counts just as much as a pull request does.
        Publishers.MergeMany(
            controller.$pullRequests.map { _ in () }.eraseToAnyPublisher(),
            controller.$inbox.map { _ in () }.eraseToAnyPublisher(),
            controller.$actions.map { _ in () }.eraseToAnyPublisher(),
            controller.$expandedCards.map { _ in () }.eraseToAnyPublisher(),
            controller.$stackStatuses.map { _ in () }.eraseToAnyPublisher(),
            controller.$ddevStatuses.map { _ in () }.eraseToAnyPublisher(),
            controller.$localStatuses.map { _ in () }.eraseToAnyPublisher(),
            // A tray opening or filling changes the card's height, so the panel has to follow.
            controller.$logTails.map { _ in () }.eraseToAnyPublisher(),
            controller.$collapsedCards.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateStatusItem()
            self?.syncPanelSizes()
        }
        .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        syncPanels()
        updateStatusItem()
        controller.start()
        installHotKey()

        // No token on any account means nothing can load; open the one window that fixes that.
        let hasAnyToken = accountsStore.accounts().contains { account in
            ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil
        }
        if !hasAnyToken {
            settingsController.show()
        }

        if CommandLine.arguments.contains("--enable-login-item"), !LoginItem.isEnabled {
            LoginItem.set(true)
        }
    }

    // MARK: Panels

    /// The built-in cards plus one per configured project, in the order the deck is laid out -
    /// Arc, then DDEV, then the plain ones, each group alphabetical. See
    /// `CardCatalog.projectOrder`.
    private var catalog: [CardDescriptor] {
        let arc = projectsStore.projects().map { project in
            CardDescriptor(
                id: project.cardID,
                title: project.title,
                subtitle: "Arc · \(project.organization)",
                isImplemented: true,
                isEnabledByDefault: true
            )
        }
        let ddev = ddevProjectsStore.projects().map { project in
            CardDescriptor(
                id: project.cardID,
                title: project.displayTitle,
                subtitle: "DDEV · \(project.name)",
                isImplemented: true,
                isEnabledByDefault: true
            )
        }
        let plain = localProjectsStore.projects().map { project in
            CardDescriptor(
                id: project.cardID,
                title: project.displayTitle,
                subtitle: project.startCommand.isEmpty ? "Project" : "Project · \(project.startCommand)",
                isImplemented: true,
                isEnabledByDefault: true
            )
        }
        return CardCatalog.all(
            including: CardCatalog.projectOrder(arc: arc, ddev: ddev, plain: plain)
        )
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

        // Before the panels, not after. This is where the controller reads which cards are
        // collapsed, and a panel built while that is still unknown opens at the wrong size and
        // then corrects itself, which moves everything under it twice.
        controller.setActiveCards(Set(wanted))

        for card in wanted where panels[card] == nil {
            showPanel(card)
        }
    }

    /// Grows and shrinks panels as their contents change, keeping the top edge where it is and
    /// pushing the rest of the column out of the way.
    private func syncPanelSizes() {
        // Once per pass, because it is a hand-over and not a query.
        let userChanged = controller.takeUserResizes()

        for (card, window) in panels {
            // A card that has never had data computes the height of an empty card. Letting that
            // through resized the panel to a shape nothing was ever in, and then back, and the
            // column walked up the screen and down again with a different set of neighbours each
            // way. It opens at the height it last settled at and waits.
            guard controller.hasLoaded(card) || preferences.height(for: card) == nil else { continue }

            let size = CardHostView.size(for: card, controller: controller)
            let old = window.frame
            guard abs(old.height - size.height) > 0.5 || abs(old.width - size.width) > 0.5 else { continue }

            let frame = NSRect(
                x: old.origin.x,
                y: old.maxY - size.height,
                width: size.width,
                height: size.height
            )
            reposition {
                window.setFrame(frame, display: true, animate: false)
            }
            // Collapsing changes the shape as well as the height.
            window.apply(cornerRadius: cornerRadius(for: card))
            window.invalidateShadow()
            preferences.setHeight(size.height, for: card)
            // The position is deliberately not saved here. A resize keeps the top edge, so there
            // is nothing new to record, and the one thing that call did record was the case it
            // should not have: a card that a neighbour's resize had displaced a moment earlier,
            // written down at the displaced position and then loaded from there at the next
            // launch.

            if preferences.packsColumns {
                packColumn(containing: card)
            } else if userChanged.contains(card) {
                // Only for a change somebody asked for. Selection uses the old frame: those are
                // the panels that were below before the resize, and they are the ones that have
                // to make room.
                shiftColumn(below: old, by: old.height - size.height)
            }
        }
    }

    /// Closes up the column this card is in, keeping the order that is on screen.
    ///
    /// Runs by itself, so it is deliberately the timid version of tidying: same column, same
    /// order, anchored on whichever card is already at the top. Cards are never moved to another
    /// column and never re-sorted, because a card that jumps sideways or swaps places on its own
    /// is worse than the gap it was closing. The menu's Tidy is still the one that does both.
    private func packColumn(containing card: CardID) {
        guard let anchor = panels[card] else { return }
        let members = panels
            .filter { DeckLayout.isSameColumn($0.value.frame, anchor.frame) }
            .sorted { $0.value.frame.maxY > $1.value.frame.maxY }
        guard members.count > 1, let top = members.first?.value.frame else { return }

        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(top) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let screen else { return }

        let placements = DeckLayout.pack(
            sizes: members.map(\.value.frame.size),
            anchorTopLeft: CGPoint(x: top.minX, y: top.maxY),
            screen: screen,
            gap: DeckTheme.panelGap
        )

        reposition {
            for (index, member) in members.enumerated() {
                let point = placements[index]
                member.value.setFrameOrigin(NSPoint(x: point.x, y: point.y - member.value.frame.height))
            }
        }
        // Saved, because this is where the cards now live. Not as a user move: a panel parked on
        // a display that is unplugged keeps the placement it belongs to.
        for member in members { persistPosition(of: member.key) }
    }

    private func showPanel(_ card: CardID) {
        var size = CardHostView.size(for: card, controller: controller)
        // Open at the height this card last settled at. Computing it now would use empty data
        // and produce a short panel that grows a moment later, pushing the rest of the column
        // down - which is how the deck crept apart across launches.
        if let remembered = preferences.height(for: card) {
            size.height = remembered
        }
        let hosting = PanelHostingView(rootView: CardHostView(controller: controller, card: card))
        let window = PanelWindow(
            card: card,
            size: size,
            origin: origin(for: card, size: size),
            cornerRadius: cornerRadius(for: card),
            content: hosting
        )
        window.level = displayMode.windowLevel
        window.isMovableByWindowBackground = !preferences.isLocked
        window.delegate = self
        // Empty, with a delegate: `menuNeedsUpdate` fills it in every time it opens. A menu
        // built once here would keep whatever checkmarks were right at launch - the lock and
        // the card toggles would look stuck no matter what was actually set.
        let contextMenu = NSMenu()
        contextMenu.delegate = self
        // Which panel a menu belongs to, so a right-click can offer something about *this* card
        // rather than only about the deck.
        menuOwners[ObjectIdentifier(contextMenu)] = card
        window.contentView?.menu = contextMenu
        reposition { window.orderFrontRegardless() }
        panels[card] = window
    }

    /// Records which display a panel is on and where on it, which is what positions are
    /// restored from.
    ///
    /// A panel sitting on a display that is not currently connected keeps the placement it
    /// already had: it is only parked somewhere visible, and parking is not a decision the user
    /// made. Overwriting it is how a deck moves house permanently every time a monitor is
    /// unplugged for an hour.
    ///
    /// `userMoved` is the exception, and it is the whole difference between the deck arranging
    /// itself and someone arranging it. Dragging a parked card, or tidying the deck while the
    /// monitor it belongs to is unplugged, is a decision, and it has to outrank the placement it
    /// replaces - otherwise the arrangement is silently dropped and the next screen change
    /// hauls every card back to where it was parked. Which is exactly what it did.
    private func persistPosition(of card: CardID, userMoved: Bool = false) {
        guard let window = panels[card] else { return }
        guard PanelPlacement.shouldRecord(
            existing: preferences.placement(for: card),
            userMoved: userMoved,
            displays: Displays.current()
        ) else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        guard let placement = PanelPlacement.from(
            topLeft: topLeft,
            size: window.frame.size,
            displays: Displays.current()
        ) else { return }
        preferences.setPlacement(placement, for: card)
    }

    /// Saved position when there is a usable one, otherwise the next slot in a column down
    /// the right edge.
    private func origin(for card: CardID, size: NSSize) -> NSPoint {
        if let placement = preferences.placement(for: card) {
            // Its own display, when that display is here.
            if let top = placement.topLeft(on: Displays.current()) {
                return NSPoint(x: top.x, y: top.y - size.height)
            }
            // Otherwise borrow whichever display is main, keeping the placement itself intact
            // so the card goes home when its own display comes back.
            if let fallback = Displays.fallback() {
                let top = placement.topLeft(borrowing: fallback, size: size)
                return NSPoint(x: top.x, y: top.y - size.height)
            }
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

    /// Moves every panel sitting under `frame` in the same column by `dy` - positive is up,
    /// since AppKit's y grows upward.
    ///
    /// This is what stops a hidden card leaving a card-shaped hole, and what makes room when a
    /// card is expanded. Only panels that overlap horizontally are touched, so a deliberately
    /// scattered layout is left alone.
    /// Every move it makes is part of the layout: it runs when a card is hidden, or when the
    /// user changed a card's height themselves. The deck settling into its data does not come
    /// through here any more, which is what it used to do and then save.
    private func shiftColumn(below frame: NSRect, by dy: CGFloat) {
        guard dy != 0 else { return }
        var moved: [CardID] = []
        reposition {
            for (card, window) in panels {
                let current = window.frame
                guard current.maxY <= frame.minY + 1 else { continue }
                guard current.maxX > frame.minX, current.minX < frame.maxX else { continue }
                window.setFrameOrigin(NSPoint(x: current.origin.x, y: current.origin.y + dy))
                moved.append(card)
            }
        }
        for card in moved { persistPosition(of: card) }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isRepositioning, let window = notification.object as? PanelWindow else { return }
        persistPosition(of: window.card, userMoved: true)
    }

    /// Runs a move the deck decided on rather than the user, so `windowDidMove` stays quiet.
    private func reposition(_ body: () -> Void) {
        isRepositioning = true
        body()
        isRepositioning = false
    }

    /// Puts every panel back where it belongs after a display comes or goes.
    ///
    /// macOS lays all the screens out in one coordinate space and re-lays it on every change,
    /// so unplugging the external display that happens to be the main one shifts the laptop's
    /// screen underneath the cards - and the deck scatters, sometimes off-screen entirely.
    /// Because a placement names its display rather than a global point, putting things back is
    /// just reading it again: home if that display is here, parked on the main one if it is
    /// not, and home again the moment it returns.
    @objc private func screensChanged() {
        // The arrangement is still settling when the notification arrives - a display that has
        // just woken reports its old frame for a moment - so this runs after a beat.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(replaceAll), object: nil)
        perform(#selector(replaceAll), with: nil, afterDelay: 0.6)
    }

    @objc private func replaceAll() {
        reposition {
            for (card, window) in panels {
                let size = window.frame.size
                let point = origin(for: card, size: size)
                guard abs(point.x - window.frame.minX) > 0.5 || abs(point.y - window.frame.minY) > 0.5
                else { continue }
                window.setFrameOrigin(point)
                window.invalidateShadow()
            }
        }
    }

    // MARK: Summoning

    /// ⌥Space, held.
    ///
    /// The deck's problem was never how the cards look, it is that they are underneath
    /// everything: at level -1 you see a sliver of them between windows. Summoning is therefore
    /// not a mode and not a second rendering - it is the same panels, the same frames and the
    /// same pixels at a different window level, which is the switch the menu's "Float above
    /// windows" already throws. Holding makes it spring-loaded, and a tap latches it for the
    /// times when both hands are needed.
    private func installHotKey() {
        hotKey = nil
        guard preferences.summonEnabled else { return }
        let combo = preferences.summonHotKey
        hotKey = GlobalHotKey(
            combo: combo,
            onPress: { [weak self] in self?.hotKeyPressed() },
            onRelease: { [weak self] in self?.hotKeyReleased() }
        )
        // Registration fails when something else already owns the combination, and a summon
        // that silently does nothing is indistinguishable from a broken app. The settings screen
        // says so where somebody will read it; this is for the log.
        if hotKey == nil {
            Log.app.error("\(combo.display, privacy: .public) is already taken by another application")
        } else {
            Log.app.info("Summon armed on \(combo.display, privacy: .public)")
        }
    }

    /// Anything shorter than this was a tap, not a hold.
    private static let latchThreshold: TimeInterval = 0.25

    private func hotKeyPressed() {
        // A press while latched puts the deck back down. Otherwise it raises it, and the
        // release decides whether that was a hold or a tap.
        if isLatched {
            isLatched = false
            summonedAt = nil
            setSummoned(false)
            return
        }
        summonedAt = Date()
        setSummoned(true)
    }

    private func hotKeyReleased() {
        guard let pressedAt = summonedAt else { return }
        summonedAt = nil
        if Date().timeIntervalSince(pressedAt) < Self.latchThreshold {
            isLatched = true
            return
        }
        setSummoned(false)
    }

    private func setSummoned(_ summoned: Bool) {
        guard summoned != isSummoned else { return }
        isSummoned = summoned

        if summoned, preferences.summonDims {
            showVeils()
        } else {
            hideVeils()
        }
        // Raised panels go above ordinary windows; at rest they go back to whatever the display
        // mode says, which may already be floating.
        let level = summoned ? NSWindow.Level.floating : displayMode.windowLevel
        for window in panels.values {
            window.level = level
            if summoned { window.orderFrontRegardless() }
        }
    }

    private func showVeils() {
        // Rebuilt each time rather than kept: a display can come and go between two summons,
        // and a veil on a screen that is no longer there is a window nobody can find.
        hideVeils()
        veils = NSScreen.screens.map(VeilWindow.init(screen:))
        for veil in veils { veil.show() }
    }

    private func hideVeils() {
        for veil in veils { veil.hide() }
        veils = []
    }

    /// Puts every deck preference into effect at once.
    ///
    /// One function rather than a handler per switch, because the settings screen writes the
    /// preference and then says only "something changed": which one it was is not worth a
    /// protocol, and applying all of them is cheap and cannot get out of step.
    private func applyDeckPreferences() {
        let level = isSummoned ? NSWindow.Level.floating : displayMode.windowLevel
        for window in panels.values {
            window.level = level
            window.isMovableByWindowBackground = !preferences.isLocked
        }

        installHotKey()
        if !preferences.summonEnabled, isSummoned {
            isLatched = false
            setSummoned(false)
        }
        if isSummoned {
            preferences.summonDims ? showVeils() : hideVeils()
        }
        // Turning packing on is a decision, so it takes effect now rather than the next time a
        // card happens to change height.
        if preferences.packsColumns {
            for card in panels.keys { packColumn(containing: card) }
        }
    }

    // MARK: Menu bar

    /// A stack of cards with the app's initials cut out of the front one - the shape says
    /// "deck", the letters say whose. Numbers go in the tooltip: a bare "8" in the menu bar
    /// belongs to nothing in particular.
    private func updateStatusItem() {
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let card = menuOwners[ObjectIdentifier(menu)] {
            let isCollapsed = controller.isCollapsed(card)
            let item = NSMenuItem(
                title: isCollapsed ? "Show the whole card" : "Collapse to one row",
                action: #selector(toggleCollapsed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = card.rawValue
            menu.addItem(item)
            menu.addItem(.separator())
        }
        populate(menu)
    }

    @objc private func toggleCollapsed(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String else { return }
        controller.toggleCollapsed(CardID(rawValue: raw))
    }

    /// A collapsed panel is a different shape, not just a shorter one.
    private func cornerRadius(for card: CardID) -> CGFloat {
        controller.isCollapsed(card) ? CollapsedCardMetrics.cornerRadius : DeckTheme.cornerRadius
    }

    /// Every menu in the app is repopulated here as it opens, so a checkmark can never show
    /// state from whenever the menu happened to be created.
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

        let resolved = preferences.cardLayout.resolved(catalog: catalog)
        let arcIDs = Set(projectsStore.projects().map(\.cardID))
        let ddevIDs = Set(ddevProjectsStore.projects().map(\.cardID))
        let plainIDs = Set(localProjectsStore.projects().map(\.cardID))
        let projectIDs = arcIDs.union(ddevIDs).union(plainIDs)

        for card in resolved where !projectIDs.contains(card.id) {
            menu.addItem(cardItem(card))
        }

        // Projects get their own groups: with several of them the built-in cards would
        // otherwise be lost in the middle of a list of site names.
        addGroup("Arc projects", cards: resolved.filter { arcIDs.contains($0.id) }, to: menu)
        addGroup("DDEV projects", cards: resolved.filter { ddevIDs.contains($0.id) }, to: menu)
        addGroup("Projects", cards: resolved.filter { plainIDs.contains($0.id) }, to: menu)

        if !ddevIDs.isEmpty {
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
        for (title, selector) in [
            ("Tidy panels into columns", #selector(restack)),
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

    private func addGroup(_ title: String, cards: [ResolvedCard], to menu: NSMenu) {
        guard !cards.isEmpty else { return }
        menu.addItem(.separator())
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for card in cards {
            menu.addItem(cardItem(card))
        }
    }

    @objc private func powerOffDDEV() {
        controller.powerOffDDEV()
    }

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



    /// Closes up the deck while keeping it where the user put it: anchor on the topmost panel
    /// and stack the rest beneath it, starting a new column whenever the next card would hang
    /// below the screen. It deliberately does not reset to a corner.
    ///
    /// The wrapping is not a nicety. Six cards are over a thousand points tall, and a single
    /// column pushed the last of them under the bottom edge - where nothing can grab it, and
    /// the position was saved.
    @objc private func restack() {
        let ordered = visibleCards.compactMap { card in panels[card].map { (card, $0) } }
        guard let anchor = ordered.max(by: { $0.1.frame.maxY < $1.1.frame.maxY })?.1 else { return }

        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(anchor.frame) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let placements = DeckLayout.tidy(
            sizes: ordered.map(\.1.frame.size),
            anchorTopLeft: CGPoint(x: anchor.frame.minX, y: anchor.frame.maxY),
            screen: screen,
            gap: DeckTheme.panelGap
        )

        reposition {
            for (index, (_, window)) in ordered.enumerated() {
                let topLeft = placements[index]
                window.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - window.frame.height))
            }
        }
        // Tidying is an arrangement somebody asked for, so it is saved against the display the
        // cards are actually on - even when that is a display they were only parked on.
        for (card, _) in ordered { persistPosition(of: card, userMoved: true) }
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

}
