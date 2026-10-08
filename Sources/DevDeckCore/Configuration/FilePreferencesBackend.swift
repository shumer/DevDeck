#if os(Windows)
import Foundation

/// Stores non-secret preferences atomically without sharing Foundation UserDefaults.
public final class FilePreferencesBackend: PreferencesBackend, @unchecked Sendable {
    private enum Value: Codable {
        case data(Data)
        case string(String)
        case bool(Bool)
    }

    private let lock = NSLock()
    private let file: URL
    private var values: [String: Value]

    public init(file: URL) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode([String: Value].self, from: data) {
            values = stored
        } else {
            values = [:]
        }
    }

    private static let shared: FilePreferencesBackend = {
        let base = ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? NSHomeDirectory()
        return FilePreferencesBackend(file: URL(fileURLWithPath: base)
            .appendingPathComponent("DevDeck/preferences.json"))
    }()

    public static func standard() -> FilePreferencesBackend { shared }

    public func data(forKey key: String) -> Data? {
        guard case .data(let value) = read(key) else { return nil }
        return value
    }

    public func string(forKey key: String) -> String? {
        guard case .string(let value) = read(key) else { return nil }
        return value
    }

    public func bool(forKey key: String) -> Bool {
        guard case .bool(let value) = read(key) else { return false }
        return value
    }

    public func hasValue(forKey key: String) -> Bool { read(key) != nil }

    public func set(_ data: Data?, forKey key: String) { write(data.map(Value.data), key) }
    public func set(_ string: String?, forKey key: String) { write(string.map(Value.string), key) }
    public func set(_ value: Bool, forKey key: String) { write(.bool(value), key) }

    private func read(_ key: String) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    private func write(_ value: Value?, _ key: String) {
        lock.lock()
        defer { lock.unlock() }
        var updated = values
        updated[key] = value
        do {
            let data = try JSONEncoder().encode(updated)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            values = updated
        } catch {
            Log.storage.debug("Could not save preferences.")
        }
    }
}
#endif
