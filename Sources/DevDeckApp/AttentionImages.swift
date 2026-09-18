import AppKit
import DevDeckCore
import DevDeckUI

/// The small picture at the start of an attention row: the mark of whatever it is about, so
/// who is asking is answered before the words are read.
@MainActor
enum AttentionImages {
    /// The same size the settings list draws its marks at, which is the Mac's own "Sidebar icon
    /// size": one mark, one size, whether it is in the menu or in the window. Hard-coded 16 made
    /// the menu's marks smaller than the same account's row in Settings on every Mac but one.
    private static var size: CGFloat { SidebarMetrics.iconSize }

    static func image(for mark: AttentionMark) -> NSImage? {
        switch mark {
        case .github: return SettingsIcons.mark(.github, size: size)
        case .gitlab: return SettingsIcons.mark(.gitlab, size: size)
        case .arc: return SettingsIcons.mark(.arc, size: size)
        case .ddev: return SettingsIcons.mark(.ddev, size: size)
        case .docker: return SettingsIcons.mark(.docker, size: size)
        case .project(let kind): return SettingsIcons.mark(CardGlyph(rawValue: kind) ?? .project, size: size)
        case .token: return symbol("key.fill")
        case .network: return symbol("wifi.exclamationmark")
        case .rateLimit: return symbol("hourglass")
        case .update: return symbol("arrow.down.circle")
        case .unpushed: return symbol("arrow.up.circle")
        case .noRemote: return symbol("arrow.triangle.branch")
        }
    }

    static var calm: NSImage? { symbol("checkmark.circle") }
    static var more: NSImage? { symbol("ellipsis.circle") }

    /// A template, so it takes the menu's own ink and inverts on the highlighted row. Drawn a
    /// little under the marks beside it: a glyph with no tile behind it reads as bigger than a
    /// filled square of the same size.
    private static func symbol(_ name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.8, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }
}
