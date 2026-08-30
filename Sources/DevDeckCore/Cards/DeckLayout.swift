import CoreGraphics
import Foundation

/// Where the panels go when the deck is tidied up.
///
/// Here rather than in the app for the same reason `CardMetrics` is: it is arithmetic, and
/// arithmetic that decides whether a panel ends up somewhere the mouse can reach deserves a
/// test. The app supplies the sizes and applies the answer.
public enum DeckLayout {
    /// Top-left corners for a run of panels, stacked down from the anchor and wrapping into a
    /// new column whenever the next one would hang below the screen.
    ///
    /// Coordinates are AppKit's - y grows upward - and the points are top-left corners, which
    /// is the same anchor positions are remembered by. Panels keep the order they are given:
    /// tidying is closing up gaps, not sorting the deck.
    ///
    /// - Parameters:
    ///   - sizes: each panel's size, in display order.
    ///   - anchorTopLeft: the top-left corner of the panel the deck hangs from, usually the
    ///     topmost one - tidying keeps the deck where the user put it rather than resetting it
    ///     to a corner.
    ///   - screen: the visible frame to stay inside.
    ///   - gap: space between panels, and between columns.
    public static func tidy(
        sizes: [CGSize],
        anchorTopLeft: CGPoint,
        screen: CGRect,
        gap: CGFloat
    ) -> [CGPoint] {
        guard !sizes.isEmpty else { return [] }

        // Decided once, from where the anchor sits: a deck anchored against the left edge has
        // to grow rightwards, and one against the right edge leftwards.
        let widest = sizes.map(\.width).max() ?? 0
        let roomRight = screen.maxX - (anchorTopLeft.x + widest)
        let roomLeft = anchorTopLeft.x - screen.minX
        let growsRight = roomRight >= roomLeft

        var placements: [CGPoint] = []
        var x = anchorTopLeft.x
        var y = anchorTopLeft.y
        var columnWidth: CGFloat = 0
        var isColumnEmpty = true

        for size in sizes {
            // The empty check is what stops a panel taller than the screen from starting a new
            // column for itself and every panel after it landing in the same place.
            if !isColumnEmpty, y - size.height < screen.minY {
                let step = columnWidth + gap
                let next = growsRight ? x + step : x - step
                // Clamped rather than allowed past the edge: on a genuinely full screen,
                // overlapping panels can still be dragged apart and off-screen ones cannot.
                x = min(max(next, screen.minX), max(screen.minX, screen.maxX - size.width))
                y = anchorTopLeft.y
                columnWidth = 0
                isColumnEmpty = true
            }

            placements.append(CGPoint(x: x, y: y))
            y -= size.height + gap
            columnWidth = max(columnWidth, size.width)
            isColumnEmpty = false
        }

        return placements
    }
}
