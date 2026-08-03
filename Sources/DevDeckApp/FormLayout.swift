import AppKit

/// A container that lays out from the top down, the way a form reads.
@MainActor
class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
}

/// Builds a settings form: captions, and grouped boxes of label-and-control rows.
///
/// Two things it exists to make impossible. Controls cannot overlap, because the cursor only
/// ever moves by what was actually placed — hand-computed `y` values are what put three lines
/// of the DDEV row on top of each other. And nothing is fixed-width: the control side of every
/// row stretches with the window, which is what left the old form with dead space down its
/// right-hand side.
@MainActor
final class FormLayout {
    private let parent: FlippedContainer
    private let width: CGFloat
    private let sideInset: CGFloat
    private var cursor: CGFloat

    /// The open group box, if any, and how far down it we are.
    private var group: (box: FlippedContainer, cursor: CGFloat, separators: [CGFloat])?

    /// Width of the label gutter. Narrower on a narrow window, as System Settings does.
    private let labelWidth: CGFloat

    init(in parent: FlippedContainer, top: CGFloat = 16, sideInset: CGFloat = 20) {
        self.parent = parent
        self.width = parent.bounds.width
        self.sideInset = sideInset
        self.cursor = top
        self.labelWidth = parent.bounds.width < 560 ? 96 : 124
    }

    var usedHeight: CGFloat { cursor }

    private var contentWidth: CGFloat { width - sideInset * 2 }

    // MARK: Free-standing text

    /// A line above a group saying what the group is.
    func header(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.secondaryLabelColor
        label.frame = NSRect(x: sideInset + 2, y: cursor, width: contentWidth - 4, height: 15)
        parent.addSubview(label)
        cursor += 20
    }

    /// An explanation under a group, in the same place macOS puts them.
    func footnote(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.secondaryLabelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = contentWidth - 4
        let height = label.sizeThatFits(NSSize(width: contentWidth - 4, height: .greatestFiniteMagnitude)).height
        label.frame = NSRect(x: sideInset + 2, y: cursor, width: contentWidth - 4, height: height)
        parent.addSubview(label)
        cursor += height + 14
    }

    func space(_ points: CGFloat = 10) {
        cursor += points
    }

    // MARK: Groups

    func beginGroup() {
        let box = FlippedContainer(frame: NSRect(x: sideInset, y: cursor, width: contentWidth, height: 0))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        box.layer?.cornerRadius = 10
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        parent.addSubview(box)
        group = (box, 0, [])
    }

    func endGroup() {
        guard let open = group else { return }
        open.box.frame.size.height = open.cursor

        // Hairlines between rows, drawn after the fact so a row never has to know whether it
        // is the last one.
        for offset in open.separators.dropFirst() {
            let line = NSView(frame: NSRect(x: 12, y: offset, width: open.box.frame.width - 12, height: 1))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
            open.box.addSubview(line)
        }

        cursor += open.cursor + 18
        group = nil
    }

    /// A row inside the open group: a label on the left, controls filling the rest.
    ///
    /// A control with a `nil` width shares whatever is left over, so fields grow with the
    /// window instead of stopping short of it.
    func row(_ label: String?, _ controls: [(view: NSView, width: CGFloat?)], height: CGFloat = 24) {
        guard var open = group else { return }
        let rowHeight = height + 16
        let top = open.cursor
        open.separators.append(top)

        if let label {
            let field = NSTextField(labelWithString: label)
            field.font = NSFont.systemFont(ofSize: 13)
            field.alignment = .right
            field.lineBreakMode = .byTruncatingTail
            field.frame = NSRect(x: 12, y: top + (rowHeight - 17) / 2, width: labelWidth - 20, height: 17)
            open.box.addSubview(field)
        }

        let left = label == nil ? 14 : labelWidth
        let available = open.box.frame.width - left - 14
        let spacing: CGFloat = 8
        let fixed = controls.compactMap(\.width).reduce(0, +)
        let flexibleCount = controls.filter { $0.width == nil }.count
        let flexible = flexibleCount > 0
            ? max(60, (available - fixed - spacing * CGFloat(controls.count - 1)) / CGFloat(flexibleCount))
            : 0

        var x = left
        for control in controls {
            let controlWidth = control.width ?? flexible
            control.view.frame = NSRect(
                x: x,
                y: top + (rowHeight - height) / 2,
                width: controlWidth,
                height: height
            )
            open.box.addSubview(control.view)
            x += controlWidth + spacing
        }

        open.cursor = top + rowHeight
        group = open
    }

    /// Small secondary text inside a group — a status line under the fields.
    func note(_ field: NSTextField) {
        guard var open = group else { return }
        let top = open.cursor
        open.separators.append(top)
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = NSColor.secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        field.frame = NSRect(x: 14, y: top + 7, width: open.box.frame.width - 28, height: 15)
        open.box.addSubview(field)
        open.cursor = top + 29
        group = open
    }
}
