import AppKit
import DevDeckCore

/// A container that lays out from the top down, the way a form reads.
@MainActor
class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
}

/// Builds a settings page the way System Settings does: a page header, a short section title,
/// a rounded group, rows inside it, and at most one line of explanation under the group.
///
/// Four row shapes and no more, because the old builder had seven and a single group could
/// mix four of them with four different left edges. Every row inside a group shares two edges:
/// the leading one at 12 points, and a control column at 130 points for rows with a label.
///
/// The column follows the window's width up to a ceiling, the way System Settings' does, and
/// nothing is rebuilt to do it: every row and every control carries the autoresizing mask that
/// says whether it stretches or keeps to the trailing edge. Rebuilding on a resize is what used
/// to throw away whatever field had focus, along with what was typed in it.
@MainActor
final class SettingsForm {
    /// The column's width at the window's default size, and its ceiling at any other: a form
    /// three feet wide is no easier to read than a menu bar is.
    nonisolated static let columnWidth: CGFloat = 760
    /// Narrow enough to keep a label column and a field beside it.
    nonisolated static let minimumColumnWidth: CGFloat = 440
    nonisolated static let sideInset: CGFloat = 20
    nonisolated static let rowInset: CGFloat = 10
    /// Text sits about two points inside its field, so a label lines up with a control's edge
    /// only if its frame starts two points further out.
    nonisolated static let labelInset: CGFloat = 8
    nonisolated static let labelColumn: CGFloat = 130

    private let parent: FlippedContainer
    private let left: CGFloat
    private let width: CGFloat
    private var cursor: CGFloat

    private var group: GroupBoxView?
    private var groupCursor: CGFloat = 0
    /// Whether the last thing placed was a group, so the next section title knows to add air.
    private var afterGroup = false

    init(in parent: FlippedContainer, top: CGFloat = 20) {
        self.parent = parent
        self.left = Self.sideInset
        self.width = max(Self.minimumColumnWidth, min(Self.columnWidth, parent.bounds.width - Self.sideInset * 2))
        self.cursor = top
    }

    /// How tall the page is, with its bottom margin.
    var usedHeight: CGFloat { cursor + 28 }

    // MARK: Page and section

