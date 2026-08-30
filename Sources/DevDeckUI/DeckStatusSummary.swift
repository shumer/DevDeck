import AppKit

/// What the menu-bar item is saying, and why.
///
/// The why is the part that was missing. A red icon that means "a review is waiting" or "your
/// own pull request is stuck" or "the inbox has something actionable" is a red icon that means
/// nothing in particular, so the two are separated here and the reason is a sentence the menu
/// can put on its first line.
public struct DeckStatusSummary {
    public init(tooltip: String, blockedCount: Int, waitingCount: Int) {
        self.tooltip = tooltip
        self.blockedCount = blockedCount
        self.waitingCount = waitingCount
    }

    public let tooltip: String
    /// Pull requests of yours that cannot move.
    public let blockedCount: Int
    /// Things another person is waiting on you for.
    public let waitingCount: Int

    /// Somebody waiting on you outranks your own queue being stuck: one of the two costs
    /// another person time.
    public var state: DeckIconState {
        if waitingCount > 0 { return .waiting }
        return blockedCount > 0 ? .blocked : .calm
    }

    /// The line the menu opens with, in words, so "why is it red" is answered by opening the
    /// menu rather than by hovering and waiting for a tooltip.
    public var reason: String? {
        var parts: [String] = []
        if waitingCount > 0 {
            parts.append("\(waitingCount) waiting on you")
        }
        if blockedCount > 0 {
            parts.append("\(blockedCount) of yours blocked")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
