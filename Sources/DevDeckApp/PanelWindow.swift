import AppKit
import DevDeckCore
import DevDeckUI
import SwiftUI

extension DisplayMode {
    /// AppKit window level for this mode.
    ///
    /// `.desktop` is one below normal windows: covered by every application window but still
    /// above the wallpaper. The real desktop levels are unusable — the WindowManager surface
    /// sits far below and would bury the panels entirely.
    var windowLevel: NSWindow.Level {
        switch self {
        case .floating: return .floating
        case .desktop: return NSWindow.Level(rawValue: -1)
        }
    }
}

/// One borderless, frosted panel hosting a single card.
final class PanelWindow: NSWindow {
    let card: CardID

    init(card: CardID, size: NSSize, origin: NSPoint, content: NSView) {
        self.card = card
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Pinned dark, the way the sibling widget does it. Every colour on a card is light over
        // dark glass, and in Light Mode the hudWindow material goes pale enough that the dimmer
        // text — the meta block, the footer — drops to roughly 1.1:1 and disappears. Pinning it
        // is also what lets the scrim be a veil rather than the flat grey slab it had to be.
        appearance = NSAppearance(named: .darkAqua)
        // Hover highlighting and the pointing-hand cursor need mouse-moved events; a
        // borderless window does not ask for them by default.
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = DeckTheme.cornerRadius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]

        // A veil between the blur and the content, so near-white text keeps its contrast over a
        // bright wallpaper. It used to be black at 42%, which is what made the cards read as
        // grey slabs: at that strength it stops being glass and becomes paint. With the window
        // pinned to dark, 22% is enough — the same figure the sibling widget arrived at.
        let scrim = NSView(frame: blur.bounds)
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        scrim.layer?.cornerRadius = DeckTheme.cornerRadius
        scrim.layer?.cornerCurve = .continuous
        // A hairline of the light the glass is made of. Without it the panel has no edge of its
        // own and dissolves into a busy wallpaper.
        scrim.layer?.borderWidth = 1
        scrim.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        scrim.autoresizingMask = [.width, .height]
        blur.addSubview(scrim)

        content.frame = blur.bounds
        content.autoresizingMask = [.width, .height]
        blur.addSubview(content)

        contentView = blur
        // The shadow is cached from the content shape, and the rounded corners come from a
        // layer mask applied afterwards, so it has to be recomputed.
        invalidateShadow()
    }

    /// Borderless windows refuse key status by default, which would stop the settings sheet
    /// and any text field inside a panel from ever receiving input.
    override var canBecomeKey: Bool { true }
}