    /// What is being edited, what it is, and the one switch that is about the card rather than
    /// the thing. Returns the switch so the form can read it back.
    @discardableResult
    func pageHeader(
        icon: NSImage?,
        title: String,
        subtitle: String?,
        toggleTitle: String? = nil,
        isOn: Bool = false,
        target: AnyObject? = nil,
        action: Selector? = nil
    ) -> NSSwitch? {
        var textLeft = left
        if let icon {
            let image = NSImageView(frame: NSRect(x: left, y: cursor + 2, width: 32, height: 32))
            image.image = icon
            image.imageScaling = .scaleProportionallyUpOrDown
            parent.addSubview(image)
            textLeft = left + 42
        }

        var toggle: NSSwitch?
        var toggleWidth: CGFloat = 0
        if let toggleTitle {
            let control = Self.makeSwitch(isOn: isOn, title: toggleTitle, target: target, action: action)
            let size = control.fittingSize
            control.frame = NSRect(x: left + width - size.width, y: cursor + 9, width: size.width, height: size.height)
            control.autoresizingMask = [.minXMargin]
            parent.addSubview(control)

            let caption = Self.label(toggleTitle, size: 12, color: .secondaryLabelColor)
            caption.sizeToFit()
            caption.frame.origin = NSPoint(x: control.frame.minX - caption.frame.width - 8, y: cursor + 10)
            caption.autoresizingMask = [.minXMargin]
            parent.addSubview(caption)
            toggleWidth = size.width + caption.frame.width + 20
            toggle = control
        }

        let name = Self.label(title, size: 17, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        name.frame = NSRect(x: textLeft, y: cursor, width: left + width - textLeft - toggleWidth, height: 21)
        name.autoresizingMask = [.width]
        parent.addSubview(name)

        if let subtitle, !subtitle.isEmpty {
            let detail = Self.label(subtitle, size: 11, color: .secondaryLabelColor)
            detail.lineBreakMode = .byTruncatingMiddle
            detail.toolTip = subtitle
            detail.frame = NSRect(x: textLeft, y: cursor + 22, width: left + width - textLeft - toggleWidth, height: 14)
            detail.autoresizingMask = [.width]
            parent.addSubview(detail)
        }

        cursor += 36 + 18
        afterGroup = false
        return toggle
    }

    /// A short title over the group that follows. `help` puts the longer explanation behind a
    /// question mark instead of under the group, where it used to outweigh the controls.
    func section(_ title: String, help: String? = nil) {
        closeGroupIfOpen()
        if afterGroup { cursor += 30 }
        let header = Self.label(title, size: 13, weight: .semibold)
        header.sizeToFit()
        header.frame.origin = NSPoint(x: left + Self.labelInset, y: cursor)
        parent.addSubview(header)

        if let help {
            let button = HelpButton(text: help)
            button.frame = NSRect(x: header.frame.maxX + 6, y: cursor - 2, width: 20, height: 20)
            parent.addSubview(button)
        }
        cursor += 17 + 9
        afterGroup = false
    }

    // MARK: Groups

    func beginGroup() {
        closeGroupIfOpen()
        // Two groups with nothing between them sit closer than a group and the next section's
        // title do.
        if afterGroup { cursor += 10 }
        let box = GroupBoxView(frame: NSRect(x: left, y: cursor, width: width, height: 0))
        box.autoresizingMask = [.width]
        parent.addSubview(box)
        group = box
        groupCursor = 0
    }

    func endGroup() {
        guard let box = group else { return }
        box.frame.size.height = groupCursor
        cursor += groupCursor
        group = nil
        afterGroup = true
    }

    private func closeGroupIfOpen() {
        if group != nil { endGroup() }
    }

    /// Adds a hairline above the next row, unless it is the first row of the group.
    private func separatorIfNeeded(in box: GroupBoxView) {
        guard groupCursor > 0 else { return }
        // Drawn rather than an NSBox separator, which is twice as dark as the hairline inside a
        // System Settings group.
        let line = HairlineView(frame: NSRect(x: Self.rowInset, y: groupCursor, width: box.frame.width - Self.rowInset * 2, height: 1))
        line.autoresizingMask = [.width]
        box.addSubview(line)
    }

    // MARK: Rows

    /// A setting with its control at the trailing edge: a switch, a pop-up, a button. The
    /// subtitle is one sentence, and wraps rather than being cut off.
    func settingRow(_ title: String, subtitle: String? = nil, control: NSView) {
        guard let box = group else { return }
        separatorIfNeeded(in: box)

        let size = Self.fittingSize(of: control)
        let textWidth = box.frame.width - Self.rowInset * 3 - size.width
        let caption = Self.label(title, size: 13)
        caption.lineBreakMode = .byTruncatingTail

        var subtitleHeight: CGFloat = 0
        var detail: NSTextField?
        if let subtitle, !subtitle.isEmpty {
            let field = NSTextField(wrappingLabelWithString: subtitle)
            field.font = NSFont.systemFont(ofSize: 11)
            field.textColor = .secondaryLabelColor
            field.isSelectable = false
            field.preferredMaxLayoutWidth = textWidth
            subtitleHeight = field.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height
            detail = field
        }

        let height = max(38, 11 + 16 + (subtitleHeight > 0 ? 2 + subtitleHeight : 0) + 11)
        let textTop = groupCursor + (height - 16 - (subtitleHeight > 0 ? 2 + subtitleHeight : 0)) / 2
        caption.frame = NSRect(x: Self.labelInset, y: textTop, width: textWidth, height: 16)
        caption.autoresizingMask = [.width]
        box.addSubview(caption)
        if let detail {
            detail.frame = NSRect(x: Self.labelInset, y: textTop + 18, width: textWidth, height: subtitleHeight)
            detail.autoresizingMask = [.width]
            box.addSubview(detail)
        }

        control.frame = NSRect(
            x: box.frame.width - Self.rowInset - size.width,
            y: groupCursor + (height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        if let toggle = control as? NSSwitch { toggle.setAccessibilityLabel(title) }
        control.autoresizingMask = [.minXMargin]
        box.addSubview(control)
        groupCursor += height
    }

    /// A label in the leading column and controls from the control column to the trailing edge.
    /// A control with a `nil` width shares what is left; a trailing button is sized to fit.
    func fieldRow(_ label: String, _ controls: [(view: NSView, width: CGFloat?)], trailing: NSView? = nil) {
        guard let box = group else { return }
        separatorIfNeeded(in: box)
        let height: CGFloat = 38

        let caption = Self.label(label, size: 13)
        caption.lineBreakMode = .byTruncatingTail
        caption.frame = NSRect(x: Self.labelInset, y: groupCursor + 11, width: Self.labelColumn - Self.labelInset - 8, height: 16)
        box.addSubview(caption)

        var right = box.frame.width - Self.rowInset
        if let trailing {
            let size = Self.fittingSize(of: trailing)
            trailing.frame = NSRect(x: right - size.width, y: groupCursor + (height - size.height) / 2, width: size.width, height: size.height)
            trailing.autoresizingMask = [.minXMargin]
            box.addSubview(trailing)
            right -= size.width + 8
        }

        let spacing: CGFloat = 8
        let fixed = controls.compactMap(\.width).reduce(0, +)
        let flexibleCount = controls.filter { $0.width == nil }.count
        let available = right - Self.labelColumn - spacing * CGFloat(max(controls.count - 1, 0))
        let flexible = flexibleCount > 0 ? max(60, (available - fixed) / CGFloat(flexibleCount)) : 0

        var x = Self.labelColumn
        // Hidden controls keep their place, so a profile pop-up appearing never moves the row.
        var afterFlexible = false
        for control in controls {
            let controlWidth = control.width ?? flexible
            let controlHeight = Self.fittingSize(of: control.view).height
            control.view.frame = NSRect(x: x, y: groupCursor + (height - controlHeight) / 2, width: controlWidth, height: controlHeight)
            if let field = control.view as? NSTextField, field.isEditable { field.setAccessibilityLabel(label) }
            // The one that shares what is left is the one that grows; anything after it keeps its
            // distance from the trailing edge instead.
            control.view.autoresizingMask = control.width == nil ? [.width] : (afterFlexible ? [.minXMargin] : [])
            afterFlexible = afterFlexible || control.width == nil
            box.addSubview(control.view)
            x += controlWidth + spacing
        }
        groupCursor += height
    }

    /// The live answer to a question the form asks: is the site up, does the token work, is
    /// there an update. The dot carries the colour; the row is updated in place, never rebuilt.
    func statusRow(_ status: StatusLine, button: NSButton?) {
        guard let box = group else { return }
        separatorIfNeeded(in: box)
        let height: CGFloat = 38
        var right = box.frame.width - Self.rowInset
        if let button {
            let size = Self.fittingSize(of: button)
            button.frame = NSRect(x: right - size.width, y: groupCursor + (height - size.height) / 2, width: size.width, height: size.height)
            button.autoresizingMask = [.minXMargin]
            box.addSubview(button)
            right -= size.width + 10
        }
        status.frame = NSRect(x: Self.labelInset, y: groupCursor, width: right - Self.labelInset, height: height)
        status.autoresizingMask = [.width]
        box.addSubview(status)
        groupCursor += height
    }

    /// A link on the card: whether it shows, its tag in the colour the chip has on the card, the
    /// address, and a small open button once there is an address to open.
    /// One width for every tag in a group, so the address fields start on the same edge.
    static func chipWidth(for tags: [String]) -> CGFloat {
        let widest = tags.map { ChipView(text: $0.uppercased(), tint: .labelColor).textWidth }.max() ?? 0
        return min(110, max(52, widest + 14))
    }

    func linkRow(toggle: NSButton, tag: String, tint: NSColor, field: NSTextField, open: NSButton?, chipWidth fixedWidth: CGFloat? = nil) {
        guard let box = group else { return }
        separatorIfNeeded(in: box)
        let height: CGFloat = 38

        toggle.frame = NSRect(x: Self.rowInset, y: groupCursor + 11, width: 18, height: 16)
        toggle.setAccessibilityLabel(tag)
        box.addSubview(toggle)

        let chip = ChipView(text: tag.uppercased(), tint: tint)
        let chipWidth = fixedWidth ?? min(110, max(52, chip.textWidth + 14))
        chip.frame = NSRect(x: 34, y: groupCursor + 10, width: chipWidth, height: 18)
        box.addSubview(chip)
        let fieldLeft = chip.frame.maxX + 8

        var right = box.frame.width - Self.rowInset
        if let open {
            open.frame = NSRect(x: right - 20, y: groupCursor + 9, width: 20, height: 20)
            open.autoresizingMask = [.minXMargin]
            box.addSubview(open)
            right -= 28
        }
        field.frame = NSRect(x: fieldLeft, y: groupCursor + 8, width: right - fieldLeft, height: 22)
        field.setAccessibilityLabel(tag)
        field.autoresizingMask = [.width]
        box.addSubview(field)
        groupCursor += height
    }

    // MARK: Under a group

    /// One line under the group above. Longer explanations belong behind a section's help
    /// button; this is cut off with its whole text in the tooltip rather than allowed to wrap.
    func footnote(_ text: String) {
        closeGroupIfOpen()
        let note = Self.label(text, size: 11, color: .secondaryLabelColor)
        note.lineBreakMode = .byTruncatingTail
        note.toolTip = text
        note.frame = NSRect(x: left + Self.labelInset, y: cursor + 6, width: width - Self.labelInset * 2, height: 14)
        note.autoresizingMask = [.width]
        parent.addSubview(note)
        cursor += 6 + 14
    }

    /// A borderless action under the group, like "Add Link".
    func textButton(_ title: String, target: AnyObject, action: Selector) {
        closeGroupIfOpen()
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.contentTintColor = .controlAccentColor
        button.font = NSFont.systemFont(ofSize: 12.5)
        button.sizeToFit()
        button.frame.origin = NSPoint(x: left + Self.labelInset - 2, y: cursor + 6)
        parent.addSubview(button)
        cursor += 6 + button.frame.height
    }

    /// The fold for what is rarely touched. Closed, it says what is inside, so nothing is
    /// hidden without a hint of where it went.
    func disclosure(_ title: String, summary: String, isOpen: Bool, target: AnyObject, action: Selector) {
        closeGroupIfOpen()
        cursor += afterGroup ? 22 : 0
        let toggle = NSButton(frame: NSRect(x: left, y: cursor, width: 13, height: 13))
        toggle.bezelStyle = .disclosure
        toggle.setButtonType(.pushOnPushOff)
        toggle.title = ""
        toggle.state = isOpen ? .on : .off
        toggle.target = target
        toggle.action = action
        toggle.setAccessibilityLabel(title)
        parent.addSubview(toggle)

        let caption = NSButton(title: title, target: target, action: action)
        caption.isBordered = false
        caption.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        caption.sizeToFit()
        caption.frame.origin = NSPoint(x: left + 18, y: cursor - 3)
        parent.addSubview(caption)

        if !isOpen {
            let hint = Self.label(summary, size: 11, color: .secondaryLabelColor)
            hint.lineBreakMode = .byTruncatingTail
            hint.frame = NSRect(x: caption.frame.maxX + 6, y: cursor, width: left + width - caption.frame.maxX - 6, height: 14)
            hint.autoresizingMask = [.width]
            parent.addSubview(hint)
        }
        cursor += 17 + 7
        afterGroup = false
    }

    // MARK: Controls

    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    static func makeSwitch(isOn: Bool, title: String, target: AnyObject?, action: Selector?) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.state = isOn ? .on : .off
        toggle.target = target
        toggle.action = action
        toggle.setAccessibilityLabel(title)
        return toggle
    }

    static func button(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    /// A text field in the style of the form. Monospaced only for what is typed as code: a
    /// command, a URL, a path.
    static func field(_ value: String, placeholder: String = "", code: Bool = false) -> NSTextField {
        let field = NSTextField()
        field.stringValue = value
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.controlSize = .regular
        field.font = code
            ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            : NSFont.systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        return field
    }

    /// A borderless icon button that opens an address.
    static func openButton(target: AnyObject?, action: Selector?) -> NSButton {
        let image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: "Open")
            ?? NSImage()
        let button = NSButton(image: image, target: target, action: action)
        button.isBordered = false
        button.contentTintColor = .controlAccentColor
        button.toolTip = "Open"
        return button
    }

    private static func fittingSize(of view: NSView) -> NSSize {
        if let control = view as? NSControl {
            if control is NSTextField { return NSSize(width: 0, height: 22) }
            control.sizeToFit()
            return control.frame.size
        }
        let size = view.fittingSize
        return size == .zero ? view.frame.size : size
    }
}

// MARK: - Pieces

/// The rounded group the rows sit in. A fill and no border, in the colour System Settings uses,
/// resolved when it is drawn so it follows a switch between light and dark.
@MainActor
final class GroupBoxView: FlippedContainer {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.03).cgColor
    }
}

