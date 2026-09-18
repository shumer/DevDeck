import Foundation

/// Rows for work that exists only on this Mac.
///
/// Good to know, never a badge. Everybody keeps a local branch or two, and a badge that is lit
/// for as long as they exist is a badge that stops meaning anything.
public enum CheckoutAttention {
    /// How old unpushed work gets before it is worth a row.
    public static let unpushedAfter: TimeInterval = 3 * 86_400

    public static func items(checkouts: [CheckoutState], folders: [String: URL], now: Date) -> [AttentionItem] {
        checkouts.compactMap { checkout in
            guard checkout.localCommits > 0,
                  let oldest = checkout.oldestLocalCommitAt,
                  now.timeIntervalSince(oldest) >= unpushedAfter
            else { return nil }
            let days = Int(now.timeIntervalSince(oldest) / 86_400)
            let commits = LN("attention.local.commits", checkout.localCommits)
            let action: AttentionAction = folders[checkout.id].map { .openTerminal($0) } ?? .none
            if checkout.hasUpstream {
                return AttentionItem(
                    id: "checkout:\(checkout.id):unpushed",
                    tier: .goodToKnow,
                    mark: .unpushed,
                    title: L("attention.local.unpushed.title", commits, checkout.title),
                    subtitle: L("attention.local.unpushed.subtitle", checkout.branch, LN("attention.local.days", days)),
                    since: oldest,
                    action: action
                )
            }
            return AttentionItem(
                id: "checkout:\(checkout.id):noremote",
                tier: .goodToKnow,
                mark: .noRemote,
                title: L("attention.local.noRemote.title", checkout.title),
                subtitle: L("attention.local.noRemote.subtitle", checkout.branch, commits, LN("attention.local.days", days)),
                since: oldest,
                action: action
            )
        }
    }
}

/// The row for a newer DevDeck.
public enum UpdateAttention {
    public enum Phase: Sendable, Equatable {
        case available
        /// An install somebody asked for, waiting for a card's command to finish.
        case waiting(card: String)
        case downloading(fraction: Double)
        case installing
        case failed(reason: String)
    }

    public static func item(version: String, phase: Phase) -> AttentionItem {
        switch phase {
        case .available:
            return AttentionItem(
                id: "update:\(version)", tier: .goodToKnow, mark: .update,
                title: L("attention.update.available.title", version),
                subtitle: L("attention.update.available.subtitle"),
                action: .installUpdate
            )
        case .waiting(let card):
            return AttentionItem(
                id: "update:\(version)", tier: .goodToKnow, mark: .update,
                title: L("attention.update.waits.title", version, card),
                subtitle: L("attention.update.waits.subtitle"),
                action: .none, isEnabled: false
            )
        case .downloading(let fraction):
            return AttentionItem(
                id: "update:\(version)", tier: .goodToKnow, mark: .update,
                title: L("attention.update.downloading.title", version, Int((fraction * 100).rounded())),
                subtitle: L("attention.update.downloading.subtitle"),
                action: .none, isEnabled: false
            )
        case .installing:
            return AttentionItem(
                id: "update:\(version)", tier: .goodToKnow, mark: .update,
                title: L("attention.update.installing.title", version),
                subtitle: L("attention.update.installing.subtitle"),
                action: .none, isEnabled: false
            )
        case .failed(let reason):
            return AttentionItem(
                id: "update:\(version)", tier: .goodToKnow, mark: .update,
                title: L("attention.update.failed.title", version),
                subtitle: reason,
                action: .installUpdate
            )
        }
    }
}
