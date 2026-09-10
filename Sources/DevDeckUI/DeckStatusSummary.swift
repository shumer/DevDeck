import AppKit
import DevDeckCore
import GitHubKit

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

    /// Assembles the summary from what the deck knows.
    ///
    /// Pure, so the suite can check the counting: the icon used to go red for any of three
    /// different things, and which of them lit it was worked out in the same object that
    /// drew the menu. `projectLines` are already worded by the caller, because what a project
    /// line says depends on which kind of project it is and that is not this type's business.
    public static func make(
        activeCards: Set<CardID>,
        pullRequests: PullRequestsSnapshot?,
        inbox: InboxSnapshot?,
        projectLines: [String],
        hasLocalCards: Bool,
        docker: DockerStatus
    ) -> DeckStatusSummary {
        var lines: [String] = []
        // Kept apart on purpose. The icon used to go red for any of these, which made it say
        // "something" and nothing about what, so the reason lived in a tooltip nobody hovers
        // long enough to read.
        var blockedCount = 0
        var waitingCount = 0

        if activeCards.contains(.githubPullRequests) {
            if let pullRequests {
                var line = "\(pullRequests.totalCount) open pull request\(pullRequests.totalCount == 1 ? "" : "s")"
                if pullRequests.blockedCount > 0 {
                    line += ", \(pullRequests.blockedCount) blocked"
                    blockedCount += pullRequests.blockedCount
                }
                if pullRequests.reviewRequestCount > 0 {
                    line += ", \(pullRequests.reviewRequestCount) waiting for your review"
                    waitingCount += pullRequests.reviewRequestCount
                }
                lines.append(line)
            } else {
                lines.append("Pull requests: not loaded yet")
            }
        }

        if activeCards.contains(.githubInbox), let inbox {
            var line = "\(inbox.unreadCount) unread"
            if inbox.actionableCount > 0 {
                line += ", \(inbox.actionableCount) waiting on you"
                waitingCount += inbox.actionableCount
            }
            lines.append(line)
        }

        lines.append(contentsOf: projectLines)

        // Said once, at the bottom, rather than repeated on every project line. Not an alert:
        // Docker being off is a normal state of a laptop, not something gone wrong.
        if hasLocalCards, let reason = docker.blockingReason {
            lines.append(reason)
        }

        if lines.isEmpty { lines.append("No cards on screen") }
        return DeckStatusSummary(
            tooltip: "DevDeck\n" + lines.joined(separator: "\n"),
            blockedCount: blockedCount,
            waitingCount: waitingCount
        )
    }
}
