import AppKit
import Combine
import DevDeckCore

/// The log of one project, in a window of its own.
///
/// It used to be a tray inside the card: six lines of 9.5-point monospace on a panel 352 points
/// wide, which answered "is it moving" and nothing else, and pushed the card 120 points taller
/// while it was open, so the column under it jumped every time somebody looked. A log is text
/// people read, copy and search, and a window is what the system already has for that.
@MainActor
final class LogWindowController: NSWindowController, NSWindowDelegate {
    private let card: CardID
    private let controller: DeckController
    private let textView = NSTextView()
    private let scroll = NSScrollView()
    private let sourceLabel = SettingsForm.label("", size: 10.5, color: .secondaryLabelColor)
    private let followToggle = NSButton(checkboxWithTitle: L("card.log.follow"), target: nil, action: nil)
    private let openFileButton = NSButton(title: L("card.log.openFile"), target: nil, action: nil)

    /// Whether new lines pull the view to the bottom. Scrolling up turns it off, because the
    /// one thing worse than not following is being yanked away from the line you are reading.
    private var isFollowing = true
    private var fileURL: URL?
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    var onClose: ((CardID) -> Void)?

    private static let defaultSize = NSSize(width: 640, height: 380)
    /// How often the window re-reads while it is on screen. A log is watched, not polled once.
    private static let interval: TimeInterval = 2

    init(card: CardID, title: String, controller: DeckController) {
        self.card = card
        self.controller = controller
        super.init(window: nil)
        makeWindow(title: title)
        // The window reads the same lines the deck holds, so what it shows and what the card
        // knows cannot disagree.
        cancellable = controller.$logTails
            .receive(on: RunLoop.main)
            .sink { [weak self] tails in self?.apply(tails[card]) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this window is built in code")
    }

    // MARK: The window

    private func makeWindow(title: String) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // Dark whatever the Mac is set to: this is a terminal, and a terminal that turns white
        // at nine in the morning is a terminal nobody asked for.
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = title
        window.subtitle = L("card.log.window.subtitle")
        window.minSize = NSSize(width: 420, height: 220)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = makeContent()
        window.center()
        // One remembered frame per project: two logs open side by side stay where they were put.
        window.setFrameAutosaveName("DevDeck Log \(card.rawValue)")
        self.window = window
    }

    private func makeContent() -> NSView {
        let content = NSView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.115, alpha: 1)
        textView.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        textView.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        // ⌘F, with the bar the system draws for it. `Find` in the Edit menu is what routes to it.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = textView.backgroundColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
        content.addSubview(scroll)

        let footer = NSVisualEffectView()
        footer.material = .titlebar
        footer.blendingMode = .withinWindow
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)

        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(sourceLabel)

        followToggle.state = .on
        followToggle.target = self
        followToggle.action = #selector(toggleFollow)
        followToggle.controlSize = .small
        followToggle.font = NSFont.systemFont(ofSize: 11)
        followToggle.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(followToggle)

        openFileButton.bezelStyle = .rounded
        openFileButton.controlSize = .small
        openFileButton.font = NSFont.systemFont(ofSize: 11)
        openFileButton.target = self
        openFileButton.action = #selector(openFile)
        openFileButton.isHidden = true
        openFileButton.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(openFileButton)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 34),

            sourceLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
            sourceLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            sourceLabel.trailingAnchor.constraint(lessThanOrEqualTo: followToggle.leadingAnchor, constant: -12),

            followToggle.trailingAnchor.constraint(equalTo: openFileButton.leadingAnchor, constant: -12),
            followToggle.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            openFileButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            openFileButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
        return content
    }

    // MARK: Showing

    func show() {
        // In the Dock while a window of ours is open, for the same reason the settings window
        // does it: a minimised window with no application behind it is a blank tile. Counted,
        // because bringing a window that is already up to the front is not a second window.
        if window?.isVisible != true { WindowPresence.retain() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        apply(controller.logs(for: card))
        controller.refreshLogsNow(for: card)
        startWatching()
    }

    private func startWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                // Nothing is read while nobody can see it: a window behind another one, or
                // minimised, is a command run for nobody.
                guard window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible) else { return }
                self.controller.refreshLogsNow(for: self.card)
            }
        }
    }

    /// The lines, or why there are none.
    private func apply(_ logs: LogLines?) {
        guard let logs else {
            textView.string = L("card.log.reading")
            return
        }
        fileURL = logs.fileURL
        openFileButton.isHidden = logs.fileURL == nil
        sourceLabel.stringValue = logs.source ?? L("card.log.source")

        let text = logs.lines.isEmpty
            ? (logs.detail ?? L("card.log.nothing"))
            : logs.lines.joined(separator: "\n")
        guard text != textView.string else { return }
        textView.string = text
        if isFollowing { scrollToEnd() }
    }

    private func scrollToEnd() {
        // Laid out first: asked before the new lines have been measured, the view scrolls to
        // where the end used to be and leaves the newest line under the footer.
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.scrollToEndOfDocument(nil)
    }

    /// Whether the view is at the bottom, within a line of it.
    private var isAtEnd: Bool {
        guard let documentView = scroll.documentView else { return true }
        let visible = scroll.contentView.bounds
        return visible.maxY >= documentView.bounds.maxY - 16
    }

    @objc private func scrolled() {
        let following = isAtEnd
        guard following != isFollowing else { return }
        isFollowing = following
        followToggle.state = following ? .on : .off
    }

    @objc private func toggleFollow() {
        isFollowing = followToggle.state == .on
        if isFollowing { scrollToEnd() }
    }

    @objc private func openFile() {
        guard let fileURL else { return }
        LocalFolder.open(fileURL)
    }

    // MARK: Closing

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        cancellable = nil
        NotificationCenter.default.removeObserver(self)
        WindowPresence.release()
        onClose?(card)
    }
}

/// The log windows that are open, one per card.
@MainActor
final class LogWindows {
    private let controller: DeckController
    private let title: (CardID) -> String
    private var windows: [CardID: LogWindowController] = [:]

    init(controller: DeckController, title: @escaping (CardID) -> String) {
        self.controller = controller
        self.title = title
    }

    func open(_ card: CardID) {
        if let existing = windows[card] {
            existing.show()
            return
        }
        let window = LogWindowController(card: card, title: title(card), controller: controller)
        window.onClose = { [weak self] card in
            self?.windows[card] = nil
            self?.controller.logWindowClosed(card)
        }
        windows[card] = window
        controller.logWindowOpened(card)
        window.show()
    }

    func close(_ card: CardID) {
        windows[card]?.close()
    }

    /// Everything shuts with the app, and a project taken out of settings takes its window with
    /// it: a window titled with a project that no longer exists has nothing to read.
    func closeAll(except cards: Set<CardID>) {
        for card in windows.keys where !cards.contains(card) {
            close(card)
        }
    }
}

/// How many windows want the app in the Dock.
///
/// An agent app has no Dock icon, and a minimised window without one is a nameless blank tile.
/// The settings window and every log window ask for the icon while they are open; the last one
/// to close gives it back, which is why this is a count rather than a flag.
@MainActor
enum WindowPresence {
    private static var count = 0

    static func retain() {
        count += 1
        NSApp.setActivationPolicy(.regular)
    }

    static func release() {
        count = max(0, count - 1)
        guard count == 0 else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
