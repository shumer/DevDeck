import AppKit
import DDEVKit
import DevDeckCore
import DevDeckEngine
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
        (.ddev, store.project(forCard: card)?.id)
    }

    // MARK: The settings section

    let kind = SettingsWindowController.Section.ddev
    let group = SettingsListGroup.projects
    var addTitle: String { L("settings.add.ddev") }
    weak var host: SettingsHost?

    func listItems() -> [SettingsListItem] {
        store.projects().map { project in
            let live = controller.ddevStatus(for: project).state
            return SettingsListItem(
                id: project.id,
                title: project.displayTitle,
                detail: "DDEV · \(project.name)",
                icon: SettingsIcons.mark(.ddev),
                dot: live == .running ? .systemGreen : (live == .working ? .systemOrange : nil),
                isDimmed: !project.isEnabled
            )
        }
    }

    func buildForm(for id: String, in container: FlippedContainer) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }) else { return false }
        let form = DDEVProjectForm(project: project, width: container.bounds.width)
        form.onChange = { [weak self] in self?.applyEdits($0) }
        form.onChooseFolder = { form in
            guard let url = SettingsSupport.chooseDirectory(message: L("project.choose.ddev")) else { return }
            // Said plainly rather than refused: the folder may be right and the project not set
            // up yet, and that is the user's business.
            form.setFolderNote(DDEVConfig.isProject(url) ? "" : L("ddev.noConfig"), isError: true)
            form.setFolder(url.path)
        }
        form.onTestLink = { [weak self] in self?.testLink($0) }
        container.addSubview(form)
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
                alert.messageText = entries.isEmpty ? L("ddev.none.title") : L("ddev.all.title")
                alert.informativeText = entries.isEmpty ? L("ddev.none.detail") : L("ddev.all.detail")
                alert.addButton(withTitle: L("button.ok"))
                alert.runModal()
                return
            }

            let alert = NSAlert()
            alert.messageText = L("ddev.add.title")
            alert.informativeText = L("ddev.add.detail")
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 25))
            for candidate in candidates {
                popUp.addItem(withTitle: "\(candidate.name) (\(candidate.state.rawValue))")
            }
            alert.accessoryView = popUp
            alert.addButton(withTitle: L("button.add"))
            alert.addButton(withTitle: L("button.cancel"))
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
              SettingsSupport.confirm(L("settings.remove.account.title", project.displayTitle), detail: L("settings.remove.project.detail.ddev"))
        else { return false }
        store.save(store.projects().filter { $0.id != id })
        return true
    }

    private func presentUnavailable() {
        let alert = NSAlert()
        alert.messageText = L("ddev.silent.title")
        alert.informativeText = L("ddev.silent.detail")
        alert.addButton(withTitle: L("button.ok"))
        alert.runModal()
    }

    private func applyEdits(_ form: DDEVProjectForm) {
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
    }

    private func testLink(_ form: DDEVProjectForm) {
        let project = form.editedProject
        Task { [weak self] in
            guard let self else { return }
            let entries = await self.environment.list()
            let status = self.environment.status(for: project, entries: entries)
            guard let link = project.links(status: status).first else {
                form.setLinkNote(L("ddev.noURL"), isError: true)
                return
            }
            form.setLinkNote("", isError: false)
            LinkOpener.open(link.url, using: project.browser)
        }
    }
}
