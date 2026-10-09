import ArcKit
import Combine
import DDEVKit
import DevDeckCore
import DevDeckEngine
import Foundation
import GitHubKit
import GitLabKit
import ProjectKit

/// The Mac's view of the deck: `DeckRuntime`, made observable for SwiftUI and Combine.
///
/// Everything the deck decides lives in the runtime, in the engine, where Windows uses the same
/// rules. This adapter only mirrors the runtime's fields into `@Published` ones, one assignment
/// for one assignment, so every view and subscription sees exactly what it saw when this class
/// was the controller, and it carries out the runtime's effects with AppKit. Nothing here may
/// decide anything: no state, no timing, no preferences. See docs/adr/0024-one-engine-two-shells.md.
@MainActor
final class DeckController: ObservableObject {
    let runtime: DeckRuntime

    @Published private(set) var pullRequests: CardState<PullRequestsSnapshot>
    @Published private(set) var inbox: CardState<InboxSnapshot>
    @Published private(set) var actions: CardState<ActionsSnapshot>
    @Published private(set) var mergeRequests: CardState<MergeRequestsSnapshot>
    @Published private(set) var checkouts: [CheckoutState]
    @Published private(set) var checkoutsCheckedAt: Date?
    @Published private(set) var expandedCards: Set<CardID>
    @Published private(set) var logTails: [CardID: LogLines]
    @Published private(set) var logWindowCards: Set<CardID>
    @Published private(set) var inboxProgress: InboxProgress?
    @Published private(set) var collapsedCards: Set<CardID>
    @Published private(set) var parkedCards: Set<CardID>
    @Published private(set) var stackStatuses: [String: LocalStackStatus]
    @Published private(set) var ddevStatuses: [String: DDEVStatus]
    @Published private(set) var localStatuses: [String: LocalProjectStatus]
    @Published private(set) var docker: DockerStatus
    @Published private(set) var watch: ProjectWatch
    @Published private(set) var localAddress: String?

    /// Opening and closing a window is the application layer's business; keeping its lines
    /// fresh is the runtime's.
    var presentLogs: ((CardID) -> Void)?
    var dismissLogs: ((CardID) -> Void)?
    /// Opens Settings with the cursor in one field, for a card that points at the setting it
    /// needs. Set by the application layer, like the log windows.
    var showSetting: ((SettingsWindowController.Section, String) -> Void)?
    /// Posts banners. Set by the app delegate, because posting one is AppKit's business.
    var onAlerts: (([DeckAlert]) -> Void)?
    /// The menu bar carries the unread count, so it has to hear about a row leaving.
    var updateStatusItem: (() -> Void)?

    init(
        preferences: Preferences,
        tokenStore: any TokenStore,
        accountsStore: GitHubAccountsStore,
        gitlabAccountsStore: GitLabAccountsStore,
        projectsStore: ArcProjectsStore,
        ddevProjectsStore: DDEVProjectsStore,
        localProjectsStore: LocalProjectsStore,
        commandRunner: any CommandRunning = ShellCommandRunner(),
        settings: GitHubSettings = .default
    ) {
        let runtime = DeckRuntime(
            preferences: preferences,
            tokenStore: tokenStore,
            accountsStore: accountsStore,
            gitlabAccountsStore: gitlabAccountsStore,
            projectsStore: projectsStore,
            ddevProjectsStore: ddevProjectsStore,
            localProjectsStore: localProjectsStore,
            commandRunner: commandRunner,
            canStartDocker: DockerApp.installedURL() != nil,
            localAddress: { LocalAddress.current() },
            settings: settings
        )
        self.runtime = runtime
        pullRequests = runtime.pullRequests
        inbox = runtime.inbox
        actions = runtime.actions
        mergeRequests = runtime.mergeRequests
        checkouts = runtime.checkouts
        checkoutsCheckedAt = runtime.checkoutsCheckedAt
        expandedCards = runtime.expandedCards
        logTails = runtime.logTails
        logWindowCards = runtime.logWindowCards
        inboxProgress = runtime.inboxProgress
        collapsedCards = runtime.collapsedCards
        parkedCards = runtime.parkedCards
        stackStatuses = runtime.stackStatuses
        ddevStatuses = runtime.ddevStatuses
        localStatuses = runtime.localStatuses
        docker = runtime.docker
        watch = runtime.watch
        localAddress = runtime.localAddress
        runtime.onChange = { [weak self] field in self?.mirror(field) }
        runtime.onEffect = { [weak self] effect in self?.carryOut(effect) }
    }

    /// One assignment in the runtime, one here: a field that was set to what it already held is
    /// still set, because that is what the subscriptions downstream were written against.
    private func mirror(_ field: DeckField) {
        switch field {
        case .pullRequests: pullRequests = runtime.pullRequests
        case .inbox: inbox = runtime.inbox
        case .actions: actions = runtime.actions
        case .mergeRequests: mergeRequests = runtime.mergeRequests
        case .checkouts: checkouts = runtime.checkouts
        case .checkoutsCheckedAt: checkoutsCheckedAt = runtime.checkoutsCheckedAt
        case .expandedCards: expandedCards = runtime.expandedCards
        case .logTails: logTails = runtime.logTails
        case .logWindowCards: logWindowCards = runtime.logWindowCards
        case .inboxProgress: inboxProgress = runtime.inboxProgress
        case .collapsedCards: collapsedCards = runtime.collapsedCards
        case .parkedCards: parkedCards = runtime.parkedCards
        case .stackStatuses: stackStatuses = runtime.stackStatuses
        case .ddevStatuses: ddevStatuses = runtime.ddevStatuses
        case .localStatuses: localStatuses = runtime.localStatuses
        case .docker: docker = runtime.docker
        case .watch: watch = runtime.watch
        case .localAddress: localAddress = runtime.localAddress
        }
    }

