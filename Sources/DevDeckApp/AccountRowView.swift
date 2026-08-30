import AppKit
import DevDeckCore
import GitHubKit

/// The form for one GitHub account.
///
/// The token field is always empty on screen. A stored secret is never written back into the
/// UI — the status line says whether one exists, and typing replaces it.
@MainActor
final class AccountRowView: FlippedContainer {
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
    /// Fired by everything except the token field, which needs an explicit press because it
    /// gets verified against the API first.
    var onChange: ((AccountRowView) -> Void)?
    var onTestLink: ((AccountRowView) -> Void)?

    init(account: GitHubAccount, hasToken: Bool, width: CGFloat) {
        self.account = account
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        let form = FormLayout(in: self)

        form.beginGroup()
        labelField.stringValue = account.label
        labelField.placeholderString = "Work"
        labelField.delegate = self
        form.row("Name", [(labelField, nil)])

        enabledButton.setButtonType(.switch)
        enabledButton.title = "Include this account in the cards"
        enabledButton.state = account.isEnabled ? .on : .off
        enabledButton.target = self
        enabledButton.action = #selector(controlChanged)
        form.row("", [(enabledButton, nil)], height: 20)

        organizationsField.stringValue = account.organizations.joined(separator: ", ")
        organizationsField.placeholderString = "comma separated, empty = everything the token sees"
        organizationsField.delegate = self
        form.row("Organisations", [(organizationsField, nil)])
        form.endGroup()

        form.header("Token")
        form.beginGroup()
        tokenField.placeholderString = hasToken ? "stored, type to replace it" : "github_pat_… or ghp_…"
        tokenField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let verifyButton = NSButton(title: "Verify token", target: self, action: #selector(save))
        verifyButton.bezelStyle = .rounded
        verifyButton.controlSize = .small
        form.row("Token", [(tokenField, nil), (verifyButton, 100)])
        statusLabel.stringValue = hasToken ? "A token is stored." : "No token yet."
        form.note(statusLabel)
        form.endGroup()
        form.footnote("Read access to pull requests, contents and metadata covers the pull "
            + "requests card; the inbox needs the account-level notifications permission and "
            + "Actions needs actions (read). A fine-grained token must be approved by each "
            + "organisation before it sees anything there.")

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
        form.endGroup()
        form.footnote("github.com allows one signed-in identity per browser profile, so an "
            + "account opens its links in the profile signed in as it.")

        frame.size.height = form.usedHeight
        loadBrowsers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    /// The account as edited, without touching the identifier the token is filed under.
    var editedAccount: GitHubAccount {
        var edited = account
        let label = labelField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.label = label.isEmpty ? account.label : label
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

    // MARK: Browser pickers

    private func loadBrowsers() {
        browsers = BrowserCatalog.installedBrowsers()
        browserPopUp.removeAllItems()
        browserPopUp.addItem(withTitle: "Default browser")
        for browser in browsers { browserPopUp.addItem(withTitle: browser.name) }

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

    @objc private func save() {
        onSave?(self)
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
