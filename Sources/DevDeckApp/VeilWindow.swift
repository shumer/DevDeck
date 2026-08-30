import AppKit

/// The dimming behind a summoned deck: one per display, black, and nothing else.
///
/// It is the whole cost of the summon, and it is worth it for one reason. The panels are dark
/// glass, and glass takes the colour of what is behind it: raised over a white editor at full
/// brightness the cards wash out and the dim text on them goes to nothing. Dropping the screen
/// 45% is what makes the deck readable in the moment you asked to see it.
///
/// It sits at level 2: above ordinary windows, below the panels at `.floating`. Mouse events go
/// straight through, so the deck can be clicked and so can whatever is under the veil.
final class VeilWindow: NSWindow {
    static let level = NSWindow.Level(rawValue: 2)
    static let opacity: CGFloat = 0.45

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .black
        alphaValue = 0
        hasShadow = false
        ignoresMouseEvents = true
        level = Self.level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        setFrame(screen.frame, display: false)
    }

    func show() {
        orderFrontRegardless()
        // Fast, because it fires on a keypress and anything slower reads as lag rather than as
        // a fade.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = Self.opacity
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
        }
    }
}
