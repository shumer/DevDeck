import AppKit
import DevDeckCore

/// One kind of thing the settings window lists: accounts of a service, projects of a kind.
///
/// The window owns the list and the form column; a section owns what goes in them for its
/// kind, and how one of its things is added, edited and removed. The rows in the list carry the
/// section's own ids; the window prefixes them with the section, since two projects of
/// different kinds can share one.
@MainActor
protocol SettingsSection: AnyObject {
    var kind: SettingsWindowController.Section { get }
    /// What the `+` calls this kind.
    var addTitle: String { get }
    /// Shown in the form column when this section has nothing to select.
    var emptyText: String { get }
    /// The window, for reloading and reselecting after a change. Set by the window.
    var host: SettingsHost? { get set }

    func listItems() -> [SettingsListItem]

    /// Builds the form for one of this section's things. False when there is no such thing,
    /// which the window answers with `emptyText`.
    func buildForm(for id: String, in container: FlippedContainer, width: CGFloat) -> Bool

    /// Adds one and returns its id, or nil when nothing was added: the user cancelled, or the
    /// section asks something first and will select the result itself through the host.
    func add() -> String?

    /// Removes one, asking first. False when the user declined or there was nothing to remove.
    func remove(_ id: String) -> Bool
}

/// What a section may ask the window to do.
@MainActor
protocol SettingsHost: AnyObject {
    /// Redraws the list column: a name, a state dot or a subtitle changed.
    func reloadList()
    /// Rebuilds the form column: the form has a different number of rows than the one on
    /// screen, or a check has come back.
    func reloadDetail()
    /// Selects one thing, switching sections if needed.
    func select(_ kind: SettingsWindowController.Section, id: String)
    /// Whether the user is still looking at this thing, for a check that comes back later.
    func isShowing(_ kind: SettingsWindowController.Section, id: String) -> Bool
    /// Tells the deck that something it renders from has changed.
    func changed()
}

/// The dialogs and wordings the sections share.
@MainActor
enum SettingsSupport {
    static func chooseDirectory(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func confirm(_ message: String, detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func browserSummary(browser: BrowserChoice) -> String {
        guard let identifier = browser.bundleIdentifier else {
            return "Saved. Links open in the default browser."
        }
        let name = BrowserCatalog.browser(withIdentifier: identifier)?.name ?? identifier
        guard let profile = browser.profileDirectory else { return "Saved. Links open in \(name)." }
        return "Saved. Links open in \(name) · \(profile)."
    }

    /// Whether a token is stored for a key. The row says one exists; it is never read back
    /// into a field.
    static func hasToken(_ key: TokenKey, in store: any TokenStore) -> Bool {
        ((try? store.token(for: key)) ?? nil) != nil
    }
}
