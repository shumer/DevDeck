import Foundation

/// Rows for accounts that cannot be read, in the same words for either service.
public enum AccountAttention {
    /// How long a network or server failure is tolerated before it becomes something to fix. A
    /// laptop changes networks and a server restarts; neither is news for the first few minutes.
    public static let unreachableAfter: TimeInterval = 15 * 60

    public static func items(
        failures: [AccountFailure],
        service: AttentionService,
        now: Date,
        unreachableAfter: TimeInterval = AccountAttention.unreachableAfter,
        failingSince: [String: Date]
    ) -> [AttentionItem] {
        var seen = Set<String>()
        return failures.compactMap { failure in
            let key = failure.accountID ?? failure.account
            guard seen.insert(key).inserted else { return nil }
            let since = failingSince[key]
            let settings: AttentionAction = failure.accountID.map { .accountSettings(service: service, account: $0) } ?? .none

            switch failure.kind {
            case .rejected where failure.accountID == nil:
                return AttentionItem(
                    id: "account:\(service.rawValue):missing",
                    tier: .needsFixing,
                    mark: .token,
                    title: L("attention.account.missing.title", service.name),
                    subtitle: L("attention.account.missing.subtitle", service.name),
                    since: since,
                    action: .accountSettings(service: service, account: "")
                )
            case .rejected:
                return AttentionItem(
                    id: "account:\(service.rawValue):\(key):rejected",
                    tier: .needsFixing,
                    mark: .token,
                    title: L("attention.account.rejected.title", service.name, failure.account),
                    subtitle: L("attention.account.rejected.subtitle", failure.message),
                    since: since,
                    action: settings
                )
            case .forbidden:
                return AttentionItem(
                    id: "account:\(service.rawValue):\(key):forbidden",
                    tier: .needsFixing,
                    mark: .token,
                    title: L("attention.account.forbidden.title", service.name, failure.account),
                    subtitle: AttentionWords.trimmed(L("attention.account.forbidden.subtitle", failure.message), to: 90),
                    since: since,
                    action: settings
                )
            case .rateLimited:
                return AttentionItem(
                    id: "account:\(service.rawValue):\(key):rate",
                    tier: .goodToKnow,
                    mark: .rateLimit,
                    title: L("attention.account.rate.title", service.name, failure.account),
                    subtitle: failure.resetAt.map { L("attention.account.rate.back", AttentionDigest.clock($0)) } ?? L("attention.account.rate.self"),
                    since: since,
                    action: .none,
                    isEnabled: false
                )
            case .other:
                // Not the network: the server answered and refused, or answered something that
                // cannot be read. That does not pass by itself.
                return AttentionItem(
                    id: "account:\(service.rawValue):\(key):error",
                    tier: .needsFixing,
                    mark: .token,
                    title: L("attention.account.refused.title", service.name, failure.account),
                    subtitle: AttentionWords.trimmed(failure.message, to: 90),
                    since: since,
                    action: settings
                )
            case .unreachable:
                let isLong = since.map { now.timeIntervalSince($0) >= unreachableAfter } ?? false
                return AttentionItem(
                    id: "account:\(service.rawValue):\(key):unreachable",
                    tier: isLong ? .needsFixing : .goodToKnow,
                    mark: .network,
                    title: L("attention.account.unreachable.title", service.name, failure.account),
                    subtitle: since.map { L("attention.account.unreachable.subtitle", failure.message, AttentionDigest.clock($0)) } ?? failure.message,
                    since: since,
                    action: settings,
                    isEnabled: isLong
                )
            }
        }
    }

    /// The banner for a token that stopped working. Once per account per episode: the id changes
    /// only when the failure starts again after a success.
    public static func alert(for failure: AccountFailure, service: AttentionService, since: Date?) -> DeckAlert? {
        guard failure.kind == .rejected, let accountID = failure.accountID else { return nil }
        let episode = since.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        return DeckAlert(
            id: "account:\(service.rawValue):\(accountID):rejected:\(episode)",
            kind: .cantCheck,
            source: .devdeck,
            title: L("attention.account.banner.title", failure.account, service.name),
            subtitle: L("attention.account.banner.subtitle"),
            body: L("attention.account.banner.body", failure.account),
            subject: failure.account,
            target: .accountSettings(service: service.rawValue, account: accountID),
            isQuiet: false
        )
    }
}
