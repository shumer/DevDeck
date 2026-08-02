import Foundation

/// Abstraction over suspending a task, so retry and refresh loops run instantly in tests.
public protocol Sleeper: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}

    public func sleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// Records requested delays instead of waiting.
///
/// An actor rather than a lock-guarded class: `sleep` is async, and NSLock is unavailable
/// from async contexts under strict concurrency.
public actor RecordingSleeper: Sleeper {
    public private(set) var delays: [TimeInterval] = []

    public init() {}

    public func sleep(seconds: TimeInterval) async throws {
        delays.append(seconds)
    }
}
