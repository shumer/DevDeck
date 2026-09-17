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
            let commits = "\(checkout.localCommits) commit\(checkout.localCommits == 1 ? "" : "s")"
            let action: AttentionAction = folders[checkout.id].map { .openTerminal($0) } ?? .none
            if checkout.hasUpstream {
                return AttentionItem(
                    id: "checkout:\(checkout.id):unpushed",
                    tier: .goodToKnow,
                    mark: .unpushed,
                    title: "\(commits) only on this Mac: \(checkout.title)",
                    subtitle: "\(checkout.branch) · oldest \(days) day\(days == 1 ? "" : "s") ago",
                    since: oldest,
                    action: action
                )
            }
            return AttentionItem(
                id: "checkout:\(checkout.id):noremote",
                tier: .goodToKnow,
                mark: .noRemote,
                title: "Branch not on any remote: \(checkout.title)",
                subtitle: "\(checkout.branch) · \(commits) · oldest \(days) day\(days == 1 ? "" : "s") ago",
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
                title: "Update to \(version)…",
                subtitle: "Restarts DevDeck, cards come back where they were",
                action: .installUpdate
            )
        case .waiting(let card):
            return AttentionItem(
                id: "update:\(version)", tier: .goodToKnow, mark: .update,
                title: "Update to \(version) waits for \(card)",
                subtitle: "Installs by itself when its command finishes",
                action: .none, isEnabled: false
            )
        case .downloading(let fraction):
            return AttentionItem(
                id: "update:\(version)", tier: .goodToKnow, mark: .update,
                title: "Downloading \(version)… \(Int((fraction * 100).rounded()))%",
                subtitle: "Restarts DevDeck when it is done",
                action: .none, isEnabled: false
            )
        case .installing:
            return AttentionItem(
                id: "update:\(version)", tier: .goodToKnow, mark: .update,
                title: "Installing \(version)…",
                subtitle: "Restarts DevDeck in a moment",
                action: .none, isEnabled: false
            )
        case .failed(let reason):
            return AttentionItem(
                id: "update:\(version)", tier: .goodToKnow, mark: .update,
                title: "Update to \(version) failed, click to retry",
                subtitle: reason,
                action: .installUpdate
            )
        }
    }
}
