import AppKit
import DevDeckCore
import GitHubKit
import GitLabKit

/// The token block both account forms share: one status line, a field for a new token, a
/// button that saves it, and where to make one.
///
/// A stored token is never written back into the field. The status line says whether one is
/// stored and whether it works; typing a new one and pressing Return, or Save Token, replaces it.
@MainActor
final class TokenBlock: NSObject {
    let field = NSSecureTextField()
    let status: StatusLine
    private let saveButton: NSButton
    var onSave: (() -> Void)?

    init(hasToken: Bool, placeholder: String) {
        status = StatusLine(
            tone: hasToken ? .good : .busy,
            state: hasToken ? "Saved in Keychain" : "No token",
            detail: hasToken ? "" : "paste one below"
        )
        saveButton = SettingsForm.button("Save Token", target: nil, action: nil)
        super.init()
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        // Return saves: the one field in the window whose value waits for a press.
        field.target = self
        field.action = #selector(save)
        saveButton.target = self
        saveButton.action = #selector(save)
    }

    func add(to form: SettingsForm) {
        form.statusRow(status, button: nil)
        form.fieldRow("New token", [(field, nil)], trailing: saveButton)
    }

    var entered: String {
        field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func checking() {
        status.update(tone: .idle, state: "Checking…", detail: "")
    }

    func works(_ detail: String) {
        field.stringValue = ""
        status.update(tone: .good, state: "Token works", detail: detail)
    }

    func refused(_ reason: String) {
        status.update(tone: .bad, state: "Not accepted", detail: reason)
    }

    @objc private func save() {
        onSave?()
    }
}

// MARK: - GitHub

/// One GitHub account: its token, its name and where its links open. What it may notify you
/// about moved to the Notifications page, next to every other account's.
@MainActor
final class GitHubAccountForm: FlippedContainer, NSTextFieldDelegate {
    private(set) var account: GitHubAccount
    let token: TokenBlock

    private let nameField: NSTextField
    private let organizationsField: NSTextField
    private let browser: BrowserPicker
    private var enabledSwitch: NSSwitch?

    var onChange: ((GitHubAccountForm) -> Void)?
    var onSave: ((GitHubAccountForm) -> Void)?
    var onTestLink: ((GitHubAccountForm) -> Void)?
    var onToggleAdvanced: (() -> Void)?