/// The hairline between two rows of a group.
@MainActor
final class HairlineView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
    }
}

/// A link's tag, tinted like its chip on the card.
@MainActor
final class ChipView: NSView {
    private let tint: NSColor
    private let label: NSTextField

    var textWidth: CGFloat {
        label.sizeToFit()
        return label.frame.width
    }

    init(text: String, tint: NSColor) {
        self.tint = tint
        label = SettingsForm.label(text, size: 9.5, weight: .semibold, color: tint)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: (bounds.height - 13) / 2, width: bounds.width, height: 13)
    }
}

/// A dot, a state and a detail, updated in place when an answer comes back.
@MainActor
final class StatusLine: NSView {
    enum Tone {
        case good, busy, bad, idle

        init(_ tone: CheckSummary.Tone) {
            switch tone {
            case .good: self = .good
            case .busy: self = .busy
            case .bad: self = .bad
            case .idle: self = .idle
            }
        }

        var color: NSColor {
            switch self {
            case .good: return .systemGreen
            case .busy: return .systemOrange
            case .bad: return .systemRed
            case .idle: return .tertiaryLabelColor
            }
        }
    }

    private let dot = NSView()
    private let state = SettingsForm.label("", size: 13)
    private let detail = SettingsForm.label("", size: 11, color: .secondaryLabelColor)
    private var tone: Tone = .idle

