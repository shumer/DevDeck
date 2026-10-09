import AppKit
import DevDeckCore
import GitHubKit
import GitLabKit

/// What the menu-bar item is saying, and why: the attention digest, with the icon and the
/// tooltip that follow from it.
///
/// The menu used to open on one greyed-out line, `1 waiting on you`, which named nothing and could
/// not be clicked. The icon now says which tier is lit, and the menu lists the things themselves.
public struct DeckStatusSummary: Sendable, Equatable {
    public let digest: AttentionDigest

    public init(digest: AttentionDigest) {
        self.digest = digest
    }

    public var state: DeckIconState { DeckIconState(tier: digest.iconTier) }

    /// One line. The list belongs in the menu; the tooltip only has to say whether opening it is
    /// worth it.
    public var tooltip: String { L("attention.tooltip", digest.summary) }
}
