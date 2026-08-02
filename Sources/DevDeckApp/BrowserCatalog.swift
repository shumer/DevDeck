import AppKit
import DevDeckCore
import Foundation

/// An installed browser the user can send links to.
struct InstalledBrowser: Equatable {
    let bundleIdentifier: String
    let name: String
    let url: URL
    /// Chromium-family browsers accept `--profile-directory`; nothing else does.
    let supportsProfiles: Bool
}

/// What is installed, and which profiles each browser has.
///
/// Safari has profiles since macOS 14 but no way to pick one from outside the app, so it is
/// listed without them rather than offering a switch that would not work. Firefox's `-P` needs
/// a separate instance and behaves differently depending on what is already running, so it is
/// treated the same way.
enum BrowserCatalog {
    /// Chromium-family bundle identifiers mapped to their support directory, relative to
    /// `~/Library/Application Support`.
    private static let chromiumSupportPaths: [String: String] = [
        "com.google.chrome": "Google/Chrome",
        "com.google.chrome.beta": "Google/Chrome Beta",
        "com.google.chrome.canary": "Google/Chrome Canary",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.browser": "BraveSoftware/Brave-Browser",
        "com.vivaldi.vivaldi": "Vivaldi",
        "org.chromium.chromium": "Chromium",
    ]

    /// Every application registered as able to open a web page.
    static func installedBrowsers() -> [InstalledBrowser] {
        guard let probe = URL(string: "https://github.com") else { return [] }
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: probe)

        var browsers: [InstalledBrowser] = []
        var seen = Set<String>()

        for url in urls {
            guard
                let bundle = Bundle(url: url),
                let identifier = bundle.bundleIdentifier?.lowercased(),
                seen.insert(identifier).inserted
            else { continue }

            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            browsers.append(
                InstalledBrowser(
                    bundleIdentifier: identifier,
                    name: name,
                    url: url,
                    supportsProfiles: chromiumSupportPaths[identifier] != nil
                )
            )
        }

        return browsers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Profiles of a Chromium-family browser, read from its `Local State` file. Empty for
    /// anything else, and for a browser that has never been launched.
    static func profiles(for bundleIdentifier: String) -> [BrowserProfile] {
        guard let relativePath = chromiumSupportPaths[bundleIdentifier.lowercased()] else { return [] }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let localState = support.appendingPathComponent(relativePath).appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localState) else { return [] }
        return ChromiumProfiles.parse(localState: data)
    }

    static func browser(withIdentifier identifier: String?) -> InstalledBrowser? {
        guard let identifier = identifier?.lowercased() else { return nil }
        return installedBrowsers().first { $0.bundleIdentifier == identifier }
    }
}