    init(tone: Tone, state text: String, detail note: String, codeDetail: Bool = false) {
        super.init(frame: .zero)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        addSubview(dot)
        addSubview(state)
        detail.lineBreakMode = .byTruncatingTail
        if codeDetail { detail.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) }
        addSubview(detail)
        update(tone: tone, state: text, detail: note)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    convenience init(_ summary: CheckSummary) {
        self.init(tone: Tone(summary.tone), state: summary.state, detail: summary.detail)
    }

    func update(_ summary: CheckSummary) {
        update(tone: Tone(summary.tone), state: summary.state, detail: summary.detail)
    }

    func update(tone: Tone, state text: String, detail note: String) {
        self.tone = tone
        state.stringValue = text
        detail.stringValue = note
        detail.toolTip = note.isEmpty ? nil : note
        setAccessibilityLabel(note.isEmpty ? text : "\(text), \(note)")
        needsDisplay = true
        needsLayout = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        dot.layer?.backgroundColor = tone.color.cgColor
    }

    override func layout() {
        super.layout()
        dot.frame = NSRect(x: 2, y: (bounds.height - 8) / 2, width: 8, height: 8)
        state.sizeToFit()
        state.frame.origin = NSPoint(x: 18, y: (bounds.height - state.frame.height) / 2)
        let detailLeft = state.frame.maxX + 8
        detail.frame = NSRect(x: detailLeft, y: (bounds.height - 14) / 2, width: max(0, bounds.width - detailLeft), height: 14)
    }

