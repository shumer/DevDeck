import AppKit
import SwiftUI

/// The chips of a project card, wrapped across as many lines as they need.
///
/// Tooling and environments used to be a row each, which spent a row of height on a distinction
/// a divider makes. Wrapping means the number of lines is no longer fixed, and the panel has to
/// know it exactly - a card an inch too short clips its own buttons - so the line arithmetic
/// lives here beside the layout that produces it.
public enum CardChipFlow {
    public nonisolated static let spacing: Double = 5
    public nonisolated static let lineSpacing: Double = 5
    public nonisolated static let topPadding: Double = 11
    /// The divider is 1 point wide with 3 either side.
    public nonisolated static let dividerWidth: Double = 7

    /// How wide a chip with this label will be. Measured with the real font rather than
    /// estimated from the character count: an estimate that is one point out per chip puts a
    /// line break in the wrong place, and the height follows the break.
    public nonisolated static func width(of label: String) -> Double {
        let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let text = NSAttributedString(string: label, attributes: [.font: font])
        return ceil(text.size().width) + 16
    }

    /// Where the second group starts, when the two only fit by being split.
    ///
    /// The groups share a line only if the second one fits on it whole. Otherwise the divider
    /// becomes the break: tools on one line, environments on the next. Breaking anywhere else
    /// puts `Local site` up with the hosted tools and `Local PageBuilder` alone underneath,
    /// which is two chips that belong together, wrapped apart, on a card whose whole point is
    /// that a glance answers the question.
    ///
    /// It costs nothing in height: the line was going to happen either way.
    public nonisolated static func groupedWidths(
        tools: [Double],
        environments: [Double],
        available: Double
    ) -> (widths: [Double], breakBefore: Int?) {
        guard !tools.isEmpty, !environments.isEmpty else {
            return (tools + environments, nil)
        }

        let widths = tools + [dividerWidth] + environments
        let toolsWidth = tools.reduce(0, +) + spacing * Double(tools.count - 1)
        let groupWidth = environments.reduce(0, +) + spacing * Double(environments.count - 1)
        let together = toolsWidth + spacing + dividerWidth + spacing + groupWidth

        // They fit side by side, or the environments would not fit on a line of their own
        // either, in which case a break buys nothing and costs a line.
        guard together > available, groupWidth <= available, lineCount(widths: tools, available: available) == 1
        else { return (widths, nil) }

        return (widths, tools.count)
    }

    /// Pure line-breaking, so the arithmetic can be tested without a font.
    public nonisolated static func lineCount(widths: [Double], available: Double, breakBefore: Int? = nil) -> Int {
        guard !widths.isEmpty else { return 0 }
        var lines = 1
        var used: Double = 0
        var isLineEmpty = true

        for (index, width) in widths.enumerated() {
            if index == breakBefore, !isLineEmpty {
                lines += 1
                used = width
                continue
            }
            let needed = isLineEmpty ? width : used + spacing + width
            // The first chip of a line is placed whatever its width: a chip wider than the card
            // has to go somewhere, and starting a new line for it would loop forever.
            if isLineEmpty || needed <= available {
                used = needed
            } else {
                lines += 1
                used = width
            }
            isLineEmpty = false
        }
        return lines
    }

    public nonisolated static func height(lineCount: Int) -> Double {
        guard lineCount > 0 else { return 0 }
        return topPadding + Double(lineCount) * CardChip.height
            + Double(lineCount - 1) * lineSpacing
    }

    /// Height of a chip block holding these labels, with a divider between the two groups.
    public nonisolated static func height(tools: [String], environments: [String]) -> Double {
        let grouped = groupedWidths(
            tools: tools.map(width(of:)),
            environments: environments.map(width(of:)),
            available: CardChromeMetrics.contentWidth
        )
        return height(lineCount: lineCount(
            widths: grouped.widths,
            available: CardChromeMetrics.contentWidth,
            breakBefore: grouped.breakBefore
        ))
    }

    /// Where the layout should break, for a row that is drawing these two groups.
    public nonisolated static func breakIndex(tools: [String], environments: [String]) -> Int? {
        groupedWidths(
            tools: tools.map(width(of:)),
            environments: environments.map(width(of:)),
            available: CardChromeMetrics.contentWidth
        ).breakBefore
    }
}

/// Lays subviews out left to right, wrapping onto a new line when the next one does not fit.
///
/// A `Layout` rather than the stack-of-rows trick this project tried once before: that version
/// reordered a conditional first child and put the local site on a line of its own. Here the
/// order on screen is the order the subviews were given, always.
public struct CardChipLayout: Layout {
    /// The subview to start a new line at, whatever else would have fitted beside it. Nil is
    /// the ordinary flow.
    private let breakBefore: Int?

    public init(breakBefore: Int? = nil) {
        self.breakBefore = breakBefore
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Typed rather than inferred: `proposal.width` is a `CGFloat?` and the fallback is a
        // `Double`, and the compiler bridging the two through `??` is a courtesy that Swift 6.1
        // does not extend, so the whole expression stayed optional there and the build only
        // failed on CI.
        let available: CGFloat = proposal.width ?? CGFloat(CardChromeMetrics.contentWidth)
        let lines = arrange(subviews: subviews, available: available)
        let height = lines.isEmpty
            ? 0
            : Double(lines.count) * CardChip.height + Double(lines.count - 1) * CardChipFlow.lineSpacing
        return CGSize(width: available, height: height)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let lines = arrange(subviews: subviews, available: bounds.width)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for index in line {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (CardChip.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + CardChipFlow.spacing
            }
            y += CardChip.height + CardChipFlow.lineSpacing
        }
    }

    private func arrange(subviews: Subviews, available: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0

        for index in subviews.indices {
            let width = subviews[index].sizeThatFits(.unspecified).width
            if index == breakBefore, !current.isEmpty {
                lines.append(current)
                current = [index]
                used = width
                continue
            }
            let needed = current.isEmpty ? width : used + CardChipFlow.spacing + width
            if current.isEmpty || needed <= available {
                current.append(index)
                used = needed
            } else {
                lines.append(current)
                current = [index]
                used = width
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
