import AppKit

/// What the menu-bar item is saying.
///
/// Three states rather than two, because the old red glyph meant three unrelated things at once
/// and the reason was only in the tooltip: "it is red and I have no idea why" is a fair
/// complaint about an icon that says something is wrong and nothing about what.
public enum DeckIconState: Sendable, Equatable {
    /// Nothing wants you.
    case calm
    /// Your own queue is stuck: a pull request of yours is blocked.
    case blocked
    /// A person is waiting on you: a review request, or something actionable in the inbox.
    case waiting
}

/// The menu-bar icon: a stack of panels with the app's initials cut out of the front one.
///
/// Drawn rather than picked from SF Symbols because no symbol carries lettering, and the
/// lettering is the point. A glyph alone left the question "which app is this?" open, and in a
/// menu bar holding eight monochrome shapes that question is the only one the icon has to
/// answer. Template images are tinted by the menu bar, so everything is drawn in black and the
/// letters are knocked out to transparency.
public enum DeckIcon {
    /// Menu-bar icons live in an 18x18 slot; 15 points tall leaves the usual optical margin.
    public static let size = NSSize(width: 18, height: 15)

    /// The badge, and the whole of the colour on this icon.
    ///
    /// 4.5 points across with a 0.9 clear ring knocked out around it, which is 16 square points
    /// of the glyph's 270 rather than all of it. In the bar's own ink it means your queue is
    /// blocked; in red it means somebody is waiting on you. Red is worth having only if it is
    /// kept for the one thing that costs another person time.
    private static let badgeCenter = CGPoint(x: 14.9, y: 11.7)
    private static let badgeRadius: CGFloat = 2.25
    private static let badgeClearance: CGFloat = 3.15

    /// The icon for a state. Calm and blocked are real template images, so the menu bar tints
    /// them along with every other icon up there; only `waiting` opts out, because red is the
    /// message rather than a shape.
    public static func statusItemImage(_ state: DeckIconState = .calm) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            // The waiting state cannot be a template, because one dot on it is red and a
            // template image has no colour at all. So it draws itself in `labelColor`, which
            // resolves against whatever appearance is drawing it - the menu bar's - and the
            // glyph still turns white on a dark bar the way its two siblings do. Drawing it in
            // plain black instead is how a menu-bar icon becomes invisible at night.
            draw(state: state, tint: state == .waiting ? .labelColor : .black)
            return true
        }
        image.isTemplate = state != .waiting
        return image
    }

    /// The drawing, in black except for the one dot that is allowed to be red.
    ///
    /// `tint` is for the preview tool, which has to imitate what the menu bar does to a template
    /// image rather than drawing the black original on a dark bar.
    public static func draw(state: DeckIconState = .calm, tint: NSColor = .black) {
        tint.setFill()

        // The card behind, peeking out at the top. It has to be clearly narrower than the front
        // one and clearly separated from it, or the pair reads as a lidded box rather than as
        // two cards. The separation is 1.9 points: at 1.5 it filled in at 1x and did exactly
        // that.
        NSBezierPath(
            roundedRect: NSRect(x: 4, y: 12, width: 10, height: 2.8),
            xRadius: 1.4,
            yRadius: 1.4
        ).fill()

        // The card in front, which carries the lettering.
        let front = NSBezierPath(
            roundedRect: NSRect(x: 0.5, y: 0, width: 17, height: 10.1),
            xRadius: 2.5,
            yRadius: 2.5
        )
        front.fill()

        // Letters cut out of the front card. Knocking them out keeps the icon a single shape,
        // so it still reads at 1x where a stroked letter would smear.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7.2, weight: .heavy),
            .foregroundColor: NSColor.black,
            .kern: -0.3,
        ]
        let letters = "DD" as NSString
        let bounds = letters.size(withAttributes: attributes)
        let origin = NSPoint(x: 9 - bounds.width / 2, y: 5.05 - bounds.height / 2)

        NSGraphicsContext.current?.compositingOperation = .destinationOut
        letters.draw(at: origin, withAttributes: attributes)

        guard state != .calm else {
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return
        }

        // A ring of nothing around the badge, so it stays a badge on a busy menu bar instead of
        // merging into the corner of the card behind it.
        NSBezierPath(ovalIn: NSRect(
            x: badgeCenter.x - badgeClearance,
            y: badgeCenter.y - badgeClearance,
            width: badgeClearance * 2,
            height: badgeClearance * 2
        )).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        (state == .waiting ? NSColor.systemRed : tint).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: badgeCenter.x - badgeRadius,
            y: badgeCenter.y - badgeRadius,
            width: badgeRadius * 2,
            height: badgeRadius * 2
        )).fill()
    }
}
