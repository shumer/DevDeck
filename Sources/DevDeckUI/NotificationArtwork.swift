import AppKit
import DevDeckCore
import SwiftUI

/// The picture on a banner: the service's own mark rather than the app's icon.
///
/// macOS puts the application icon on every notification and will not be talked out of it, but a
/// notification can carry an attachment, and that is drawn beside the text. So a review request
/// arrives showing the octocat or the tanuki, and "who is asking" is answered before the words
/// are read.
///
/// Rendered to the caches directory rather than shipped, for the same reason the app icon is
/// drawn: there is no asset catalog here. Rendered once per launch and reused, because a banner
/// is not the place to be doing work.
public enum NotificationArtwork {
    /// 128 points square. The thumbnail is small, and a mark drawn at 40 and scaled up is the
    /// difference between a logo and a smudge.
    private static let size: CGFloat = 128

    /// Nil for the app's own news, which the application icon macOS puts on every banner
    /// already says.
    public static func fileURL(for source: DeckAlert.Source) -> URL? {
        guard source != .devdeck else { return nil }
        let directory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("DevDeck", isDirectory: true)
        guard let directory else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("notify-\(source.rawValue).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let data = render(source) else { return nil }
        try? data.write(to: url)
        return url
    }

    /// The mark on the same dark tile the cards are made of.
    ///
    /// Not a bare transparent logo: GitHub's mark is white, which disappears on a light banner,
    /// and the tile is what makes both marks read the same way in both appearances.
    private static func render(_ source: DeckAlert.Source) -> Data? {
        let bounds = NSRect(x: 0, y: 0, width: size, height: size)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size),
            pixelsHigh: Int(size),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        NSColor(srgbRed: 26 / 255, green: 30 / 255, blue: 36 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 28, yRadius: 28).fill()

        // The mark at 60% of the tile, which is the usual optical margin for a logo in a square.
        let inset = size * 0.2
        let markRect = bounds.insetBy(dx: inset, dy: inset)
        // The vectors are authored with y pointing down, which is the opposite of what AppKit
        // draws in, so every mark arrives upside down unless it is flipped back here.
        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: bounds.height)
        flip.scaleX(by: 1, yBy: -1)

        switch source {
        case .github, .gitlab, .ddev, .docker:
            let vector: BrandMark.Vector = {
                switch source {
                case .gitlab: return BrandMark.gitlab
                case .ddev: return BrandMark.ddev
                case .docker: return BrandMark.docker
                default: return BrandMark.github
                }
            }()
            NSColor(vector.color).setFill()
            for data in vector.paths {
                let bezier = NSBezierPath(cgPath: SVGPath.path(data, viewBox: vector.viewBox, in: markRect).cgPath)
                bezier.windingRule = vector.isEvenOdd ? .evenOdd : .nonZero
                bezier.transform(using: flip as AffineTransform)
                bezier.fill()
            }
        case .arc:
            // The two strokes of Arc's A, as the card draws them, on a 100-unit square.
            let unit = markRect.width / 100
            func polygon(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
                let path = NSBezierPath()
                for (index, point) in points.enumerated() {
                    let scaled = NSPoint(x: markRect.minX + point.0 * unit, y: markRect.minY + point.1 * unit)
                    index == 0 ? path.move(to: scaled) : path.line(to: scaled)
                }
                path.close()
                path.transform(using: flip as AffineTransform)
                return path
            }
            NSColor.white.setFill()
            polygon([(44, 14), (64, 14), (34, 86), (8, 86)]).fill()
            NSColor(srgbRed: 0.25, green: 0.71, blue: 0.75, alpha: 1).setFill()
            polygon([(64, 14), (92, 86), (62, 86), (48, 50)]).fill()
        case .project, .devdeck:
            let configuration = NSImage.SymbolConfiguration(pointSize: markRect.height * 0.8, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let glyph = symbol.size
                symbol.draw(in: NSRect(
                    x: bounds.midX - glyph.width / 2,
                    y: bounds.midY - glyph.height / 2,
                    width: glyph.width,
                    height: glyph.height
                ))
            }
        }

        return rep.representation(using: .png, properties: [:])
    }
}
