import AppKit
import DevDeckCore
import ProjectKit

/// The form for one plain project.
///
/// The longest of the three project forms, and unavoidably so: an Arc or DDEV project is
/// described by its own tooling, while this one is described only by what is typed here. The
/// grouping follows the three questions in order — where is it, how does it start, how do we
/// know it worked.
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

    init(project: LocalProject, width: CGFloat) {
        self.project = project
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        let form = FormLayout(in: self)

        form.beginGroup()
        titleField.stringValue = project.title
        titleField.placeholderString = project.folderURL?.lastPathComponent ?? "Project"
        titleField.delegate = self
        form.row("Name", [(titleField, nil)])

        enabledButton.setButtonType(.switch)
        enabledButton.title = "Show a card for this project"
        enabledButton.state = project.isEnabled ? .on : .off
        enabledButton.target = self
        enabledButton.action = #selector(controlChanged)
        form.row("", [(enabledButton, nil)], height: 20)

        folderField.stringValue = project.folder ?? ""
        folderField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        folderField.placeholderString = "~/Projects/…"
        folderField.delegate = self
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .small
        form.row("Folder", [(folderField, nil), (chooseButton, 84)])

        subtitleField.stringValue = project.subtitle
        subtitleField.placeholderString = "what it is — vite, docker compose"
        subtitleField.delegate = self
        form.row("Footer", [(subtitleField, nil)])
        form.endGroup()

        form.header("How it starts")
        form.beginGroup()
        startField.stringValue = project.startCommand
        startField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        startField.placeholderString = "docker compose up -d"
        startField.delegate = self
        let detectButton = NSButton(title: "Detect", target: self, action: #selector(detect))
        detectButton.bezelStyle = .rounded
        detectButton.controlSize = .small
        detectButton.toolTip = "Read the folder and fill these in"
        form.row("Start", [(startField, nil), (detectButton, 66)])

        stopField.stringValue = project.stopCommand
        stopField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        stopField.placeholderString = "empty — kill what was started"
        stopField.delegate = self
        form.row("Stop", [(stopField, nil)])

        holdsButton.setButtonType(.switch)
        holdsButton.title = "The command keeps running"
        holdsButton.state = project.holdsProcess ? .on : .off
        holdsButton.target = self
        holdsButton.action = #selector(controlChanged)
        form.row("", [(holdsButton, nil)], height: 20)

        dockerButton.setButtonType(.switch)
        dockerButton.title = "Needs Docker"
        dockerButton.state = project.requiresDocker ? .on : .off
        dockerButton.target = self
        dockerButton.action = #selector(controlChanged)
        form.row("", [(dockerButton, nil)], height: 20)
        form.endGroup()
        form.footnote("Tick the first one for a command that holds its terminal, such as "
            + "npm run dev: it is started in the background, its output goes to a log the card "
            + "can open, and Stop kills it and everything it spawned. Leave it clear for a "
            + "command that returns on its own, such as docker compose up -d. Tick Needs Docker "
            + "and the card says so instead of offering a Start that cannot work.")

        form.header("How to tell it is up")
        form.beginGroup()
        healthField.stringValue = project.healthURL
        healthField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        healthField.placeholderString = "http://localhost:3000"
        healthField.delegate = self
        form.row("Health URL", [(healthField, nil)])

        siteField.stringValue = project.localSiteURL
        siteField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        siteField.placeholderString = "empty — same as the health URL"
        siteField.delegate = self
        form.row("Local site", [(siteField, nil)])
        form.endGroup()
        form.footnote("Whatever answers this URL decides whether the card says running — which "
            + "is what keeps it honest about a stack you started yourself in a terminal. Any "
            + "answer counts, including a 404. With it empty the card can only report on a "
            + "process it started itself.")

        form.header("Links on the card")
        form.beginGroup()
        for link in project.links {
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(controlChanged))
            check.state = link.isEnabled ? .on : .off
            linkChecks.append(check)

            let address = NSTextField()
            address.stringValue = link.urlTemplate
            address.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            address.placeholderString = "https://…"
            address.delegate = self
            linkFields.append(address)

            form.row(link.label, [(check, 18), (address, nil)], height: 22)
        }
        form.endGroup()

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
        fatalError("init(coder:) is not used — this view is built in code")
    }

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
}

extension LocalProjectRowView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        onChange?(self)
    }
}
