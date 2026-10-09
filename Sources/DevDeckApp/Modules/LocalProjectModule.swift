import AppKit
import DevDeckCore
import DevDeckEngine
import DevDeckUI
import ProjectKit
import SwiftUI

/// Plain projects: a folder, a command and a URL. The card, one per project, and the settings
/// section they are added in.
@MainActor
final class LocalProjectModule: CardModule, SettingsSection {
    private let context: ModuleContext
    private let store: LocalProjectsStore
    private var controller: DeckController { context.controller }

    init(context: ModuleContext, store: LocalProjectsStore) {
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
        (.project, store.project(forCard: card)?.id)
    }

    // MARK: The settings section

    let kind = SettingsWindowController.Section.project
    let group = SettingsListGroup.projects
    var addTitle: String { L("settings.add.local") }
    weak var host: SettingsHost?
    /// The form on screen, so an answer that comes back updates its row instead of rebuilding it.
    private weak var form: LocalProjectForm?

    func listItems() -> [SettingsListItem] {
        controller.runtime.settingsItems(.project)
    }

    func buildForm(for id: String, in container: FlippedContainer) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }) else { return false }
        let fold = "project:\(id):advanced"
        let health = StatusLine(healthSummary(for: project))
        let form = LocalProjectForm(project: project, health: health, isAdvancedOpen: host?.isOpen(fold) ?? false, width: container.bounds.width)
        form.onChange = { [weak self] in self?.applyEdits($0) }
        form.onChooseFolder = { form in
            guard let url = SettingsSupport.chooseDirectory(message: L("project.choose.local")) else { return }
            form.setFolder(url.path)
        }
        form.onDetect = { [weak self] in self?.detect($0) }
        form.onCheckHealth = { [weak self] in self?.checkHealth($0.editedProject) }
        form.onOpenLink = { form, index in
            guard let url = form.linkURL(at: index) else { return }
            LinkOpener.open(url, using: form.editedProject.browser)
        }
        form.onTestLink = { [controller] form in
            LinkOpener.open(controller.runtime.testLink(form.editedProject)) { form.setLinkNote($0, isError: !$0.isEmpty) }
        }
        form.onToggleAdvanced = { [weak self] in self?.host?.toggle(fold) }
        container.addSubview(form)
        self.form = form

        // Checked on arrival: the form is where someone lands when a card is wrong, and the
        // answer is the point of the group it sits in.
        if statuses[project.id] == nil || statuses[project.id]?.url != project.healthURL {
            checkHealth(project)
        }
        return true
    }

    /// Adds a project from a folder, filling in what the folder already says about itself.
    func add() -> String? {
        guard let url = SettingsSupport.chooseDirectory(message: L("project.choose.local")) else {
            return nil
        }
        let id = controller.runtime.addLocalProject(folder: url)
        host?.changed()
        return id
    }

    func remove(_ id: String) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }),
              SettingsSupport.confirm(L("settings.remove.account.title", project.displayTitle), detail: L("settings.remove.project.detail.local"))
        else { return false }
        controller.runtime.removeLocalProject(id)
        return true
    }

    // MARK: Editing

    /// What the last check said, and the address it said it about.
    private var statuses: [String: (status: LocalProjectStatus, url: String)] = [:]

    private func healthSummary(for project: LocalProject) -> CheckSummary {
        guard let known = statuses[project.id] else { return .notChecked }
        return known.status.summary(checkedURL: known.url, currentURL: project.healthURL)
    }

    private func applyEdits(_ form: LocalProjectForm) {
        let edited = form.editedProject
        let asksAgain = controller.runtime.saveLocalProject(edited)
        form.apply(edited)
        host?.reloadList()
        host?.changed()
        if asksAgain { checkHealth(edited) }
    }

    private func checkHealth(_ project: LocalProject) {
        form?.health.update(.checking)
        Task { [weak self] in
            guard let self else { return }
            let status = await self.controller.runtime.checkLocalProject(project)
            self.statuses[project.id] = (status, project.healthURL)
            // Only into the row the answer belongs to, and only if it is still on screen.
            guard let form = self.form, form.project.id == project.id else { return }
            form.health.update(status.summary(checkedURL: project.healthURL, currentURL: form.editedProject.healthURL))
        }
    }

    private func detect(_ form: LocalProjectForm) {
        let detection = controller.runtime.detect(folder: form.editedProject.folderURL)
        if let suggestion = detection.suggestion { form.applySuggestion(suggestion) }
        form.setDetectNote(detection.note, isError: detection.isError)
    }
}
