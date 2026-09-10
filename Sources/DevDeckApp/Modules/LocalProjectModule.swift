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
    /// What the last health check said, per project, so the form can show it.
    private var statuses: [String: LocalProjectStatus] = [:]

    init(context: ModuleContext, store: LocalProjectsStore) {
        self.context = context
        self.store = store
    }

    // MARK: The card

    let menuGroup: String? = "Projects"

    func descriptors() -> [CardDescriptor] {
        CardCatalog.sortedByTitle(store.projects().map { project in
            CardDescriptor(
                id: project.cardID,
                title: project.displayTitle,
                subtitle: project.startCommand.isEmpty ? "Project" : "Project · \(project.startCommand)",
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
            logs: controller.logs(for: card),
            isCollapsed: controller.isCollapsed(card),
            // A plain project was told where it serves; nothing can find out for it.
            phoneURL: controller.phoneURL(for: project.siteURL ?? project.healthCheckURL, isRunning: status.isRunning),
            onOpen: { LinkOpener.open($0, using: project.browser) },
            onAction: { [controller] in controller.perform($0, for: project) },
            onOpenTerminal: { LocalFolder.openTerminal(project.folderURL) },
            onRevealFolder: { LocalFolder.reveal(project.folderURL) },
            onStartDocker: context.startDocker,
            onToggleLogs: { [controller] in controller.toggleLogs(for: card) },
            onOpenLogFile: { LocalFolder.open($0) }
        ))
    }

    func size(for card: CardID) -> NSSize {
        guard let project = store.project(forCard: card) else {
            return NSSize(width: CardMetrics.width, height: 150)
        }
        return LocalProjectCard.size(
            for: project,
            status: controller.localStatus(for: project),
            logs: controller.logs(for: card),
            isCollapsed: controller.isCollapsed(card)
        )
    }

    // MARK: The settings section

    let kind = SettingsWindowController.Section.project
    let addTitle = "Project"
    let emptyText = "No projects yet. Press + below the list and pick a folder. Anything with a "
        + "folder and a command belongs here: docker compose, a dev server, a Makefile."
    weak var host: SettingsHost?

    func listItems() -> [SettingsListItem] {
        store.projects().map { project in
            SettingsListItem(
                id: project.id,
                title: project.displayTitle,
                // The command rather than the folder: with several checkouts under one parent
                // the folder names look alike, and the command is what differs.
                subtitle: project.startCommand.isEmpty ? "no start command" : project.startCommand,
                state: project.isEnabled ? .systemGreen : .tertiaryLabelColor
            )
        }
    }

    func buildForm(for id: String, in container: FlippedContainer, width: CGFloat) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }) else { return false }
        let row = LocalProjectRowView(
            project: project,
            status: statuses[project.id] ?? .unavailable,
            width: width
        )
        row.onChange = { [weak self] in self?.applyEdits($0) }
        row.onTestLink = { [weak self] in self?.testLink($0) }
        row.onChooseFolder = { [weak self] in self?.chooseFolder($0) }
        row.onDetect = { [weak self] in self?.detect($0) }
        row.onCheckHealth = { [weak self] in self?.checkHealth($0.editedProject) }
        row.onOpenLink = { [weak self] row, index in
            guard let url = row.linkURL(at: index) else { return }
            self?.applyEdits(row)
            LinkOpener.open(url, using: row.editedProject.browser)
        }
        row.frame.origin = .zero
        container.addSubview(row)

        // The form is where someone lands when a card is misconfigured, and until now it said
        // nothing about whether the settings actually work. Checked on arrival rather than on
        // demand, because the answer is the point of the group it sits in.
        if statuses[project.id] == nil {
            checkHealth(project)
        }
        return true
    }

    /// Adds a project from a folder, filling in what the folder already says about itself.
    func add() -> String? {
        guard let url = SettingsSupport.chooseDirectory(
            message: "Pick the project folder: the one its start command runs in."
        ) else { return nil }

        var projects = store.projects()
        let name = url.lastPathComponent
        let id = LocalProject.makeID(from: name, existing: projects.map(\.id))
        var project = LocalProject(id: id, title: name, folder: url.path)

        // Applied on creation only. From here on the fields belong to the user, and a later
        // guess must never quietly replace what they typed - the Detect button is how they ask
        // for one.
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
              SettingsSupport.confirm(
                  "Remove \(project.displayTitle)?",
                  detail: "The card disappears from the deck. Anything it started keeps running."
              )
        else { return false }
        store.save(store.projects().filter { $0.id != id })
        return true
    }

    private func applyEdits(_ row: LocalProjectRowView) {
        let edited = row.editedProject
        var projects = store.projects()
        if let index = projects.firstIndex(where: { $0.id == edited.id }) {
            projects[index] = edited
        } else {
            projects.append(edited)
        }
        store.save(projects)
        row.apply(edited)
        row.setStatus(SettingsSupport.browserSummary(browser: edited.browser))
        host?.reloadList()
        host?.changed()
    }

    private func testLink(_ row: LocalProjectRowView) {
        applyEdits(row)
        let project = row.editedProject
        guard let link = project.environmentLinks().first ?? project.toolLinks().first else {
            row.setStatus("No link to test. Set a health URL or an environment.", isError: true)
            return
        }
        row.setStatus("Opening \(link.url.absoluteString)")
        LinkOpener.open(link.url, using: project.browser)
    }

    private func chooseFolder(_ row: LocalProjectRowView) {
        guard let url = SettingsSupport.chooseDirectory(
            message: "Pick the project folder: the one its start command runs in."
        ) else { return }
        row.setFolder(url.path)
    }

    /// Asks the project's health URL and redraws the form with the answer.
    private func checkHealth(_ project: LocalProject) {
        Task { [weak self] in
            guard let self else { return }
            let status = await LocalProjectService(project: project).status()
            self.statuses[project.id] = status
            // Only if the user is still looking at this project - the check takes a moment and
            // they may have moved on.
            guard self.host?.isShowing(self.kind, id: project.id) == true else { return }
            self.host?.reloadDetail()
        }
    }

    private func detect(_ row: LocalProjectRowView) {
        guard let folder = row.editedProject.folderURL else {
            row.setStatus("Set a folder first.", isError: true)
            return
        }
        guard let suggestion = ProjectProbe.suggestion(for: folder) else {
            row.setStatus(
                "Nothing recognisable in that folder: no compose file, package.json script or Makefile target.",
                isError: true
            )
            return
        }
        row.applySuggestion(suggestion)
        row.setStatus("Filled in from the folder: \(suggestion.startCommand)")
    }
}