    private func carryOut(_ effect: DeckEffect) {
        switch effect {
        case .announce(let alerts): onAlerts?(alerts)
        case .openLogs(let card): presentLogs?(card)
        case .closeLogs(let card): dismissLogs?(card)
        case .launchDocker: DockerApp.launch()
        case .attentionChanged: updateStatusItem?()
        }
    }

    // MARK: The runtime, as the views ask for it

    var refreshPolicy: RefreshPolicy { runtime.refreshPolicy }
    var actionsFollowPullRequests: Bool { runtime.actionsFollowPullRequests }
    var canStartDocker: Bool { runtime.canStartDocker }
    var workingCardTitle: String? { runtime.workingCardTitle }
    var gitlabAccountLabels: [String: String] { runtime.gitlabAccountLabels }
    var accountLabels: [String: String] { runtime.accountLabels }
    var githubLabels: [String: String] { runtime.githubLabels }
    var gitlabLabels: [String: String] { runtime.gitlabLabels }
    var watchedProjects: [WatchedProject] { runtime.watchedProjects }
    var lastCheckedAt: Date? { runtime.lastCheckedAt }
    var firstGitHubBrowser: BrowserChoice { runtime.firstGitHubBrowser }

    func setActiveCards(_ cards: Set<CardID>) { runtime.setActiveCards(cards) }
    func start() { runtime.start() }
    func stop() { runtime.stop() }
    func refreshNow() { runtime.refreshNow() }

    func project(forCard card: CardID) -> ArcProject? { runtime.project(forCard: card) }
    func stackStatus(for project: ArcProject) -> LocalStackStatus { runtime.stackStatus(for: project) }
    func perform(_ action: LocalStackAction, for project: ArcProject) { runtime.perform(action, for: project) }

    func ddevProject(forCard card: CardID) -> DDEVProject? { runtime.ddevProject(forCard: card) }
    func ddevStatus(for project: DDEVProject) -> DDEVStatus { runtime.ddevStatus(for: project) }
    func perform(_ action: DDEVAction, for project: DDEVProject) { runtime.perform(action, for: project) }
    func powerOffDDEV() { runtime.powerOffDDEV() }

    func startDockerRuntime() { runtime.startDockerRuntime() }

    func localProject(forCard card: CardID) -> LocalProject? { runtime.localProject(forCard: card) }
    func localStatus(for project: LocalProject) -> LocalProjectStatus { runtime.localStatus(for: project) }
    func perform(_ action: LocalProjectAction, for project: LocalProject) { runtime.perform(action, for: project) }

    func markRead(_ item: InboxItem) { runtime.markRead(item) }
    func markRead(threadID: String) { runtime.markRead(threadID: threadID) }
    func markRestRead() { runtime.markRestRead() }
    func markAllRead() { runtime.markAllRead() }

    func folder(forCheckout state: CheckoutState) -> URL? { runtime.folder(forCheckout: state) }
    func phoneURL(for site: URL?, isRunning: Bool) -> URL? { runtime.phoneURL(for: site, isRunning: isRunning) }

    func isExpanded(_ card: CardID) -> Bool { runtime.isExpanded(card) }
    func logs(for card: CardID) -> LogLines? { runtime.logs(for: card) }
    func isShowingLogs(_ card: CardID) -> Bool { runtime.isShowingLogs(card) }
    func hasLogSource(_ card: CardID) -> Bool { runtime.hasLogSource(card) }
    func toggleLogs(for card: CardID) { runtime.toggleLogs(for: card) }
    func logWindowOpened(_ card: CardID) { runtime.logWindowOpened(card) }
    func logWindowClosed(_ card: CardID) { runtime.logWindowClosed(card) }
    func refreshLogsNow(for card: CardID) { runtime.refreshLogsNow(for: card) }

    func takeUserResizes() -> Set<CardID> { runtime.takeUserResizes() }
    func hasLoaded(_ card: CardID) -> Bool { runtime.hasLoaded(card) }
    func isCollapsed(_ card: CardID) -> Bool { runtime.isCollapsed(card) }
    func isCollapsedByChoice(_ card: CardID) -> Bool { runtime.isCollapsedByChoice(card) }
    func isParked(_ card: CardID) -> Bool { runtime.isParked(card) }
    func setParked(_ cards: Set<CardID>) { runtime.setParked(cards) }
    func toggleCollapsed(_ card: CardID) { runtime.toggleCollapsed(card) }
    func toggleExpanded(_ card: CardID) { runtime.toggleExpanded(card) }

    func gitlabBrowser(for accountID: String) -> BrowserChoice { runtime.gitlabBrowser(for: accountID) }
    func browser(for accountID: String) -> BrowserChoice { runtime.browser(for: accountID) }

    func attention(update: AttentionItem?) -> AttentionDigest { runtime.attention(update: update) }
    func dismiss(_ item: AttentionItem) { runtime.dismiss(item) }
}
