import AppKit

/// Lays a settings row out from the top down.
///
/// Every field here used to carry its own hand-computed `y`, which meant a label could be
/// placed over the control above it and nothing would complain — that is exactly how the DDEV
/// row ended up with three overlapping lines. The cursor moves by what was actually placed,
/// so overlap stops being expressible.
@MainActor
final class RowLayout {
    private let parent: NSView
    private let x: CGFloat
    private let width: CGFloat
    /// Top edge of the next control, in AppKit's upward coordinates.
    private var cursor: CGFloat

    init(in parent: NSView, inset: CGFloat = 12, top: CGFloat = 12) {
        self.parent = parent
        self.x = inset
        self.width = parent.bounds.width - inset * 2
        self.cursor = parent.bounds.height - top
    }

    /// How much vertical space has been used so far, including the top inset.
    var usedHeight: CGFloat {
        parent.bounds.height - cursor
    }

    @discardableResult
    func caption(_ text: String, gap: CGFloat = 3) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 10)
        field.textColor = NSColor.secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        place(field, height: 14, gap: gap)
        return field
    }

    /// Places a control across the full width.
    func place(_ view: NSView, height: CGFloat, gap: CGFloat = 10) {
        cursor -= height
        view.frame = NSRect(x: x, y: cursor, width: width, height: height)
        parent.addSubview(view)
        cursor -= gap
    }

    /// Places controls side by side, sharing the width in the given proportions.
    ///
    /// Fixed widths are given as points; `nil` means "share what is left".
    func row(_ views: [(view: NSView, width: CGFloat?)], height: CGFloat, gap: CGFloat = 10, spacing: CGFloat = 8) {
        let fixed = views.compactMap(\.width).reduce(0, +)
        let flexibleCount = views.filter { $0.width == nil }.count
        let spacingTotal = spacing * CGFloat(max(views.count - 1, 0))
        let flexibleWidth = flexibleCount > 0
            ? max(40, (width - fixed - spacingTotal) / CGFloat(flexibleCount))
            : 0

        cursor -= height
        var left = x
        for entry in views {
            let itemWidth = entry.width ?? flexibleWidth
            entry.view.frame = NSRect(x: left, y: cursor, width: itemWidth, height: height)
            parent.addSubview(entry.view)
            left += itemWidth + spacing
        }
        cursor -= gap
    }

    /// Extra breathing room between groups of fields.
    func space(_ points: CGFloat) {
        cursor -= points
    }
}
