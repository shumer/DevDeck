import AppKit

/// The menu-bar icon: a stack of panels with the app's initials cut out of the front one.
///
/// Drawn rather than picked from SF Symbols because no symbol carries lettering, and the
/// lettering is the point — a glyph alone left the question "which app is this?" open.
/// Template images are tinted by the menu bar, so everything is drawn in black and the
/// letters are knocked out to transparency.
public enum DeckIcon {
    /// Menu-bar icons live in an 18×18 slot; 15 points tall leaves the usual optical margin.
    public static let size = NSSize(width: 18, height: 15)

    public static func statusItemImage() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Alert state. Not a template, because red is the message rather than a shape.
    public static func alertImage(color: NSColor = .systemRed) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(tint: color)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(tint: NSColor = .black) {
        tint.setFill()

        // The card behind, peeking out at the top. It has to be clearly narrower than the
        // front one and clearly separated from it, or the pair reads as a lidded box rather
        // than as two cards.
        let back = NSBezierPath(
            roundedRect: NSRect(x: 4.5, y: 12, width: 9, height: 2.2),
            xRadius: 1.1,
            yRadius: 1.1
        )
        back.fill()

        // The card in front, which carries the lettering.
        let front = NSBezierPath(
            roundedRect: NSRect(x: 0.5, y: 0.5, width: 17, height: 10),
            xRadius: 2.4,
            yRadius: 2.4
        )
        front.fill()

        // Letters cut out of the front card. Knocking them out keeps the icon a single shape,
        // so it still reads at 1× where a stroked letter would smear.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6.8, weight: .heavy),
            .foregroundColor: NSColor.black,
            .kern: -0.2,
        ]
        let letters = "DD" as NSString
        let bounds = letters.size(withAttributes: attributes)
        let origin = NSPoint(x: 9 - bounds.width / 2, y: 5.4 - bounds.height / 2)

        NSGraphicsContext.current?.compositingOperation = .destinationOut
        letters.draw(at: origin, withAttributes: attributes)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}
