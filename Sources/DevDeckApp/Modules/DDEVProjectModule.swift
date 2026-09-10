import AppKit
import DDEVKit
import DevDeckCore
import DevDeckUI
import SwiftUI

/// DDEV projects: the card, one per project, and the settings section they are added in.
@MainActor
final class DDEVProjectModule: CardModule, SettingsSection {
    private let context: ModuleContext
    private let store: DDEVProjectsStore
    private let environment = DDEVEnvironment()
    private var controller: DeckController { context.controller }

    init(context: ModuleContext, store: DDEVProjectsStore) {
        self.context = context
        self.store = store
    }

    // MARK: The card

    let menuGroup: String? = "DDEV projects"

    func descriptors() -> [CardDescriptor] {
        CardCatalog.sortedByTitle(store.projects().map { project in
            CardDescriptor(
                id: project.cardID,
                title: project.displayTitle,
                subtitle: "DDEV · \(project.name)",
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
        let status = controller.ddevStatus(for: project)
        return AnyView(DDEVProjectCard(
            project: project,
            status: status,
            docker: controller.docker,
            logs: controller.logs(for: card),
            isCollapsed: controller.isCollapsed(card),
            // DDEV knows where it serves; `ddev list` says so.
            phoneURL: controller.phoneURL(for: status.entry?.primaryURL, isRunning: status.isRunning),
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
        return DDEVProjectCard.size(
            for: project,
            status: controller.ddevStatus(for: project),
            logs: controller.logs(for: card),
            isCollapsed: controller.isCollapsed(card)
        )
    }

    // MARK: The settings section

    let kind = SettingsWindowController.Section.ddev
    let addTitle = "DDEV project"
    let emptyText = "No DDEV projects yet. Press + below the list and pick one ddev already knows."
    weak var host: SettingsHost?

    func listItems() -> [SettingsListItem] {
        store.projects().map { project in
            SettingsListItem(
                id: project.id,
                title: project.displayTitle,
                subtitle: project.name,
                state: project.isEnabled ? .systemGreen : .tertiaryLabelColor
            )
        }
    }

    func buildForm(for id: String, in container: FlippedContainer, width: CGFloat) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }) else { return false }
        let row = DDEVProjectRowView(project: project, width: width)
        row.onChange = { [weak self] in self?.applyEdits($0) }
        row.onTestLink = { [weak self] in self?.testLink($0) }
        row.onChooseFolder = { [weak self] in self?.chooseFolder($0) }
        row.frame.origin = .zero
        container.addSubview(row)
        return true
    }

    /// Offers what `ddev list` found rather than making the user go looking for a folder. Asks
    /// first, so the selection is made through the host once the answer is in.
    func add() -> String? {
        Task { [weak self] in
            guard let self else { return }
            guard let entries = await self.environment.list() else {
                self.presentUnavailable()
                return
            }

            let known = Set(self.store.projects().map(\.name))
            let candidates = entries.filter { !known.contains($0.name) }

            guard !candidates.isEmpty else {
                let alert = NSAlert()
                alert.messageText = entries.isEmpty
                    ? "ddev has no projects"
                    : "Every DDEV project is already on the deck"
                alert.informativeText = entries.isEmpty
                    ? "Run ddev config in a project folder first."
                    : "Nothing left to add."
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            let alert = NSAlert()
            alert.messageText = "Add a DDEV project"
            alert.informativeText = "Found by ddev list."
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 25))
            for candidate in candidates {
                popUp.addItem(withTitle: "\(candidate.name) (\(candidate.state.rawValue))")
            }
            alert.accessoryView = popUp
            alert.addButton(withTitle: "Add")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            let index = max(0, min(popUp.indexOfSelectedItem, candidates.count - 1))
            let chosen = candidates[index]
            var projects = self.store.projects()
            let id = DDEVProject.makeID(from: chosen.name, existing: projects.map(\.id))
            projects.append(DDEVProject(id: id, name: chosen.name, folder: chosen.approot))
            self.store.save(projects)
            self.host?.select(self.kind, id: id)
            self.host?.changed()
        }
        return nil
    }

    func remove(_ id: String) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }),
              SettingsSupport.confirm(
                  "Remove \(project.displayTitle)?",
                  detail: "The card disappears from the deck. The project itself is untouched."
              )
        else { return false }
        store.save(store.projects().filter { $0.id != id })
        return true
    }

    private func presentUnavailable() {
        let alert = NSAlert()
        alert.messageText = "ddev did not answer"
        alert.informativeText = "Either DDEV is not installed, or it is not on the PATH a login "
            + "shell sees. Running ddev list in a terminal will say which."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func applyEdits(_ row: DDEVProjectRowView) {
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

    private func testLink(_ row: DDEVProjectRowView) {
        applyEdits(row)
        let project = row.editedProject

        Task { [weak self] in
            guard let self else { return }
            let entries = await self.environment.list()
            let status = self.environment.status(for: project, entries: entries)
            guard let link = project.links(status: status).first else {
                row.setStatus("ddev has no URL for this project yet.", isError: true)
                return
            }
            row.setStatus("Opening \(link.url.absoluteString)")
            LinkOpener.open(link.url, using: project.browser)
        }
    }

    private func chooseFolder(_ row: DDEVProjectRowView) {
        guard let url = SettingsSupport.chooseDirectory(message: "Pick the project checkout: the folder holding .ddev.")
        else { return }
        // Said plainly rather than refused: the folder may be right and the project not set up
        // yet, and that is the user's business.
        if !DDEVConfig.isProject(url) {
            row.setStatus("No .ddev/config.yaml in that folder.", isError: true)
        }
        row.setFolder(url.path)
    }
}
