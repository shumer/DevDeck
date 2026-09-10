import Foundation

/// A version as GitHub tags it and `VERSION` states it: `v0.10`, `0.9.1`, `1.0`.
///
/// Compared by number, not by string: `0.10` is newer than `0.9`, and a string comparison
/// says the opposite.
public struct SemanticVersion: Comparable, Sendable, Equatable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        let parts = trimmed.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        components = parts.compactMap { $0 }
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public var description: String { components.map(String.init).joined(separator: ".") }
}

/// One file attached to a release.
public struct ReleaseAsset: Decodable, Sendable, Equatable {
    public let name: String
    public let browserDownloadUrl: URL
    public let size: Int

    public init(name: String, browserDownloadUrl: URL, size: Int) {
        self.name = name
        self.browserDownloadUrl = browserDownloadUrl
        self.size = size
    }
}

/// What GitHub says about a release. Only the fields the updater reads.
public struct Release: Decodable, Sendable, Equatable {
    public let tagName: String
    public let htmlUrl: URL
    public let draft: Bool
    public let prerelease: Bool
    public let publishedAt: Date?
    public let assets: [ReleaseAsset]

    public init(
        tagName: String,
        htmlUrl: URL,
        draft: Bool = false,
        prerelease: Bool = false,
        publishedAt: Date? = nil,
        assets: [ReleaseAsset]
    ) {
        self.tagName = tagName
        self.htmlUrl = htmlUrl
        self.draft = draft
        self.prerelease = prerelease
        self.publishedAt = publishedAt
        self.assets = assets
    }
}

/// A release worth installing: newer than what is running, and carrying a build to install.
public struct AvailableUpdate: Sendable, Equatable {
    public let version: SemanticVersion
    /// The release page, for "what's new".
    public let pageURL: URL
    public let asset: ReleaseAsset
    public let publishedAt: Date?

    public init(version: SemanticVersion, pageURL: URL, asset: ReleaseAsset, publishedAt: Date?) {
        self.version = version
        self.pageURL = pageURL
        self.asset = asset
        self.publishedAt = publishedAt
    }
}

/// Whether a newer build exists, and everything about installing one that does not need
/// AppKit: which release, which file, whether what was unpacked is really the app, and how
/// to come back up afterwards.
///
/// The updater in the app does the downloading, the swapping and the quitting; this is what
/// it decides by, and it is here so the suite can check the decisions.
public enum UpdateCheck {
    /// `owner/name` on GitHub.
    public static let repository = "shumer/DevDeck"

    /// The app's bundle identifier, which an unpacked update has to carry to be trusted.
    public static let bundleIdentifier = "com.shumer.devdeck"

    /// Once after launch, then this often. A release is a rare thing and GitHub's unauthenticated
    /// limit is sixty requests an hour per address.
    public static let interval: TimeInterval = 6 * 60 * 60

    /// How long after launch the first check runs. Not at launch: the deck is busy putting
    /// itself on screen, and an update is the least urgent thing it will do all day.
    public static let firstCheckDelay: TimeInterval = 30

    /// The latest release, unauthenticated: the repository is public, and a token would only
    /// tie the check to whichever account happens to be first.
    public static func request(repository: String = repository) -> HTTPRequest {
        HTTPRequest(
            url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!,
            headers: [
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            ]
        )
    }

    public static func decode(_ data: Data) throws -> Release {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Release.self, from: data)
    }

    /// The build attached to a release: what `build.sh` and the release workflow name it.
    public static func asset(in release: Release) -> ReleaseAsset? {
        release.assets.first { $0.name.hasPrefix("DevDeck-") && $0.name.hasSuffix(".zip") }
    }

    /// Nil when there is nothing to do: the release is a draft or a prerelease, it carries no
    /// build, its tag is not a version, or it is not newer than what is running.
    ///
    /// Not newer, rather than not equal: a deck built from a commit past the last tag runs a
    /// version the tag also names, and must not be offered itself.
    public static func available(current: String, release: Release) -> AvailableUpdate? {
        guard !release.draft, !release.prerelease,
              let latest = SemanticVersion(release.tagName),
              let running = SemanticVersion(current),
              latest > running,
              let asset = asset(in: release)
        else { return nil }
        return AvailableUpdate(
            version: latest,
            pageURL: release.htmlUrl,
            asset: asset,
            publishedAt: release.publishedAt
        )
    }

    /// Whether what was unpacked is this app at the version the release promised.
    ///
    /// Read from the bundle's own `Info.plist` rather than trusted from the file name. A zip
    /// that unpacks to something else, or to an older build under a newer name, is refused,
    /// and the running copy is left alone.
    public static func verifyBundle(at bundle: URL, version: SemanticVersion) -> Bool {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleIdentifier,
              let short = info["CFBundleShortVersionString"] as? String,
              let found = SemanticVersion(short)
        else { return false }
        return found == version
    }

    /// The bundle inside an unpacked archive, wherever `ditto` put it.
    public static func bundle(inUnpacked folder: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.first { $0.pathExtension == "app" }
    }

    /// What is left behind to bring the app back up.
    ///
    /// A shell that waits for the old process to be gone and then opens the new bundle at the
    /// same path. Waiting rather than sleeping a fixed time: quitting takes as long as it takes,
    /// and opening the bundle while the old process still holds it launches the old one.
    public static func relaunchScript(waitingFor pid: Int32, appPath: String) -> String {
        let quoted = "'" + appPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \(quoted)"
    }
}
