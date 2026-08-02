import AppKit
import DevDeckCore
import Foundation

/// Opens a URL as the account that owns it.
@MainActor
enum LinkOpener {
    static func open(_ url: URL, using choice: BrowserChoice) {
        guard
            let identifier = choice.bundleIdentifier,
            let browser = BrowserCatalog.browser(withIdentifier: identifier)
        else {
            // No choice, or the chosen browser has been uninstalled since. Falling back to the
            // default browser is better than silently doing nothing.
            NSWorkspace.shared.open(url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()

        if let profile = choice.profileDirectory, !profile.isEmpty {
            // Chromium only honours `--profile-directory` on launch, and it routes the request
            // to the already-running process itself. A new instance has to be requested for
            // the arguments to be read at all — this is what `open -na … --args` does.
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ["--profile-directory=\(profile)", url.absoluteString]
            NSWorkspace.shared.openApplication(at: browser.url, configuration: configuration) { _, error in
                guard error != nil else { return }
                Task { @MainActor in
                    Log.app.error("Could not open \(url.absoluteString, privacy: .public) in \(browser.name, privacy: .public)")
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        NSWorkspace.shared.open([url], withApplicationAt: browser.url, configuration: configuration) { _, error in
            guard error != nil else { return }
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
    }
}
