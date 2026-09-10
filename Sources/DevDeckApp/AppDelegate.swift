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
    // One module per kind of card, in deck order: the built-in cards, then Arc, DDEV and plain
    // projects. The project modules are their own settings sections as well.
    private lazy var arcModule = ArcProjectModule(context: ModuleContext(controller: controller), store: projectsStore)
    private lazy var ddevModule = DDEVProjectModule(context: ModuleContext(controller: controller), store: ddevProjectsStore)
    private lazy var localModule = LocalProjectModule(context: ModuleContext(controller: controller), store: localProjectsStore)
    private lazy var modules: [CardModule] = {
        let context = ModuleContext(controller: controller)
        return [
            PullRequestsModule(context: context),
            InboxModule(context: context),
            ActionsModule(context: context),
            MergeRequestsModule(context: context),
            WorkInFlightModule(context: context),
            arcModule,
            ddevModule,
            localModule,
        ]
    }()
    private lazy var cards: DeckCards = DeckCards(preferences: preferences, modules: modules)
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
    private lazy var updater: Updater = Updater(preferences: preferences)
    private lazy var menu: DeckMenu = DeckMenu(
        controller: controller,
        cards: cards,
        panels: panels,
        arrangements: arrangements,
        updater: updater,
        openSettings: { [unowned self] in self.settingsController.show() },
        quit: { [unowned self] in
            self.controller.stop()
            NSApp.terminate(nil)
        }
    )
    private lazy var summoner: Summoner = Summoner(preferences: preferences) { [unowned self] raised in
        self.panels.setRaised(raised)
    }
    private lazy var generalPage: GeneralSettingsPage = GeneralSettingsPage(
        preferences: preferences,
        updater: updater
    ) { [weak self] in self?.settingsChanged() }
    private lazy var settingsController: SettingsWindowController = SettingsWindowController(
        sections: [
            GitHubAccountsSection(store: accountsStore, tokenStore: tokenStore),
            GitLabInstancesSection(store: gitlabAccountsStore, tokenStore: tokenStore, preferences: preferences),
            arcModule,
            ddevModule,
            localModule,
        ],
        general: generalPage
    ) { [weak self] in self?.settingsChanged() }

    private let notifier = Notifier()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before any window exists, because a settings field with no Edit menu behind it cannot
        // be pasted into.
        EditMenu.install()
        CardHostView.modules = modules
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

        // A newer build: one banner, and the settings page redrawn as the state moves.
        updater.onAvailable = { [weak self] update in self?.notifier.postUpdate(update.version.description) }
        updater.onChange = { [weak self] in self?.settingsController.reloadDetail() }
        notifier.onUpdate = { [weak self] in self?.updater.install() }

        alignKeychainAccess()

        panels.syncPanels()
        menu.updateStatusItem()
        controller.start()
        summoner.install()
        updater.start()

        generalPage.onRequestNotifications = { [weak self] completion in
            self?.notifier.requestAuthorization(completion) ?? completion(false)
        }
        generalPage.onTestNotification = { [weak self] in self?.notifier.postTest() }

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

        // `open -a DevDeck --args --update`: the same as choosing Update in the menu, for a
        // terminal or a script.
        if CommandLine.arguments.contains("--update") {
            updater.checkAndInstall()
        }
    }

    /// Anything in settings changed: a project added or removed changes the card list, not just
    /// the data, and any deck preference may have changed, which only counts once it is applied.
    private func settingsChanged() {
        panels.syncPanels()
        controller.refreshNow()
        applyDeckPreferences()
    }

    /// Puts every deck preference into effect at once.
    ///
    /// One function rather than a handler per switch, because the settings screen writes the
    /// preference and then says only "something changed": which one it was is not worth a
    /// protocol, and applying all of them is cheap and cannot get out of step.
    private func applyDeckPreferences() {
        panels.applyPreferences()
        summoner.applyPreferences()
        updater.applyPreferences()
        if preferences.packsColumns {
            panels.packAllColumns()
        }
    }

    /// Rewrites every stored token when the way it should be protected has changed.
    ///
    /// The protection follows the signature, see `KeychainAccessPolicy`. An ad-hoc build writes
    /// items anybody can read, because binding them to a signature that changes every build
    /// costs one password prompt per token per update. A build signed with a real identity
    /// binds them to itself. The first launch after the signature changes rewrites the items
    /// once, one prompt each, and the mode is remembered so it is not done again.
    private func alignKeychainAccess() {
        let wanted = KeychainAccessPolicy.mode(for: CodeIdentity.current())
        guard preferences.keychainAccessMode != wanted else { return }

        let keys = accountsStore.accounts().map(\.tokenKey)
            + gitlabAccountsStore.accounts().map(\.tokenKey)
        var rewritten = 0
        for key in keys {
            guard let token = (try? tokenStore.token(for: key)) ?? nil else { continue }
            try? tokenStore.setToken(token, for: key)
            rewritten += 1
        }
        preferences.keychainAccessMode = wanted
        Log.app.info("Rewrote \(rewritten, privacy: .public) Keychain item(s) for access mode \(wanted, privacy: .public)")
    }
}
