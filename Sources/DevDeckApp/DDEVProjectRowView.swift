import AppKit
import DDEVKit
import DevDeckCore

/// One DDEV project in the settings window.
///
/// Much shorter than the Arc row on purpose: DDEV knows the name, the type, the URLs and the
/// state, so the only things worth asking about are the folder, what to call it, and where
/// its links should open.
@MainActor
final class DDEVProjectRowView: NSView {
    private(set) var project: DDEVProject

    private let titleField = NSTextField()
    private let folderField = NSTextField()
    private let enabledButton = NSButton()
    private let mailpitButton = NSButton()
    private let xhguiButton = NSButton()
    private let browserPopUp = NSPopUpButton()
    private let profilePopUp = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "")

    private var browsers: [InstalledBrowser] = []
    private var profiles: [BrowserProfile] = []

    var onChange: ((DDEVProjectRowView) -> Void)?
    var onRemove: ((DDEVProjectRowView) -> Void)?
    var onTestLink: ((DDEVProjectRowView) -> Void)?
    var onChooseFolder: ((DDEVProjectRowView) -> Void)?

    static let height: CGFloat = 196

    init(project: DDEVProject, width: CGFloat) {
        self.project = project
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))

        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.35).cgColor
        layer?.cornerRadius = 8

        let inset: CGFloat = 12
        let full = width - inset * 2
        var y = bounds.height - 34

        func label(_ text: String, _ top: CGFloat, x: CGFloat = inset, width: CGFloat = 260) {
            let field = NSTextField(labelWithString: text)
            field.frame = NSRect(x: x, y: top, width: width, height: 15)
            field.font = NSFont.systemFont(ofSize: 10)
            field.textColor = NSColor.secondaryLabelColor
            addSubview(field)
        }

        titleField.frame = NSRect(x: inset, y: y, width: 190, height: 22)
        titleField.stringValue = project.title
        titleField.placeholderString = project.name
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

        y -= 26
        label("DDEV name — \(project.name); everything else comes from the project itself", y, width: full)

        y -= 30
        label("Project folder", y + 22, width: full)
        folderField.frame = NSRect(x: inset, y: y, width: full - 86, height: 22)
        folderField.stringValue = project.folder ?? ""
        folderField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        folderField.placeholderString = "~/Projects/…"
        folderField.delegate = self
        addSubview(folderField)

        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseButton.frame = NSRect(x: width - inset - 78, y: y - 1, width: 78, height: 25)
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .small
        addSubview(chooseButton)

        y -= 28
        label("Links on the card — the site is always there", y + 18, width: full)
        y -= 4
        mailpitButton.frame = NSRect(x: inset, y: y, width: 100, height: 20)
        mailpitButton.setButtonType(.switch)
        mailpitButton.title = "Mailpit"
        mailpitButton.state = project.showsMailpit ? .on : .off
        mailpitButton.target = self
        mailpitButton.action = #selector(controlChanged)
        addSubview(mailpitButton)

        xhguiButton.frame = NSRect(x: inset + 110, y: y, width: 100, height: 20)
        xhguiButton.setButtonType(.switch)
        xhguiButton.title = "xhgui"
        xhguiButton.state = project.showsXhgui ? .on : .off
        xhguiButton.target = self
        xhguiButton.action = #selector(controlChanged)
        addSubview(xhguiButton)

        y -= 32
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

    var editedProject: DDEVProject {
        var edited = project
        edited.title = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        let folder = folderField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.folder = folder.isEmpty ? nil : folder
        edited.isEnabled = enabledButton.state == .on
        edited.showsMailpit = mailpitButton.state == .on
        edited.showsXhgui = xhguiButton.state == .on
        edited.browser = selectedBrowserChoice
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

extension DDEVProjectRowView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        onChange?(self)
    }
}
