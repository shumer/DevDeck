import AppKit
import DevDeckCore
import DevDeckUI
import GitHubKit
import SwiftUI

// The three GitHub cards and the accounts they draw from. Three modules rather than one
// because each is a card of its own on the deck, and one settings section because the
// accounts are what all three share.

/// Your pull requests, plus the ones waiting on your review.
@MainActor
final class PullRequestsModule: CardModule {
    private let context: ModuleContext
    private var controller: DeckController { context.controller }

    init(context: ModuleContext) {
        self.context = context
    }

    func owns(_ card: CardID) -> Bool { card == .githubPullRequests }

    func view(for card: CardID) -> AnyView {
        AnyView(PullRequestsCard(
            state: controller.pullRequests,
            accountLabels: controller.accountLabels,
            isExpanded: controller.isExpanded(card),
            isCollapsed: controller.isCollapsed(card),
            onOpen: context.openGitHub,
            onToggleExpand: { [controller] in controller.toggleExpanded(card) },
            onOpenDashboard: { [context] in context.openGitHubDashboard(for: card) }
        ))
    }

    func size(for card: CardID) -> NSSize {
        PullRequestsCard.size(
            for: controller.pullRequests,
            isExpanded: controller.isExpanded(card),
            isCollapsed: controller.isCollapsed(card)
        )
    }

    func dashboardURL(for card: CardID) -> URL? {
        URL(string: "https://github.com/pulls")
    }
}

/// Unread notifications.
@MainActor
final class InboxModule: CardModule {
    private let context: ModuleContext
    private var controller: DeckController { context.controller }

    init(context: ModuleContext) {
        self.context = context
    }

    func owns(_ card: CardID) -> Bool { card == .githubInbox }

    func view(for card: CardID) -> AnyView {
        AnyView(InboxCard(
            state: controller.inbox,
            accountLabels: controller.accountLabels,
            isExpanded: controller.isExpanded(card),
            isCollapsed: controller.isCollapsed(card),
            onOpen: context.openGitHub,
            onToggleExpand: { [controller] in controller.toggleExpanded(card) },
            onOpenDashboard: { [context] in context.openGitHubDashboard(for: card) },
            onMarkRead: { [controller] in controller.markRead($0) }
        ))
    }

    func size(for card: CardID) -> NSSize {
        InboxCard.size(
            for: controller.inbox,
            isExpanded: controller.isExpanded(card),
            isCollapsed: controller.isCollapsed(card)
        )
    }

    func dashboardURL(for card: CardID) -> URL? {
        URL(string: "https://github.com/notifications")
    }
}

/// Workflow success rate and running jobs.
@MainActor
final class ActionsModule: CardModule {
    private let context: ModuleContext
    private var controller: DeckController { context.controller }

    init(context: ModuleContext) {
        self.context = context
    }

    func owns(_ card: CardID) -> Bool { card == .githubActions }

    func view(for card: CardID) -> AnyView {
        AnyView(ActionsCard(
            state: controller.actions,
            isCollapsed: controller.isCollapsed(card),
            onOpen: context.openGitHub,
            onOpenDashboard: { [context] in context.openGitHubDashboard(for: card) }
        ))
    }

    func size(for card: CardID) -> NSSize {
        ActionsCard.size(isCollapsed: controller.isCollapsed(card))
    }

    /// Actions has no cross-repository page; the closest thing is the dashboard.
    func dashboardURL(for card: CardID) -> URL? {
        URL(string: "https://github.com")
    }
}

extension ModuleContext {
    /// The same place a double-click on the panel goes. The dashboard belongs to whichever
    /// account is first; there is no row to ask.
    func openGitHubDashboard(for card: CardID) {
        guard let url = CardHostView.dashboardURL(for: card) else { return }
        openGitHub(url, account: controller.accountLabels.keys.sorted().first ?? "")
    }
}

/// The GitHub accounts, one token each.
@MainActor
final class GitHubAccountsSection: SettingsSection {
    let kind = SettingsWindowController.Section.github
    let group = SettingsListGroup.accounts
    let addTitle = "GitHub Account"
    weak var host: SettingsHost?

