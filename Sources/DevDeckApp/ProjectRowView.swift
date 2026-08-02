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

    /// The fixed blocks plus one line per link template. `RowLayout` places from the top
    /// down, so this only has to be generous enough not to clip the last line.
    static func height(for project: ArcProject) -> CGFloat {
        296 + CGFloat(project.links.count) * 26
    }

    init(project: ArcProject, width: CGFloat) {
        self.project = project
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height(for: project)))

        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.35).cgColor
        layer?.cornerRadius = 8

        let layout = RowLayout(in: self)

        func field(_ target: NSTextField, mono: Bool = false, placeholder: String = "") {
            target.font = mono
                ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                : NSFont.systemFont(ofSize: 12)
            target.placeholderString = placeholder
            target.delegate = self
        }

        titleField.stringValue = project.title
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleField.delegate = self

        enabledButton.setButtonType(.switch)
        enabledButton.title = "Enabled"
        enabledButton.state = project.isEnabled ? .on : .off
        enabledButton.target = self
        enabledButton.action = #selector(controlChanged)

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(remove))
        removeButton.bezelStyle = .rounded
        removeButton.controlSize = .small
        layout.row([(titleField, nil), (enabledButton, 90), (removeButton, 80)], height: 24, gap: 10)

        layout.caption("Organisation — includes the environment, such as sandbox.ilgiornale")
        organizationField.stringValue = project.organization
        field(organizationField, placeholder: "sandbox.ilgiornale")
        siteField.stringValue = project.site ?? ""
        field(siteField, placeholder: "site id (optional)")
        layout.row([(organizationField, nil), (siteField, nil)], height: 24, gap: 12)

        layout.caption("Links on the card — {org} and {site} are substituted")
        for link in project.links {
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(controlChanged))
            check.state = link.isEnabled ? .on : .off
            linkChecks.append(check)

            let name = NSTextField(labelWithString: link.label)
            name.font = NSFont.systemFont(ofSize: 11)
            name.lineBreakMode = .byTruncatingTail

            let template = NSTextField()
            template.stringValue = link.urlTemplate
            // The site links ship empty because nothing can derive a published domain.
            field(template, mono: true, placeholder: "https://…")
            linkFields.append(template)

            layout.row([(check, 18), (name, 86), (template, nil)], height: 22, gap: 4, spacing: 4)
        }
        layout.space(8)

        layout.caption("Open links in")
        browserPopUp.target = self
        browserPopUp.action = #selector(browserChanged)
        profilePopUp.target = self
        profilePopUp.action = #selector(controlChanged)
        let testButton = NSButton(title: "Test", target: self, action: #selector(testLink))
        testButton.bezelStyle = .rounded
        testButton.controlSize = .small
        layout.row([(browserPopUp, nil), (profilePopUp, nil), (testButton, 52)], height: 24, gap: 12)

        layout.caption("Project folder")
        folderField.stringValue = project.folder ?? ""
        field(folderField, mono: true, placeholder: "~/Projects/…")
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .small
        layout.row([(folderField, nil), (chooseButton, 80)], height: 24, gap: 12)

        layout.caption("Start and stop commands")
        startField.stringValue = project.startCommand
        field(startField, mono: true)
        stopField.stringValue = project.stopCommand
        field(stopField, mono: true)
        layout.row([(startField, nil), (stopField, nil)], height: 24, gap: 12)

        layout.caption("Local URL — empty reads PORT from the project's .env — and health path")
        localURLField.stringValue = project.localURL
        field(localURLField, mono: true, placeholder: EnvFile.localURL(in: project.folderURL))
        healthField.stringValue = project.healthPath
        field(healthField, mono: true, placeholder: "/release")
        layout.row([(localURLField, nil), (healthField, nil)], height: 24, gap: 10)

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        layout.place(statusLabel, height: 16, gap: 0)

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