    override var isFlipped: Bool { true }
}

/// The question mark that holds what used to be a paragraph under a group.
@MainActor
final class HelpButton: NSButton {
    private let text: String
    private var popover: NSPopover?

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        bezelStyle = .helpButton
        title = ""
        target = self
        action = #selector(show)
        setAccessibilityLabel("Help")
        toolTip = text
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    @objc private func show() {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.preferredMaxLayoutWidth = 300
        let size = label.sizeThatFits(NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300 + 28, height: size.height + 24))
        label.frame = NSRect(x: 14, y: 12, width: 300, height: size.height)
        container.addSubview(label)

        let controller = NSViewController()
        controller.view = container
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        self.popover = popover
    }
}

/// The browser, and the profile in it, that a thing's links open in.
///
/// One piece instead of the same eighty lines in five forms. The profile pop-up is hidden
/// rather than greyed out when the browser has none to offer: a disabled control reading "none"
/// looked like a broken one.
@MainActor
final class BrowserPicker: NSObject {
    let browserPopUp = NSPopUpButton()
    let profilePopUp = NSPopUpButton()
    var onChange: (() -> Void)?

    private var browsers: [InstalledBrowser] = []
    private var profiles: [BrowserProfile] = []

    init(choice: BrowserChoice) {
        super.init()
        browserPopUp.target = self
        browserPopUp.action = #selector(browserChanged)
        profilePopUp.target = self
        profilePopUp.action = #selector(profileChanged)
        browserPopUp.setAccessibilityLabel("Browser")
        profilePopUp.setAccessibilityLabel("Profile")

        browsers = BrowserCatalog.installedBrowsers()
        browserPopUp.addItem(withTitle: "Default Browser")
        for browser in browsers { browserPopUp.addItem(withTitle: browser.name) }
        if let identifier = choice.bundleIdentifier,
           let index = browsers.firstIndex(where: { $0.bundleIdentifier == identifier.lowercased() }) {
            browserPopUp.selectItem(at: index + 1)
        }
        reloadProfiles(selecting: choice.profileDirectory)
    }

