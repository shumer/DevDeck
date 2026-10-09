import AppKit
import DevDeckCore
import DevDeckEngine
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

/// The GitLab instances, one token each, because GitLab is routinely self-hosted.
@MainActor
final class GitLabInstancesSection: SettingsSection {
    let kind = SettingsWindowController.Section.gitlab
    let group = SettingsListGroup.accounts
    var addTitle: String { L("settings.add.gitlab") }
    weak var host: SettingsHost?

    private let store: GitLabAccountsStore
    private let runtime: DeckRuntime
    /// A token half typed, by instance, kept while the window is open.
    private var drafts: [String: String] = [:]

    init(store: GitLabAccountsStore, runtime: DeckRuntime) {
        self.store = store
        self.runtime = runtime
    }

    func listItems() -> [SettingsListItem] {
        runtime.settingsItems(.gitlab)
    }

    func buildForm(for id: String, in container: FlippedContainer) -> Bool {
        guard let account = store.accounts().first(where: { $0.id == id }) else { return false }
        let form = GitLabAccountForm(
            account: account,
            hasToken: runtime.hasToken(account.tokenKey),
            draft: drafts[id] ?? "",
            width: container.bounds.width
        )
        form.token.onDraftChange = { [weak self] text in self?.drafts[id] = text }
        form.onChange = { [weak self] in self?.applyEdits($0) }
        form.onSave = { [weak self] in self?.save($0) }
        form.onTestLink = { [runtime] in LinkOpener.open(runtime.testLink($0.editedAccount)) { _ in } }
        container.addSubview(form)
        return true
    }

    func add() -> String? {
        let id = runtime.addGitLabAccount()
        host?.changed()
        return id
    }

    func remove(_ id: String) -> Bool {
        guard let account = store.accounts().first(where: { $0.id == id }),
              SettingsSupport.confirm(L("settings.remove.account.title", account.label), detail: L("settings.remove.account.detail"))
        else { return false }
        runtime.removeGitLabAccount(account.id)
        return true
    }

    private func applyEdits(_ form: GitLabAccountForm) {
        let edited = form.editedAccount
        runtime.saveGitLabAccount(edited)
        form.apply(edited)
        host?.reloadList()
        host?.changed()
    }

    /// Verified before it is stored, the same as a GitHub token.
    private func save(_ form: GitLabAccountForm) {
        let edited = form.editedAccount
        let token = form.token.entered
        runtime.saveGitLabAccount(edited)
        form.apply(edited)
        form.token.checking()
        Task { [weak self, runtime] in
            switch await runtime.checkGitLabToken(for: edited, typed: token) {
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
