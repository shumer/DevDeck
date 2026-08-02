import Foundation

/// A decoded REST payload plus the two pieces of transport metadata the refresh loop cares
/// about: whether anything actually changed, and how often the server wants to be polled.
public struct RESTResult<Value: Sendable>: Sendable {
    public let value: Value
    public let wasNotModified: Bool
    public let pollIntervalSeconds: TimeInterval?

    public init(value: Value, wasNotModified: Bool, pollIntervalSeconds: TimeInterval?) {
        self.value = value
        self.wasNotModified = wasNotModified
        self.pollIntervalSeconds = pollIntervalSeconds
    }
}
