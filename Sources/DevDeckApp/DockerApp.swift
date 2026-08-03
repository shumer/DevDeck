import AppKit
import Foundation

/// The container runtime as something that can be launched.
///
/// Separate from `DockerEnvironment`, which asks the daemon whether it is up: that question has
/// an answer on every machine, while this one only does where the runtime ships as an
/// application. Colima has no app to open, and a card on such a machine offers no button rather
/// than one that would do nothing.
enum DockerApp {
    /// Docker Desktop first, then the drop-in replacements people use instead of it.
    static let bundleIdentifiers = [
        "com.docker.docker",
        "dev.orbstack.OrbStack",
        "io.rancherdesktop.app",
        "com.podman-desktop.PodmanDesktop",
    ]

    static func installedURL() -> URL? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        return nil
    }

    /// Opens the runtime without stealing focus: the point is to get the daemon up, not to put
    /// a whale in front of whatever the user is doing.
    static func launch() {
        guard let url = installedURL() else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
