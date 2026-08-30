import AppKit
import DevDeckCore

/// The field you press a shortcut into.
///
/// A pop-up of combinations somebody chose in advance is the other way to do this, and it is
/// always wrong: the one you want is never in the list. Recording needs no permission, because
/// the settings window is a normal key window and a local monitor only sees events already
/// delivered to this app.
final class HotKeyRecorderView: NSView {
    private(set) var combo: HotKeyCombo
    var onChange: ((HotKeyCombo) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var monitor: Any?
    private var isRecording = false {
        didSet {
            update()
            needsDisplay = true
        }
    }

    init(combo: HotKeyCombo) {
        self.combo = combo
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        update()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    override func updateLayer() {
        layer?.backgroundColor = (isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : NSColor.textBackgroundColor).cgColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        isRecording ? stop() : start()
    }

    func set(_ combo: HotKeyCombo) {
        self.combo = combo
        update()
    }

    private func update() {
        label.stringValue = isRecording ? "Press a combination" : combo.display
        label.textColor = isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor
        toolTip = isRecording
            ? "Escape cancels"
            : "Click, then press the keys you want. At least one modifier is required."
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            // Swallowed either way: a shortcut being recorded must not also be typed into
            // whatever had focus a moment ago.
            self.record(event)
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func record(_ event: NSEvent) {
        guard event.keyCode != 53 else { // Escape leaves what was there.
            stop()
            return
        }

        var modifiers: HotKeyCombo.Modifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }

        let candidate = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        // A bare key would be taken from every application on the machine: pressing `k` in an
        // editor would raise the deck instead of typing one. Keep listening rather than
        // accepting it.
        guard candidate.isValid else { return }

        combo = candidate
        stop()
        onChange?(candidate)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
