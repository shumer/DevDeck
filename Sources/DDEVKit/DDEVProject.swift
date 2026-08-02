import DevDeckCore
import Foundation

/// An extra link on a DDEV card.
///
/// The useful ones — the site, Mailpit, xhgui — come from DDEV itself and need no
/// configuring; this is for whatever else a project wants, such as an admin login page.
public struct DDEVCustomLink: Sendable, Equatable, Codable, Identifiable {
    public var label: String
    /// `{site}` is substituted with the project's primary URL.
    public var urlTemplate: String
    public var isEnabled: Bool

    public init(label: String, urlTemplate: String, isEnabled: Bool = true) {
        self.label = label
        self.urlTemplate = urlTemplate
        self.isEnabled = isEnabled
    }

    public var id: String { label }

    public func url(primaryURL: URL?) -> URL? {
        let resolved = urlTemplate.replacingOccurrences(
            of: "{site}",
            with: primaryURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        )
        return URL(string: resolved)
    }
}

/// A project managed by DDEV.
///
/// Deliberately thin: DDEV already knows the name, the type, the URLs and the state, so the
/// only thing worth storing is which folder to ask about and how the user wants it shown.
public struct DDEVProject: Sendable, Equatable, Codable, Identifiable {
    /// Stable slug used in the card identifier, so it is never renamed.
    public let id: String
    /// The DDEV project name, which is how `ddev list` identifies it.
    public var name: String
    /// Overrides the card's title. Empty means "use the DDEV name".
    public var title: String
    public var folder: String?
    public var showsMailpit: Bool
    public var showsXhgui: Bool
    public var customLinks: [DDEVCustomLink]
    public var browser: BrowserChoice
    public var isEnabled: Bool

    public init(
        id: String,
        name: String,
        title: String = "",
        folder: String? = nil,
        showsMailpit: Bool = true,
        showsXhgui: Bool = false,
        customLinks: [DDEVCustomLink] = [],
        browser: BrowserChoice = .systemDefault,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.folder = folder
        self.showsMailpit = showsMailpit
        self.showsXhgui = showsXhgui
        self.customLinks = customLinks
        self.browser = browser
        self.isEnabled = isEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        showsMailpit = try container.decodeIfPresent(Bool.self, forKey: .showsMailpit) ?? true
        showsXhgui = try container.decodeIfPresent(Bool.self, forKey: .showsXhgui) ?? false
        customLinks = try container.decodeIfPresent([DDEVCustomLink].self, forKey: .customLinks) ?? []
        browser = try container.decodeIfPresent(BrowserChoice.self, forKey: .browser) ?? .systemDefault
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }

    public var folderURL: URL? {
        guard let folder, !folder.isEmpty else { return nil }
        return URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
    }

    public var cardID: CardID { CardID(rawValue: "ddev.project.\(id)") }

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

    /// The chips for this project, given what DDEV last reported.
    ///
    /// A link to a stopped project goes nowhere, so those chips are dimmed rather than
    /// hidden: the row keeps its shape and says why nothing happens.
    public func links(status: DDEVStatus) -> [DDEVResolvedLink] {
        let entry = status.entry
        var links: [DDEVResolvedLink] = []

        if let site = entry?.primaryURL {
            links.append(DDEVResolvedLink(label: "Site", url: site, kind: .site))
        }
        if showsMailpit, let mailpit = entry?.mailpitURL {
            links.append(DDEVResolvedLink(label: "Mailpit", url: mailpit, kind: .tool))
        }
        if showsXhgui, let xhgui = entry?.xhguiURL {
            links.append(DDEVResolvedLink(label: "xhgui", url: xhgui, kind: .tool))
        }
        for custom in customLinks where custom.isEnabled {
            guard let url = custom.url(primaryURL: entry?.primaryURL) else { continue }
            links.append(DDEVResolvedLink(label: custom.label, url: url, kind: .tool))
        }

        return links
    }
}

public enum DDEVLinkKind: Sendable, Equatable {
    case site
    case tool
}

public struct DDEVResolvedLink: Sendable, Equatable, Identifiable {
    public let label: String
    public let url: URL
    public let kind: DDEVLinkKind

    public init(label: String, url: URL, kind: DDEVLinkKind) {
        self.label = label
        self.url = url
        self.kind = kind
    }

    public var id: String { label }
}

/// Reads and writes the DDEV project list.
public struct DDEVProjectsStore: Sendable {
    private let backend: any PreferencesBackend
    private static let key = "ddev.projects"

    public init(backend: any PreferencesBackend) {
        self.backend = backend
    }

    public func projects() -> [DDEVProject] {
        guard
            let data = backend.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([DDEVProject].self, from: data)
        else { return [] }
        return decoded
    }

    public func enabledProjects() -> [DDEVProject] {
        projects().filter(\.isEnabled)
    }

    public func project(forCard card: CardID) -> DDEVProject? {
        projects().first { $0.cardID == card }
    }

    public func save(_ projects: [DDEVProject]) {
        backend.set(try? JSONEncoder().encode(projects), forKey: Self.key)
    }
}
