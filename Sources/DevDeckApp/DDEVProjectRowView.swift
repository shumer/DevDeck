import AppKit
import DDEVKit
import DevDeckCore

/// The form for one DDEV project.
///
/// Much shorter than the Arc one on purpose: DDEV knows the name, the type, the URLs and the
/// state, so the only things worth asking about are the folder, what to call it, and where its
/// links should open.
@MainActor
final class DDEVProjectRowView: FlippedContainer {
    private(set) var project: DDEVProject

    private let titleField = NSTextField()
    private let folderField = NSTextField()
    private let enabledButton = NSButton()
    private let mailpitButton = NSButton()
    private let xhguiButton = NSButton()
    private let browserPopUp = NSPopUpButton()
    private let profilePopUp = NSPopUpButton()
    private var linkChecks: [NSButton] = []
    private var linkFields: [NSTextField] = []
    private let statusLabel = NSTextField(labelWithString: "")

    private var browsers: [InstalledBrowser] = []
    private var profiles: [BrowserProfile] = []

    var onChange: ((DDEVProjectRowView) -> Void)?
    var onTestLink: ((DDEVProjectRowView) -> Void)?
    var onChooseFolder: ((DDEVProjectRowView) -> Void)?

    init(project: DDEVProject, width: CGFloat) {
        self.project = project
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        let form = FormLayout(in: self)

        form.beginGroup()
        titleField.stringValue = project.title
        titleField.placeholderString = project.name
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
        form.endGroup()
        form.footnote("The DDEV name is \(project.name). Its type, URLs and state come from DDEV "
            + "itself; PHP and database versions are read from .ddev/config.yaml.")

        form.header("Links on the card")
        form.beginGroup()
        mailpitButton.setButtonType(.switch)
        mailpitButton.title = "Mailpit"
        mailpitButton.state = project.showsMailpit ? .on : .off
        mailpitButton.target = self
        mailpitButton.action = #selector(controlChanged)

        xhguiButton.setButtonType(.switch)
        xhguiButton.title = "xhgui"
        xhguiButton.state = project.showsXhgui ? .on : .off
        xhguiButton.target = self
        xhguiButton.action = #selector(controlChanged)
        form.row("Tools", [(mailpitButton, 90), (xhguiButton, nil)], height: 20)

        for link in project.customLinks {
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
        form.footnote("The local site comes from DDEV. The deployed ones live on their own "
            + "domains, so there is nothing to derive them from.")

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

    var editedProject: DDEVProject {
        var edited = project
        edited.title = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        let folder = folderField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.folder = folder.isEmpty ? nil : folder
        edited.isEnabled = enabledButton.state == .on
        edited.showsMailpit = mailpitButton.state == .on
        edited.showsXhgui = xhguiButton.state == .on
        edited.browser = selectedBrowserChoice

        edited.customLinks = zip(project.customLinks.indices, project.customLinks).map { index, link in
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

    func apply(_ project: DDEVProject) {
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

extension DDEVProjectRowView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        onChange?(self)
    }
}
