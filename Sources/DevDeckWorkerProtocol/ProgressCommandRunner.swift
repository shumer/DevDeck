import DevDeckCore
import Foundation

struct ProgressCommandRunner: CommandRunning {
    let base: any CommandRunning
    let progress: (@Sendable (String) -> Void)?
    func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
             onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await base.run(command, in: directory, timeout: timeout, isInteractive: isInteractive, onOutput: onOutput ?? progress)
    }
}

final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var previous = Date.distantPast
    func line(_ value: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(previous) >= 0.1 else { return nil }
        previous = now
        return LogTail.lines(from: String(value.prefix(2048)), limit: 1).last
    }
}
