import AppKit
import DevDeckCore
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

    var menuGroup: String? { L("menu.group.projects") }

    func descriptors() -> [CardDescriptor] {
        CardCatalog.sortedByTitle(store.projects().map { project in
            CardDescriptor(
                id: project.cardID,
                title: project.displayTitle,
                subtitle: project.startCommand.isEmpty ? L("project.section.project") : "\(L("project.section.project")) · \(project.startCommand)",
                isImplemented: true,
                isEnabledByDefault: true
            )
        })
    }

    func owns(_ card: CardID) -> Bool {
        store.project(forCard: card) != nil
    }

    func view(for card: CardID) -> AnyView {
        guard let project = store.project(forCard: card) else { return AnyView(EmptyView()) }
        let status = controller.localStatus(for: project)
        return AnyView(LocalProjectCard(
            project: project,
            status: status,
            docker: controller.docker,
            isShowingLogs: controller.isShowingLogs(card),
            isCollapsed: controller.isCollapsed(card),
            // A plain project was told where it serves; nothing can find out for it.
            phoneURL: controller.phoneURL(for: project.siteURL ?? project.healthCheckURL, isRunning: status.isRunning),
            onOpen: { LinkOpener.open($0, using: project.browser) },
            onAction: { [controller] in controller.perform($0, for: project) },
            onOpenTerminal: { LocalFolder.openTerminal(project.folderURL) },
            onRevealFolder: { LocalFolder.reveal(project.folderURL) },
            onStartDocker: context.startDocker,
            onToggleLogs: { [controller] in controller.toggleLogs(for: card) }
        ))
    }

    func size(for card: CardID) -> NSSize {
        guard let project = store.project(forCard: card) else {
            return NSSize(width: CardMetrics.width, height: 150)
        }
        return LocalProjectCard.size(
            for: project,
            status: controller.localStatus(for: project),
            isCollapsed: controller.isCollapsed(card)
        )
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
        store.projects().map { project in
            let live = controller.localStatus(for: project).state
            return SettingsListItem(
                id: project.id,
                title: project.displayTitle,
                // The command rather than the folder: with several checkouts under one parent
                // the folder names look alike, and the command is what differs.
                detail: project.startCommand.isEmpty ? L("project.list.noStart") : project.startCommand,
                icon: SettingsIcons.mark(LocalProjectForm.glyph(for: project)),
                dot: live == .running ? .systemGreen : (live == .starting || live == .working ? .systemOrange : nil),
                isDimmed: !project.isEnabled
            )
        }
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
        form.onTestLink = { form in
            let project = form.editedProject
            guard let link = project.environmentLinks().first ?? project.toolLinks().first else {
                form.setLinkNote(L("project.link.nothingToOpen"), isError: true)
                return
            }
            form.setLinkNote("", isError: false)
            LinkOpener.open(link.url, using: project.browser)
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
        var projects = store.projects()
        let name = url.lastPathComponent
        let id = LocalProject.makeID(from: name, existing: projects.map(\.id))
        var project = LocalProject(id: id, title: name, folder: url.path)

        // Applied on creation only. From here on the fields belong to the user, and a later
        // guess must never quietly replace what they typed; Detect is how they ask for one.
        if let suggestion = ProjectProbe.suggestion(for: url) {
            project.subtitle = suggestion.subtitle
            project.startCommand = suggestion.startCommand
            project.stopCommand = suggestion.stopCommand
            project.holdsProcess = suggestion.holdsProcess
            project.requiresDocker = suggestion.requiresDocker
            project.healthURL = suggestion.healthURL
        }
        projects.append(project)
        store.save(projects)
        host?.changed()
        return id
    }

    func remove(_ id: String) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }),
              SettingsSupport.confirm(L("settings.remove.account.title", project.displayTitle), detail: L("settings.remove.project.detail.local"))
        else { return false }
        store.save(store.projects().filter { $0.id != id })
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
        let before = store.projects().first { $0.id == form.project.id }
        let edited = form.editedProject
        var projects = store.projects()
        if let index = projects.firstIndex(where: { $0.id == edited.id }) {
            projects[index] = edited
        } else {
            projects.append(edited)
        }
        store.save(projects)
        form.apply(edited)
        host?.reloadList()
        host?.changed()

        // A new address, folder or command is a new question; the old answer is not its answer.
        if before?.healthURL != edited.healthURL || before?.folder != edited.folder || before?.startCommand != edited.startCommand {
            checkHealth(edited)
        }
    }

    private func checkHealth(_ project: LocalProject) {
        form?.health.update(.checking)
        Task { [weak self] in
            guard let self else { return }
            let status = await LocalProjectService(project: project).status()
            self.statuses[project.id] = (status, project.healthURL)
            // Only into the row the answer belongs to, and only if it is still on screen.
            guard let form = self.form, form.project.id == project.id else { return }
            form.health.update(status.summary(checkedURL: project.healthURL, currentURL: form.editedProject.healthURL))
        }
    }

    private func detect(_ form: LocalProjectForm) {
        guard let folder = form.editedProject.folderURL else {
            form.setDetectNote(L("project.detect.noFolder"), isError: true)
            return
        }
        guard let suggestion = ProjectProbe.suggestion(for: folder) else {
            form.setDetectNote(L("project.detect.nothing"), isError: true)
            return
        }
        form.applySuggestion(suggestion)
        let found = [suggestion.subtitle, suggestion.requiresDocker ? L("project.detect.needsDocker") : ""].filter { !$0.isEmpty }.joined(separator: ", ")
        form.setDetectNote(L("project.detect.found", found.isEmpty ? suggestion.startCommand : found), isError: false)
    }
}
