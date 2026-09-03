import AppKit

/// The Edit menu nobody sees, and every text field needs.
///
/// This is an agent app: `LSUIElement` means no Dock icon and no menu bar of its own, and it
/// went the whole way without a main menu at all. That is fine until somebody opens Settings and
/// presses ⌘V, because AppKit routes those keys through the main menu: with no Edit menu there
/// is nothing to route to, the key does nothing, and pasting a token - the one thing you cannot
/// reasonably type by hand - is impossible.
///
/// The items carry no action of their own. `nil` targets mean AppKit sends them down the
/// responder chain to whatever field has focus, which is exactly what Cut, Copy and Paste are.
enum EditMenu {
    static func install() {
        let main = NSMenu()

        // An application menu has to come first, even unseen: AppKit treats the first item as
        // the app menu and would otherwise hand Edit that role, hiding it.
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "DevDeck")
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in editItems {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            edit.addItem(item)
        }
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    private static let editItems: [(String, Selector, String)] = [
        ("Undo", Selector(("undo:")), "z"),
        ("Redo", Selector(("redo:")), "Z"),
        ("Cut", #selector(NSText.cut(_:)), "x"),
        ("Copy", #selector(NSText.copy(_:)), "c"),
        ("Paste", #selector(NSText.paste(_:)), "v"),
        ("Select All", #selector(NSText.selectAll(_:)), "a"),
    ]
}
