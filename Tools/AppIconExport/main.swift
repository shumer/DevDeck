import AppKit
import DevDeckUI

// Renders the application icon at every size an .icns holds, into an .iconset directory that
// `iconutil` packs. There is no asset catalog in this project and no Xcode to build one, so the
// icon is drawn in code and this is what turns it into a file the bundle can carry.
//
// Every size is rendered from the drawing rather than resampled from the biggest one, which is
// the point of drawing it: a 32-point icon downscaled from 1024 is mush, and a 32-point icon
// drawn at 32 is a decision.

let directory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "DevDeck.iconset"
let sizes: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2),
    ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2),
    ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2),
]

let root = URL(fileURLWithPath: directory)
try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

for entry in sizes {
    let pixels = entry.points * entry.scale
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("could not allocate \(entry.name)")
        exit(1)
    }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    AppIcon.image(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("could not render \(entry.name)")
        exit(1)
    }
    try png.write(to: root.appendingPathComponent("\(entry.name).png"))
}

print("wrote \(sizes.count) sizes into \(directory)")
