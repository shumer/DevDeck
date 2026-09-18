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
    let group = SettingsListGroup.accounts
    let addTitle = "GitLab Instance"
    weak var host: SettingsHost?

    private let store: GitLabAccountsStore
    private let tokenStore: any TokenStore
    private let preferences: Preferences
    /// A token half typed, by instance, kept while the window is open.
    private var drafts: [String: String] = [:]

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
                detail: hasToken ? account.displayHost : "\(account.displayHost) · no token",
                icon: SettingsIcons.mark(.gitlab),
                dot: hasToken ? nil : .systemOrange,
                isDimmed: !account.isEnabled
            )
        }
    }

    func buildForm(for id: String, in container: FlippedContainer) -> Bool {
        guard let account = store.accounts().first(where: { $0.id == id }) else { return false }
        let form = GitLabAccountForm(
            account: account,
            hasToken: SettingsSupport.hasToken(account.tokenKey, in: tokenStore),
            draft: drafts[id] ?? "",
            width: container.bounds.width
        )
        form.token.onDraftChange = { [weak self] text in self?.drafts[id] = text }
        form.onChange = { [weak self] in self?.applyEdits($0) }
        form.onSave = { [weak self] in self?.save($0) }
        form.onTestLink = { form in
            let account = form.editedAccount
            LinkOpener.open(account.host.appendingPathComponent("dashboard").appendingPathComponent("merge_requests"), using: account.browser)
        }
        container.addSubview(form)
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

    private func applyEdits(_ form: GitLabAccountForm) {
        let edited = form.editedAccount
        persist(edited)
        form.apply(edited)
        host?.reloadList()
        host?.changed()
    }

    private func persist(_ account: GitLabAccount) {
        var accounts = store.accounts()
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        store.save(accounts)
    }

    /// Verified before it is stored, the same as a GitHub token.
    private func save(_ form: GitLabAccountForm) {
        let edited = form.editedAccount
        let token = form.token.entered
        persist(edited)
        form.apply(edited)
        form.token.checking()

        let probeStore: any TokenStore = token.isEmpty ? tokenStore : InMemoryTokenStore(tokens: [edited.tokenKey: token])
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await MergeRequestsService(
                    client: GitLabClient.makeDefault(account: edited, tokenStore: probeStore),
                    accountID: edited.id
                ).fetch()
                if !token.isEmpty { try self.tokenStore.setToken(token, for: edited.tokenKey) }
                form.token.works("\(snapshot.totalCount) open merge requests")
                self.host?.reloadList()
                self.host?.changed()
            } catch let error as APIError {
                form.token.refused(error.displayMessage)
            } catch {
                form.token.refused(error.localizedDescription)
            }
        }
    }
}
