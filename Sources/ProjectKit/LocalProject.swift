import DevDeckCore
import Foundation

/// What a link on a plain project card points at. The card groups and colours by this rather
/// than by label, so a renamed link keeps its place.
public enum LocalProjectLinkKind: String, Sendable, Equatable, Codable {
    /// The site itself, in some environment.
    case site
    /// Something you work in rather than look at: an admin page, a mail catcher, a profiler.
    case tool
}

/// One link on a plain project card.
public struct LocalProjectLink: Sendable, Equatable, Codable, Identifiable {
    public var label: String
    /// `{site}` is substituted with the project's local URL, so a tool hanging off the local
    /// site does not have to repeat the port.
    public var urlTemplate: String
    public var isEnabled: Bool
    public var kind: LocalProjectLinkKind

    public init(
        label: String,
        urlTemplate: String,
        isEnabled: Bool = true,
        kind: LocalProjectLinkKind = .site
    ) {
        self.label = label
        self.urlTemplate = urlTemplate
        self.isEnabled = isEnabled
        self.kind = kind
    }

    /// The deployed environments, the same three every project here has. Nothing can derive
    /// them - each lives on its own domain - so they ship empty for the user to paste in.
    public static func defaultEnvironments() -> [LocalProjectLink] {
        ["Test", "UAT", "Prod"].map {
            LocalProjectLink(label: $0, urlTemplate: "", isEnabled: false, kind: .site)
        }
    }

    public var id: String { label }

    public func url(localSite: URL?) -> URL? {
        let site = localSite?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let resolved = urlTemplate.replacingOccurrences(of: "{site}", with: site)
        guard !resolved.isEmpty else { return nil }
        return URL(string: resolved)
    }
}

