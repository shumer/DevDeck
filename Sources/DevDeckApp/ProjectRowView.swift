import AppKit
import ArcKit
import DevDeckCore

/// The form for one Arc project.
///
/// Everything applies as it is edited - a control that waits for a button nobody presses is
/// how the browser choice failed to take effect the first time.
@MainActor
final class ProjectRowView: FlippedContainer {
    private(set) var project: ArcProject

    private let titleField = NSTextField()
    private let organizationField = NSTextField()
    private let siteField = NSTextField()
    private let folderField = NSTextField()
    private let startField = NSTextField()
    private let stopField = NSTextField()
    private let localURLField = NSTextField()
    private let healthField = NSTextField()
    private let enabledButton = NSButton()
    private let browserPopUp = NSPopUpButton()
    private let profilePopUp = NSPopUpButton()
    private var linkChecks: [NSButton] = []
    private var linkFields: [NSTextField] = []
    /// One per link, nil where the name is not editable.
    private var labelFields: [NSTextField?] = []
    private let statusLabel = NSTextField(labelWithString: "")

    private var browsers: [InstalledBrowser] = []
    private var profiles: [BrowserProfile] = []

    var onChange: ((ProjectRowView) -> Void)?
    var onTestLink: ((ProjectRowView) -> Void)?
    var onChooseFolder: ((ProjectRowView) -> Void)?
    /// Adding or removing a link changes the shape of the form, not just its values, so the
    /// window has to build it again rather than read it back.
    var onStructureChange: ((ProjectRowView, ArcProject) -> Void)?

