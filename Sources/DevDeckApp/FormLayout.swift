import AppKit

/// A container that lays out from the top down, the way a form reads.
@MainActor
class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
}

/// Builds a settings form: captions, and grouped boxes of label-and-control rows.
///
/// Two things it exists to make impossible. Controls cannot overlap, because the cursor only
/// ever moves by what was actually placed - hand-computed `y` values are what put three lines
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

    /// A gap owed to whatever comes next, spent when it arrives.
    ///
    /// The one thing a form cannot know at the moment it closes a group is whether the next
    /// thing explains it. A footnote belongs to the group above and needs to sit close to it; a
    /// header belongs to what follows and needs air before it. Closing a group therefore owes a
    /// gap rather than spending one, and the next call decides how much of it to pay.
    private var pendingGap: CGFloat = 0

    /// Gaps between blocks. A footnote is 10 under its group and 22 above the next header, so it
    /// reads as belonging to what it explains. It used to be 18 and 14, closer to the wrong one.
    static let gapAfterGroup: CGFloat = 24
    static let gapBeforeFootnote: CGFloat = 10
    static let gapAfterFootnote: CGFloat = 22
    static let gapAfterHeader: CGFloat = 6

    /// Width of the label gutter. Narrower on a narrow window, as System Settings does.
    private let labelWidth: CGFloat

    init(in parent: FlippedContainer, top: CGFloat = 16, sideInset: CGFloat = 20) {
        self.parent = parent
        self.width = parent.bounds.width
        self.sideInset = sideInset
        self.cursor = top
        // One gutter, wide enough for the longest label this form has. It used to be 96 on a
        // narrow window and 124 on a wide one, which put two different forms in one window and
        // truncated "Organisations", 83.7 points of text in a 76-point field.
        self.labelWidth = 132
    }

    /// How much room the form needs, with the margin under it.
    ///
    /// Without the last one, the bottom group's border ends flush against the edge of the scroll
    /// view, which reads as a page that was cut off rather than one that finished.
    var usedHeight: CGFloat { cursor + Self.bottomInset }

    /// Every row indents by the same amount, whatever kind of row it is. It used to be 12 for a
    /// labelled row and 14 for a toggle, which is invisible on its own and a wobble down the
    /// left edge when a form stacks both.
    static let rowInset: CGFloat = 16
    static let bottomInset: CGFloat = 24

    private var contentWidth: CGFloat { width - sideInset * 2 }

    // MARK: Free-standing text

    /// A line above a group saying what the group is.
    func header(_ text: String) {
        flush()
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.secondaryLabelColor
        label.frame = NSRect(x: sideInset + 2, y: cursor, width: contentWidth - 4, height: 15)
        parent.addSubview(label)
        cursor += 15 + Self.gapAfterHeader
    }

    /// An explanation under a group, in the same place macOS puts them.
    func footnote(_ text: String) {
        // A footnote is the one thing that wants to be closer to what came before it than to
        // what comes after, so it pays a smaller gap than anything else would.
        flush(Self.gapBeforeFootnote)
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.secondaryLabelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = contentWidth - 4
        let height = label.sizeThatFits(NSSize(width: contentWidth - 4, height: .greatestFiniteMagnitude)).height
        label.frame = NSRect(x: sideInset + 2, y: cursor, width: contentWidth - 4, height: height)
        parent.addSubview(label)
        cursor += height
        pendingGap = Self.gapAfterFootnote
    }

    func space(_ points: CGFloat = 10) {
        flush()
        cursor += points
    }

    /// Pays the gap owed by whatever came before, or the amount asked for instead.
    private func flush(_ override: CGFloat? = nil) {
        guard pendingGap > 0 else { return }
        cursor += override ?? pendingGap
        pendingGap = 0
    }

    /// The form's own title: what is being edited, where it lives, and the one switch that is
    /// about the card rather than about the project.
    ///
    /// The switch belongs here rather than in a row of its own with an empty label gutter -
    /// "show a card for this project" is not a field of the project, and as a row it produced
    /// the one thing the label gutter cannot do gracefully, which is nothing.
    func formHeader(title: String, subtitle: String?, accessory: (label: String, view: NSView)?) {
        flush()
        let name = NSTextField(labelWithString: title)
        name.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        name.frame = NSRect(x: sideInset, y: cursor, width: contentWidth - 160, height: 20)
        parent.addSubview(name)

        var height: CGFloat = 20
        if let subtitle, !subtitle.isEmpty {
            let path = NSTextField(labelWithString: subtitle)
            path.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            path.textColor = NSColor.tertiaryLabelColor
            path.lineBreakMode = .byTruncatingMiddle
            path.frame = NSRect(x: sideInset, y: cursor + 22, width: contentWidth - 160, height: 14)
            parent.addSubview(path)
            height += 17
        }

        if let accessory {
            let caption = NSTextField(labelWithString: accessory.label)
            caption.font = NSFont.systemFont(ofSize: 11.5)
            caption.textColor = NSColor.secondaryLabelColor
            caption.alignment = .right
            caption.frame = NSRect(x: width - sideInset - 150, y: cursor + 3, width: 110, height: 15)
            parent.addSubview(caption)

            accessory.view.frame = NSRect(x: width - sideInset - 34, y: cursor, width: 34, height: 21)
            parent.addSubview(accessory.view)
        }

        cursor += height + 14
        let rule = NSView(frame: NSRect(x: sideInset, y: cursor, width: contentWidth, height: 1))
        rule.wantsLayer = true
        rule.layer?.backgroundColor = NSColor.separatorColor.cgColor
        parent.addSubview(rule)
        cursor += 16
    }

    // MARK: Groups

    func beginGroup() {
        flush()
        let box = FlippedContainer(frame: NSRect(x: sideInset, y: cursor, width: contentWidth, height: 0))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        box.layer?.cornerRadius = 10
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        // Or a row that paints its own background - `liveRow` does - covers the bottom border
        // and squares off the two corners it reaches.
        box.layer?.masksToBounds = true
        parent.addSubview(box)
        group = (box, 0, [])
    }

    func endGroup() {
        guard let open = group else { return }
        open.box.frame.size.height = open.cursor

        // Hairlines between rows, drawn after the fact so a row never has to know whether it
        // is the last one.
        for offset in open.separators.dropFirst() {
            let line = NSView(frame: NSRect(x: Self.rowInset, y: offset, width: open.box.frame.width - Self.rowInset, height: 1))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
            open.box.addSubview(line)
        }

        cursor += open.cursor
        // Owed rather than spent: what comes next decides. See `pendingGap`.
        pendingGap = Self.gapAfterGroup
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
            field.frame = NSRect(x: Self.rowInset, y: top + (rowHeight - 17) / 2, width: labelWidth - Self.rowInset - 14, height: 17)
            open.box.addSubview(field)
        }

        let left = label == nil ? Self.rowInset : labelWidth
        let available = open.box.frame.width - left - Self.rowInset
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

    /// A row for a command or a URL: the caption above the field rather than beside it.
    ///
    /// These are the fields that matter most and are longest, and the 110-point label gutter was
    /// spending a third of the row on a word. Without it the field is about 1.6 times wider.
    /// `isRequired` marks the one field nothing works without.
    func commandRow(
        _ caption: String,
        field: NSTextField,
        accessory: NSView? = nil,
        isRequired: Bool = false
    ) {
        guard var open = group else { return }
        let top = open.cursor
        open.separators.append(top)

        let label = NSTextField(labelWithString: isRequired ? "\(caption) •" : caption)
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        label.textColor = isRequired ? NSColor.systemOrange : NSColor.secondaryLabelColor
        label.frame = NSRect(x: Self.rowInset, y: top + 8, width: open.box.frame.width - Self.rowInset * 2, height: 12)
        open.box.addSubview(label)

        let accessoryWidth: CGFloat = accessory == nil ? 0 : 66
        field.frame = NSRect(
            x: 12,
            y: top + 24,
            width: open.box.frame.width - 24 - accessoryWidth - (accessory == nil ? 0 : 7),
            height: 24
        )
        open.box.addSubview(field)

        if let accessory {
            accessory.frame = NSRect(
                x: open.box.frame.width - 12 - accessoryWidth,
                y: top + 24,
                width: accessoryWidth,
                height: 24
            )
            open.box.addSubview(accessory)
        }

        open.cursor = top + 56
        group = open
    }

    /// A switch with its own explanation, instead of a footnote under the box.
    ///
    /// This is what killed four paragraphs of small print: the sentence that explained a switch
    /// now sits under that switch, and says one thing rather than three.
    func toggleRow(_ toggle: NSButton, title: String, subtitle: String) {
        guard var open = group else { return }
        let top = open.cursor
        open.separators.append(top)

        toggle.frame = NSRect(x: Self.rowInset, y: top + 10, width: 34, height: 21)
        open.box.addSubview(toggle)

        let caption = NSTextField(labelWithString: title)
        caption.font = NSFont.systemFont(ofSize: 12)
        caption.frame = NSRect(x: 58, y: top + 8, width: open.box.frame.width - 70, height: 15)
        open.box.addSubview(caption)

        let detail = NSTextField(labelWithString: subtitle)
        detail.font = NSFont.systemFont(ofSize: 10.5)
        detail.textColor = NSColor.secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.frame = NSRect(x: 58, y: top + 24, width: open.box.frame.width - 70, height: 14)
        open.box.addSubview(detail)

        open.cursor = top + 46
        group = open
    }

    /// The live answer to "and how does the app know it worked", instead of a paragraph saying
    /// how it would find out.
    func liveRow(color: NSColor, title: String, detail: String, accessory: NSView?) {
        guard var open = group else { return }
        let top = open.cursor
        open.separators.append(top)

        let strip = NSView(frame: NSRect(x: 0, y: top, width: open.box.frame.width, height: 34))
        strip.wantsLayer = true
        strip.layer?.backgroundColor = color.withAlphaComponent(0.08).cgColor
        open.box.addSubview(strip)

        let dot = NSView(frame: NSRect(x: 14, y: 14, width: 7, height: 7))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = color.cgColor
        dot.layer?.cornerRadius = 3.5
        strip.addSubview(dot)

        let caption = NSTextField(labelWithString: title)
        caption.font = NSFont.systemFont(ofSize: 12)
        caption.frame = NSRect(x: 29, y: 9, width: 120, height: 16)
        strip.addSubview(caption)

        let note = NSTextField(labelWithString: detail)
        note.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        note.textColor = NSColor.secondaryLabelColor
        note.lineBreakMode = .byTruncatingTail
        note.frame = NSRect(x: 153, y: 10, width: strip.frame.width - 165 - 80, height: 14)
        strip.addSubview(note)

        if let accessory {
            accessory.frame = NSRect(x: strip.frame.width - 12 - 76, y: 6, width: 76, height: 21)
            strip.addSubview(accessory)
        }

        open.cursor = top + 34
        group = open
    }

    /// An environment link: on or off, its tag in the colour the card gives it, then the URL.
    ///
    /// The tag is what ties the row to the chip on the card without a word of explanation.
    func linkRow(_ check: NSButton, tag: String, tint: NSColor, field: NSTextField, open button: NSView?) {
        guard var open = group else { return }
        let top = open.cursor
        open.separators.append(top)

        check.frame = NSRect(x: Self.rowInset, y: top + 10, width: 16, height: 16)
        open.box.addSubview(check)

        let badge = NSTextField(labelWithString: tag.uppercased())
        badge.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        badge.alignment = .center
        badge.textColor = check.state == .on ? tint : tint.withAlphaComponent(0.5)
        badge.wantsLayer = true
        badge.layer?.backgroundColor = tint.withAlphaComponent(check.state == .on ? 0.16 : 0.08).cgColor
        badge.layer?.cornerRadius = 4
        badge.frame = NSRect(x: 36, y: top + 9, width: 46, height: 18)
        open.box.addSubview(badge)

        let buttonWidth: CGFloat = button == nil ? 0 : 60
        field.frame = NSRect(
            x: 90,
            y: top + 7,
            width: open.box.frame.width - 102 - buttonWidth - (button == nil ? 0 : 7),
            height: 22
        )
        open.box.addSubview(field)

        if let button {
            button.frame = NSRect(
                x: open.box.frame.width - 12 - buttonWidth,
                y: top + 7,
                width: buttonWidth,
                height: 22
            )
            open.box.addSubview(button)
        }

        open.cursor = top + 36
        group = open
    }

    /// Small secondary text inside a group - a status line under the fields.
    func note(_ field: NSTextField) {
        guard var open = group else { return }
        let top = open.cursor
        open.separators.append(top)
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = NSColor.secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        field.frame = NSRect(x: Self.rowInset, y: top + 7, width: open.box.frame.width - Self.rowInset * 2, height: 15)
        open.box.addSubview(field)
        open.cursor = top + 29
        group = open
    }
}
