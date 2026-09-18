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
        preferences: preferences,
        openSettings: { [unowned self] in self.settingsController.show() },
        openCardSettings: { [unowned self] card in
            let target = CardHostView.module(for: card)?.settingsTarget(for: card) ?? (.cards, nil)
            self.settingsController.show(target.section, id: target.id)
        },
        openAccountSettings: { [unowned self] service, id in
            self.settingsController.show(service == .github ? .github : .gitlab, id: id)
        },
        showCard: { [unowned self] card in self.showCard(card) },
        quit: { [unowned self] in
            self.controller.stop()
            NSApp.terminate(nil)
        }
    )
    private lazy var summoner: Summoner = Summoner(preferences: preferences) { [unowned self] raised in
        self.panels.setRaised(raised)
    }
    private lazy var generalPage = GeneralSettingsPage(preferences: preferences, updater: updater)
    private lazy var notificationsPage = NotificationsSettingsPage(
        preferences: preferences,
        githubStore: accountsStore,
        gitlabStore: gitlabAccountsStore,
        arcStore: projectsStore,
        ddevStore: ddevProjectsStore,
        localStore: localProjectsStore
    )
    private lazy var settingsController: SettingsWindowController = SettingsWindowController(
        pages: [
            generalPage,
            DeckSettingsPage(preferences: preferences),
            CardsSettingsPage(preferences: preferences),
            notificationsPage,
        ],
        sections: [
            GitHubAccountsSection(store: accountsStore, tokenStore: tokenStore),
            GitLabInstancesSection(store: gitlabAccountsStore, tokenStore: tokenStore, preferences: preferences),
            arcModule,
            ddevModule,
            localModule,
        ]
    ) { [weak self] in self?.settingsChanged() }

    /// The log windows, one per project, opened from a card's header button.
    private lazy var logWindows: LogWindows = LogWindows(controller: controller) { [unowned self] card in
        self.cards.resolved.first { $0.id == card }?.descriptor.title ?? card.rawValue
    }

    private let notifier = Notifier()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything is worded: menus, cards and banners all read their words as they are
        // drawn, and this is what decides which table they read them from.
        Strings.use(preferences.language)
        // Before any window exists, because a settings field with no Edit menu behind it cannot
        // be pasted into.
        EditMenu.install()
        CardHostView.modules = modules
        menu.install()
        // A card's log button opens a window; the controller keeps its lines fresh and knows
        // which cards have one open, which is what the button shows.
        controller.presentLogs = { [unowned self] card in self.logWindows.open(card) }
        controller.dismissLogs = { [unowned self] card in self.logWindows.close(card) }

        // Panels are sized from the data, so anything that changes it can change their height -
        // a branch line appearing on a project card counts just as much as a pull request does.
        Publishers.MergeMany(
            controller.$pullRequests.map { _ in () }.eraseToAnyPublisher(),
            controller.$inbox.map { _ in () }.eraseToAnyPublisher(),
            controller.$actions.map { _ in () }.eraseToAnyPublisher(),
            controller.$expandedCards.map { _ in () }.eraseToAnyPublisher(),
            // The header button of a card whose log is on screen is lit, so the card is drawn
            // again when a window opens or closes.
            controller.$logWindowCards.map { _ in () }.eraseToAnyPublisher(),
            controller.$stackStatuses.map { _ in () }.eraseToAnyPublisher(),
            controller.$ddevStatuses.map { _ in () }.eraseToAnyPublisher(),
            controller.$localStatuses.map { _ in () }.eraseToAnyPublisher(),
            controller.$collapsedCards.map { _ in () }.eraseToAnyPublisher(),
            // The rest of what the menu-bar badge is made of: GitLab, Docker, the projects'
            // history and the checkouts.
            controller.$mergeRequests.map { _ in () }.eraseToAnyPublisher(),
            controller.$docker.map { _ in () }.eraseToAnyPublisher(),
            controller.$watch.map { _ in () }.eraseToAnyPublisher(),
            controller.$checkouts.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.menu.updateStatusItem()
            self?.panels.syncPanelSizes()
            // The dots in the settings list are the projects' live state. Only the list is
            // redrawn, never the form, so nothing being typed is disturbed.
            if self?.settingsController.isVisible == true { self?.settingsController.reloadList() }
        }
        .store(in: &cancellables)

        // A banner opens what it is about: a page in the browser profile of the account that owns
        // it, a project's card, an account's settings, or the menu that lists a summary's items.
        notifier.onTarget = { [weak self] target in self?.open(target) }
        controller.onAlerts = { [weak self] alerts in self?.notifier.post(alerts) }
        controller.updateStatusItem = { [weak self] in self?.menu.updateStatusItem() }
        notifier.refreshAuthorization()

        // A newer build: one banner, and the settings page redrawn as the state moves.
        updater.onAvailable = { [weak self] update in
            guard let self, self.preferences.notificationsEnabled, self.preferences.notifiesUpdates else { return }
            self.notifier.postUpdate(update.version.description)
        }
        updater.workingCard = { [weak self] in self?.controller.workingCardTitle }
        updater.onChange = { [weak self] in
            self?.generalPage.refreshUpdateRow()
            self?.menu.updateStatusItem()
        }
        notifier.onUpdate = { [weak self] in self?.updater.install() }

        alignKeychainAccess()

        panels.syncPanels()
        menu.updateStatusItem()
        controller.start()
        summoner.install()
        updater.start()

        notificationsPage.onRequestAuthorization = { [weak self] completion in
            self?.notifier.requestAuthorization(completion) ?? completion(false)
        }
        notificationsPage.onTest = { [weak self] in self?.notifier.postTest() }

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
            // `--settings project agrica-qdd` opens that project's form; `--settings deck` a page.
            let arguments = CommandLine.arguments
            let named = arguments.count > index + 1 ? SettingsWindowController.Section(rawValue: arguments[index + 1]) : nil
            let id = arguments.count > index + 2 && !arguments[index + 2].hasPrefix("-") ? arguments[index + 2] : nil
            settingsController.show(named ?? .general, id: id)
        }

        // `open -a DevDeck --args --menu` opens the menu-bar menu once the first answers are in,
        // for looking at it, and for a screenshot of it, without a hand on the mouse. `--menu
        // sample` fills it with made-up rows of every tier.
        if let index = CommandLine.arguments.firstIndex(of: "--menu") {
            let arguments = CommandLine.arguments
            menu.showsSamples = arguments.count > index + 1 && arguments[index + 1] == "sample"
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.menu.open() }
        }

        // `open -a DevDeck --args --logs` opens a log window without a hand on the mouse, for
        // looking at it and for a screenshot. A card id after it picks the project; without one
        // it takes the first card that has a log to read.
        if let index = CommandLine.arguments.firstIndex(of: "--logs") {
            let arguments = CommandLine.arguments
            let named = arguments.count > index + 1 && !arguments[index + 1].hasPrefix("-")
                ? CardID(rawValue: arguments[index + 1])
                : nil
            let card = named ?? cards.visible.first { controller.hasLogSource($0) }
            if let card { logWindows.open(card) }
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

    /// Where a clicked banner goes.
    private func open(_ target: DeckAlert.Target) {
        switch target {
        case .url(let url, let accountID):
            let isGitLab = controller.gitlabAccountLabels[accountID] != nil
            LinkOpener.open(url, using: isGitLab ? controller.gitlabBrowser(for: accountID) : controller.browser(for: accountID))
        case .card(let card):
            showCard(card)
        case .accountSettings(let service, let accountID):
            settingsController.show(service == "gitlab" ? .gitlab : .github, id: accountID.isEmpty ? nil : accountID)
        case .menu:
            menu.open()
        }
    }

    /// Brings the deck up with this card's log open in its window: what a row about a project
    /// promises. A folded card has a log like any other; the window is not on the card.
    private func showCard(_ card: CardID) {
        if !cards.isEnabled(card) {
            cards.setEnabled(true, for: card)
            panels.syncPanels()
        }
        if controller.hasLogSource(card), !controller.isShowingLogs(card) {
            controller.toggleLogs(for: card)
        }
        summoner.present()
    }

    /// Anything in settings changed: a project added or removed changes the card list, not just
    /// the data, and any deck preference may have changed, which only counts once it is applied.
    private func settingsChanged() {
        panels.syncPanels()
        // A project taken out of settings takes its log window with it: a window titled with a
        // project that no longer exists has nothing to read.
        logWindows.closeAll(except: Set(cards.resolved.map(\.id)))
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
        let stored = preferences.keychainAccessMode
        guard KeychainAccessPolicy.shouldRewrite(storedMode: stored, wantedMode: wanted) else {
            if stored != wanted {
                Log.app.info("Keychain stays \(stored ?? "unset", privacy: .public): this copy would open it, and that is not done by itself")
            }
            return
        }

        let keys = accountsStore.accounts().map(\.tokenKey)
            + gitlabAccountsStore.accounts().map(\.tokenKey)
        let result = KeychainAccessPolicy.rewrite(keys: keys, in: tokenStore)
        guard result.isComplete else {
            // Left unrecorded, so the next launch tries again rather than trusting a half done job.
            Log.app.error("Keychain rewrite for \(wanted, privacy: .public) incomplete: \(result.failed, privacy: .public) item(s) failed")
            return
        }
        preferences.keychainAccessMode = wanted
        Log.app.info("Rewrote \(result.rewritten, privacy: .public) Keychain item(s) for access mode \(wanted, privacy: .public)")
    }
}
