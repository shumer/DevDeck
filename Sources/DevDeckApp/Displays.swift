import AppKit
import DevDeckCore

/// The screens as `PanelPlacement` needs to see them.
///
/// The identity is `CGDisplayCreateUUIDFromDisplayID`, not the display id and not the screen's
/// index. Display ids are handed out per connection and change when a screen is unplugged and
/// plugged back in; the index changes whenever the arrangement does. The UUID belongs to the
/// physical display, which is exactly what "keep this card on the laptop screen" means.
@MainActor
enum Displays {
    static func current() -> [DisplayFrame] {
        NSScreen.screens.compactMap { screen in
            guard let id = identifier(of: screen) else { return nil }
            return DisplayFrame(id: id, visibleFrame: screen.visibleFrame)
        }
    }

    /// Where a card goes when its own display is not connected.
    static func fallback() -> DisplayFrame? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        guard let id = identifier(of: screen) else { return nil }
        return DisplayFrame(id: id, visibleFrame: screen.visibleFrame)
    }

    static func identifier(of screen: NSScreen) -> String? {
        guard
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)

        // A virtual or freshly-attached display can have no UUID for a moment; the display id
        // is a worse identity but a working one, and it is better than dropping the screen.
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return "display-\(displayID)"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
