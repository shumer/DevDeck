import Foundation

/// One account that could not be reached during a refresh.
///
/// Carried on the snapshot rather than thrown, because with several accounts the useful
/// outcome is usually partial: three organisations loaded, one token expired. The card shows
/// what it has and says plainly that something is missing.
public struct AccountFailure: Sendable, Equatable, Codable {
    /// The account's label, as shown in settings.
    public let account: String
    public let message: String

    public init(account: String, message: String) {
        self.account = account
        self.message = message
    }
}

public extension Array where Element == AccountFailure {
    /// Footer text for a card: "1 account failed", or nothing when everything loaded.
    var summary: String? {
        guard !isEmpty else { return nil }
        if count == 1 { return "\(self[0].account): \(self[0].message)" }
        return "\(count) accounts failed"
    }
}
