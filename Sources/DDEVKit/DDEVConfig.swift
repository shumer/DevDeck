import Foundation

/// The bits of `.ddev/config.yaml` a card shows.
///
/// PHP and database versions are the usual answer to "it works on mine", and `ddev list`
/// does not carry them — only `ddev describe`, one process per project. The file is right
/// there in the checkout, so it is read directly, the same way the git branch and Arc's
/// `PORT` are.
public struct DDEVConfig: Sendable, Equatable {
    public var name: String?
    public var type: String?
    public var phpVersion: String?
    public var databaseType: String?
    public var databaseVersion: String?

    public init(
        name: String? = nil,
        type: String? = nil,
        phpVersion: String? = nil,
        databaseType: String? = nil,
        databaseVersion: String? = nil
    ) {
        self.name = name
        self.type = type
        self.phpVersion = phpVersion
        self.databaseType = databaseType
        self.databaseVersion = databaseVersion
    }

    /// `mysql 8.0`, or nil when the file says nothing about a database.
    public var databaseLabel: String? {
        switch (databaseType, databaseVersion) {
        case let (type?, version?): return "\(type) \(version)"
        case let (type?, nil): return type
        default: return nil
        }
    }

    /// Parses just enough YAML for those five values.
    ///
    /// A real YAML parser would be a dependency for four keys, and DDEV writes this file
    /// itself in a predictable shape: top-level scalars, and `database:` with two indented
    /// entries. Anything unexpected yields nil rather than a guess.
    public static func parse(_ contents: String) -> DDEVConfig {
        var config = DDEVConfig()
        var inDatabaseBlock = false

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let isIndented = line.first == " " || line.first == "\t"
            if !isIndented { inDatabaseBlock = trimmed.hasPrefix("database:") }

            guard let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<separator])
            let value = unquote(String(trimmed[trimmed.index(after: separator)...]))
            guard !value.isEmpty else { continue }

            if inDatabaseBlock, isIndented {
                switch key {
                case "type": config.databaseType = value
                case "version": config.databaseVersion = value
                default: break
                }
                continue
            }

            guard !isIndented else { continue }
            switch key {
            case "name": config.name = value
            case "type": config.type = value
            case "php_version": config.phpVersion = value
            default: break
            }
        }

        return config
    }

    public static func load(in folder: URL?) -> DDEVConfig {
        guard
            let folder,
            let contents = try? String(
                contentsOf: folder.appendingPathComponent(".ddev/config.yaml"),
                encoding: .utf8
            )
        else { return DDEVConfig() }
        return parse(contents)
    }

    /// Whether a folder is a DDEV project at all.
    public static func isProject(_ folder: URL?) -> Bool {
        guard let folder else { return false }
        return FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(".ddev/config.yaml").path
        )
    }

    private static func unquote(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        // Strip a trailing comment only when the value is not quoted, so a URL with a hash
        // in it survives.
        if !value.hasPrefix("\""), !value.hasPrefix("'"), let hash = value.firstIndex(of: "#") {
            value = String(value[value.startIndex..<hash]).trimmingCharacters(in: .whitespaces)
        }
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}
