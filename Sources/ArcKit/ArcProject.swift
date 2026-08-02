import DevDeckCore
import Foundation

/// One link on a project card.
///
/// Built-in and custom links are the same type on purpose: every Arc URL differs between
/// organisations and Fusion versions, so the defaults below are a starting point the user can
/// correct rather than something baked into the code.
public struct ArcLink: Sendable, Equatable, Codable, Identifiable {
    public var label: String
    /// `{org}` and `{site}` are substituted from the project.
    public var urlTemplate: String
    public var isEnabled: Bool

    public init(label: String, urlTemplate: String, isEnabled: Bool) {
        self.label = label
        self.urlTemplate = urlTemplate
        self.isEnabled = isEnabled
    }

    public var id: String { label }

    public func url(organization: String, site: String?) -> URL? {
        let resolved = urlTemplate
            .replacingOccurrences(of: "{org}", with: organization)
            .replacingOccurrences(of: "{site}", with: site ?? "")
        return URL(string: resolved)
    }

    /// Defaults follow the sandbox host, which is where day-to-day work happens:
    /// `https://sandbox.ilgiornale.arcpublishing.com/home/` for org `ilgiornale`.
    ///
    /// A project pointed at production edits the templates — that is why they are fields and
    /// not constants. Only PageBuilder is confirmed against a real organisation; the rest are
    /// the same host with the path each tool is usually mounted at, and the Test button in
    /// settings is there to check them one at a time.
    public static func defaults() -> [ArcLink] {
        [
            ArcLink(label: "PageBuilder", urlTemplate: "https://sandbox.{org}.arcpublishing.com/home/", isEnabled: true),
            ArcLink(label: "Composer", urlTemplate: "https://sandbox.{org}.arcpublishing.com/composer/", isEnabled: true),
            ArcLink(label: "Dev Center", urlTemplate: "https://sandbox.{org}.arcpublishing.com/developer/", isEnabled: true),
            ArcLink(label: "Site Service", urlTemplate: "https://sandbox.{org}.arcpublishing.com/developer/sites/", isEnabled: false),
            ArcLink(label: "Delivery API", urlTemplate: "https://api.sandbox.{org}.arcpublishing.com/content/v4", isEnabled: false),
        ]
    }
}

/// An Arc XP project: where it lives on the web, where it lives on disk, and how to run it.
public struct ArcProject: Sendable, Equatable, Codable, Identifiable {
    /// Stable slug. Used in the card identifier, so it is never renamed.
    public let id: String
    public var title: String
    public var organization: String
    public var site: String?
    public var links: [ArcLink]
    /// Where this project's links open. Arc organisations are often signed into in a
    /// different browser profile than GitHub.
    public var browser: BrowserChoice
    /// Absolute path to the checkout. Nil disables every local-stack control.
    public var folder: String?
    public var startCommand: String
    public var stopCommand: String
    public var rebuildCommand: String
    public var teardownCommand: String
    /// Base URL the local stack answers on.
    public var localURL: String
    /// Path that proves the engine is up. `/release` reports the running engine version.
    public var healthPath: String
    public var isEnabled: Bool

    public init(
        id: String,
        title: String,
        organization: String,
        site: String? = nil,
        links: [ArcLink] = ArcLink.defaults(),
        browser: BrowserChoice = .systemDefault,
        folder: String? = nil,
        // `fusion start` runs in the foreground and would hold the app hostage; `daemon` is
        // the CLI's own background mode and is what a button should use.
        startCommand: String = "npx fusion daemon",
        stopCommand: String = "npx fusion stop",
        rebuildCommand: String = "npx fusion rebuild",
        teardownCommand: String = "npx fusion down",
        localURL: String = "http://localhost",
        healthPath: String = "/release",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.organization = organization
        self.site = site
        self.links = links
        self.browser = browser
        self.folder = folder
        self.startCommand = startCommand
        self.stopCommand = stopCommand
        self.rebuildCommand = rebuildCommand
        self.teardownCommand = teardownCommand
        self.localURL = localURL
        self.healthPath = healthPath
        self.isEnabled = isEnabled
    }

    /// Links that are switched on and produce a valid URL.
    public var resolvedLinks: [(label: String, url: URL)] {
        links.compactMap { link in
            guard link.isEnabled, let url = link.url(organization: organization, site: site) else { return nil }
            return (label: link.label, url: url)
        }
    }

    public var folderURL: URL? {
        guard let folder, !folder.isEmpty else { return nil }
        return URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Nothing local can be done without a folder to do it in.
    public var supportsLocalStack: Bool { folderURL != nil }

    public var healthURL: URL? {
        URL(string: localURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + healthPath)
    }

    public var localSiteURL: URL? {
        URL(string: localURL)
    }

    /// Card identifier for this project.
    public var cardID: CardID { CardID(rawValue: "arc.project.\(id)") }

    public static func makeID(from title: String, existing: [String]) -> String {
        let allowed = CharacterSet.alphanumerics
        let base = title.lowercased().unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let candidate = base.isEmpty ? "project" : base
        guard existing.contains(candidate) else { return candidate }
        var index = 2
        while existing.contains("\(candidate)-\(index)") { index += 1 }
        return "\(candidate)-\(index)"
    }
}

/// Reads and writes the project list.
public struct ArcProjectsStore: Sendable {
    private let backend: any PreferencesBackend
    private static let key = "arc.projects"

    public init(backend: any PreferencesBackend) {
        self.backend = backend
    }

    /// Empty by default: unlike GitHub, there is no sensible "one project" to invent.
    public func projects() -> [ArcProject] {
        guard
            let data = backend.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([ArcProject].self, from: data)
        else { return [] }
        return decoded
    }

    public func enabledProjects() -> [ArcProject] {
        projects().filter(\.isEnabled)
    }

    public func project(withID id: String) -> ArcProject? {
        projects().first { $0.id == id }
    }

    /// The project a card identifier belongs to.
    public func project(forCard card: CardID) -> ArcProject? {
        projects().first { $0.cardID == card }
    }

    public func save(_ projects: [ArcProject]) {
        backend.set(try? JSONEncoder().encode(projects), forKey: Self.key)
    }
}
