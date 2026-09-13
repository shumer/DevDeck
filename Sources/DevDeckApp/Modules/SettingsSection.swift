import AppKit
import DevDeckCore

/// Where a kind's rows sit in the sidebar.
enum SettingsListGroup {
    case accounts
    case projects
}

/// One kind of thing the settings window lists: accounts of a service, projects of a kind.
///
/// The window owns the sidebar and the form column; a section owns what goes in them for its
/// kind, and how one of its things is added, edited and removed. The rows carry the section's
/// own ids; the window prefixes them with the kind, since two projects of different kinds can
/// share one.
@MainActor
protocol SettingsSection: AnyObject {
    var kind: SettingsWindowController.Section { get }
    /// Which heading its rows go under. Accounts of both services share one, and so do projects
    /// of every kind: a person looking for a project thinks of its name, not of its tooling.
    var group: SettingsListGroup { get }
    /// What the `+` calls this kind.
    var addTitle: String { get }
    /// The window, for reloading and reselecting after a change. Set by the window.
    var host: SettingsHost? { get set }

    func listItems() -> [SettingsListItem]

    /// Builds the form for one of this section's things into a container as wide as the form
    /// column. False when there is no such thing.
    func buildForm(for id: String, in container: FlippedContainer) -> Bool

    /// Adds one and returns its id, or nil when nothing was added: the user cancelled, or the
    /// section asks something first and will select the result itself through the host.
    func add() -> String?

    /// Removes one, asking first. False when the user declined or there was nothing to remove.
    func remove(_ id: String) -> Bool
}

/// What a section or a page may ask the window to do.
@MainActor
protocol SettingsHost: AnyObject {
    /// Redraws the sidebar: a name, a dot or a dimmed row changed. Never touches the form.
    func reloadList()
    /// Rebuilds the form column, after ending any edit in it so what was typed is kept. Only for
    /// a change of shape, a link added or a fold opened, never for an answer arriving: those
    /// update the row they belong to.
    func reloadDetail()
    /// Selects one thing, switching pages if needed.
    func select(_ kind: SettingsWindowController.Section, id: String)
    /// Whether the user is still looking at this thing, for a check that comes back later.
    func isShowing(_ kind: SettingsWindowController.Section, id: String) -> Bool
    /// Whether a fold is open. Remembered for the session, per thing, so opening Advanced on one
    /// project does not open it on all of them.
    func isOpen(_ fold: String) -> Bool
    /// Opens or closes a fold and rebuilds the form around it.
    func toggle(_ fold: String)
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

    /// Whether a token is stored for a key. The row says one exists; it is never read back
    /// into a field.
    static func hasToken(_ key: TokenKey, in store: any TokenStore) -> Bool {
        ((try? store.token(for: key)) ?? nil) != nil
    }
}
