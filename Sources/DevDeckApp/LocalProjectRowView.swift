import AppKit
import DevDeckCore
import ProjectKit

/// The form for one plain project.
///
/// The longest of the project forms, and unavoidably so: an Arc or DDEV project is described by
/// its own tooling, while this one is described only by what is typed here. What the redesign
/// changed is where the words are. The three questions — where is it, how does it start, how do
/// we know it worked — are now group headers, the paragraphs that used to explain the switches
/// sit under those switches one line each, and the answer to the third question is a live row
/// showing what the health check just returned rather than a description of how it would.
@MainActor
final class LocalProjectRowView: FlippedContainer {
    private(set) var project: LocalProject

    private let titleField = NSTextField()
    private let subtitleField = NSTextField()
    private let folderField = NSTextField()
    private let enabledButton = NSButton()
    private let startField = NSTextField()
    private let stopField = NSTextField()
    private let holdsButton = NSButton()
    private let dockerButton = NSButton()
    private let healthField = NSTextField()
    private let siteField = NSTextField()
    private let browserPopUp = NSPopUpButton()
    private let profilePopUp = NSPopUpButton()
    private var linkChecks: [NSButton] = []
    private var linkFields: [NSTextField] = []
    private let statusLabel = NSTextField(labelWithString: "")

    private var browsers: [InstalledBrowser] = []
    private var profiles: [BrowserProfile] = []

    var onChange: ((LocalProjectRowView) -> Void)?
    var onTestLink: ((LocalProjectRowView) -> Void)?
    var onChooseFolder: ((LocalProjectRowView) -> Void)?
    var onDetect: ((LocalProjectRowView) -> Void)?
    var onCheckHealth: ((LocalProjectRowView) -> Void)?
    var onOpenLink: ((LocalProjectRowView, Int) -> Void)?

