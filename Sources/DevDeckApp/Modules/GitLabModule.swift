import AppKit
import DevDeckCore
import DevDeckUI
import GitLabKit
import SwiftUI

/// Merge requests: yours, plus the ones waiting on your review.
@MainActor
final class MergeRequestsModule: CardModule {
    private let context: ModuleContext
    private var controller: DeckController { context.controller }

    init(context: ModuleContext) {
        self.context = context
    }

    func owns(_ card: CardID) -> Bool { card == .gitlabMergeRequests }

    func view(for card: CardID) -> AnyView {
        AnyView(MergeRequestsCard(
            state: controller.mergeRequests,
            accountLabels: controller.gitlabAccountLabels,
            isExpanded: controller.isExpanded(card),
            isCollapsed: controller.isCollapsed(card),
            onOpen: context.openGitLab,
            onToggleExpand: { [controller] in controller.toggleExpanded(card) },
            onOpenDashboard: { [self] in self.openDashboard(for: card) }
        ))
    }

    func size(for card: CardID) -> NSSize {
        MergeRequestsCard.size(
            for: controller.mergeRequests,
            isExpanded: controller.isExpanded(card),
            isCollapsed: controller.isCollapsed(card)
        )
    }

    /// The instance is per account, so the dashboard cannot be a constant. The card's own rows
    /// carry absolute URLs; this is only the double-click on the background.
    func dashboardURL(for card: CardID) -> URL? {
        URL(string: "https://gitlab.com/dashboard/merge_requests")
    }

    private func openDashboard(for card: CardID) {
        guard let url = dashboardURL(for: card) else { return }
        context.openGitLab(url, account: controller.gitlabAccountLabels.keys.sorted().first ?? "")
    }
}

/// The GitLab instances, one token each, because GitLab is routinely self-hosted.
@MainActor
final class GitLabInstancesSection: SettingsSection {
    let kind = SettingsWindowController.Section.gitlab
    let addTitle = "GitLab instance"
    let emptyText = "No GitLab instances yet. Press + below the list, then paste a token with read_api."
    weak var host: SettingsHost?

    private let store: GitLabAccountsStore
    private let tokenStore: any TokenStore
    private let preferences: Preferences

    init(store: GitLabAccountsStore, tokenStore: any TokenStore, preferences: Preferences) {
        self.store = store
        self.tokenStore = tokenStore
        self.preferences = preferences
    }

    func listItems() -> [SettingsListItem] {
        store.accounts().map { account in
            let hasToken = SettingsSupport.hasToken(account.tokenKey, in: tokenStore)
            return SettingsListItem(
                id: account.id,
                title: account.label,
                subtitle: hasToken ? account.displayHost : "no token yet",
                state: account.isEnabled ? (hasToken ? .systemGreen : .systemOrange) : .tertiaryLabelColor
            )
        }
    }

    func buildForm(for id: String, in container: FlippedContainer, width: CGFloat) -> Bool {
        guard let account = store.accounts().first(where: { $0.id == id }) else { return false }
        let row = GitLabAccountRowView(
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
        let id = GitLabAccount.makeID(from: "gitlab", existing: accounts.map(\.id))
        accounts.append(GitLabAccount(id: id, label: "GitLab"))
        store.save(accounts)
        // The card is off by default, and adding an instance is the moment it becomes worth
        // having. Turning it on by hand afterwards is a step nobody would guess at.
        var layout = preferences.cardLayout
        layout.setEnabled(true, for: .gitlabMergeRequests)
        preferences.cardLayout = layout
        host?.changed()
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

    private func applyEdits(_ row: GitLabAccountRowView) {
        let edited = row.editedAccount
        persist(edited)
        row.apply(edited)
        row.setStatus(SettingsSupport.browserSummary(browser: edited.browser))
        host?.reloadList()
        host?.changed()
    }

    private func testLink(_ row: GitLabAccountRowView) {
        applyEdits(row)
        let account = row.editedAccount
        LinkOpener.open(
            account.host.appendingPathComponent("dashboard").appendingPathComponent("merge_requests"),
            using: account.browser
        )
    }

    private func persist(_ account: GitLabAccount) {
        var accounts = store.accounts()
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        store.save(accounts)
    }

    /// Verified before it is stored, the same as a GitHub token: a rejected token that lands in
    /// the Keychain anyway turns into a card that fails for reasons nobody can see.
    private func save(_ row: GitLabAccountRowView) {
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
            let probe = GitLabClient.makeDefault(
                account: edited,
                tokenStore: InMemoryTokenStore(tokens: [edited.tokenKey: token])
            )
            do {
                let snapshot = try await MergeRequestsService(client: probe, accountID: edited.id).fetch()
                try self.tokenStore.setToken(token, for: edited.tokenKey)
                self.persist(edited)
                row.apply(edited)
                row.clearTokenField()
                row.setStatus("Saved. \(snapshot.totalCount) open merge requests on \(edited.displayHost).")
                self.host?.reloadList()
                self.host?.changed()
            } catch let error as APIError {
                row.setStatus("Rejected: \(error.displayMessage)", isError: true)
            } catch {
                row.setStatus("Rejected: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func verifyStoredToken(for account: GitLabAccount, row: GitLabAccountRowView) {
        guard SettingsSupport.hasToken(account.tokenKey, in: tokenStore) else {
            row.setStatus("No token yet. Paste one above.", isError: true)
            return
        }
        row.setStatus("Checking the stored token…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await MergeRequestsService(
                    client: GitLabClient.makeDefault(account: account, tokenStore: self.tokenStore),
                    accountID: account.id
                ).fetch()
                row.setStatus("Token works. \(snapshot.totalCount) open merge requests.")
            } catch let error as APIError {
                row.setStatus("Stored token: \(error.displayMessage)", isError: true)
            } catch {
                row.setStatus("Stored token: \(error.localizedDescription)", isError: true)
            }
        }
    }
}
