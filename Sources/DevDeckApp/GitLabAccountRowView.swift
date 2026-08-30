import AppKit
import DevDeckCore
import GitLabKit

/// The form for one GitHub account.
///
/// The token field is always empty on screen. A stored secret is never written back into the
/// UI - the status line says whether one exists, and typing replaces it.
@MainActor
final class GitLabAccountRowView: FlippedContainer {
    private(set) var account: GitLabAccount

    private let labelField = NSTextField()
    private let hostField = NSTextField()
    private let tokenField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let enabledButton = NSButton()
    private let reviewNotifyButton = NSButton()
    private let blockedNotifyButton = NSButton()
    private let browserPopUp = NSPopUpButton()
    private let profilePopUp = NSPopUpButton()

    private var browsers: [InstalledBrowser] = []
    private var profiles: [BrowserProfile] = []

    var onSave: ((GitLabAccountRowView) -> Void)?
    /// Fired by everything except the token field, which needs an explicit press because it
    /// gets verified against the API first.
    var onChange: ((GitLabAccountRowView) -> Void)?
    var onTestLink: ((GitLabAccountRowView) -> Void)?

    init(account: GitLabAccount, hasToken: Bool, width: CGFloat) {
        self.account = account
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        let form = FormLayout(in: self)

        enabledButton.setButtonType(.switch)
        enabledButton.title = ""
        enabledButton.state = account.isEnabled ? .on : .off
        enabledButton.target = self
        enabledButton.action = #selector(controlChanged)
        // The same header the plain-project form has: the thing's name at the top, what it is
        // underneath, and the one switch that decides whether it exists at all.
        form.formHeader(
            title: account.label,
            subtitle: account.displayHost,
            accessory: (label: "Include", view: enabledButton)
        )

        form.beginGroup()
        labelField.stringValue = account.label
        labelField.placeholderString = "Work"
        labelField.delegate = self
        form.row("Name", [(labelField, nil)])


        hostField.stringValue = account.host.absoluteString
        hostField.placeholderString = "https://gitlab.com"
        hostField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        hostField.delegate = self
        form.row("Instance", [(hostField, nil)])
        form.endGroup()

        form.header("Token")
        form.beginGroup()
        tokenField.placeholderString = hasToken ? "stored, type to replace it" : "glpat-…"
        tokenField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let verifyButton = NSButton(title: "Verify token", target: self, action: #selector(save))
        verifyButton.bezelStyle = .rounded
        verifyButton.controlSize = .small
        form.row("Token", [(tokenField, nil), (verifyButton, 100)])
        statusLabel.stringValue = hasToken ? "A token is stored." : "No token yet."
        form.note(statusLabel)
        form.endGroup()
        form.footnote("A personal access token with the read_api scope is enough: the card asks "
            + "for merge requests, their pipeline and their approvals, and nothing else. Make it "
            + "on the instance itself, under Preferences, Access tokens.")

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
        form.footnote("A customer's GitLab and your own are usually two different signed-in "
            + "identities, and a browser holds one per profile, so each instance opens its links "
            + "in the profile signed in to it.")

        form.header("Notify me")
        form.beginGroup()
        reviewNotifyButton.setButtonType(.switch)
        reviewNotifyButton.title = ""
        reviewNotifyButton.state = account.notifiesReviewRequests ? .on : .off
        reviewNotifyButton.target = self
        reviewNotifyButton.action = #selector(controlChanged)
        form.toggleRow(
            reviewNotifyButton,
            title: "When somebody asks for my review",
            subtitle: "A banner carrying GitLab's own mark, so it is clear who is asking."
        )

        blockedNotifyButton.setButtonType(.switch)
        blockedNotifyButton.title = ""
        blockedNotifyButton.state = account.notifiesBlocked ? .on : .off
        blockedNotifyButton.target = self
        blockedNotifyButton.action = #selector(controlChanged)
        form.toggleRow(
            blockedNotifyButton,
            title: "When something of mine here is blocked",
            subtitle: "Off by default: a red build on a branch you are pushing to is not news."
        )
        form.endGroup()
        form.footnote("Per account, so a customer's work can stay quiet while your own does not. "
            + "Notifications have to be switched on for the app as a whole first, under General.")

        frame.size.height = form.usedHeight
        loadBrowsers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    /// The account as edited, without touching the identifier the token is filed under.
    var editedAccount: GitLabAccount {
        var edited = account
        let label = labelField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.label = label.isEmpty ? account.label : label
        // A host that will not parse is left alone rather than blanked: losing the instance
        // because of a typo would leave an account that can never be fixed from this form.
        let typed = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = GitLabAccountRowView.normalisedHost(typed) { edited.host = host }
        edited.isEnabled = enabledButton.state == .on
        edited.notifiesReviewRequests = reviewNotifyButton.state == .on
        edited.notifiesBlocked = blockedNotifyButton.state == .on
        edited.browser = selectedBrowserChoice
        return edited
    }

    /// Empty when the user did not type a new one, which means "keep what is stored".
    var enteredToken: String {
        tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func apply(_ account: GitLabAccount) {
        self.account = account
    }

    /// A host typed by a person, turned into something that can be asked for `/api/graphql`.
    ///
    /// People write `gitlab.acme.io`, `https://gitlab.acme.io/` and occasionally the URL of a
    /// project they were looking at. The scheme is added when missing and the path is dropped,
    /// because everything below the host belongs to the API, not to the setting.
    static func normalisedHost(_ text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        let withScheme = text.contains("://") ? text : "https://\(text)"
        guard var components = URLComponents(string: withScheme), let host = components.host, !host.isEmpty else {
            return nil
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
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

extension GitLabAccountRowView: NSTextFieldDelegate {
    /// Text edits commit when the field is left, so a typed name or organisation list does not
    /// need a button either.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field !== tokenField else { return }
        onChange?(self)
    }
}
