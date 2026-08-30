import AppKit

/// The application icon, drawn rather than shipped.
///
/// There is no asset catalog in this project and no Xcode to build one, so the icon is code and
/// `Tools/AppIconExport` renders the sizes that `iconutil` packs into an `.icns`. That is not
/// only a workaround: an icon that is drawn can be judged at 32 points by rendering it at 32
/// points, which is where an application icon is actually decided.
///
/// What it draws is one card, not a stack of them. A stack was the other direction and it loses
/// its own back cards at 32, arriving at this drawing with two hundred units of wasted ink. So
/// the squircle stops pretending to hold cards and becomes one, showing the thing ADR 0009 says
/// a card is for: the state dot with its halo, the state word beside it, and the quiet rows
/// under it fading away.
public enum AppIcon {
    /// The design grid. Every number below is on it, and `image(size:)` scales the lot.
    private static let grid: CGFloat = 1024
    /// 824 of 1024, the modern macOS inset: 100 units of margin on every side.
    private static let radius: CGFloat = 412

    public static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            draw(size: size)
            return true
        }
    }

    /// A superellipse of degree 5, sampled rather than approximated with an arc.
    ///
    /// A plain rounded rectangle is visibly not the shape macOS uses: at 256 the difference shows
    /// along the flat of the side, where a circular corner keeps curving and this one does not.
    /// 240 points is smooth at 1024 and costs nothing, since it is appended to a path once.
    public static func squirclePath(center: CGPoint, radius: CGFloat, degree: CGFloat = 5, steps: Int = 240) -> NSBezierPath {
        let path = NSBezierPath()
        for step in 0...steps {
            let angle = CGFloat(step) / CGFloat(steps) * .pi * 2
            let cosine = cos(angle)
            let sine = sin(angle)
            let x = center.x + radius * (cosine < 0 ? -1 : 1) * pow(abs(cosine), 2 / degree)
            let y = center.y + radius * (sine < 0 ? -1 : 1) * pow(abs(sine), 2 / degree)
            let point = CGPoint(x: x, y: y)
            step == 0 ? path.move(to: point) : path.line(to: point)
        }
        path.close()
        return path
    }

    private static func draw(size: CGFloat) {
        let scale = size / grid
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.cgContext.scaleBy(x: scale, y: scale)

        let squircle = squirclePath(center: CGPoint(x: 512, y: 512), radius: radius)

        // Lit from the top, the way every icon on the dock is, and dropped onto its own shadow.
        context.saveGraphicsState()
        context.cgContext.setShadow(
            offset: CGSize(width: 0, height: -14),
            blur: 16,
            color: NSColor.black.withAlphaComponent(0.34).cgColor
        )
        NSGradient(
            starting: NSColor(srgbRed: 64 / 255, green: 70 / 255, blue: 82 / 255, alpha: 1),
            ending: NSColor(srgbRed: 28 / 255, green: 32 / 255, blue: 39 / 255, alpha: 1)
        )?.draw(in: squircle, angle: -90)
        context.restoreGraphicsState()

        context.saveGraphicsState()
        squircle.setClip()
        drawContents()
        // The gloss stops halfway down: a highlight that runs the whole face reads as plastic.
        NSGradient(
            colors: [
                NSColor.white.withAlphaComponent(0.13),
                NSColor.white.withAlphaComponent(0),
            ],
            atLocations: [0, 0.48],
            colorSpace: .sRGB
        )?.draw(in: squircle, angle: -90)
        context.restoreGraphicsState()

        // The same hairline a card wears in the app, at 16%.
        NSColor.white.withAlphaComponent(0.16).setStroke()
        squircle.lineWidth = 5
        squircle.stroke()

        context.restoreGraphicsState()
    }

    /// One card's worth of content, in the app's own proportions.
    private static func drawContents() {
        let paper = NSColor(srgbRed: 242 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
        let green = NSColor(srgbRed: 112 / 255, green: 199 / 255, blue: 153 / 255, alpha: 1)

        // The header: the vendor mark's square, the title, and the clock at the far end.
        fill(NSRect(x: 182, y: 704, width: 48, height: 48), radius: 14, paper.withAlphaComponent(0.30))
        fill(NSRect(x: 248, y: 720, width: 200, height: 16), radius: 8, paper.withAlphaComponent(0.22))
        fill(NSRect(x: 712, y: 720, width: 130, height: 16), radius: 8, paper.withAlphaComponent(0.14))

        // The hero: the dot at 92 with its halo at 148, the 1.6 ratio the cards use, and the
        // state word beside it. This is the whole reason the deck exists, so it is the whole
        // reason the icon exists.
        circle(center: CGPoint(x: 268, y: 524), radius: 148, green.withAlphaComponent(0.14))
        circle(center: CGPoint(x: 268, y: 524), radius: 92, green)
        fill(NSRect(x: 406, y: 482, width: 300, height: 84), radius: 42, paper.withAlphaComponent(0.78))

        // The meta rows, fading out. Two of them, because one reads as an underline.
        fill(NSRect(x: 182, y: 326, width: 420, height: 34), radius: 17, paper.withAlphaComponent(0.26))
        fill(NSRect(x: 182, y: 260, width: 290, height: 34), radius: 17, paper.withAlphaComponent(0.16))
    }

    private static func fill(_ rect: NSRect, radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    private static func circle(center: CGPoint, radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )).fill()
    }
}
