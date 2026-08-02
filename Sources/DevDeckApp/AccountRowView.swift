import AppKit
import DevDeckCore
import GitHubKit

/// One account in the settings window: what it is called, which organisations it covers, where
/// its links open, and a field for its token.
///
/// The token field is always empty on screen. A stored secret is never written back into the
/// UI — the row says whether one exists, and typing replaces it.
@MainActor
final class AccountRowView: NSView {
    private(set) var account: GitHubAccount

    private let labelField = NSTextField()
    private let organizationsField = NSTextField()
    private let tokenField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let enabledButton = NSButton()
    private let browserPopUp = NSPopUpButton()
    private let profilePopUp = NSPopUpButton()

    private var browsers: [InstalledBrowser] = []
    private var profiles: [BrowserProfile] = []

    var onSave: ((AccountRowView) -> Void)?
    var onRemove: ((AccountRowView) -> Void)?
    /// Fired by everything except the token field, which needs an explicit press because it
    /// gets verified against the API first.
    ///
    /// Editing a control and having nothing happen is how the browser choice silently did not
    /// apply: the only way to commit it was a button labelled as being about the token.
    var onChange: ((AccountRowView) -> Void)?
    var onTestLink: ((AccountRowView) -> Void)?

    static let height: CGFloat = 170

