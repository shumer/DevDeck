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

    /// Tall enough for what the layout above places: a title row, the folder, the link
    /// toggles, the browser pickers and a status line.
    static let height: CGFloat = 212

    init(project: DDEVProject, width: CGFloat) {
        self.project = project
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))

        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.35).cgColor
        layer?.cornerRadius = 8

        let layout = RowLayout(in: self)

        titleField.stringValue = project.title
        titleField.placeholderString = project.name
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

        layout.row(
            [(titleField, nil), (enabledButton, 90), (removeButton, 80)],
            height: 24,
            gap: 4
        )
        layout.caption("DDEV name — \(project.name); the type, URLs and state come from DDEV itself", gap: 10)

        layout.caption("Project folder")
        folderField.stringValue = project.folder ?? ""
        folderField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        folderField.placeholderString = "~/Projects/…"
        folderField.delegate = self

        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded
        chooseButton.controlSize = .small
        layout.row([(folderField, nil), (chooseButton, 80)], height: 24, gap: 12)

        layout.caption("Links on the card — the site itself is always there")
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
        layout.row([(mailpitButton, 100), (xhguiButton, 100)], height: 20, gap: 12)

        layout.caption("Open links in")
        browserPopUp.target = self
        browserPopUp.action = #selector(browserChanged)
        profilePopUp.target = self
        profilePopUp.action = #selector(controlChanged)

        let testButton = NSButton(title: "Test", target: self, action: #selector(testLink))
        testButton.bezelStyle = .rounded
        testButton.controlSize = .small
        layout.row([(browserPopUp, nil), (profilePopUp, nil), (testButton, 52)], height: 24, gap: 10)

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
