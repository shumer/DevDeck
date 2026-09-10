import AppKit
import ArcKit
import DevDeckCore
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

    let menuGroup: String? = "Arc projects"

    func descriptors() -> [CardDescriptor] {
        CardCatalog.sortedByTitle(store.projects().map { project in
            CardDescriptor(
                id: project.cardID,
                title: project.title,
                subtitle: "Arc · \(project.organization)",
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
        let status = controller.stackStatus(for: project)
        return AnyView(ArcProjectCard(
            project: project,
            status: status,
            docker: controller.docker,
            logs: controller.logs(for: card),
            isCollapsed: controller.isCollapsed(card),
            // Where the site is served is read from the checkout's `.env`, and the stack says
            // whether it is up.
            phoneURL: controller.phoneURL(for: status.siteURL ?? project.localSiteURL, isRunning: status.isRunning),
            onOpen: { LinkOpener.open($0, using: project.browser) },
            onAction: { [controller] in controller.perform($0, for: project) },
            onRevealFolder: { LocalFolder.reveal(project.folderURL) },
            onOpenTerminal: { LocalFolder.openTerminal(project.folderURL) },
            onStartDocker: context.startDocker,
            onToggleLogs: { [controller] in controller.toggleLogs(for: card) },
            onOpenLogFile: { LocalFolder.open($0) }
        ))
    }

    func size(for card: CardID) -> NSSize {
        guard let project = store.project(forCard: card) else {
            return NSSize(width: CardMetrics.width, height: 150)
        }
        return ArcProjectCard.size(
            for: project,
            status: controller.stackStatus(for: project),
            logs: controller.logs(for: card),
            isCollapsed: controller.isCollapsed(card)
        )
    }

    // MARK: The settings section

    let kind = SettingsWindowController.Section.arc
    let addTitle = "Arc project"
    let emptyText = "No Arc projects yet. Press + below the list."
    weak var host: SettingsHost?

    func listItems() -> [SettingsListItem] {
        store.projects().map { project in
            SettingsListItem(
                id: project.id,
                title: project.title,
                subtitle: project.organization.isEmpty ? "no organisation" : project.organization,
                state: project.isEnabled ? .systemGreen : .tertiaryLabelColor
            )
        }
    }

    func buildForm(for id: String, in container: FlippedContainer, width: CGFloat) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }) else { return false }
        let row = ProjectRowView(project: project, width: width)
        row.onChange = { [weak self] in self?.applyEdits($0) }
        row.onTestLink = { [weak self] in self?.testLink($0) }
        row.onChooseFolder = { [weak self] in self?.chooseFolder($0) }
        row.onStructureChange = { [weak self] _, project in
            guard let self else { return }
            var projects = self.store.projects()
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index] = project
                self.store.save(projects)
            }
            self.host?.changed()
            // Rebuilt rather than reloaded: a link was added or removed, so the form has a
            // different number of rows than the one on screen.
            self.host?.reloadDetail()
        }
        row.frame.origin = .zero
        container.addSubview(row)
        return true
    }

    func add() -> String? {
        var projects = store.projects()
        let id = ArcProject.makeID(from: "project", existing: projects.map(\.id))
        projects.append(ArcProject(id: id, title: "New project", organization: ""))
        store.save(projects)
        host?.changed()
        return id
    }

    func remove(_ id: String) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }),
              SettingsSupport.confirm("Remove \(project.title)?", detail: "The card disappears from the deck.")
        else { return false }
        store.save(store.projects().filter { $0.id != id })
        return true
    }

    private func applyEdits(_ row: ProjectRowView) {
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

    private func testLink(_ row: ProjectRowView) {
        applyEdits(row)
        let project = row.editedProject
        guard let link = project.resolvedLinks.first else {
            row.setStatus("No enabled link to test.", isError: true)
            return
        }
        row.setStatus("Opening \(link.url.absoluteString)")
        LinkOpener.open(link.url, using: project.browser)
    }

    private func chooseFolder(_ row: ProjectRowView) {
        guard let url = SettingsSupport.chooseDirectory(
            message: "Pick the project checkout: the folder the fusion commands run in."
        ) else { return }
        row.setFolder(url.path)
    }
}
