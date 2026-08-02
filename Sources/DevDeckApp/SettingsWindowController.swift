import AppKit
import DevDeckCore
import GitHubKit

/// The accounts window. Deliberately the only place a secret is ever typed: a token goes
/// straight to the Keychain and is verified against the API before it is stored.
@MainActor
final class SettingsWindowController: NSObject {
    private let tokenStore: any TokenStore
    private let accountsStore: GitHubAccountsStore
    private let onChanged: () -> Void

    private var window: NSWindow?
    private var documentView: NSView?
    private var rows: [AccountRowView] = []

    private static let contentWidth: CGFloat = 520
    private static let rowWidth: CGFloat = 484

    init(
        tokenStore: any TokenStore,
        accountsStore: GitHubAccountsStore,
        onChanged: @escaping () -> Void
    ) {
        self.tokenStore = tokenStore
        self.accountsStore = accountsStore
        self.onChanged = onChanged
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DevDeck — GitHub accounts"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: Self.contentWidth, height: 320)
        window.center()

        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))

        let hint = NSTextField(labelWithString: """
            One account per token. A fine-grained token must be approved by each organisation, \
            and the inbox card also needs the account-level notifications permission.
            """)
        hint.frame = NSRect(x: 18, y: 400, width: Self.contentWidth - 36, height: 40)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = NSColor.secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 3
        content.addSubview(hint)

        let scroll = NSScrollView(frame: NSRect(x: 18, y: 56, width: Self.contentWidth - 36, height: 336))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        content.addSubview(scroll)

        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: 0))
        scroll.documentView = document
        documentView = document

        let add = NSButton(title: "Add account", target: self, action: #selector(addAccount))
        add.frame = NSRect(x: 18, y: 16, width: 120, height: 30)
        add.bezelStyle = .rounded
        content.addSubview(add)

        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        close.frame = NSRect(x: Self.contentWidth - 18 - 86, y: 16, width: 86, height: 30)
        close.bezelStyle = .rounded
        content.addSubview(close)

        window.contentView = content
        self.window = window

        reload()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Rows

    private func reload() {
        guard let documentView else { return }
        for row in rows { row.removeFromSuperview() }
        rows = []

        var y: CGFloat = 8
        for account in accountsStore.accounts() {
            let hasToken = ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil
            let row = AccountRowView(account: account, hasToken: hasToken, width: Self.rowWidth)
            row.frame.origin = NSPoint(x: 0, y: y)
            row.onSave = { [weak self] in self?.save($0) }
            row.onRemove = { [weak self] in self?.remove($0) }
            documentView.addSubview(row)
            rows.append(row)
            y += AccountRowView.height + 10
        }

        documentView.frame = NSRect(x: 0, y: 0, width: Self.rowWidth, height: max(y, 1))
    }

    @objc private func addAccount() {
        var accounts = accountsStore.accounts()
        let id = GitHubAccount.makeID(from: "account", existing: accounts.map(\.id))
        accounts.append(GitHubAccount(id: id, label: "New account"))
        accountsStore.save(accounts)
        reload()
    }

    private func remove(_ row: AccountRowView) {
        let alert = NSAlert()
        alert.messageText = "Remove \(row.account.label)?"
        alert.informativeText = "Its token is deleted from the Keychain as well."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        try? tokenStore.setToken(nil, for: row.account.tokenKey)
        accountsStore.save(accountsStore.accounts().filter { $0.id != row.account.id })
        reload()
        onChanged()
    }

    private func save(_ row: AccountRowView) {
        let edited = row.editedAccount
        let token = row.enteredToken

        // No new token typed: this is a metadata edit, and there is nothing to verify.
        guard !token.isEmpty else {
            persist(edited)
            row.apply(edited)
            row.setStatus("Saved.")
            onChanged()
            return
        }

        row.setStatus("Checking…")
        Task { [weak self] in
            guard let self else { return }
            // Verify before storing: a rejected token that silently lands in the Keychain
            // turns into a card that fails for reasons nobody can see.
            let probe = GitHubClient.makeDefault(
                tokenStore: InMemoryTokenStore(tokens: [edited.tokenKey: token]),
                settings: edited.settings(basedOn: .default),
                tokenKey: edited.tokenKey
            )
            do {
                let snapshot = try await PullRequestsService(
                    client: probe,
                    settings: edited.settings(basedOn: .default),
                    accountID: edited.id
                ).fetch()
                try self.tokenStore.setToken(token, for: edited.tokenKey)
                self.persist(edited)
                row.apply(edited)
                row.clearTokenField()
                row.setStatus("Saved — \(snapshot.totalCount) open pull requests.")
                self.onChanged()
            } catch let error as APIError {
                row.setStatus("Rejected — \(error.displayMessage)", isError: true)
            } catch {
                row.setStatus("Rejected — \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func persist(_ account: GitHubAccount) {
        var accounts = accountsStore.accounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        accountsStore.save(accounts)
    }

    @objc private func closeWindow() {
        window?.close()
    }
}

/// Rows are laid out from the top, which is the opposite of AppKit's default.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
