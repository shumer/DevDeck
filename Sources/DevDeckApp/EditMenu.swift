import AppKit
import DevDeckCore

/// The menus nobody sees, and a window needs anyway.
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
        let edit = NSMenu(title: L("menu.edit"))
        for (title, selector, key) in editItems {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            edit.addItem(item)
        }
        // Find, for the log window: ⌘F is routed through the main menu like everything else, and
        // `performTextFinderAction:` is what a text view listens for. The tags are the system's
        // own numbering of what to do.
        edit.addItem(.separator())
        let findItem = NSMenuItem(title: L("menu.edit.find"), action: nil, keyEquivalent: "")
        let find = NSMenu(title: L("menu.edit.find"))
        for (title, tag, key, modifiers) in findItems {
            let item = NSMenuItem(title: title, action: Selector(("performTextFinderAction:")), keyEquivalent: key)
            item.tag = tag
            item.keyEquivalentModifierMask = modifiers
            find.addItem(item)
        }
        findItem.submenu = find
        edit.addItem(findItem)

        editItem.submenu = edit
        main.addItem(editItem)

        // Window, for the same reason as Edit: ⌘W and ⌘M are routed through the main menu, and
        // without them the settings window can only be closed by its red button.
        let windowItem = NSMenuItem()
        let windows = NSMenu(title: L("menu.window"))
        windows.addItem(NSMenuItem(title: L("menu.window.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windows.addItem(NSMenuItem(title: L("menu.window.minimise"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowItem.submenu = windows
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windows
    }

    /// The four the system draws a find bar for, by `NSTextFinder.Action`.
    private static var findItems: [(String, Int, String, NSEvent.ModifierFlags)] {
        [
            (L("menu.edit.find.find"), NSTextFinder.Action.showFindInterface.rawValue, "f", .command),
            (L("menu.edit.find.next"), NSTextFinder.Action.nextMatch.rawValue, "g", .command),
            (L("menu.edit.find.previous"), NSTextFinder.Action.previousMatch.rawValue, "G", [.command, .shift]),
            (L("menu.edit.find.selection"), NSTextFinder.Action.setSearchString.rawValue, "e", .command),
        ]
    }

    private static var editItems: [(String, Selector, String)] {
        [
            (L("menu.edit.undo"), Selector(("undo:")), "z"),
            (L("menu.edit.redo"), Selector(("redo:")), "Z"),
            (L("menu.edit.cut"), #selector(NSText.cut(_:)), "x"),
            (L("menu.edit.copy"), #selector(NSText.copy(_:)), "c"),
            (L("menu.edit.paste"), #selector(NSText.paste(_:)), "v"),
            (L("menu.edit.selectAll"), #selector(NSText.selectAll(_:)), "a"),
        ]
    }
}
