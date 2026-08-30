import Foundation

/// A card folded down to one row.
///
/// The deck has two sizes and only two. A card is either the whole thing or a single row that
/// proves the thing exists: a logo, a name, a state dot and the one action that state implies.
/// A two-line version was drawn and dropped, because at 62 points the saving against a full card
/// is no longer decisive and the deck ends up with three sizes. Two sizes is a rule anyone can
/// hold in their head; three is a settings screen.
public enum CollapsedCardMetrics {
    public static let verticalPadding: Double = 10
    public static let rowHeight: Double = 24
    /// Fixed, unlike a full card's: there are no wrapping chips here, so there is nothing to
    /// measure.
    public static var height: Double { verticalPadding * 2 + rowHeight }

    /// The one number a collapsed card cannot inherit from a full one. At 44 points tall a
    /// 20-point radius eats most of the panel and the card reads as a pill.
    public static let cornerRadius: Double = 14
}
