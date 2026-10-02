import DevDeckCore
import Foundation

/// Linux Foundation cannot read Apple's stringsdict plural records safely. Prepare an owned
/// copy once before starting any requests; keep original Mac resources and Strings unchanged.
/// Numeric worker wording uses each original `other` form. Native WIF presentation rebuilds
/// its title/subtitle from validated facts with the correct Windows plural rules.
public final class WorkerStartupLocalization {
    public enum Failure: Error { case unavailable }
    public let root: URL

    public init(originalRoot: URL) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-worker-localization-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            for language in AppLanguage.allCases where language != .system {
                let source = originalRoot.appendingPathComponent(language.rawValue + ".lproj")
                let stringsData = try Data(contentsOf: source.appendingPathComponent("Localizable.strings"))
                let pluralData = try Data(contentsOf: source.appendingPathComponent("Localizable.stringsdict"))
                guard stringsData.count <= WorkerProtocol.maximumFrameBytes, pluralData.count <= WorkerProtocol.maximumFrameBytes,
                      var table = try PropertyListSerialization.propertyList(from: stringsData, format: nil) as? [String: String],
                      let plurals = try PropertyListSerialization.propertyList(from: pluralData, format: nil) as? [String: [String: Any]] else { throw Failure.unavailable }
                for (key, entry) in plurals {
                    guard entry["NSStringLocalizedFormatKey"] as? String == "%#@count@",
                          let count = entry["count"] as? [String: String], count["NSStringFormatSpecTypeKey"] == "NSStringPluralRuleType",
                          count["NSStringFormatValueTypeKey"] == "d", let other = count["other"], !other.contains("%#@") else { throw Failure.unavailable }
                    table[key] = other
                }
                guard table["attention.local.commits"] != nil, table["attention.local.days"] != nil else { throw Failure.unavailable }
                let destination = root.appendingPathComponent(language.rawValue + ".lproj")
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                let data = try PropertyListSerialization.data(fromPropertyList: table, format: .xml, options: 0)
                try data.write(to: destination.appendingPathComponent("Localizable.strings"), options: .atomic)
                guard Bundle(url: destination) != nil else { throw Failure.unavailable }
            }
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw Failure.unavailable
        }
    }
    /// Call at startup, before readers exist. Tests may select languages sequentially.
    public func use(_ language: AppLanguage) throws {
        guard language != .system,
              Bundle(url: root.appendingPathComponent(language.rawValue + ".lproj")) != nil,
              Bundle(url: root.appendingPathComponent("en.lproj")) != nil else { throw Failure.unavailable }
        Strings.use(language, lookingIn: root)
    }
    public func close() { try? FileManager.default.removeItem(at: root) }
    deinit { close() }
}
