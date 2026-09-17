import AppKit
import DevDeckUI

// Renders the menu-bar icon at the size it is actually seen, on a light and a dark bar, plus
// the alert state and a magnified copy. Iterating on a 15-point drawing without looking at it
// at 15 points is guesswork.

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-preview.png"

let width: CGFloat = 560
let height: CGFloat = 230

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

func label(_ text: String, at point: NSPoint, color: NSColor = NSColor.black.withAlphaComponent(0.55)) {
    (text as NSString).draw(at: point, withAttributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        .foregroundColor: color,
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

/// Draws a state the way the menu bar would: templates tinted, the red one in its own ink under
/// the bar's appearance.
func draw(_ state: DeckIconState, in rect: NSRect, dark: Bool) {
    let image = DeckIcon.statusItemImage(state)
    if image.isTemplate {
        tinted(image, color: dark ? .white : .black).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}

let states: [(DeckIconState, String)] = [(.calm, "calm"), (.stuck, "stuck"), (.needsFixing, "fix"), (.waiting, "waiting")]

// Real size, on a light and a dark bar.
for (row, dark) in [(0, false), (1, true)] {
    let y = 190 - CGFloat(row) * 40
    NSColor(white: dark ? 0.15 : 0.95, alpha: 1).setFill()
    NSRect(x: 20, y: y - 12, width: 520, height: 36).fill()
    for (index, entry) in states.enumerated() {
        let x = 40 + CGFloat(index) * 125
        draw(entry.0, in: NSRect(origin: NSPoint(x: x, y: y - 2), size: DeckIcon.size), dark: dark)
        label(entry.1, at: NSPoint(x: x + 26, y: y), color: dark ? NSColor.white.withAlphaComponent(0.6) : NSColor.black.withAlphaComponent(0.55))
    }
}

// Magnified, to judge the drawing itself.
label("крупно ×6", at: NSPoint(x: 20, y: 112))
for (index, entry) in states.enumerated() {
    let x = 20 + CGFloat(index) * 135
    let large = NSRect(x: x + 10, y: 12, width: DeckIcon.size.width * 6, height: DeckIcon.size.height * 6)
    NSColor(white: 0.15, alpha: 1).setFill()
    NSRect(x: x, y: 4, width: large.width + 20, height: large.height + 12).fill()
    draw(entry.0, in: large, dark: true)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    print("could not render")
    exit(1)
}

try png.write(to: URL(fileURLWithPath: path))
print("wrote \(path)")
