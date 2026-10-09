import AppKit
import ArcKit
import DevDeckCore
import DevDeckEngine
import DevDeckUI
import SwiftUI

/// Arc XP projects: the card, one per project, and the settings section they are added in.
@MainActor
final class ArcProjectModule: CardModule, SettingsSection {
    private let context: ModuleContext
    private let store: ArcProjectsStore
    private var controller: DeckController { context.controller }

    init(context: ModuleContext, store: ArcProjectsStore) {
        self.context = context
        self.store = store
    }

    // MARK: The card

    func owns(_ card: CardID) -> Bool {
        store.project(forCard: card) != nil
    }

    func view(for card: CardID) -> AnyView {
        guard case .project(let model)? = controller.model(for: card) else { return AnyView(EmptyView()) }
        return AnyView(ProjectCard(model: model, onCommand: context.perform))
    }

    func size(for card: CardID) -> NSSize {
        guard case .project(let model)? = controller.model(for: card) else {
            return NSSize(width: CardMetrics.width, height: 150)
        }
        return ProjectCard.size(for: model)
    }

    func settingsTarget(for card: CardID) -> (section: SettingsWindowController.Section, id: String?) {
        (.arc, store.project(forCard: card)?.id)
    }

    // MARK: The settings section

    let kind = SettingsWindowController.Section.arc
    let group = SettingsListGroup.projects
    var addTitle: String { L("settings.add.arc") }
    weak var host: SettingsHost?
    private weak var form: ArcProjectForm?
    /// What the last stack check said, and the address it said it about.
    private var checks: [String: (status: LocalStackStatus, address: String)] = [:]

    func listItems() -> [SettingsListItem] {
        controller.runtime.settingsItems(.arc)
    }

    func buildForm(for id: String, in container: FlippedContainer) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }) else { return false }
        let fold = "arc:\(id):advanced"
        let summary = checks[project.id].map { $0.status.summary(checkedAddress: $0.address, currentAddress: Self.address(of: project)) } ?? .notChecked
        let form = ArcProjectForm(project: project, stack: StatusLine(summary), isAdvancedOpen: host?.isOpen(fold) ?? false, width: container.bounds.width)
        form.onChange = { [weak self] in self?.applyEdits($0) }
        form.onChooseFolder = { form in
            guard let url = SettingsSupport.chooseDirectory(message: L("project.choose.arc")) else { return }
            form.setFolder(url.path)
        }
        form.onCheckStack = { [weak self] in self?.checkStack($0.editedProject) }
        form.onTestLink = { [controller] form in
            LinkOpener.open(controller.runtime.testLink(form.editedProject)) { form.setLinkNote($0, isError: !$0.isEmpty) }
        }
        form.onToggleAdvanced = { [weak self] in self?.host?.toggle(fold) }
        form.onStructureChange = { [weak self] _, project in
            guard let self else { return }
            self.controller.runtime.restructureArcProject(project)
            self.host?.changed()
            // Rebuilt rather than updated: a link was added or removed.
            self.host?.reloadDetail()
        }
        container.addSubview(form)
        self.form = form

        if project.supportsLocalStack, checks[project.id]?.address != Self.address(of: project) {
            checkStack(project)
        }
        return true
    }

    func add() -> String? {
        let id = controller.runtime.addArcProject()
        host?.changed()
        return id
    }

    func remove(_ id: String) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }),
              SettingsSupport.confirm(L("settings.remove.account.title", project.title), detail: L("settings.remove.project.detail.arc"))
        else { return false }
        controller.runtime.removeArcProject(id)
        return true
    }

    private static func address(of project: ArcProject) -> String {
        DeckRuntime.stackAddress(of: project)
    }

    private func applyEdits(_ form: ArcProjectForm) {
        let edited = form.editedProject
        let asksAgain = controller.runtime.saveArcProject(edited)
        form.apply(edited)
        host?.reloadList()
        host?.changed()
        if asksAgain { checkStack(edited) }
    }

    private func checkStack(_ project: ArcProject) {
        guard project.supportsLocalStack else {
            form?.stack.update(DeckRuntime.stackNotConfigured)
            return
        }
        form?.stack.update(.checking)
        Task { [weak self] in
            guard let self, let status = await self.controller.runtime.checkArcStack(project) else { return }
            let address = Self.address(of: project)
            self.checks[project.id] = (status, address)
            guard let form = self.form, form.project.id == project.id else { return }
            form.stack.update(status.summary(checkedAddress: address, currentAddress: Self.address(of: form.editedProject)))
        }
    }
}
