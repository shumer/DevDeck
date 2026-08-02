import AppKit
import DevDeckCore
import GitHubKit

/// The token sheet. Deliberately the only place a secret is ever typed: it goes straight to
/// the Keychain and is verified against the API before it is stored.
@MainActor
final class SettingsWindowController: NSObject {
    private let tokenStore: any TokenStore
    private let onSaved: () -> Void

    private var window: NSWindow?
    private var tokenField: NSSecureTextField?
    private var statusLabel: NSTextField?

    init(tokenStore: any TokenStore, onSaved: @escaping () -> Void) {
        self.tokenStore = tokenStore
        self.onSaved = onSaved
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DevDeck — Settings"
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))

        func label(_ text: String, _ y: CGFloat, size: CGFloat = 12, bold: Bool = false, alpha: CGFloat = 1) {
            let field = NSTextField(labelWithString: text)
            field.frame = NSRect(x: 20, y: y, width: 430, height: 18)
            field.font = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            field.textColor = NSColor.labelColor.withAlphaComponent(alpha)
            content.addSubview(field)
        }

        label("GitHub  —  pull requests, reviews and checks", 200, bold: true)

        let token = NSSecureTextField(frame: NSRect(x: 20, y: 172, width: 430, height: 23))
        token.placeholderString = "github_pat_… or ghp_…"
        token.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        content.addSubview(token)

        label("Fine-grained token: read access to pull requests, contents and metadata.", 150, size: 10, alpha: 0.55)
        label("Under SAML SSO, authorise the token for each organisation.", 132, size: 10, alpha: 0.55)
        label("The token is stored in the login Keychain, never in the project.", 114, size: 10, alpha: 0.55)

        let status = NSTextField(labelWithString: "")
        status.frame = NSRect(x: 20, y: 70, width: 430, height: 18)
        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = NSColor.labelColor.withAlphaComponent(0.75)
        content.addSubview(status)

        let save = NSButton(title: "Test & Save", target: self, action: #selector(save))
        save.frame = NSRect(x: 350, y: 18, width: 100, height: 30)
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        content.addSubview(save)

        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        close.frame = NSRect(x: 256, y: 18, width: 86, height: 30)
        close.bezelStyle = .rounded
        content.addSubview(close)

        // Show that a token exists without ever putting the secret back on screen.
        if (try? tokenStore.token(for: .github)) ?? nil != nil {
            status.stringValue = "A token is already stored. Enter a new one to replace it."
        }

        window.contentView = content
        self.window = window
        tokenField = token
        statusLabel = status

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(token)
    }

    @objc private func closeWindow() {
        window?.close()
    }

    @objc private func save() {
        let value = tokenField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else {
            statusLabel?.stringValue = "Enter a token first."
            return
        }
        statusLabel?.stringValue = "Checking…"

        Task { [weak self] in
            guard let self else { return }
            // Verify before storing: a rejected token that silently lands in the Keychain
            // turns into a card that fails for reasons nobody can see.
            let probe = GitHubClient.makeDefault(
                tokenStore: InMemoryTokenStore(tokens: [.github: value])
            )
            do {
                let snapshot = try await PullRequestsService(client: probe).fetch()
                try self.tokenStore.setToken(value, for: .github)
                self.statusLabel?.stringValue = "Saved — \(snapshot.totalCount) open pull requests."
                self.tokenField?.stringValue = ""
                self.onSaved()
            } catch let error as APIError {
                self.statusLabel?.stringValue = "Rejected — \(error.displayMessage)"
            } catch {
                self.statusLabel?.stringValue = "Rejected — \(error.localizedDescription)"
            }
        }
    }
}
