import Foundation

/// Moves waiting to be believed.
///
/// AppKit posts the same `windowDidMove` for a window somebody dragged and for one the window
/// server pushed onto another screen because a display came or went, and the second kind arrives
/// a few milliseconds *before* the screen-parameters notification, with `NSScreen` already
/// describing the new arrangement. Measured on a real unplug: 8 ms. Saving on the spot therefore
/// records the window server's shove as a decision the user made, against the display the card
/// landed on, and the card has moved house without anybody touching it.
///
/// So a move waits. It is written down once the screens have kept quiet for `quietPeriod` after
/// it, and a screen change in the meantime throws every waiting move away: whatever they were,
/// they were not the user's, and the deck is about to be put back from its placements anyway. A
/// drag ends with a last move and 150 ms of silence, which nobody notices.
public struct PendingMoves: Equatable, Sendable {
    public let quietPeriod: TimeInterval
    private var waiting: [CardID: TimeInterval] = [:]

    public init(quietPeriod: TimeInterval = 0.15) {
        self.quietPeriod = quietPeriod
    }

    public var isEmpty: Bool { waiting.isEmpty }

    /// When the earliest waiting move becomes believable, or nil when nothing waits.
    public var nextDue: TimeInterval? {
        waiting.values.min().map { $0 + quietPeriod }
    }

    /// A window moved. Another move of the same card restarts its wait, which is what makes a
    /// drag one move rather than a hundred.
    public mutating func moved(_ card: CardID, at time: TimeInterval) {
        waiting[card] = time
    }

    /// The screens changed: everything waiting was the window server, not the user.
    @discardableResult
    public mutating func screensChanged() -> [CardID] {
        let dropped = Array(waiting.keys)
        waiting = [:]
        return dropped
    }

    /// The moves old enough to be believed, taken out of the queue.
    public mutating func settled(at time: TimeInterval) -> [CardID] {
        let due = waiting.filter { time - $0.value >= quietPeriod - 0.0005 }.map(\.key)
        for card in due {
            waiting[card] = nil
        }
        return due
    }
}
