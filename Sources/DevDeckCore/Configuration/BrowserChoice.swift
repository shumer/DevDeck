import Foundation

/// Which browser, and which profile inside it, a link should open in.
///
/// This exists because github.com allows exactly one signed-in identity per browser profile.
/// With a work account and a personal one, "open in the default browser" is wrong half the
/// time, and no amount of link handling inside one profile can fix it.
public struct BrowserChoice: Sendable, Equatable, Codable {
    /// Nil means the system default browser.
    public var bundleIdentifier: String?
    /// Chromium's `--profile-directory` value, such as `Default` or `Profile 2`. Nil means
    /// whichever profile the browser opens on its own.
    public var profileDirectory: String?

    public init(bundleIdentifier: String? = nil, profileDirectory: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.profileDirectory = profileDirectory
    }

    public static let systemDefault = BrowserChoice()

    public var isSystemDefault: Bool { bundleIdentifier == nil }
}

/// One profile inside a Chromium-family browser.
public struct BrowserProfile: Sendable, Equatable, Identifiable {
    /// The on-disk directory name, which is what `--profile-directory` takes.
    public let directory: String
    /// What the user called it.
    public let name: String

    public init(directory: String, name: String) {
        self.directory = directory
        self.name = name
    }

    public var id: String { directory }
}

/// Reads the profile list out of a Chromium `Local State` file.
///
/// Kept as a pure function over the file's contents so it can be covered by the offline
/// suite; the app supplies the bytes.
public enum ChromiumProfiles {
    public static func parse(localState data: Data) -> [BrowserProfile] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = root["profile"] as? [String: Any],
            let cache = profile["info_cache"] as? [String: Any]
        else { return [] }

        var profiles: [BrowserProfile] = []
        for (directory, value) in cache {
            let entry = value as? [String: Any]
            // Chrome falls back to the directory name when a profile has never been named.
            let name = (entry?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? directory
            profiles.append(BrowserProfile(directory: directory, name: name))
        }

        // `Default` first, then the numbered ones in their natural order rather than the
        // dictionary's, so the list does not reshuffle between launches.
        return profiles.sorted { left, right in
            if left.directory == "Default" { return true }
            if right.directory == "Default" { return false }
            return left.directory.localizedStandardCompare(right.directory) == .orderedAscending
        }
    }
}
