import DevDeckCore
import Foundation

/// A sleeper that moves an injected clock forward instead of waiting.
///
/// Anything that polls until a deadline needs both halves to be fake: a recording sleeper
/// alone leaves the clock frozen and the loop never ends.
public actor AdvancingSleeper: Sleeper {
    private let clock: MutableDateProvider
    public private(set) var delays: [TimeInterval] = []

    public init(clock: MutableDateProvider) {
        self.clock = clock
    }

    public func sleep(seconds: TimeInterval) async throws {
        delays.append(seconds)
        clock.advance(by: seconds)
    }
}
