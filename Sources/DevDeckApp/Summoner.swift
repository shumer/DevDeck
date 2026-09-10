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
