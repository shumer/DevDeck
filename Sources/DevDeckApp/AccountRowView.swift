import AppKit
import GitHubKit

/// One account in the settings window: what it is called, which organisations it covers, and
/// a field for its token.
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

    var onSave: ((AccountRowView) -> Void)?
    var onRemove: ((AccountRowView) -> Void)?

    static let height: CGFloat = 132

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

        enabledButton.frame = NSRect(x: inset + 212, y: Self.height - 33, width: 90, height: 20)
        enabledButton.setButtonType(.switch)
        enabledButton.title = "Enabled"
        enabledButton.state = account.isEnabled ? .on : .off
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
        addSubview(organizationsField)

        tokenField.frame = NSRect(x: inset, y: Self.height - 94, width: fieldWidth - 100, height: 22)
        tokenField.placeholderString = hasToken
            ? "Token stored — type to replace it"
            : "github_pat_… or ghp_…"
        tokenField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        addSubview(tokenField)

        let saveButton = NSButton(title: "Test & save", target: self, action: #selector(save))
        saveButton.frame = NSRect(x: width - inset - 92, y: Self.height - 96, width: 92, height: 26)
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .small
        addSubview(saveButton)

        statusLabel.frame = NSRect(x: inset, y: 10, width: fieldWidth, height: 18)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.stringValue = hasToken ? "Token stored." : "No token yet."
        addSubview(statusLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — this view is built in code")
    }

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
