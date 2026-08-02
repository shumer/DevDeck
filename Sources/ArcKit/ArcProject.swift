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

    /// Templates never add an environment prefix of their own.
    ///
    /// The organisation field carries the whole host label — `sandbox.ilgiornale` for the
    /// sandbox, `ilgiornale` for production — so a template that helpfully prepended
    /// `sandbox.` produced `sandbox.sandbox.ilgiornale`. One place owns the environment, and
    /// it is the field the user types.
    ///
    /// Only PageBuilder, Composer and the Deployer are confirmed against a real organisation;
    /// the last two are the same host with the path each tool is usually mounted at, and the
    /// Test button in settings is there to check them one at a time.
    public static func defaults() -> [ArcLink] {
        [
            ArcLink(label: "PageBuilder", urlTemplate: "https://{org}.arcpublishing.com/home/", isEnabled: true),
            ArcLink(label: "Composer", urlTemplate: "https://{org}.arcpublishing.com/composer", isEnabled: true),
            ArcLink(label: "Deployer", urlTemplate: "https://{org}.arcpublishing.com/deployments/fusion/", isEnabled: true),
            ArcLink(label: "Site Service", urlTemplate: "https://{org}.arcpublishing.com/developer/sites", isEnabled: false),
            ArcLink(label: "Delivery API", urlTemplate: "https://api.{org}.arcpublishing.com/content/v4", isEnabled: false),
            // The published sites. There is nothing to derive them from — a site lives on its
            // own domain — so they ship empty for the user to paste in, next to the local one.
            ArcLink(label: "Sandbox", urlTemplate: "", isEnabled: false),
            ArcLink(label: "Prod", urlTemplate: "", isEnabled: false),
        ]
    }

    /// Templates shipped by earlier builds, mapped onto what they should have been.
    ///
    /// Only exact matches are rewritten: a template the user has edited is theirs, however
    /// close it looks to one of ours.
    static let supersededTemplates: [String: String] = [
        "https://{org}.arcpublishing.com/pagebuilder": "https://{org}.arcpublishing.com/home/",
        "https://sandbox.{org}.arcpublishing.com/home/": "https://{org}.arcpublishing.com/home/",
        "https://sandbox.{org}.arcpublishing.com/composer/": "https://{org}.arcpublishing.com/composer",
        "https://{org}.arcpublishing.com/developer": "https://{org}.arcpublishing.com/deployments/fusion/",
        "https://sandbox.{org}.arcpublishing.com/developer/": "https://{org}.arcpublishing.com/deployments/fusion/",
        "https://sandbox.{org}.arcpublishing.com/deployments/fusion/": "https://{org}.arcpublishing.com/deployments/fusion/",
        "https://sandbox.{org}.arcpublishing.com/developer/sites/": "https://{org}.arcpublishing.com/developer/sites",
        "https://api.sandbox.{org}.arcpublishing.com/content/v4": "https://api.{org}.arcpublishing.com/content/v4",
    ]

    /// Labels that were renamed along the way.
    static let renamedLabels: [String: String] = ["Dev Center": "Deployer"]
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
        // Empty means "read PORT from the project's .env", which is where the port actually
        // lives. Filling this in only makes sense for a stack that does not follow it.
        localURL: String = "",
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

    /// Tolerates projects stored by older builds, and drops the one default that turned out
    /// to be wrong.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        organization = try container.decodeIfPresent(String.self, forKey: .organization) ?? ""
        site = try container.decodeIfPresent(String.self, forKey: .site)
        let storedLinks = try container.decodeIfPresent([ArcLink].self, forKey: .links) ?? ArcLink.defaults()
        links = ArcProject.migrate(links: storedLinks)
        browser = try container.decodeIfPresent(BrowserChoice.self, forKey: .browser) ?? .systemDefault
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        startCommand = try container.decodeIfPresent(String.self, forKey: .startCommand) ?? "npx fusion daemon"
        stopCommand = try container.decodeIfPresent(String.self, forKey: .stopCommand) ?? "npx fusion stop"
        rebuildCommand = try container.decodeIfPresent(String.self, forKey: .rebuildCommand) ?? "npx fusion rebuild"
        teardownCommand = try container.decodeIfPresent(String.self, forKey: .teardownCommand) ?? "npx fusion down"
        healthPath = try container.decodeIfPresent(String.self, forKey: .healthPath) ?? "/release"
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true

        // `http://localhost` was an earlier default, not a decision anyone made, and it is
        // wrong for any project whose .env overrides PORT. Clearing it hands the question back
        // to the checkout; a project genuinely on port 80 resolves to the same URL anyway.
        let storedLocalURL = try container.decodeIfPresent(String.self, forKey: .localURL) ?? ""
        localURL = storedLocalURL == "http://localhost" ? "" : storedLocalURL
    }

    /// Brings a stored link list up to date: rewrites templates this project shipped and got
    /// wrong, applies renames, and appends links added since — otherwise a project made last
    /// week never learns about the ones added this week.
    static func migrate(links: [ArcLink]) -> [ArcLink] {
        let defaults = ArcLink.defaults()

        var updated = links.map { link -> ArcLink in
            var link = link
            if let template = ArcLink.supersededTemplates[link.urlTemplate] {
                link.urlTemplate = template
            }
            // Renamed only when it is still our link. Someone who pointed "Dev Center" at
            // their own page named it, and that name stays.
            if let newLabel = ArcLink.renamedLabels[link.label],
               let target = defaults.first(where: { $0.label == newLabel }),
               link.urlTemplate == target.urlTemplate {
                link.label = newLabel
            }
            return link
        }

        let known = Set(updated.map(\.label))
        for missing in ArcLink.defaults() where !known.contains(missing.label) {
            updated.append(missing)
        }
        return updated
    }

    /// Where the local stack serves: the override when one is set, otherwise `PORT` from the
    /// project's own `.env`.
    public var effectiveLocalURL: String {
        let explicit = localURL.trimmingCharacters(in: .whitespaces)
        guard explicit.isEmpty else { return explicit }
        return EnvFile.localURL(in: folderURL)
    }

    public var healthURL: URL? {
        let base = effectiveLocalURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + healthPath)
    }

    public var localSiteURL: URL? {
        URL(string: effectiveLocalURL)
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
