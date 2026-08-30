import AppKit
import DevDeckUI

// Renders the menu-bar icon at the size it is actually seen, on a light and a dark bar, plus
// the alert state and a magnified copy. Iterating on a 15-point drawing without looking at it
// at 15 points is guesswork.

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-preview.png"

let width: CGFloat = 520
let height: CGFloat = 150

// Rendered at 2×, because that is what a Retina menu bar shows. Judging a 15-point drawing
// from a 1× render makes it look blobbier than it will ever be in use.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width * 2),
    pixelsHigh: Int(height * 2),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    print("could not allocate the bitmap")
    exit(1)
}
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

func label(_ text: String, at point: NSPoint) {
    (text as NSString).draw(at: point, withAttributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        .foregroundColor: NSColor.black.withAlphaComponent(0.55),
    ])
}

/// A template image is a mask: the menu bar fills it with the label colour, so the preview
/// has to do the same rather than drawing the black original.
/// Uses a drawing handler rather than `lockFocus`, so the result re-renders for whatever
/// scale and size it is drawn at instead of being baked at 1× and then blown up.
func tinted(_ image: NSImage, color: NSColor) -> NSImage {
    NSImage(size: image.size, flipped: false) { rect in
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

let icon = DeckIcon.statusItemImage()
let blocked = DeckIcon.statusItemImage(.blocked)
let alert = DeckIcon.statusItemImage(.waiting)

// Light bar.
NSColor(white: 0.95, alpha: 1).setFill()
NSRect(x: 20, y: 90, width: 220, height: 40).fill()
tinted(icon, color: .black).draw(at: NSPoint(x: 40, y: 102), from: NSRect.zero, operation: .sourceOver, fraction: 1)
label("светлая полоса", at: NSPoint(x: 70, y: 105))

// Dark bar.
NSColor(white: 0.15, alpha: 1).setFill()
NSRect(x: 270, y: 90, width: 230, height: 40).fill()
tinted(icon, color: .white).draw(at: NSPoint(x: 290, y: 102), from: NSRect.zero, operation: .sourceOver, fraction: 1)
("тёмная полоса" as NSString).draw(at: NSPoint(x: 320, y: 105), withAttributes: [
    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.6),
])
tinted(blocked, color: .white).draw(at: NSPoint(x: 410, y: 102), from: NSRect.zero, operation: .sourceOver, fraction: 1)
// The waiting icon draws itself in `labelColor`, so the preview has to ask for the appearance
// it will actually be drawn in rather than the tool's own.
NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
    alert.draw(at: NSPoint(x: 450, y: 102), from: NSRect.zero, operation: .sourceOver, fraction: 1)
}

// Magnified, to judge the drawing itself.
label("крупно ×6", at: NSPoint(x: 20, y: 60))
let large = NSRect(x: 20, y: 10, width: DeckIcon.size.width * 6, height: DeckIcon.size.height * 6)
NSColor(white: 0.15, alpha: 1).setFill()
NSRect(x: 10, y: 4, width: large.width + 20, height: large.height + 12).fill()
tinted(icon, color: .white).draw(in: large, from: NSRect.zero, operation: .sourceOver, fraction: 1)

let alertLarge = NSRect(x: 180, y: 10, width: DeckIcon.size.width * 6, height: DeckIcon.size.height * 6)
NSColor(white: 0.15, alpha: 1).setFill()
NSRect(x: 170, y: 4, width: alertLarge.width + 20, height: alertLarge.height + 12).fill()
NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
    alert.draw(in: alertLarge, from: NSRect.zero, operation: .sourceOver, fraction: 1)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    print("could not render")
    exit(1)
}

try png.write(to: URL(fileURLWithPath: path))
print("wrote \(path)")