    init(project: LocalProject, status: LocalProjectStatus, width: CGFloat) {
        self.project = project
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        let form = FormLayout(in: self)

        enabledButton.setButtonType(.switch)
        enabledButton.title = ""
        enabledButton.state = project.isEnabled ? .on : .off
        enabledButton.target = self
        enabledButton.action = #selector(controlChanged)
        form.formHeader(
            title: project.displayTitle,
            subtitle: project.folder,
            accessory: (label: "Show card", view: enabledButton)
        )

        form.beginGroup()
        titleField.stringValue = project.title
        titleField.placeholderString = project.folderURL?.lastPathComponent ?? "Project"
        titleField.delegate = self
        form.row("Name", [(titleField, nil)])

        folderField.stringValue = project.folder ?? ""
        folderField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        folderField.placeholderString = "~/Projects/…"
        folderField.delegate = self
        form.row("Folder", [(folderField, nil), (button("Choose…", #selector(chooseFolder)), 84)])

        subtitleField.stringValue = project.subtitle
        subtitleField.placeholderString = "what it is — vite, docker compose"
        subtitleField.delegate = self
        form.row("Card footer", [(subtitleField, nil)])
        form.endGroup()

        form.header("How it starts")
        form.beginGroup()
        startField.stringValue = project.startCommand
        startField.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        startField.placeholderString = "docker compose up -d"
        startField.delegate = self
        form.commandRow(
            "Start command",
            field: startField,
            accessory: button("Detect", #selector(detect), tooltip: "Read the folder and fill these in"),
            isRequired: true
        )

        stopField.stringValue = project.stopCommand
        stopField.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        stopField.placeholderString = "optional — DevDeck kills what it started"
        stopField.delegate = self
        form.commandRow("Stop command", field: stopField)

        holdsButton.setButtonType(.switch)
        holdsButton.title = ""
        holdsButton.state = project.holdsProcess ? .on : .off
        holdsButton.target = self
        holdsButton.action = #selector(controlChanged)
        form.toggleRow(
            holdsButton,
            title: "The command keeps running",
            subtitle: "Started in the background, output to a log, Stop kills it and its children."
        )

        dockerButton.setButtonType(.switch)
        dockerButton.title = ""
        dockerButton.state = project.requiresDocker ? .on : .off
        dockerButton.target = self
        dockerButton.action = #selector(controlChanged)
        form.toggleRow(
            dockerButton,
            title: "Needs Docker",
            subtitle: "The card says so instead of offering a Start that cannot work."
        )
        form.endGroup()

        form.header("How the app knows it is up")
        form.beginGroup()
        healthField.stringValue = project.healthURL
        healthField.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        healthField.placeholderString = "http://localhost:3000"
        healthField.delegate = self
        form.commandRow("Health URL", field: healthField)

        siteField.stringValue = project.localSiteURL
        siteField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        siteField.placeholderString = "empty — same as the health URL"
        siteField.delegate = self
        form.row("Local site", [(siteField, nil)])

        form.liveRow(
            color: Self.colour(for: status),
            title: Self.title(for: status),
            detail: Self.detail(for: status, project: project),
            accessory: button("Check now", #selector(checkHealth))
        )
        form.endGroup()
        form.footnote("Up means the URL answered 2xx, 3xx, 401 or 403. A 404 or a 500 does not "
            + "count: a local port is shared, and somebody else's server answering it is how a "
            + "project nobody started reads as running. With it empty only a process started "
            + "from here can be reported on.")

        form.header("Links on the card")
        form.beginGroup()
        for (index, link) in project.links.enumerated() {
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(controlChanged))
            check.state = link.isEnabled ? .on : .off
            linkChecks.append(check)

            let address = NSTextField()
            address.stringValue = link.urlTemplate
            address.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            address.placeholderString = "https://…"
            address.delegate = self
            linkFields.append(address)

            let open = button("Open", #selector(openLink(_:)))
            open.tag = index
            open.isEnabled = !link.urlTemplate.isEmpty

            form.linkRow(
                check,
                tag: link.label,
                tint: Self.tint(for: link.label),
                field: address,
                open: open
            )
        }
        form.endGroup()

        form.header("Open links in")
        form.beginGroup()
        browserPopUp.target = self
        browserPopUp.action = #selector(browserChanged)
        profilePopUp.target = self
        profilePopUp.action = #selector(controlChanged)
        form.row("Browser", [
            (browserPopUp, nil),
            (profilePopUp, nil),
            (button("Test", #selector(testLink)), 56),
        ])
        form.note(statusLabel)
        form.endGroup()

        frame.size.height = form.usedHeight
        loadBrowsers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — this view is built in code")
    }

    private func button(_ title: String, _ action: Selector, tooltip: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.toolTip = tooltip
        return button
    }

    // MARK: The live row

    /// The card's own colours, so the form and the deck agree at a glance.
    private static func colour(for status: LocalProjectStatus) -> NSColor {
        switch status.state {
        case .running: return .systemGreen
        case .starting, .working: return .systemOrange
        case .stopped, .unavailable: return .tertiaryLabelColor
        }
    }

    private static func title(for status: LocalProjectStatus) -> String {
        switch status.state {
        case .running: return "running"
        case .starting: return "starting"
        case .working: return "working"
        case .stopped: return "stopped"
        case .unavailable: return "not configured"
        }
    }

    private static func detail(for status: LocalProjectStatus, project: LocalProject) -> String {
        if let detail = status.detail { return detail }
        guard let checkedAt = status.checkedAt else { return "not checked yet" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        let source = project.healthCheckURL?.absoluteString ?? "no health URL"
        return "\(source) · \(formatter.string(from: checkedAt))"
    }

    private static func tint(for label: String) -> NSColor {
        label.lowercased().contains("prod") ? .systemOrange : .systemPurple
    }

    // MARK: Editing

    var editedProject: LocalProject {
        var edited = project
        edited.title = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.subtitle = subtitleField.stringValue.trimmingCharacters(in: .whitespaces)
        let folder = folderField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.folder = folder.isEmpty ? nil : folder
        edited.isEnabled = enabledButton.state == .on
        edited.startCommand = startField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.stopCommand = stopField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.holdsProcess = holdsButton.state == .on
        edited.requiresDocker = dockerButton.state == .on
        edited.healthURL = healthField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.localSiteURL = siteField.stringValue.trimmingCharacters(in: .whitespaces)
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

        return edited
    }

    func apply(_ project: LocalProject) {
        self.project = project
    }

    func setFolder(_ path: String) {
        folderField.stringValue = path
        onChange?(self)
    }

    /// Fills the command fields in from what the folder looks like. Only ever called from the
    /// Detect button, so a guess never overwrites something the user typed by surprise.
    func applySuggestion(_ suggestion: ProjectSuggestion) {
        startField.stringValue = suggestion.startCommand
        stopField.stringValue = suggestion.stopCommand
        holdsButton.state = suggestion.holdsProcess ? .on : .off
        dockerButton.state = suggestion.requiresDocker ? .on : .off
        if subtitleField.stringValue.isEmpty { subtitleField.stringValue = suggestion.subtitle }
        if healthField.stringValue.isEmpty { healthField.stringValue = suggestion.healthURL }
        onChange?(self)
    }

    func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? NSColor.systemRed : NSColor.secondaryLabelColor
    }

    /// The URL of one of the environment rows, for its Open button.
    func linkURL(at index: Int) -> URL? {
        guard index >= 0, index < linkFields.count else { return nil }
        return URL(string: linkFields[index].stringValue.trimmingCharacters(in: .whitespaces))
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

    @objc private func detect() {
        onDetect?(self)
    }

    @objc private func checkHealth() {
        onCheckHealth?(self)
    }

    @objc private func openLink(_ sender: NSButton) {
        onOpenLink?(self, sender.tag)
    }
}

extension LocalProjectRowView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        onChange?(self)
    }
}
