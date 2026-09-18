import AppKit
import DevDeckUI
import SwiftUI

/// The small pictures in the settings list and page headers, drawn in code.
///
/// A page gets a tile, a coloured rounded square with a white symbol, the way System Settings
/// marks its panes. An account or a project gets its brand mark, the same one its card wears,
/// so a row in the list and a card on the desktop are recognisably the same thing.
@MainActor
enum SettingsIcons {
    private static var cache: [String: NSImage] = [:]

    static func tile(_ symbol: String, color: NSColor, size: CGFloat = SidebarMetrics.iconSize) -> NSImage {
        let key = "tile:\(symbol):\(color):\(size)"
        if let cached = cache[key] { return cached }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let radius = size * 0.24
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let glyphSize = glyph.size
                glyph.draw(in: NSRect(
                    x: (rect.width - glyphSize.width) / 2,
                    y: (rect.height - glyphSize.height) / 2,
                    width: glyphSize.width,
                    height: glyphSize.height
                ))
            }
            return true
        }
        cache[key] = image
        return image
    }

    /// A card's own mark, at the size asked for. Rendered once per glyph and size.
    static func mark(_ glyph: CardGlyph, size: CGFloat = SidebarMetrics.iconSize) -> NSImage {
        let key = "mark:\(glyph.rawValue):\(size)"
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(content: CardGlyphView(glyph, size: size * 0.8)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24).fill(Color(white: 0.16))))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: size, height: size))
        cache[key] = image
        return image
    }

    // Computed rather than stored: the size follows the Mac's own sidebar icon size, which can
    // change while the app is running.
    static var general: NSImage { tile("gearshape.fill", color: .systemGray) }
    static var deck: NSImage { tile("rectangle.stack.fill", color: .systemBlue) }
    static var cards: NSImage { tile("square.grid.2x2.fill", color: .systemIndigo) }
    static var notifications: NSImage { tile("bell.badge.fill", color: .systemRed) }
}