    private let store: GitHubAccountsStore
    private let tokenStore: any TokenStore

    init(store: GitHubAccountsStore, tokenStore: any TokenStore) {
        self.store = store
        self.tokenStore = tokenStore
    }

    func listItems() -> [SettingsListItem] {
        store.accounts().map { account in
            let hasToken = SettingsSupport.hasToken(account.tokenKey, in: tokenStore)
            return SettingsListItem(
                id: account.id,
                title: account.label,
                detail: hasToken ? "GitHub" : "GitHub · no token",
                icon: SettingsIcons.mark(.github),
                dot: hasToken ? nil : .systemOrange,
                isDimmed: !account.isEnabled
            )
        }
    }

    func buildForm(for id: String, in container: FlippedContainer) -> Bool {
        guard let account = store.accounts().first(where: { $0.id == id }) else { return false }
        let fold = "github:\(id):advanced"
        let form = GitHubAccountForm(
            account: account,
            hasToken: SettingsSupport.hasToken(account.tokenKey, in: tokenStore),
            isAdvancedOpen: host?.isOpen(fold) ?? false,
            width: container.bounds.width
        )
        form.onChange = { [weak self] in self?.applyEdits($0) }
        form.onSave = { [weak self] in self?.save($0) }
        form.onTestLink = { LinkOpener.open(URL(string: "https://github.com/pulls")!, using: $0.editedAccount.browser) }
        form.onToggleAdvanced = { [weak self] in self?.host?.toggle(fold) }
        container.addSubview(form)
        return true
    }

    func add() -> String? {
        var accounts = store.accounts()
        let id = GitHubAccount.makeID(from: "account", existing: accounts.map(\.id))
        accounts.append(GitHubAccount(id: id, label: "New Account"))
        store.save(accounts)
        return id
    }

    func remove(_ id: String) -> Bool {
        guard let account = store.accounts().first(where: { $0.id == id }),
              SettingsSupport.confirm("Remove \(account.label)?", detail: "Its token is deleted from the Keychain as well.")
        else { return false }
        try? tokenStore.setToken(nil, for: account.tokenKey)
        store.save(store.accounts().filter { $0.id != id })
        return true
    }

    // MARK: Editing

    private func applyEdits(_ form: GitHubAccountForm) {
        let edited = form.editedAccount
        persist(edited)
        form.apply(edited)
        host?.reloadList()
        host?.changed()
    }

    /// Verified before it is stored: a rejected token that lands in the Keychain turns into a
    /// card that fails for reasons nobody can see. The answer goes on the token's own line.
    private func save(_ form: GitHubAccountForm) {
        let edited = form.editedAccount
        let token = form.token.entered
        persist(edited)
        form.apply(edited)
        form.token.checking()

        let probeStore: any TokenStore = token.isEmpty ? tokenStore : InMemoryTokenStore(tokens: [edited.tokenKey: token])
        Task { [weak self] in
            guard let self else { return }
            do {
                let settings = edited.settings(basedOn: .default)
                let snapshot = try await PullRequestsService(
                    client: GitHubClient.makeDefault(tokenStore: probeStore, settings: settings, tokenKey: edited.tokenKey),
                    settings: settings,
                    accountID: edited.id
                ).fetch()
                if !token.isEmpty { try self.tokenStore.setToken(token, for: edited.tokenKey) }
                form.token.works("\(snapshot.totalCount) open pull requests")
                self.host?.reloadList()
                self.host?.changed()
            } catch let error as APIError {
                form.token.refused(token.isEmpty && !SettingsSupport.hasToken(edited.tokenKey, in: self.tokenStore) ? "paste a token first" : error.displayMessage)
            } catch {
                form.token.refused(error.localizedDescription)
            }
        }
    }

    private func persist(_ account: GitHubAccount) {
        var accounts = store.accounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        store.save(accounts)
    }
}
