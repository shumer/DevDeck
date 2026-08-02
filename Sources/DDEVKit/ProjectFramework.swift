import Foundation

/// What a project is actually built on, read from `composer.lock`.
///
/// `.ddev/config.yaml` has a `type:` — but it configures DDEV's own behaviour and nobody
/// updates it after a major upgrade: two projects here still said `drupal9` while running
/// Drupal 11.4.4 and 10.6.11. The lock file cannot be stale in the same way, because it is
/// what the code is installed from.
public enum ProjectFramework {
    /// Packages worth naming, in the order they are looked for.
    private static let known: [(package: String, label: String)] = [
        ("drupal/core", "drupal"),
        ("typo3/cms-core", "typo3"),
        ("laravel/framework", "laravel"),
        ("symfony/framework-bundle", "symfony"),
    ]

    /// `drupal 11.4.4`, or nil when there is no lock file to read.
    public static func label(in folder: URL?) -> String? {
        guard let folder else { return nil }
        let lock = folder.appendingPathComponent("composer.lock")

        let attributes = try? FileManager.default.attributesOfItem(atPath: lock.path)
        let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast
        if let cached = cache.value(for: lock.path, modified: modified) { return cached.label }

        guard let data = try? Data(contentsOf: lock) else {
            cache.store(nil, for: lock.path, modified: modified)
            return nil
        }
        let label = parse(composerLock: data)
        cache.store(label, for: lock.path, modified: modified)
        return label
    }

    public static func parse(composerLock data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let packages = root["packages"] as? [[String: Any]]
        else { return nil }

        for candidate in known {
            guard let package = packages.first(where: { $0["name"] as? String == candidate.package }),
                  let version = package["version"] as? String
            else { continue }
            // Composer writes tags as `v1.2.3` for some projects and bare for others.
            let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
            return "\(candidate.label) \(trimmed)"
        }
        return nil
    }

    /// A lock file is megabytes of JSON and the card asks every ten seconds, so the answer is
    /// kept until the file itself changes.
    private static let cache = FrameworkCache()
}

private final class FrameworkCache: @unchecked Sendable {
    private struct Entry {
        let modified: Date
        let label: String?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func value(for path: String, modified: Date) -> (label: String?, Void)? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path], entry.modified == modified else { return nil }
        return (entry.label, ())
    }

    func store(_ label: String?, for path: String, modified: Date) {
        lock.lock()
        defer { lock.unlock() }
        entries[path] = Entry(modified: modified, label: label)
    }
}
