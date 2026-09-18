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

    var menuGroup: String? { L("menu.group.arc") }

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
            isShowingLogs: controller.isShowingLogs(card),
            isCollapsed: controller.isCollapsed(card),
            // Where the site is served is read from the checkout's `.env`, and the stack says
            // whether it is up.
            phoneURL: controller.phoneURL(for: status.siteURL ?? project.localSiteURL, isRunning: status.isRunning),
            onOpen: { LinkOpener.open($0, using: project.browser) },
            onAction: { [controller] in controller.perform($0, for: project) },
            onRevealFolder: { LocalFolder.reveal(project.folderURL) },
            onOpenTerminal: { LocalFolder.openTerminal(project.folderURL) },
            onStartDocker: context.startDocker,
            onToggleLogs: { [controller] in controller.toggleLogs(for: card) }
        ))
    }

    func size(for card: CardID) -> NSSize {
        guard let project = store.project(forCard: card) else {
            return NSSize(width: CardMetrics.width, height: 150)
        }
        return ArcProjectCard.size(
            for: project,
            status: controller.stackStatus(for: project),
            isCollapsed: controller.isCollapsed(card)
        )
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
        store.projects().map { project in
            let live = controller.stackStatus(for: project).state
            return SettingsListItem(
                id: project.id,
                title: project.title,
                detail: project.organization.isEmpty ? "Arc XP" : "Arc XP · \(project.organization)",
                icon: SettingsIcons.mark(.arc),
                dot: live == .running ? .systemGreen : (live == .working ? .systemOrange : nil),
                isDimmed: !project.isEnabled
            )
        }
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
        form.onTestLink = { form in
            let project = form.editedProject
            guard let link = project.resolvedLinks.first else {
                form.setLinkNote(L("project.link.noneEnabled"), isError: true)
                return
            }
            form.setLinkNote("", isError: false)
            LinkOpener.open(link.url, using: project.browser)
        }
        form.onToggleAdvanced = { [weak self] in self?.host?.toggle(fold) }
        form.onStructureChange = { [weak self] _, project in
            guard let self else { return }
            var projects = self.store.projects()
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index] = project
                self.store.save(projects)
            }
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
        var projects = store.projects()
        let id = ArcProject.makeID(from: "project", existing: projects.map(\.id))
        projects.append(ArcProject(id: id, title: L("project.new.title"), organization: ""))
        store.save(projects)
        host?.changed()
        return id
    }

    func remove(_ id: String) -> Bool {
        guard let project = store.projects().first(where: { $0.id == id }),
              SettingsSupport.confirm(L("settings.remove.account.title", project.title), detail: L("settings.remove.project.detail.arc"))
        else { return false }
        store.save(store.projects().filter { $0.id != id })
        return true
    }

    /// What the stack check asks: the folder and the address it resolves to.
    private static func address(of project: ArcProject) -> String {
        "\(project.folder ?? "")|\(project.effectiveLocalURL)|\(project.healthPath)"
    }

    private func applyEdits(_ form: ArcProjectForm) {
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
        if let before, Self.address(of: before) != Self.address(of: edited), edited.supportsLocalStack {
            checkStack(edited)
        }
    }

    private func checkStack(_ project: ArcProject) {
        guard project.supportsLocalStack else {
            form?.stack.update(CheckSummary(tone: .idle, state: L("project.notConfigured"), detail: L("project.notConfigured.detail")))
            return
        }
        form?.stack.update(.checking)
        Task { [weak self] in
            guard let self else { return }
            let status = await LocalStackService(project: project).status()
            let address = Self.address(of: project)
            self.checks[project.id] = (status, address)
            guard let form = self.form, form.project.id == project.id else { return }
            form.stack.update(status.summary(checkedAddress: address, currentAddress: Self.address(of: form.editedProject)))
        }
    }
}
