import AppKit
import ArcKit
import DDEVKit
import Combine
import DevDeckCore
import DevDeckUI
import GitHubKit
import GitLabKit
import ProjectKit
import SwiftUI

/// The composition root: builds the stores and the five objects that are the app, and wires
/// the events between them. It does nothing itself that one of them could do.
///
/// - `DeckController` owns the data and the loops.
/// - `PanelCoordinator` owns the windows: which, how big, where.
/// - `DeckMenu` owns the menu-bar item and every menu.
/// - `ArrangementsController` owns saved decks.
/// - `Summoner` owns the key that raises the deck.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let tokenStore: any TokenStore = CompositeTokenStore.standard()
    private let accountsStore = GitHubAccountsStore(backend: UserDefaults.standard)
    private let gitlabAccountsStore = GitLabAccountsStore(backend: UserDefaults.standard)
    private let projectsStore = ArcProjectsStore(backend: UserDefaults.standard)
    private let ddevProjectsStore = DDEVProjectsStore(backend: UserDefaults.standard)
    private let localProjectsStore = LocalProjectsStore(backend: UserDefaults.standard)

    private lazy var controller: DeckController = DeckController(
        preferences: preferences,
        tokenStore: tokenStore,
        accountsStore: accountsStore,
        gitlabAccountsStore: gitlabAccountsStore,
        projectsStore: projectsStore,
        ddevProjectsStore: ddevProjectsStore,
        localProjectsStore: localProjectsStore
    )
    private lazy var cards: DeckCards = DeckCards(
        preferences: preferences,
        projectsStore: projectsStore,
        ddevProjectsStore: ddevProjectsStore,
        localProjectsStore: localProjectsStore
    )
    private lazy var panels: PanelCoordinator = PanelCoordinator(
        preferences: preferences,
        controller: controller,
        cards: cards
    ) { [unowned self] card in self.menu.contextMenu(for: card) }
    private lazy var arrangements: ArrangementsController = ArrangementsController(
        preferences: preferences,
        controller: controller,
        cards: cards,
        panels: panels
    )
    private lazy var menu: DeckMenu = DeckMenu(
        controller: controller,
        cards: cards,
        panels: panels,
        arrangements: arrangements,
        openSettings: { [unowned self] in self.settingsController.show() },
        quit: { [unowned self] in
            self.controller.stop()
            NSApp.terminate(nil)
        }
    )
    private lazy var summoner: Summoner = Summoner(preferences: preferences) { [unowned self] raised in
        self.panels.setRaised(raised)
    }
    private lazy var settingsController: SettingsWindowController = SettingsWindowController(
        tokenStore: tokenStore,
        accountsStore: accountsStore,
        gitlabAccountsStore: gitlabAccountsStore,
        projectsStore: projectsStore,
        ddevProjectsStore: ddevProjectsStore,
        localProjectsStore: localProjectsStore,
        preferences: preferences
    ) { [weak self] in
        // A project added or removed in settings changes the card list, not just the data.
        self?.panels.syncPanels()
        self?.controller.refreshNow()
        // And any deck preference may have changed, which only counts once it is applied.
        self?.applyDeckPreferences()
    }

    private let notifier = Notifier()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before any window exists, because a settings field with no Edit menu behind it cannot
        // be pasted into.
        EditMenu.install()
        menu.install()

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
            self?.menu.updateStatusItem()
            self?.panels.syncPanelSizes()
        }
        .store(in: &cancellables)

        // A banner opens what it is about, in the browser profile of the account that owns it.
        notifier.onOpen = { [weak self] url, accountID in
            guard let self else { return }
            let isGitLab = self.controller.gitlabAccountLabels[accountID] != nil
            LinkOpener.open(
                url,
                using: isGitLab ? self.controller.gitlabBrowser(for: accountID) : self.controller.browser(for: accountID)
            )
        }
        controller.onAlerts = { [weak self] alerts in self?.notifier.post(alerts) }
        controller.updateStatusItem = { [weak self] in self?.menu.updateStatusItem() }
        notifier.refreshAuthorization()

        repairKeychainOnce()

        panels.syncPanels()
        menu.updateStatusItem()
        controller.start()
        summoner.install()

        settingsController.onRequestNotifications = { [weak self] completion in
            self?.notifier.requestAuthorization(completion) ?? completion(false)
        }
        settingsController.onTestNotification = { [weak self] in self?.notifier.postTest() }

        // No token on any account means nothing can load; open the one window that fixes that.
        let hasAnyToken = accountsStore.accounts().contains { account in
            ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil
        }
        if !hasAnyToken {
            settingsController.show()
        }

        // `open -a DevDeck --args --settings`, for looking at the settings window without
        // hunting through a menu bar that has no window of its own. An optional section after
        // it opens that page.
        if let index = CommandLine.arguments.firstIndex(of: "--settings") {
            let named = CommandLine.arguments.count > index + 1
                ? SettingsWindowController.Section(rawValue: CommandLine.arguments[index + 1])
                : nil
            settingsController.show(named ?? .github)
        }

        if CommandLine.arguments.contains("--enable-login-item"), !LoginItem.isEnabled {
            LoginItem.set(true)
        }
    }

    /// Puts every deck preference into effect at once.
    ///
    /// One function rather than a handler per switch, because the settings screen writes the
    /// preference and then says only "something changed": which one it was is not worth a
    /// protocol, and applying all of them is cheap and cannot get out of step.
    private func applyDeckPreferences() {
        panels.applyPreferences()
        summoner.applyPreferences()
        if preferences.packsColumns {
            panels.packAllColumns()
        }
    }

    /// Rewrites every stored token once, with an access list that a rebuild does not invalidate.
    ///
    /// A token written by an earlier build is bound to that build's code identity, and this app
    /// is ad-hoc signed, so every update makes macOS ask for the Keychain password once per
    /// token. Reading them here costs one last round of those prompts and ends them: after this
    /// pass the items are readable by this user's processes without one.
    private func repairKeychainOnce() {
        guard !preferences.hasRepairedKeychain else { return }

        let keys = accountsStore.accounts().map(\.tokenKey)
            + gitlabAccountsStore.accounts().map(\.tokenKey)
        var repaired = 0
        for key in keys {
            guard let token = (try? tokenStore.token(for: key)) ?? nil else { continue }
            try? tokenStore.setToken(token, for: key)
            repaired += 1
        }
        preferences.hasRepairedKeychain = true
        Log.app.info("Rewrote \(repaired, privacy: .public) Keychain item(s) so a rebuild stops asking")
    }
}
