import CoreGraphics
import Foundation

/// One display, as a placement remembers it.
public struct DisplayFrame: Sendable, Equatable {
    /// Stable identity of the physical display. `CGDisplayCreateUUIDFromDisplayID` survives
    /// unplugging, replugging and rearranging, which the display id itself does not.
    public let id: String
    /// The area a panel may occupy, in global coordinates, menu bar and Dock excluded.
    public let visibleFrame: CGRect

    public init(id: String, visibleFrame: CGRect) {
        self.id = id
        self.visibleFrame = visibleFrame
    }
}

/// Where a panel sits: which display, and where on it.
///
/// Stored relative to a display rather than in global coordinates, which is the whole point.
/// macOS lays every screen out in one coordinate space and re-lays it whenever a display comes
/// or goes: unplug the external one that happens to be the main display and the laptop's screen
/// moves under the cards, so an absolute point that meant "top left of the laptop" now means
/// somewhere else entirely - often off every screen. Remembering the display and the offset
/// within it means a card comes back where it was, and a card whose display is gone can be
/// parked somewhere visible **without forgetting where it belongs**.
public struct PanelPlacement: Sendable, Equatable {
    public let displayID: String
    /// Top-left corner, as an offset from the display's own top-left. Y grows downward here,
    /// unlike AppKit's global space, because "40 points down from the top of that screen" is
    /// the thing that stays true when the screen moves.
    public let offset: CGPoint

    public init(displayID: String, offset: CGPoint) {
        self.displayID = displayID
        self.offset = offset
    }

    // MARK: Storage

    /// `display-uuid|x|y`. A plain string because that is what the preferences backend holds,
    /// and because a placement that cannot be read back by eye is harder to debug than it needs
    /// to be.
    public var storage: String {
        "\(displayID)|\(offset.x)|\(offset.y)"
    }

    public init?(storage: String) {
        let parts = storage.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let x = Double(parts[1]),
              let y = Double(parts[2]),
              !parts[0].isEmpty
        else { return nil }
        self.init(displayID: String(parts[0]), offset: CGPoint(x: x, y: y))
    }

    // MARK: Converting

    /// The placement for a panel whose top-left is at this global point.
    ///
    /// The display it belongs to is the one it overlaps most, so a card straddling two screens
    /// is remembered against the one it is mostly on.
    public static func from(
        topLeft: CGPoint,
        size: CGSize,
        displays: [DisplayFrame]
    ) -> PanelPlacement? {
        let frame = CGRect(
            x: topLeft.x,
            y: topLeft.y - size.height,
            width: size.width,
            height: size.height
        )
        let display = displays.max { left, right in
            area(of: left.visibleFrame.intersection(frame)) < area(of: right.visibleFrame.intersection(frame))
        }
        guard let display, area(of: display.visibleFrame.intersection(frame)) > 0 else { return nil }

        return PanelPlacement(
            displayID: display.id,
            offset: CGPoint(
                x: topLeft.x - display.visibleFrame.minX,
                y: display.visibleFrame.maxY - topLeft.y
            )
        )
    }

    /// The global top-left this placement means on the display it names, or nil when that
    /// display is not connected.
    public func topLeft(on displays: [DisplayFrame]) -> CGPoint? {
        guard let display = displays.first(where: { $0.id == displayID }) else { return nil }
        return CGPoint(
            x: display.visibleFrame.minX + offset.x,
            y: display.visibleFrame.maxY - offset.y
        )
    }

    /// The same offset applied to some other display, clamped so the panel stays reachable.
    ///
    /// What a card falls back to while its own display is unplugged. It keeps its shape of the
    /// layout - the same distance from the top, roughly the same side - instead of being piled
    /// into a corner, and the placement itself is left alone so the card goes home when the
    /// display returns.
    public func topLeft(borrowing display: DisplayFrame, size: CGSize) -> CGPoint {
        let x = min(
            max(display.visibleFrame.minX + offset.x, display.visibleFrame.minX),
            max(display.visibleFrame.maxX - size.width, display.visibleFrame.minX)
        )
        let top = display.visibleFrame.maxY - offset.y
        let y = min(
            max(top, display.visibleFrame.minY + size.height),
            display.visibleFrame.maxY
        )
        return CGPoint(x: x, y: y)
    }

    /// Whether the display this placement names is connected.
    public func isHome(on displays: [DisplayFrame]) -> Bool {
        displays.contains { $0.id == displayID }
    }

    /// Whether a panel's current position is worth writing down.
    ///
    /// The rule has two halves and both matter. A panel parked on a borrowed display keeps the
    /// placement it already has, so unplugging a monitor for an hour does not make the deck move
    /// house. But a panel the user has just dragged, or a deck they have just tidied, is a
    /// decision, and a decision outranks the placement it replaces - otherwise the arrangement is
    /// dropped on the floor and the next screen change hauls every card back to where it was
    /// parked.
    public static func shouldRecord(
        existing: PanelPlacement?,
        userMoved: Bool,
        displays: [DisplayFrame]
    ) -> Bool {
        guard let existing, !userMoved else { return true }
        return existing.isHome(on: displays)
    }

    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
