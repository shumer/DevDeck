import AppKit
import Foundation

/// The ways a project's files are opened from a card.
@MainActor
enum LocalFolder {
    static func reveal(_ folder: URL?) {
        guard let folder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Opens a file in whatever handles it — the log of a project that was started from here.
    /// A missing file is revealed instead of opened, because the folder is still the answer to
    /// "where would it be".
    static func open(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else {
            NSWorkspace.shared.activateFileViewerSelecting([file.deletingLastPathComponent()])
            return
        }
        NSWorkspace.shared.open(file)
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
