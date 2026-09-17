import AppKit
import DevDeckCore
import DevDeckUI

/// The small picture at the start of an attention row: the mark of whatever it is about, so
/// who is asking is answered before the words are read.
@MainActor
enum AttentionImages {
    private static let size: CGFloat = 16

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

    /// A template, so it takes the menu's own ink and inverts on the highlighted row.
    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        image?.isTemplate = true
        return image
    }
}
