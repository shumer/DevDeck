import DevDeckCore
import Foundation
import Glibc
import WSLProcessSupport

/// Linux-only process sessions keep cancellation away from other projects and the worker itself.
public struct WSLCommandRunner: CommandRunning {
    private let shell: String
    public init(shell: String = ShellCommandRunner.defaultShell) { self.shell = shell }

    public func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
                    onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try Task.checkCancellation()
        let path = isInteractive ? nil : await ShellPath.shared.value(runner: self)
        let session = CommandSession()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try execute(command, directory: directory, path: path, interactive: isInteractive,
                                                                   timeout: timeout, onOutput: onOutput, session: session)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { session.stop(timedOut: false) }
    }

    private func execute(_ command: String, directory: URL, path: String?, interactive: Bool, timeout: TimeInterval,
                         onOutput: (@Sendable (String) -> Void)?, session: CommandSession) throws -> CommandResult {
        let output = Pipe(), error = Pipe()
        try session.launch {
            var pid: pid_t = 0
            func spawn(_ environmentPath: UnsafePointer<CChar>?) -> Int32 {
                devdeck_spawn_session(shell, command, directory.path, environmentPath, interactive ? 1 : 0,
                                      output.fileHandleForWriting.fileDescriptor, error.fileHandleForWriting.fileDescriptor, &pid)
            }
            let result = path.map { $0.withCString { spawn($0) } } ?? spawn(nil)
            guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(result)) }
            return pid
        }
        output.fileHandleForWriting.closeFile(); error.fileHandleForWriting.closeFile()
        let watchdog = DispatchWorkItem { session.stop(timedOut: true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + max(0.01, timeout), execute: watchdog)
        nonisolated(unsafe) var outputData = Data()
        nonisolated(unsafe) var errorData = Data()
        let draining = DispatchGroup()
        DispatchQueue.global().async(group: draining) { outputData = Self.drain(output.fileHandleForReading, onOutput: onOutput) }
        DispatchQueue.global().async(group: draining) { errorData = Self.drain(error.fileHandleForReading, onOutput: onOutput) }
        let status = session.wait()
        // Reap children before finishing the cancellation scope; descendants can hold a pipe open.
        draining.wait()
        watchdog.cancel()
        let reason = session.finish()
        if reason == .cancelled { throw CancellationError() }
        if reason == .timedOut { throw CommandError.timedOut("Command exceeded its deadline.") }
        return CommandResult(exitCode: status, standardOutput: String(decoding: outputData, as: UTF8.self),
                             standardError: String(decoding: errorData, as: UTF8.self))
    }

    private static func drain(_ handle: FileHandle, onOutput: (@Sendable (String) -> Void)?) -> Data {
        var collected = Data(), pending = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            if collected.count < WorkerProtocol.maximumFrameBytes {
                collected.append(chunk.prefix(WorkerProtocol.maximumFrameBytes - collected.count))
            }
            if let onOutput {
                pending.append(chunk)
                while let newline = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                    onOutput(String(decoding: pending.prefix(upTo: newline).prefix(2048), as: UTF8.self))
                    pending.removeSubrange(...newline)
                }
                if pending.count > 4096 { pending.removeAll(keepingCapacity: true) }
            }
        }
        if !pending.isEmpty { onOutput?(String(decoding: pending.prefix(2048), as: UTF8.self)) }
        return collected
    }
}

private final class CommandSession: @unchecked Sendable {
    enum Reason { case cancelled, timedOut }
    private let lock = NSLock()
    private var pid: pid_t?
    private var reason: Reason?
    private var complete = false

    func launch(_ action: () throws -> pid_t) throws {
        lock.lock(); defer { lock.unlock() }
        if reason != nil { throw CancellationError() }
        pid = try action()
    }
    func stop(timedOut: Bool) {
        lock.lock()
        guard !complete else { lock.unlock(); return }
        if reason == nil { reason = timedOut ? .timedOut : .cancelled }
        if let pid { _ = devdeck_signal_group(pid, SIGTERM) }
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
            lock.lock(); defer { lock.unlock() }
            if !complete, let pid { _ = devdeck_signal_group(pid, SIGKILL) }
        }
    }
    func wait() -> Int32 {
        lock.lock(); let current = pid; lock.unlock()
        guard let current else { return 127 }
        var code: Int32 = 127
        _ = devdeck_wait_child(current, &code)
        return code
    }
    func finish() -> Reason? {
        lock.lock(); defer { lock.unlock() }
        complete = true; pid = nil
        return reason
    }
}
