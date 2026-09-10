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
    let addTitle = "GitHub account"
    let emptyText = "No accounts yet. Press + below the list."
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
                subtitle: hasToken ? "token stored" : "no token yet",
                state: account.isEnabled ? (hasToken ? .systemGreen : .systemOrange) : .tertiaryLabelColor
            )
        }
    }

    func buildForm(for id: String, in container: FlippedContainer, width: CGFloat) -> Bool {
        guard let account = store.accounts().first(where: { $0.id == id }) else { return false }
        let row = AccountRowView(
            account: account,
            hasToken: SettingsSupport.hasToken(account.tokenKey, in: tokenStore),
            width: width
        )
        row.onChange = { [weak self] in self?.applyEdits($0) }
        row.onSave = { [weak self] in self?.save($0) }
        row.onTestLink = { [weak self] in self?.testLink($0) }
        row.frame.origin = .zero
        container.addSubview(row)
        return true
    }

    func add() -> String? {
        var accounts = store.accounts()
        let id = GitHubAccount.makeID(from: "account", existing: accounts.map(\.id))
        accounts.append(GitHubAccount(id: id, label: "New account"))
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

    private func applyEdits(_ row: AccountRowView) {
        let edited = row.editedAccount
        persist(edited)
        row.apply(edited)
        row.setStatus(SettingsSupport.browserSummary(browser: edited.browser))
        host?.reloadList()
        host?.changed()
    }

    private func testLink(_ row: AccountRowView) {
        applyEdits(row)
        guard let url = URL(string: "https://github.com/pulls") else { return }
        LinkOpener.open(url, using: row.editedAccount.browser)
    }

    private func save(_ row: AccountRowView) {
        let edited = row.editedAccount
        let token = row.enteredToken

        guard !token.isEmpty else {
            persist(edited)
            row.apply(edited)
            verifyStoredToken(for: edited, row: row)
            host?.changed()
            return
        }

        row.setStatus("Checking…")
        Task { [weak self] in
            guard let self else { return }
            // Verify before storing: a rejected token that silently lands in the Keychain turns
            // into a card that fails for reasons nobody can see.
            let probe = GitHubClient.makeDefault(
                tokenStore: InMemoryTokenStore(tokens: [edited.tokenKey: token]),
                settings: edited.settings(basedOn: .default),
                tokenKey: edited.tokenKey
            )
            do {
                let snapshot = try await PullRequestsService(
                    client: probe,
                    settings: edited.settings(basedOn: .default),
                    accountID: edited.id
                ).fetch()
                try self.tokenStore.setToken(token, for: edited.tokenKey)
                self.persist(edited)
                row.apply(edited)
                row.clearTokenField()
                row.setStatus("Saved. \(snapshot.totalCount) open pull requests.")
                self.host?.reloadList()
                self.host?.changed()
            } catch let error as APIError {
                row.setStatus("Rejected: \(error.displayMessage)", isError: true)
            } catch {
                row.setStatus("Rejected: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func verifyStoredToken(for account: GitHubAccount, row: AccountRowView) {
        guard SettingsSupport.hasToken(account.tokenKey, in: tokenStore) else {
            row.setStatus("No token yet. Paste one above.", isError: true)
            return
        }
        row.setStatus("Checking the stored token…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await PullRequestsService(
                    client: GitHubClient.makeDefault(
                        tokenStore: self.tokenStore,
                        settings: account.settings(basedOn: .default),
                        tokenKey: account.tokenKey
                    ),
                    settings: account.settings(basedOn: .default),
                    accountID: account.id
                ).fetch()
                row.setStatus("Token works. \(snapshot.totalCount) open pull requests.")
            } catch let error as APIError {
                row.setStatus("Stored token: \(error.displayMessage)", isError: true)
            } catch {
                row.setStatus("Stored token: \(error.localizedDescription)", isError: true)
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