    var choice: BrowserChoice {
        guard let browser = selectedBrowser else { return .systemDefault }
        let index = profilePopUp.indexOfSelectedItem - 1
        let profile = (index >= 0 && index < profiles.count) ? profiles[index].directory : nil
        return BrowserChoice(bundleIdentifier: browser.bundleIdentifier, profileDirectory: profile)
    }

    private var selectedBrowser: InstalledBrowser? {
        let index = browserPopUp.indexOfSelectedItem - 1
        guard index >= 0, index < browsers.count else { return nil }
        return browsers[index]
    }

    private func reloadProfiles(selecting directory: String?) {
        profilePopUp.removeAllItems()
        guard let browser = selectedBrowser, browser.supportsProfiles else {
            profiles = []
            profilePopUp.isHidden = true
            return
        }
        profiles = BrowserCatalog.profiles(for: browser.bundleIdentifier)
        profilePopUp.isHidden = profiles.isEmpty
        profilePopUp.addItem(withTitle: "Last Used Profile")
        for profile in profiles { profilePopUp.addItem(withTitle: profile.name) }
        if let directory, let index = profiles.firstIndex(where: { $0.directory == directory }) {
            profilePopUp.selectItem(at: index + 1)
        }
    }

    @objc private func browserChanged() {
        reloadProfiles(selecting: nil)
        onChange?()
    }

    @objc private func profileChanged() {
        onChange?()
    }
}

/// The answer to a button, next to the button: what Detect found, why a link would not open.
///
/// A popover rather than a line reserved under the row. A reserved line is an empty row until
/// something is said, and an empty row reads as a form that was not finished; a line that
/// appears pushes every row under it down. This takes no room and goes away by itself.
@MainActor
enum ButtonAnswer {
    private static var current: NSPopover?

    static func show(_ text: String, isError: Bool, at anchor: NSView) {
        current?.close()
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = isError ? .systemRed : .labelColor
        label.preferredMaxLayoutWidth = 280
        let size = label.sizeThatFits(NSSize(width: 280, height: CGFloat.greatestFiniteMagnitude))
        let width = min(280, max(size.width, 80))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width + 24, height: size.height + 18))
        label.frame = NSRect(x: 12, y: 9, width: width, height: size.height)
        container.addSubview(label)

        let controller = NSViewController()
        controller.view = container
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        current = popover
        NSAccessibility.post(element: anchor, notification: .announcementRequested, userInfo: [.announcement: text])

        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 6 : 3.5)) { [weak popover] in
            popover?.close()
        }
    }
}
