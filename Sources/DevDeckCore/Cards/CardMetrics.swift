import Foundation

/// How tall a card is for a given number of rows.
///
/// Lives here rather than in the view layer because two places have to agree on it exactly:
/// the SwiftUI card that draws the rows, and the AppKit panel that has to be resized around
/// them. A disagreement shows up as a clipped last row or a strip of empty glass.
public enum CardMetrics {
    public static let width: Double = 320
    public static let rowHeight: Double = 27
    public static let expanderHeight: Double = 22

    /// Rows shown before the card is expanded. Three is what fits without the panel becoming
    /// something you read rather than glance at.
    public static let collapsedRows = 3

    /// Ceiling on the expanded card, so a busy week cannot produce a panel taller than the
    /// screen.
    public static let maxExpandedRows = 12

    public static func rowCount(total: Int, isExpanded: Bool) -> Int {
        guard isExpanded else { return min(total, collapsedRows) }
        return min(total, maxExpandedRows)
    }

    /// The expander only appears when it would do something.
    public static func showsExpander(total: Int) -> Bool {
        total > collapsedRows
    }

    /// Rows still hidden while expanded — the ones beyond the ceiling.
    public static func hiddenWhenExpanded(total: Int) -> Int {
        max(0, total - maxExpandedRows)
    }

    public static func height(base: Double, total: Int, isExpanded: Bool) -> Double {
        let rows = rowCount(total: total, isExpanded: isExpanded)
        let expander = showsExpander(total: total) ? expanderHeight : 0
        return base + rowHeight * Double(rows) + expander
    }
}