    init(project: ArcProject, width: CGFloat) {
        self.project = project
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        func mono(_ field: NSTextField, placeholder: String = "") {
            field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            field.placeholderString = placeholder
            field.delegate = self
        }

        let form = FormLayout(in: self)

        enabledButton.setButtonType(.switch)
        enabledButton.title = ""
        enabledButton.state = project.isEnabled ? .on : .off
        enabledButton.target = self
        enabledButton.action = #selector(controlChanged)
        form.formHeader(
            title: project.title,
            subtitle: project.organization,
            accessory: (label: "Show card", view: enabledButton)
        )

        form.beginGroup()
        titleField.stringValue = project.title
        titleField.delegate = self
        form.row("Name", [(titleField, nil)])

        organizationField.stringValue = project.organization
        organizationField.placeholderString = "sandbox.acme"
        organizationField.delegate = self
        form.row("Organisation", [(organizationField, nil)])

        siteField.stringValue = project.site ?? ""
        siteField.placeholderString = "optional"
        siteField.delegate = self
        form.row("Site id", [(siteField, nil)])
        form.endGroup()
        form.footnote("The organisation carries the environment: sandbox.acme for the sandbox, "
            + "acme for production. Templates add nothing of their own.")

        form.header("Links on the card")
        form.beginGroup()
        let shipped = Set(ArcLink.defaults().map(\.label))
        for (index, link) in project.links.enumerated() {
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(controlChanged))
            check.state = link.isEnabled ? .on : .off
            linkChecks.append(check)

            let template = NSTextField()
            template.stringValue = link.urlTemplate
            mono(template, placeholder: "https://…")
            linkFields.append(template)

            // A link that shipped with the app keeps its name as a caption: renaming one would
            // orphan it at the next migration, which matches links by label. A link somebody
            // added has no such history, so it gets a name field and a way to remove it.
            guard !shipped.contains(link.label) else {
                labelFields.append(nil)
                form.row(link.label, [(check, 18), (template, nil)], height: 22)
                continue
            }

            let name = NSTextField()
            name.stringValue = link.label
            name.placeholderString = "Name"
            name.delegate = self
            labelFields.append(name)

            let remove = NSButton(title: "−", target: self, action: #selector(removeLinkPressed(_:)))
            remove.bezelStyle = .rounded
            remove.controlSize = .small
            remove.tag = index
            form.row("", [(name, 104), (check, 18), (template, nil), (remove, 28)], height: 22)
        }
        let addLink = NSButton(title: "Add a link", target: self, action: #selector(addLinkPressed))
        addLink.bezelStyle = .rounded
        addLink.controlSize = .small
        form.row("", [(addLink, 96)], height: 24)
        form.endGroup()
        form.footnote("{org} and {site} are substituted. Sandbox and Prod ship empty because a "
            + "published site lives on its own domain.")

        form.header("Local stack")
        form.beginGroup()
        folderField.stringValue = project.folder ?? ""
        mono(folderField, placeholder: "~/Projects/…")
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .small
        form.row("Folder", [(folderField, nil), (chooseButton, 84)])

        startField.stringValue = project.startCommand
        mono(startField)
        form.commandRow("Start command", field: startField)

        stopField.stringValue = project.stopCommand
        mono(stopField)
        form.commandRow("Stop command", field: stopField)

        localURLField.stringValue = project.localURL
        mono(localURLField, placeholder: EnvFile.localURL(in: project.folderURL))
        form.row("Local URL", [(localURLField, nil)])

        healthField.stringValue = project.healthPath
        mono(healthField, placeholder: "/release")
        form.row("Health path", [(healthField, nil)])
        form.endGroup()
        form.footnote("Leave the local URL empty and the card reads PORT from the project's .env.")

        form.header("Open links in")
        form.beginGroup()
        browserPopUp.target = self
        browserPopUp.action = #selector(browserChanged)
        profilePopUp.target = self
        profilePopUp.action = #selector(controlChanged)
        let testButton = NSButton(title: "Test", target: self, action: #selector(testLink))
        testButton.bezelStyle = .rounded
        testButton.controlSize = .small
        form.row("Browser", [(browserPopUp, nil), (profilePopUp, nil), (testButton, 56)])
        form.note(statusLabel)
        form.endGroup()

        frame.size.height = form.usedHeight
        loadBrowsers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    // MARK: Editing

    var editedProject: ArcProject {
        var edited = project
        let title = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.title = title.isEmpty ? project.title : title
        edited.organization = organizationField.stringValue.trimmingCharacters(in: .whitespaces)
        let site = siteField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.site = site.isEmpty ? nil : site
        edited.isEnabled = enabledButton.state == .on
        edited.browser = selectedBrowserChoice

        edited.links = zip(project.links.indices, project.links).map { index, link in
            var updated = link
            if index < linkChecks.count { updated.isEnabled = linkChecks[index].state == .on }
            if index < linkFields.count {
                // Taken as typed, including empty: clearing a field has to mean something.
                updated.urlTemplate = linkFields[index].stringValue.trimmingCharacters(in: .whitespaces)
            }
            if index < labelFields.count, let field = labelFields[index] {
                let name = field.stringValue.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { updated.label = name }
            }
            return updated
        }

        let folder = folderField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.folder = folder.isEmpty ? nil : folder
        edited.startCommand = startField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.stopCommand = stopField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.localURL = localURLField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.healthPath = healthField.stringValue.trimmingCharacters(in: .whitespaces)
        return edited
    }

    func apply(_ project: ArcProject) {
        self.project = project
    }

    func setFolder(_ path: String) {
        folderField.stringValue = path
        onChange?(self)
    }

    func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? NSColor.systemRed : NSColor.secondaryLabelColor
    }

    // MARK: Browser pickers

    private func loadBrowsers() {
        browsers = BrowserCatalog.installedBrowsers()
        browserPopUp.removeAllItems()
        browserPopUp.addItem(withTitle: "Default browser")
        for browser in browsers { browserPopUp.addItem(withTitle: browser.name) }

        if let identifier = project.browser.bundleIdentifier,
           let index = browsers.firstIndex(where: { $0.bundleIdentifier == identifier.lowercased() }) {
            browserPopUp.selectItem(at: index + 1)
        } else {
            browserPopUp.selectItem(at: 0)
        }
        reloadProfiles(selecting: project.browser.profileDirectory)
    }

    private var selectedBrowser: InstalledBrowser? {
        let index = browserPopUp.indexOfSelectedItem - 1
        guard index >= 0, index < browsers.count else { return nil }
        return browsers[index]
    }

    private func reloadProfiles(selecting directory: String?) {
        profilePopUp.removeAllItems()
        guard let browser = selectedBrowser, browser.supportsProfiles else {
            profiles = []
            profilePopUp.addItem(withTitle: selectedBrowser == nil ? "none" : "not supported")
            profilePopUp.isEnabled = false
            return
        }
        profiles = BrowserCatalog.profiles(for: browser.bundleIdentifier)
        profilePopUp.isEnabled = !profiles.isEmpty
        profilePopUp.addItem(withTitle: profiles.isEmpty ? "not launched yet" : "Whatever it opens")
        for profile in profiles { profilePopUp.addItem(withTitle: profile.name) }

        if let directory, let index = profiles.firstIndex(where: { $0.directory == directory }) {
            profilePopUp.selectItem(at: index + 1)
        } else {
            profilePopUp.selectItem(at: 0)
        }
    }

    private var selectedBrowserChoice: BrowserChoice {
        guard let browser = selectedBrowser else { return .systemDefault }
        let index = profilePopUp.indexOfSelectedItem - 1
        let profile = (index >= 0 && index < profiles.count) ? profiles[index].directory : nil
        return BrowserChoice(bundleIdentifier: browser.bundleIdentifier, profileDirectory: profile)
    }

    // MARK: Actions

    @objc private func browserChanged() {
        reloadProfiles(selecting: nil)
        onChange?(self)
    }

    /// Adds a link of your own. The model has always carried them; there was simply no way to
    /// make one, so a project with a fourth environment had nowhere to put it.
    @objc private func addLinkPressed() {
        var edited = editedProject
        let existing = Set(edited.links.map(\.label))
        var name = "New link"
        var index = 2
        while existing.contains(name) {
            name = "New link \(index)"
            index += 1
        }
        edited.links.append(ArcLink(label: name, urlTemplate: "", isEnabled: true, kind: .admin))
        onStructureChange?(self, edited)
    }

    @objc private func removeLinkPressed(_ sender: NSButton) {
        var edited = editedProject
        guard sender.tag >= 0, sender.tag < edited.links.count else { return }
        edited.links.remove(at: sender.tag)
        onStructureChange?(self, edited)
    }

    @objc private func controlChanged() {
        onChange?(self)
    }

    @objc private func testLink() {
        onTestLink?(self)
    }

    @objc private func chooseFolder() {
        onChooseFolder?(self)
    }
}

extension ProjectRowView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        onChange?(self)
    }
}
