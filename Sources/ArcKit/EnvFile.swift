import Foundation

/// The project's own `.env`, which is where the local stack's port really lives.
///
/// Fusion defaults to port 80 but every project is free to override `PORT`, and the value in
/// the checkout is the only honest source — a port typed into settings goes stale the moment
/// someone edits `.env`.
public enum EnvFile {
    public static let defaultPort = 80

    public static func parse(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let separator = line.firstIndex(of: "=") else { continue }

            let key = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty else { continue }
            values[key] = String(value)
        }

        return values
    }

    public static func load(in directory: URL?) -> [String: String] {
        guard
            let directory,
            let contents = try? String(contentsOf: directory.appendingPathComponent(".env"), encoding: .utf8)
        else { return [:] }
        return parse(contents)
    }

    public static func port(in directory: URL?) -> Int {
        guard let raw = load(in: directory)["PORT"], let port = Int(raw), port > 0 else {
            return defaultPort
        }
        return port
    }

    /// Base URL the local stack serves on. Port 80 is left implicit, the way a browser shows it.
    public static func localURL(in directory: URL?) -> String {
        let port = port(in: directory)
        return port == defaultPort ? "http://localhost" : "http://localhost:\(port)"
    }
}
