import Foundation

/// A locked value for recording what concurrent code did.
///
/// Tests often need to note "which accounts were asked" from a closure the production code
/// calls on several tasks; a plain captured `var` is a data race the compiler rejects.
public final class Box<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    public init(_ value: Value) {
        self.storage = value
    }

    public var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}