    init(account: GitHubAccount, hasToken: Bool, width: CGFloat) {
        self.account = account
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))

        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.35).cgColor
        layer?.cornerRadius = 8

        let inset: CGFloat = 12
        let fieldWidth = width - inset * 2

        labelField.frame = NSRect(x: inset, y: Self.height - 34, width: 200, height: 22)
        labelField.stringValue = account.label
        labelField.placeholderString = "Account name"
        labelField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        addSubview(labelField)

        labelField.delegate = self

        enabledButton.frame = NSRect(x: inset + 212, y: Self.height - 33, width: 90, height: 20)
        enabledButton.setButtonType(.switch)
        enabledButton.title = "Enabled"
        enabledButton.state = account.isEnabled ? .on : .off
        enabledButton.target = self
        enabledButton.action = #selector(controlChanged)
        addSubview(enabledButton)

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(remove))
        removeButton.frame = NSRect(x: width - inset - 80, y: Self.height - 36, width: 80, height: 24)
        removeButton.bezelStyle = .rounded
        removeButton.controlSize = .small
        addSubview(removeButton)

        organizationsField.frame = NSRect(x: inset, y: Self.height - 64, width: fieldWidth, height: 22)
        organizationsField.stringValue = account.organizations.joined(separator: ", ")
        organizationsField.placeholderString = "Organisations, comma separated (empty = everything the token sees)"
        organizationsField.font = NSFont.systemFont(ofSize: 11)
        organizationsField.delegate = self
        addSubview(organizationsField)

        tokenField.frame = NSRect(x: inset, y: Self.height - 94, width: fieldWidth - 100, height: 22)
        tokenField.placeholderString = hasToken
            ? "Token stored — type to replace it"
            : "github_pat_… or ghp_…"
        tokenField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        addSubview(tokenField)

        let saveButton = NSButton(title: "Verify token", target: self, action: #selector(save))
        saveButton.frame = NSRect(x: width - inset - 92, y: Self.height - 96, width: 92, height: 26)
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .small
        addSubview(saveButton)

        let openLabel = NSTextField(labelWithString: "Open links in")
        openLabel.frame = NSRect(x: inset, y: Self.height - 118, width: 200, height: 16)
        openLabel.font = NSFont.systemFont(ofSize: 10)
        openLabel.textColor = NSColor.secondaryLabelColor
        addSubview(openLabel)

        let popUpWidth = (fieldWidth - 70) / 2
        browserPopUp.frame = NSRect(x: inset, y: Self.height - 144, width: popUpWidth, height: 24)
        browserPopUp.target = self
        browserPopUp.action = #selector(browserChanged)
        addSubview(browserPopUp)

        profilePopUp.frame = NSRect(x: inset + popUpWidth + 8, y: Self.height - 144, width: popUpWidth, height: 24)
        profilePopUp.target = self
        profilePopUp.action = #selector(controlChanged)
        addSubview(profilePopUp)

        // Opening one link is the only honest way to know the mapping works, so it is one
        // click away rather than something to discover by clicking a pull request.
        let testButton = NSButton(title: "Test", target: self, action: #selector(testLink))
        testButton.frame = NSRect(x: inset + popUpWidth * 2 + 16, y: Self.height - 145, width: 50, height: 25)
        testButton.bezelStyle = .rounded
        testButton.controlSize = .small
        addSubview(testButton)

        statusLabel.frame = NSRect(x: inset, y: 8, width: fieldWidth, height: 18)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.stringValue = hasToken ? "Token stored." : "No token yet."
        addSubview(statusLabel)

        loadBrowsers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — this view is built in code")
    }

    // MARK: Browser pickers

    private func loadBrowsers() {
        browsers = BrowserCatalog.installedBrowsers()

        browserPopUp.removeAllItems()
        browserPopUp.addItem(withTitle: "Default browser")
        for browser in browsers {
            browserPopUp.addItem(withTitle: browser.name)
        }

        if let identifier = account.browser.bundleIdentifier,
           let index = browsers.firstIndex(where: { $0.bundleIdentifier == identifier.lowercased() }) {
            browserPopUp.selectItem(at: index + 1)
        } else {
            browserPopUp.selectItem(at: 0)
        }

        reloadProfiles(selecting: account.browser.profileDirectory)
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
            // Safari and Firefox cannot be told which profile to use from outside, so the
            // picker says so rather than offering a control that would do nothing.
            profilePopUp.addItem(withTitle: selectedBrowser == nil ? "—" : "not supported")
            profilePopUp.isEnabled = false
            return
        }

        profiles = BrowserCatalog.profiles(for: browser.bundleIdentifier)
        profilePopUp.isEnabled = !profiles.isEmpty
        profilePopUp.addItem(withTitle: profiles.isEmpty ? "not launched yet" : "Whatever it opens")
        for profile in profiles {
            profilePopUp.addItem(withTitle: profile.name)
        }

        if let directory, let index = profiles.firstIndex(where: { $0.directory == directory }) {
            profilePopUp.selectItem(at: index + 1)
        } else {
            profilePopUp.selectItem(at: 0)
        }
    }

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

    private var selectedBrowserChoice: BrowserChoice {
        guard let browser = selectedBrowser else { return .systemDefault }
        let profileIndex = profilePopUp.indexOfSelectedItem - 1
        let profile = (profileIndex >= 0 && profileIndex < profiles.count)
            ? profiles[profileIndex].directory
            : nil
        return BrowserChoice(bundleIdentifier: browser.bundleIdentifier, profileDirectory: profile)
    }

    // MARK: Editing

    /// The account as edited, without touching the identifier the token is filed under.
    var editedAccount: GitHubAccount {
        var edited = account
        edited.label = labelField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
            ? account.label
            : labelField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.organizations = organizationsField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        edited.isEnabled = enabledButton.state == .on
        edited.browser = selectedBrowserChoice
        return edited
    }

    /// Empty when the user did not type a new one, which means "keep what is stored".
    var enteredToken: String {
        tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func apply(_ account: GitHubAccount) {
        self.account = account
    }

    func clearTokenField() {
        tokenField.stringValue = ""
    }

    func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? NSColor.systemRed : NSColor.secondaryLabelColor
    }

    @objc private func save() {
        onSave?(self)
    }

    @objc private func remove() {
        onRemove?(self)
    }
}

extension AccountRowView: NSTextFieldDelegate {
    /// Text edits commit when the field is left, so a typed name or organisation list does not
    /// need a button either.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field !== tokenField else { return }
        onChange?(self)
    }
}
