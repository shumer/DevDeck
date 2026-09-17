import Foundation

/// One account that could not be reached during a refresh.
///
/// Carried on the snapshot rather than thrown, because with several accounts the useful
/// outcome is usually partial: three organisations loaded, one token expired. The card shows
/// what it has and says plainly that something is missing.
public struct AccountFailure: Sendable, Equatable, Codable {
    /// What went wrong, as far as the next step goes. The message alone could not say whether
    /// to replace a token or wait for a network, which is the only question the menu asks.
    public enum Kind: String, Sendable, Equatable, Codable {
        /// The token is missing, expired or revoked.
        case rejected
        /// The token works but is not allowed here, most often SSO not authorised.
        case forbidden
        case rateLimited
        /// The server or the network did not answer.
        case unreachable
        case other
    }

    /// The account's label, as shown in settings.
    public let account: String
    public let message: String
    /// The account's id, so the menu can open its form. Nil for a failure stored by an older
    /// version.
    public let accountID: String?
    public let kind: Kind
    /// When a spent rate limit comes back.
    public let resetAt: Date?

    public init(
        account: String,
        message: String,
        accountID: String? = nil,
        kind: Kind = .other,
        resetAt: Date? = nil
    ) {
        self.account = account
        self.message = message
        self.accountID = accountID
        self.kind = kind
        self.resetAt = resetAt
    }

    /// From what the transport threw.
    public init(account: String, accountID: String, error: Error) {
        guard let apiError = error as? APIError else {
            self.init(account: account, message: error.localizedDescription, accountID: accountID, kind: .unreachable)
            return
        }
        switch apiError {
        case .unauthorized, .missingToken:
            self.init(account: account, message: apiError.displayMessage, accountID: accountID, kind: .rejected)
        case .forbidden:
            self.init(account: account, message: apiError.displayMessage, accountID: accountID, kind: .forbidden)
        case .rateLimited(let resetAt):
            self.init(account: account, message: apiError.displayMessage, accountID: accountID, kind: .rateLimited, resetAt: resetAt)
        case .server, .transport:
            self.init(account: account, message: apiError.displayMessage, accountID: accountID, kind: .unreachable)
        case .notFound, .decoding, .graphQL, .accounts:
            self.init(account: account, message: apiError.displayMessage, accountID: accountID, kind: .other)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case account, message, accountID, kind, resetAt
    }

    /// Written out so a snapshot stored before `kind` existed still decodes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        account = try container.decode(String.self, forKey: .account)
        message = try container.decode(String.self, forKey: .message)
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .other
        resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
    }

    /// The line a card footer shows: who, what, and the next step when there is one.
    public var line: String {
        switch kind {
        case .rejected: return "\(account): token rejected, replace it in Settings"
        case .forbidden: return "\(account): \(message)"
        case .rateLimited: return "\(account): \(message)"
        case .unreachable: return "\(account): \(message), retrying"
        case .other: return "\(account): \(message)"
        }
    }
}

public extension Array where Element == AccountFailure {
    /// Footer text for a card, naming every account that is missing, or nothing when
    /// everything loaded.
    var summary: String? {
        guard !isEmpty else { return nil }
        if count == 1 { return self[0].line }
        return "\(map(\.account).joined(separator: ", ")) can't load, hover for why"
    }
}
