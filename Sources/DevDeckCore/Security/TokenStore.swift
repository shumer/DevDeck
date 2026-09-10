import Foundation
import KeychainACL
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
    /// Who signed the running app, which decides how an item is protected. See
    /// `KeychainAccessPolicy`.
    private let identity: CodeIdentity.Kind

    public init(identity: CodeIdentity.Kind = CodeIdentity.current()) {
        self.identity = identity
    }

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

        // Deleted and re-added rather than updated, because an update leaves the old access
        // control list in place and the access control list is the whole point here.
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        // Tokens are only needed while the user is logged in and the machine is unlocked.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        // Only for a build with no identity to bind to. Signed, the default access list is
        // the right one: this application, and a prompt for anybody else.
        if KeychainAccessPolicy.opensAccess(for: identity), let access = Self.openAccess() {
            insert[kSecAttrAccess as String] = access
        }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw TokenStoreError.keychain(addStatus) }
    }

    /// An access control list that does not name a single application.
    ///
    /// For an ad-hoc build. A Keychain item is bound to the exact binary that wrote it, and an
    /// ad-hoc signature is different for every build, so the next launch is a different
    /// application as far as macOS is concerned and it asks for the Keychain password once per
    /// stored token. Three tokens, three password prompts, on every update.
    ///
    /// The trade is real and worth stating: any process running as this user can read these
    /// tokens without a prompt. It is the same trade `scripts/seed-token.sh` has always made with
    /// `security -A`. A build signed with an identity does not make it: see
    /// `KeychainAccessPolicy`. A token nobody stores because the prompt drove them off is not
    /// safer.
    ///
    /// The three calls it needs were deprecated with `SecKeychain` in 10.10 and have no modern
    /// equivalent, because on iOS the question does not arise, so they live in `KeychainACL` in C
    /// where a pragma can say they are deliberate.
    private static func openAccess() -> SecAccess? {
        devdeck_open_access("DevDeck" as CFString)?.takeRetainedValue()
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
/// running the app from a shell that already exports `GITHUB_TOKEN` or `GITLAB_TOKEN`.
public struct EnvironmentTokenStore: TokenStore {
    private let environment: [String: String]
    private let variableNames: [String: [String]]

    /// The first account of each service, by the names a shell would already have them under.
    public static let defaultVariableNames: [String: [String]] = [
        "github": ["DEVDECK_GITHUB_TOKEN", "GITHUB_TOKEN"],
        "gitlab": ["DEVDECK_GITLAB_TOKEN", "GITLAB_TOKEN"],
    ]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        variableNames: [String: [String]] = EnvironmentTokenStore.defaultVariableNames
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
