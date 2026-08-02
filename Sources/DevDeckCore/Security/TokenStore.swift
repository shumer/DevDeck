import Foundation
import Security

public struct TokenKey: Sendable, Hashable {
    public let service: String
    public let account: String

    public init(service: String = "com.shumer.devdeck", account: String) {
        self.service = service
        self.account = account
    }

    public static let github = TokenKey(account: "github")
}

public enum TokenStoreError: Error, Sendable, Equatable {
    case keychain(OSStatus)
    case readOnly
    case invalidEncoding
}

/// Where API tokens come from. Reading is separate from writing so the environment-backed
/// store can exist without pretending it can persist anything.
public protocol TokenStore: Sendable {
    func token(for key: TokenKey) throws -> String?
    func setToken(_ token: String?, for key: TokenKey) throws
}

/// The Keychain is the only place a token is persisted. It is never written to the repo,
/// to `UserDefaults`, or to a dotfile in the project.
public struct KeychainTokenStore: TokenStore {
    public init() {}

    public func token(for key: TokenKey) throws -> String? {
        var query = Self.baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw TokenStoreError.invalidEncoding
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case errSecItemNotFound:
            return nil
        default:
            throw TokenStoreError.keychain(status)
        }
    }

    public func setToken(_ token: String?, for key: TokenKey) throws {
        let query = Self.baseQuery(key)

        guard let token, !token.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TokenStoreError.keychain(status)
            }
            return
        }

        guard let data = token.data(using: .utf8) else { throw TokenStoreError.invalidEncoding }

        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw TokenStoreError.keychain(updateStatus) }

        var insert = query
        insert[kSecValueData as String] = data
        // Tokens are only needed while the user is logged in and the machine is unlocked.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw TokenStoreError.keychain(addStatus) }
    }

    private static func baseQuery(_ key: TokenKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.service,
            kSecAttrAccount as String: key.account,
        ]
    }
}

/// Reads tokens from the process environment. Used by the smoke-test tool and by anyone
/// running the app from a shell that already exports `GITHUB_TOKEN`.
public struct EnvironmentTokenStore: TokenStore {
    private let environment: [String: String]
    private let variableNames: [String: [String]]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        variableNames: [String: [String]] = ["github": ["DEVDECK_GITHUB_TOKEN", "GITHUB_TOKEN"]]
    ) {
        self.environment = environment
        self.variableNames = variableNames
    }

    public func token(for key: TokenKey) throws -> String? {
        for name in variableNames[key.account] ?? [] {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    public func setToken(_ token: String?, for key: TokenKey) throws {
        throw TokenStoreError.readOnly
    }
}

/// Tries each store in order for reads and writes to the first store that accepts them.
///
/// Order matters: the Keychain wins over the environment, so a token set in the app's
/// settings is not silently shadowed by a stale shell export.
public struct CompositeTokenStore: TokenStore {
    private let stores: [any TokenStore]

    public init(_ stores: [any TokenStore]) {
        self.stores = stores
    }

    public static func standard() -> CompositeTokenStore {
        CompositeTokenStore([KeychainTokenStore(), EnvironmentTokenStore()])
    }

    public func token(for key: TokenKey) throws -> String? {
        var lastError: Error?
        for store in stores {
            do {
                if let token = try store.token(for: key) { return token }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return nil
    }

    public func setToken(_ token: String?, for key: TokenKey) throws {
        var lastError: Error = TokenStoreError.readOnly
        for store in stores {
            do {
                try store.setToken(token, for: key)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

/// Test double.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [TokenKey: String]

    public init(tokens: [TokenKey: String] = [:]) {
        self.tokens = tokens
    }

    public func token(for key: TokenKey) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return tokens[key]
    }

    public func setToken(_ token: String?, for key: TokenKey) throws {
        lock.lock()
        defer { lock.unlock() }
        tokens[key] = token
    }
}
