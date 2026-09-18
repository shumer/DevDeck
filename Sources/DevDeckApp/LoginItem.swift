import AppKit
import DevDeckCore
import Foundation
import ServiceManagement

/// Whether macOS starts the app at login.
///
/// A type of its own because two places ask about it: the settings screen, where the switch
/// lives, and the launch argument the install script uses. Nothing about it is stored here.
/// `SMAppService` is the truth, so a login item the user removes in System Settings shows as off
/// without this app having to be told.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the state it actually ended in, so a switch can be put back rather than left
    /// lying about what happened.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item: \(error.localizedDescription, privacy: .public)")
            report(error)
        }
        return isEnabled
    }

    /// The failure is nearly always the same one and has nearly always the same fix, so the
    /// alert says what to do rather than only what went wrong.
    private static func report(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("loginItem.error.title")
        alert.informativeText = L("loginItem.error.detail", error.localizedDescription)
        alert.addButton(withTitle: L("button.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