    /// Where a fine-grained token is made, with nothing filled in: the account a person is
    /// signed into in their browser is the one the token belongs to.
    static let createTokenURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    init(account: GitHubAccount, hasToken: Bool, isAdvancedOpen: Bool, width: CGFloat) {
        self.account = account
        token = TokenBlock(hasToken: hasToken, placeholder: "github_pat_… or ghp_…")
        nameField = SettingsForm.field(account.label, placeholder: "Work")
        organizationsField = SettingsForm.field(account.organizations.joined(separator: ", "), placeholder: "all the token can see")
        browser = BrowserPicker(choice: account.browser)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        let form = SettingsForm(in: self)
        enabledSwitch = form.pageHeader(
            icon: SettingsIcons.mark(.github, size: 32),
            title: account.label,
            subtitle: account.apiBaseURL.host ?? "github.com",
            toggleTitle: "Show on deck",
            isOn: account.isEnabled,
            target: self,
            action: #selector(changed)
        )

        form.section("Token", help: "Read access to Pull requests, Contents and Metadata covers the pull requests card. The inbox needs the Notifications account permission, and the Actions card needs Actions. Each organisation has to approve a fine-grained token before it sees anything there.")
        form.beginGroup()
        token.add(to: form)
        form.endGroup()
        form.textButton("Create a Token on GitHub…", target: self, action: #selector(createToken))

        form.section("Account")
        form.beginGroup()
        nameField.delegate = self
        form.fieldRow("Name", [(nameField, nil)])
        browser.onChange = { [weak self] in self?.changed() }
        form.fieldRow("Open links in", [(browser.browserPopUp, 170), (browser.profilePopUp, nil)], trailing: SettingsForm.button("Test", target: self, action: #selector(testLink)))
        form.endGroup()

        form.disclosure("Advanced", summary: "Limit to organisations", isOpen: isAdvancedOpen, target: self, action: #selector(toggleAdvanced))
        if isAdvancedOpen {
            form.beginGroup()
            organizationsField.delegate = self
            form.fieldRow("Organisations", [(organizationsField, nil)])
            form.endGroup()
        }

        frame.size.height = form.usedHeight
        token.onSave = { [weak self] in
            guard let self else { return }
            self.onSave?(self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    /// The account as edited, without touching the identifier the token is filed under.
    var editedAccount: GitHubAccount {
        var edited = account
        let label = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.label = label.isEmpty ? account.label : label
        edited.organizations = organizationsField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        edited.isEnabled = enabledSwitch?.state != .off
        edited.browser = browser.choice
        return edited
    }

    func apply(_ account: GitHubAccount) {
        self.account = account
    }

    @objc private func changed() { onChange?(self) }
    @objc private func testLink() { onTestLink?(self) }
    @objc private func toggleAdvanced() { onToggleAdvanced?() }
    @objc private func createToken() { NSWorkspace.shared.open(Self.createTokenURL) }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard (notification.object as? NSTextField) !== token.field else { return }
        onChange?(self)
    }
}

// MARK: - GitLab

/// One GitLab instance: its token, where it lives, its name and where its links open.
@MainActor
final class GitLabAccountForm: FlippedContainer, NSTextFieldDelegate {
    private(set) var account: GitLabAccount
    let token: TokenBlock

    private let nameField: NSTextField
    private let hostField: NSTextField
    private let browser: BrowserPicker
    private var enabledSwitch: NSSwitch?

    var onChange: ((GitLabAccountForm) -> Void)?
    var onSave: ((GitLabAccountForm) -> Void)?
    var onTestLink: ((GitLabAccountForm) -> Void)?

    init(account: GitLabAccount, hasToken: Bool, width: CGFloat) {
        self.account = account
        token = TokenBlock(hasToken: hasToken, placeholder: "glpat-…")
        nameField = SettingsForm.field(account.label, placeholder: "GitLab")
        hostField = SettingsForm.field(account.host.absoluteString, placeholder: "https://gitlab.com", code: true)
        browser = BrowserPicker(choice: account.browser)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        let form = SettingsForm(in: self)
        enabledSwitch = form.pageHeader(
            icon: SettingsIcons.mark(.gitlab, size: 32),
            title: account.label,
            subtitle: account.displayHost,
            toggleTitle: "Show on deck",
            isOn: account.isEnabled,
            target: self,
            action: #selector(changed)
        )

        form.section("Token", help: "A personal access token with the read_api scope. The card asks for merge requests, their pipeline and their approvals, and nothing else.")
        form.beginGroup()
        token.add(to: form)
        form.endGroup()
        form.textButton("Create a Token on \(account.displayHost)…", target: self, action: #selector(createToken))

        form.section("Instance")
        form.beginGroup()
        nameField.delegate = self
        form.fieldRow("Name", [(nameField, nil)])
        hostField.delegate = self
        form.fieldRow("Address", [(hostField, nil)])
        browser.onChange = { [weak self] in self?.changed() }
        form.fieldRow("Open links in", [(browser.browserPopUp, 170), (browser.profilePopUp, nil)], trailing: SettingsForm.button("Test", target: self, action: #selector(testLink)))
        form.endGroup()

        frame.size.height = form.usedHeight
        token.onSave = { [weak self] in
            guard let self else { return }
            self.onSave?(self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    var editedAccount: GitLabAccount {
        var edited = account
        let label = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.label = label.isEmpty ? account.label : label
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        if let url = GitLabAccount.normalizedHost(host) { edited.host = url }
        edited.isEnabled = enabledSwitch?.state != .off
        edited.browser = browser.choice
        return edited
    }

    func apply(_ account: GitLabAccount) {
        self.account = account
    }

    @objc private func changed() { onChange?(self) }
    @objc private func testLink() { onTestLink?(self) }

    /// GitLab's own page for a new token, with the name and the one scope filled in.
    @objc private func createToken() {
        let base = editedAccount.host
        var components = URLComponents(url: base.appendingPathComponent("-/user_settings/personal_access_tokens"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "name", value: "DevDeck"), URLQueryItem(name: "scopes", value: "read_api")]
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard (notification.object as? NSTextField) !== token.field else { return }
        onChange?(self)
    }
}
