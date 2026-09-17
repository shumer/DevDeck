import AppKit
import DevDeckCore

/// ⌥Space, held.
///
/// The deck's problem was never how the cards look, it is that they are underneath everything:
/// at level -1 you see a sliver of them between windows. Summoning is therefore not a mode and
/// not a second rendering - it is the same panels at a different window level, which is the
/// switch the settings' "Float above windows" already throws. Holding makes it spring-loaded,
/// and a tap latches it for the times when both hands are needed.
///
/// This object owns the key, the latch and the veils. What "raised" does to the panels is the
/// coordinator's, and it hears about it through `onRaise`.
@MainActor
final class Summoner {
    private let preferences: Preferences
    private let onRaise: (Bool) -> Void

    private var hotKey: GlobalHotKey?
    private var veils: [VeilWindow] = []
    /// Raised right now, whether by a held key or a latched tap.
    private(set) var isSummoned = false
    /// Latched by a tap, so it stays up until the next press.
    private var isLatched = false
    private var summonedAt: Date?
    /// While the deck is up because a menu row or a banner asked for it: the click and the key
    /// that put it back.
    private var dismissMonitors: [Any] = []

    /// Anything shorter than this was a tap, not a hold.
    private static let latchThreshold: TimeInterval = 0.25

    init(preferences: Preferences, onRaise: @escaping (Bool) -> Void) {
        self.preferences = preferences
        self.onRaise = onRaise
    }

    /// Registers the key, or unregisters it when summoning is off.
    func install() {
        hotKey = nil
        guard preferences.summonEnabled else { return }
        let combo = preferences.summonHotKey
        hotKey = GlobalHotKey(
            combo: combo,
            onPress: { [weak self] in self?.pressed() },
            onRelease: { [weak self] in self?.released() }
        )
        // Registration fails when something else already owns the combination, and a summon
        // that silently does nothing is indistinguishable from a broken app. The settings screen
        // says so where somebody will read it; this is for the log.
        if hotKey == nil {
            Log.app.error("\(combo.display, privacy: .public) is already taken by another application")
        } else {
            Log.app.info("Summon armed on \(combo.display, privacy: .public)")
        }
    }

    /// Re-reads every summon preference: the key, whether it is on at all, and the dimming.
    func applyPreferences() {
        install()
        if !preferences.summonEnabled, isSummoned {
            isLatched = false
            setSummoned(false)
        }
        if isSummoned {
            preferences.summonDims ? showVeils() : hideVeils()
        }
    }

    /// Raises the deck for a menu row or a banner that is about a card, until the next click
    /// anywhere but a card, Esc, or the shortcut.
    ///
    /// Latched the way a tap is, but a person who got here from a menu has not pressed the
    /// shortcut and does not know it is the way back: a colleague was left with the screen
    /// dimmed and nothing to click, and quit the app. Clicks on the cards themselves are the
    /// app's own events and do not count, so the card can still be used.
    func present() {
        guard preferences.summonEnabled, !isSummoned else { return }
        isLatched = true
        setSummoned(true)
        watchForDismissal()
    }

    private func watchForDismissal() {
        stopWatchingForDismissal()
        if let click = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.putBack() }
        }) {
            dismissMonitors.append(click)
        }
        // Esc while a card has the keyboard. A global key monitor would need Input Monitoring, and
        // a click outside is already the way back that needs no permission.
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor in self?.putBack() }
            return nil
        }) {
            dismissMonitors.append(escape)
        }
    }

    private func stopWatchingForDismissal() {
        for monitor in dismissMonitors { NSEvent.removeMonitor(monitor) }
        dismissMonitors = []
    }

    private func putBack() {
        isLatched = false
        summonedAt = nil
        setSummoned(false)
    }

    private func pressed() {
        // A press while latched puts the deck back down. Otherwise it raises it, and the
        // release decides whether that was a hold or a tap.
        if isLatched {
            isLatched = false
            summonedAt = nil
            setSummoned(false)
            return
        }
        summonedAt = Date()
        setSummoned(true)
    }

    private func released() {
        guard let pressedAt = summonedAt else { return }
        summonedAt = nil
        if Date().timeIntervalSince(pressedAt) < Self.latchThreshold {
            isLatched = true
            return
        }
        setSummoned(false)
    }

    private func setSummoned(_ summoned: Bool) {
        guard summoned != isSummoned else { return }
        isSummoned = summoned
        if !summoned { stopWatchingForDismissal() }

        if summoned, preferences.summonDims {
            showVeils()
        } else {
            hideVeils()
        }
        onRaise(summoned)
    }

    private func showVeils() {
        // Rebuilt each time rather than kept: a display can come and go between two summons,
        // and a veil on a screen that is no longer there is a window nobody can find.
        hideVeils()
        veils = NSScreen.screens.map(VeilWindow.init(screen:))
        for veil in veils { veil.show() }
    }

    private func hideVeils() {
        for veil in veils { veil.hide() }
        veils = []
    }
}
