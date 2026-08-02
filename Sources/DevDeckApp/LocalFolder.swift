import AppKit
import Foundation

/// The two ways a project folder is opened from a card.
@MainActor
enum LocalFolder {
    static func reveal(_ folder: URL?) {
        guard let folder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Opens the folder in a terminal.
    ///
    /// macOS has no "default terminal" the way it has a default browser, so the installed
    /// ones are tried in the order someone who has them would expect.
    static func openTerminal(_ folder: URL?) {
        guard let folder else { return }

        let candidates = [
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "com.apple.Terminal",
        ]

        for identifier in candidates {
            guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
                continue
            }
            NSWorkspace.shared.open(
                [folder],
                withApplicationAt: application,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
