import Foundation

/// Where the panels sit relative to other windows.
///
/// Kept AppKit-free so it can be persisted and tested head-less; the app target maps it
/// onto an `NSWindow.Level`.
public enum DisplayMode: String, Codable, Sendable, CaseIterable {
    /// Behind every application window but above the wallpaper - the widget feel.
    case desktop
    /// Above normal windows, for keeping an eye on a deploy while working.
    case floating

    public var menuTitle: String {
        switch self {
        case .desktop: return "Keep on desktop (behind windows)"
        case .floating: return "Float above windows"
        }
    }
}