/// A project that is neither Arc nor DDEV: a folder, a command that starts it, and a URL that
/// proves it worked.
///
/// The three fields at the heart of it are deliberately unopinionated. `docker compose up -d`
/// returns as soon as the containers are up, while `npm run dev` holds its terminal until it is
/// killed - the difference is one checkbox rather than two kinds of project, because everything
/// downstream of it is the same.
public struct LocalProject: Sendable, Equatable, Codable, Identifiable {
    /// Stable slug used in the card identifier, so it is never renamed.
    public let id: String
    public var title: String
    /// What the footer says the project is - `vite`, `docker compose`. Free text; nothing
    /// derives behaviour from it.
    public var subtitle: String
    public var folder: String?
    public var startCommand: String
    /// Empty means "kill what we started", which is the only sensible stop for a command that
    /// holds its own process.
    public var stopCommand: String
    /// Whether the start command keeps running. `npm run dev` does; `docker compose up -d`
    /// does not.
    public var holdsProcess: Bool
    /// Nothing containerised can start without Docker, and a Start button that cannot work is
    /// worse than a disabled one.
    public var requiresDocker: Bool
    /// The URL that answers when the project is up. Empty falls back to the started process
    /// still being alive, which is weaker but better than nothing.
    public var healthURL: String
    /// What the Local site chip opens. Empty means the health URL, which it usually is.
    public var localSiteURL: String
    public var links: [LocalProjectLink]
    public var browser: BrowserChoice
    public var isEnabled: Bool

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        folder: String? = nil,
        startCommand: String = "",
        stopCommand: String = "",
        holdsProcess: Bool = false,
        requiresDocker: Bool = false,
        healthURL: String = "",
        localSiteURL: String = "",
        links: [LocalProjectLink] = LocalProjectLink.defaultEnvironments(),
        browser: BrowserChoice = .systemDefault,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.folder = folder
        self.startCommand = startCommand
        self.stopCommand = stopCommand
        self.holdsProcess = holdsProcess
        self.requiresDocker = requiresDocker
        self.healthURL = healthURL
        self.localSiteURL = localSiteURL
        self.links = links
        self.browser = browser
        self.isEnabled = isEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        startCommand = try container.decodeIfPresent(String.self, forKey: .startCommand) ?? ""
        stopCommand = try container.decodeIfPresent(String.self, forKey: .stopCommand) ?? ""
        holdsProcess = try container.decodeIfPresent(Bool.self, forKey: .holdsProcess) ?? false
        requiresDocker = try container.decodeIfPresent(Bool.self, forKey: .requiresDocker) ?? false
        healthURL = try container.decodeIfPresent(String.self, forKey: .healthURL) ?? ""
        localSiteURL = try container.decodeIfPresent(String.self, forKey: .localSiteURL) ?? ""
        // Environments added after a project was created are appended, so an existing card does
        // not quietly miss them.
        let stored = try container.decodeIfPresent([LocalProjectLink].self, forKey: .links) ?? []
        let known = Set(stored.map(\.label))
        links = stored + LocalProjectLink.defaultEnvironments().filter { !known.contains($0.label) }
        browser = try container.decodeIfPresent(BrowserChoice.self, forKey: .browser) ?? .systemDefault
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return folderURL?.lastPathComponent ?? id
    }

    public var folderURL: URL? {
        guard let folder, !folder.isEmpty else { return nil }
        return URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Nothing local can be done without a folder to do it in.
    public var supportsCommands: Bool { folderURL != nil && !startCommand.isEmpty }

    public var healthCheckURL: URL? {
        let trimmed = healthURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    /// What the Local site chip opens: the override when there is one, otherwise whatever is
    /// being health-checked - for a dev server they are the same address.
    public var siteURL: URL? {
        let trimmed = localSiteURL.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return URL(string: trimmed) }
        return healthCheckURL
    }

    /// Tooling: whatever runs alongside the site.
    public func toolLinks() -> [LocalProjectResolvedLink] {
        resolve(links.filter { $0.kind == .tool })
    }

    /// The environments, local first - the local one is derived, the deployed ones are typed in.
    public func environmentLinks() -> [LocalProjectResolvedLink] {
        var resolved: [LocalProjectResolvedLink] = []
        if let site = siteURL {
            resolved.append(LocalProjectResolvedLink(label: "Local site", url: site, kind: .site))
        }
        resolved.append(contentsOf: resolve(links.filter { $0.kind == .site }))
        return resolved
    }

    private func resolve(_ links: [LocalProjectLink]) -> [LocalProjectResolvedLink] {
        links.compactMap { link in
            guard link.isEnabled, let url = link.url(localSite: siteURL) else { return nil }
            return LocalProjectResolvedLink(label: link.label, url: url, kind: link.kind)
        }
    }

    public var cardID: CardID { CardID(rawValue: "project.\(id)") }

    public static func makeID(from name: String, existing: [String]) -> String {
        let allowed = CharacterSet.alphanumerics
        let base = name.lowercased().unicodeScalars
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

/// A link with its placeholders filled in, ready for the card.
public struct LocalProjectResolvedLink: Sendable, Equatable, Identifiable {
    public let label: String
    public let url: URL
    public let kind: LocalProjectLinkKind

    public init(label: String, url: URL, kind: LocalProjectLinkKind) {
        self.label = label
        self.url = url
        self.kind = kind
    }

    public var id: String { label }
}

/// Reads and writes the plain project list.
public struct LocalProjectsStore: Sendable {
    private let backend: any PreferencesBackend
    private static let key = "local.projects"

    public init(backend: any PreferencesBackend) {
        self.backend = backend
    }

    public func projects() -> [LocalProject] {
        guard
            let data = backend.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([LocalProject].self, from: data)
        else { return [] }
        return decoded
    }

    public func enabledProjects() -> [LocalProject] {
        projects().filter(\.isEnabled)
    }

    public func project(forCard card: CardID) -> LocalProject? {
        projects().first { $0.cardID == card }
    }

    public func save(_ projects: [LocalProject]) {
        backend.set(try? JSONEncoder().encode(projects), forKey: Self.key)
    }
}
