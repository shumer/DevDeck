import AppKit
import DevDeckUI
import SwiftUI

// Renders every card mark on the deck's own glass, at the 15 points a card draws it and blown
// up beside it. Same reason IconPreview exists: a mark that comes out a blob, or filled the
// wrong way round so a knocked-out letter turns solid, is invisible in source and obvious here.

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "glyph-preview.png"

let glyphs = CardGlyph.allCases
let cell: CGFloat = 96
let width = cell * CGFloat(glyphs.count)
let height: CGFloat = 150

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

// The glass a panel actually sits on, near enough: dark, and not black.
NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.14, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

/// `ImageRenderer` rather than a hosting view drawn into a cache: the cache comes back with an
/// opaque white backing, and a mark that is white itself would be invisible on it.
func draw(_ glyph: CardGlyph, in rect: NSRect) {
    // Top-level code in a command line tool is the main thread, which is what the renderer
    // wants; the compiler cannot see that from here.
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: CardGlyphView(glyph, size: rect.width))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return }
        image.draw(in: rect)
    }
}

for (index, glyph) in glyphs.enumerated() {
    let x = CGFloat(index) * cell
    draw(glyph, in: NSRect(x: x + (cell - 64) / 2, y: 58, width: 64, height: 64))
    draw(glyph, in: NSRect(x: x + (cell - 15) / 2, y: 34, width: 15, height: 15))
    (glyph.rawValue as NSString).draw(
        in: NSRect(x: x, y: 12, width: cell, height: 14),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                return style
            }(),
        ]
    )
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    print("could not encode the PNG")
    exit(1)
}
try data.write(to: URL(fileURLWithPath: path))
print("wrote \(path)")
