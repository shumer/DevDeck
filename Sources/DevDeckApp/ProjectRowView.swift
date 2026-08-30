import AppKit
import ArcKit
import DevDeckCore

/// The form for one Arc project.
///
/// Everything applies as it is edited — a control that waits for a button nobody presses is
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
    private let statusLabel = NSTextField(labelWithString: "")

    private var browsers: [InstalledBrowser] = []
    private var profiles: [BrowserProfile] = []

    var onChange: ((ProjectRowView) -> Void)?
    var onTestLink: ((ProjectRowView) -> Void)?
    var onChooseFolder: ((ProjectRowView) -> Void)?

    init(project: ArcProject, width: CGFloat) {
        self.project = project
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        func mono(_ field: NSTextField, placeholder: String = "") {
            field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            field.placeholderString = placeholder
            field.delegate = self
        }

        let form = FormLayout(in: self)

        form.beginGroup()
        titleField.stringValue = project.title
        titleField.delegate = self
        form.row("Name", [(titleField, nil)])

        enabledButton.setButtonType(.switch)
        enabledButton.title = "Show a card for this project"
        enabledButton.state = project.isEnabled ? .on : .off
        enabledButton.target = self
        enabledButton.action = #selector(controlChanged)
        form.row("", [(enabledButton, nil)], height: 20)

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
        for link in project.links {
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(controlChanged))
            check.state = link.isEnabled ? .on : .off
            linkChecks.append(check)

            let template = NSTextField()
            template.stringValue = link.urlTemplate
            mono(template, placeholder: "https://…")
            linkFields.append(template)

            form.row(link.label, [(check, 18), (template, nil)], height: 22)
        }
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
        form.row("Start", [(startField, nil)])

        stopField.stringValue = project.stopCommand
        mono(stopField)
        form.row("Stop", [(stopField, nil)])

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
