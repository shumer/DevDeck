import AppKit
import DevDeckCore
import DevDeckEngine
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
        guard case .reviewList(let model)? = controller.model(for: card) else { return AnyView(EmptyView()) }
        return AnyView(ReviewListCard(model: model, onCommand: context.perform))
    }

    func size(for card: CardID) -> NSSize {
        guard case .reviewList(let model)? = controller.model(for: card) else { return .zero }
        return ReviewListCard.size(for: model)
    }

    func dashboardURL(for card: CardID) -> URL? {
        controller.dashboardURL(for: card)
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
        guard case .inbox(let model)? = controller.model(for: card) else { return AnyView(EmptyView()) }
        return AnyView(InboxCard(model: model, onCommand: context.perform))
    }

    func size(for card: CardID) -> NSSize {
        guard case .inbox(let model)? = controller.model(for: card) else { return .zero }
        return InboxCard.size(for: model)
    }

    func dashboardURL(for card: CardID) -> URL? {
        controller.dashboardURL(for: card)
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
        guard case .actions(let model)? = controller.model(for: card) else { return AnyView(EmptyView()) }
        return AnyView(ActionsCard(model: model, onCommand: context.perform))
    }

    func size(for card: CardID) -> NSSize {
        ActionsCard.size(isCollapsed: controller.isCollapsed(card))
    }

    func dashboardURL(for card: CardID) -> URL? {
        controller.dashboardURL(for: card)
    }
}

/// The GitHub accounts, one token each.
@MainActor
final class GitHubAccountsSection: SettingsSection {
    let kind = SettingsWindowController.Section.github
    let group = SettingsListGroup.accounts
    var addTitle: String { L("settings.add.github") }
    weak var host: SettingsHost?

    private let store: GitHubAccountsStore
    private let runtime: DeckRuntime
    /// A token half typed, by account, kept while the window is open: selecting another row
    /// rebuilds the form, and the field used to come back empty with no word about it.
    private var drafts: [String: String] = [:]

    init(store: GitHubAccountsStore, runtime: DeckRuntime) {
        self.store = store
        self.runtime = runtime
    }

    func listItems() -> [SettingsListItem] {
        runtime.settingsItems(.github)
    }

    func buildForm(for id: String, in container: FlippedContainer) -> Bool {
        guard let account = store.accounts().first(where: { $0.id == id }) else { return false }
        let fold = "github:\(id):advanced"
        let form = GitHubAccountForm(
            account: account,
            hasToken: runtime.hasToken(account.tokenKey),
            isAdvancedOpen: host?.isOpen(fold) ?? false,
            draft: drafts[id] ?? "",
            width: container.bounds.width
        )
        form.token.onDraftChange = { [weak self] text in self?.drafts[id] = text }
        form.onChange = { [weak self] in self?.applyEdits($0) }
        form.onSave = { [weak self] in self?.save($0) }
        form.onTestLink = { [runtime] in LinkOpener.open(runtime.testLink($0.editedAccount)) { _ in } }
        form.onToggleAdvanced = { [weak self] in self?.host?.toggle(fold) }
        container.addSubview(form)
        return true
    }

    func add() -> String? {
        runtime.addGitHubAccount()
    }

    func remove(_ id: String) -> Bool {
        guard let account = store.accounts().first(where: { $0.id == id }),
              SettingsSupport.confirm(L("settings.remove.account.title", account.label), detail: L("settings.remove.account.detail"))
        else { return false }
        runtime.removeGitHubAccount(account.id)
        return true
    }

    // MARK: Editing

    private func applyEdits(_ form: GitHubAccountForm) {
        let edited = form.editedAccount
        runtime.saveGitHubAccount(edited)
        form.apply(edited)
        host?.reloadList()
        host?.changed()
    }

    /// Verified before it is stored; see `DeckRuntime.checkGitHubToken(for:typed:)`. The answer
    /// goes on the token's own line.
    private func save(_ form: GitHubAccountForm) {
        let edited = form.editedAccount
        let token = form.token.entered
        runtime.saveGitHubAccount(edited)
        form.apply(edited)
        form.token.checking()
        Task { [weak self, runtime] in
            switch await runtime.checkGitHubToken(for: edited, typed: token) {
            case .works(let detail):
                form.token.works(detail)
                self?.host?.reloadList()
                self?.host?.changed()
            case .refused(let reason):
                form.token.refused(reason)
            }
        }
    }
}
