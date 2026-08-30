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

    public static func fileURL(for source: DeckAlert.Source) -> URL? {
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
        let vector = source == .github ? BrandMark.github : BrandMark.gitlab
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
        let path = SVGPath.path(vector.paths[0], viewBox: vector.viewBox, in: markRect)
        NSColor(vector.color).setFill()
        let bezier = NSBezierPath(cgPath: path.cgPath)
        // The vector is authored with y pointing down, which is the opposite of what AppKit
        // draws in, so the mark arrives upside down unless it is flipped back here.
        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: bounds.height)
        flip.scaleX(by: 1, yBy: -1)
        bezier.transform(using: flip as AffineTransform)
        bezier.fill()

        return rep.representation(using: .png, properties: [:])
    }
}
