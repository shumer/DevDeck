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
        controller.runtime.settingsItems(.ddev)
    }

    func buildForm(for id: String, in container: FlippedContainer) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }) else { return false }
        let form = DDEVProjectForm(project: project, width: container.bounds.width)
        form.onChange = { [weak self] in self?.applyEdits($0) }
        form.onChooseFolder = { [controller] form in
            guard let url = SettingsSupport.chooseDirectory(message: L("project.choose.ddev")) else { return }
            form.setFolderNote(controller.runtime.ddevFolderNote(url) ?? "", isError: true)
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
            let candidates: [DDEVListEntry]
            switch await self.controller.runtime.ddevCandidates() {
            case .unavailable:
                self.presentUnavailable()
                return
            case .none:
                self.present(L("ddev.none.title"), L("ddev.none.detail"))
                return
            case .allAdded:
                self.present(L("ddev.all.title"), L("ddev.all.detail"))
                return
            case .some(let found):
                candidates = found
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
            let id = self.controller.runtime.addDDEVProject(candidates[index])
            self.host?.select(self.kind, id: id)
            self.host?.changed()
        }
        return nil
    }

    func remove(_ id: String) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }),
              SettingsSupport.confirm(L("settings.remove.account.title", project.displayTitle), detail: L("settings.remove.project.detail.ddev"))
        else { return false }
        controller.runtime.removeDDEVProject(id)
        return true
    }

    private func present(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: L("button.ok"))
        alert.runModal()
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
        controller.runtime.saveDDEVProject(edited)
        form.apply(edited)
        host?.reloadList()
        host?.changed()
    }

    private func testLink(_ form: DDEVProjectForm) {
        let project = form.editedProject
        Task { [controller] in
            LinkOpener.open(await controller.runtime.testLink(project)) { form.setLinkNote($0, isError: !$0.isEmpty) }
        }
    }
}
