import AppKit
import ArcKit
import DevDeckCore

/// One Arc project in the settings window.
///
/// Everything here applies as it is edited, like the account rows — a control that waits for
/// a button nobody presses is how the browser choice failed to take effect the first time.
@MainActor
final class ProjectRowView: NSView {
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
    var onRemove: ((ProjectRowView) -> Void)?
    var onTestLink: ((ProjectRowView) -> Void)?
    var onChooseFolder: ((ProjectRowView) -> Void)?

    static func height(for project: ArcProject) -> CGFloat {
        // Fixed block plus one line per link template.
        302 + CGFloat(project.links.count) * 26
    }

    init(project: ArcProject, width: CGFloat) {
        self.project = project
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height(for: project)))

        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.35).cgColor
        layer?.cornerRadius = 8

        let inset: CGFloat = 12
        let full = width - inset * 2
        var y = bounds.height - 34

        func label(_ text: String, _ top: CGFloat, x: CGFloat = inset, width: CGFloat = 200) {
            let field = NSTextField(labelWithString: text)
            field.frame = NSRect(x: x, y: top, width: width, height: 15)
            field.font = NSFont.systemFont(ofSize: 10)
            field.textColor = NSColor.secondaryLabelColor
            addSubview(field)
        }

        func configure(_ field: NSTextField, mono: Bool = false, placeholder: String = "") {
            field.font = mono
                ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                : NSFont.systemFont(ofSize: 12)
            field.placeholderString = placeholder
            field.delegate = self
            addSubview(field)
        }

        // Identity.
        titleField.frame = NSRect(x: inset, y: y, width: 190, height: 22)
        titleField.stringValue = project.title
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleField.delegate = self
        addSubview(titleField)

        enabledButton.frame = NSRect(x: inset + 200, y: y + 1, width: 90, height: 20)
        enabledButton.setButtonType(.switch)
        enabledButton.title = "Enabled"
        enabledButton.state = project.isEnabled ? .on : .off
        enabledButton.target = self
        enabledButton.action = #selector(controlChanged)
        addSubview(enabledButton)

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(remove))
        removeButton.frame = NSRect(x: width - inset - 80, y: y - 2, width: 80, height: 24)
        removeButton.bezelStyle = .rounded
        removeButton.controlSize = .small
        addSubview(removeButton)

        y -= 30
        label("Organisation", y + 22, width: 140)
        organizationField.frame = NSRect(x: inset, y: y, width: (full - 10) / 2, height: 22)
        organizationField.stringValue = project.organization
        configure(organizationField, placeholder: "editoriaitaliana")

        label("Site id (optional)", y + 22, x: inset + (full - 10) / 2 + 10, width: 140)
        siteField.frame = NSRect(x: inset + (full - 10) / 2 + 10, y: y, width: (full - 10) / 2, height: 22)
        siteField.stringValue = project.site ?? ""
        configure(siteField, placeholder: "ilgiornale")

        // Links.
        y -= 34
        label("Links on the card — {org} and {site} are substituted", y + 20, width: full)
        for link in project.links {
            y -= 26
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(controlChanged))
            check.frame = NSRect(x: inset, y: y + 2, width: 18, height: 18)
            check.state = link.isEnabled ? .on : .off
            addSubview(check)
            linkChecks.append(check)

            let name = NSTextField(labelWithString: link.label)
            name.frame = NSRect(x: inset + 20, y: y + 3, width: 86, height: 16)
            name.font = NSFont.systemFont(ofSize: 11)
            addSubview(name)

            let template = NSTextField()
            template.frame = NSRect(x: inset + 110, y: y, width: full - 110, height: 21)
            template.stringValue = link.urlTemplate
            // The site links ship empty because nothing can derive a published domain.
            configure(template, mono: true, placeholder: "https://…")
            linkFields.append(template)
        }

        // Browser.
        y -= 34
        label("Open links in", y + 22, width: full)
        let popUpWidth = (full - 70) / 2
        browserPopUp.frame = NSRect(x: inset, y: y, width: popUpWidth, height: 24)
        browserPopUp.target = self
        browserPopUp.action = #selector(browserChanged)
        addSubview(browserPopUp)

        profilePopUp.frame = NSRect(x: inset + popUpWidth + 8, y: y, width: popUpWidth, height: 24)
        profilePopUp.target = self
        profilePopUp.action = #selector(controlChanged)
        addSubview(profilePopUp)

        let testButton = NSButton(title: "Test", target: self, action: #selector(testLink))
        testButton.frame = NSRect(x: inset + popUpWidth * 2 + 16, y: y - 1, width: 50, height: 25)
        testButton.bezelStyle = .rounded
        testButton.controlSize = .small
        addSubview(testButton)

        // Local stack.
        y -= 34
        label("Project folder", y + 22, width: full)
        folderField.frame = NSRect(x: inset, y: y, width: full - 86, height: 22)
        folderField.stringValue = project.folder ?? ""
        configure(folderField, mono: true, placeholder: "~/Projects/…")

        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseButton.frame = NSRect(x: width - inset - 78, y: y - 1, width: 78, height: 25)
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .small
        addSubview(chooseButton)

        y -= 32
        label("Start", y + 22, width: 100)
        startField.frame = NSRect(x: inset, y: y, width: (full - 10) / 2, height: 22)
        startField.stringValue = project.startCommand
        configure(startField, mono: true)

        label("Stop", y + 22, x: inset + (full - 10) / 2 + 10, width: 100)
        stopField.frame = NSRect(x: inset + (full - 10) / 2 + 10, y: y, width: (full - 10) / 2, height: 22)
        stopField.stringValue = project.stopCommand
        configure(stopField, mono: true)

        y -= 32
        label("Local URL — empty reads PORT from the project's .env", y + 22, width: 260)
        localURLField.frame = NSRect(x: inset, y: y, width: (full - 10) / 2, height: 22)
        localURLField.stringValue = project.localURL
        configure(localURLField, mono: true, placeholder: EnvFile.localURL(in: project.folderURL))

        label("Health path", y + 22, x: inset + (full - 10) / 2 + 10, width: 100)
        healthField.frame = NSRect(x: inset + (full - 10) / 2 + 10, y: y, width: (full - 10) / 2, height: 22)
        healthField.stringValue = project.healthPath
        configure(healthField, mono: true, placeholder: "/release")

        statusLabel.frame = NSRect(x: inset, y: 8, width: full, height: 16)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        addSubview(statusLabel)

        loadBrowsers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — this view is built in code")
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
            profilePopUp.addItem(withTitle: selectedBrowser == nil ? "—" : "not supported")
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

    @objc private func remove() {
        onRemove?(self)
    }
}

extension ProjectRowView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        onChange?(self)
    }
}
