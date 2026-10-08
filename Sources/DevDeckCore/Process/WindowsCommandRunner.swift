#if os(Windows)
import Foundation

/// Runs project commands in one explicitly selected WSL distribution.
public struct ShellCommandRunner: CommandRunning {
    public let distribution: String

    public init(distribution: String = "Ubuntu-24.04") {
        self.distribution = distribution
    }

    public func run(
        _ command: String,
        in directory: URL,
        timeout: TimeInterval = 120,
        isInteractive: Bool = false,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> CommandResult {
        let execution = Execution()
        let distribution = self.distribution
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try execution.run(
                            command, directory: directory, distribution: distribution,
                            timeout: timeout, onOutput: onOutput
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            execution.cancel()
        }
    }

    private final class Execution: @unchecked Sendable {
        private let lock = NSLock()
        private let process = Process()
        private var cancelled = false
        private var timedOut = false

        func cancel(timeout: Bool = false) {
            lock.lock()
            defer { lock.unlock() }
            if timeout { timedOut = true } else { cancelled = true }
            if process.isRunning { process.terminate() }
        }

        func run(
            _ command: String, directory: URL, distribution: String,
            timeout: TimeInterval, onOutput: (@Sendable (String) -> Void)?
        ) throws -> CommandResult {
            let systemRoot = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
            process.executableURL = URL(fileURLWithPath: systemRoot)
                .appendingPathComponent("System32/wsl.exe")
            process.arguments = ["-d", distribution, "--cd", Self.linuxPath(directory, distribution),
                                 "--", "bash", "-lc", command]
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            process.standardInput = FileHandle.nullDevice
            lock.lock()
            if cancelled {
                lock.unlock()
                throw CancellationError()
            }
            do { try process.run() } catch {
                lock.unlock()
                throw CommandError.launchFailed(error.localizedDescription)
            }
            lock.unlock()
            let watchdog = DispatchWorkItem { self.cancel(timeout: true) }
            DispatchQueue.global().asyncAfter(deadline: .now() + max(0, timeout), execute: watchdog)
            nonisolated(unsafe) var outputData = Data()
            nonisolated(unsafe) var errorData = Data()
            let group = DispatchGroup()
            DispatchQueue.global().async(group: group) {
                outputData = Self.drain(output.fileHandleForReading, onOutput: onOutput)
            }
            DispatchQueue.global().async(group: group) {
                errorData = Self.drain(error.fileHandleForReading, onOutput: onOutput)
            }
            process.waitUntilExit()
            group.wait()
            watchdog.cancel()
            lock.lock()
            let wasCancelled = cancelled
            let wasTimedOut = timedOut
            lock.unlock()
            if wasCancelled { throw CancellationError() }
            if wasTimedOut { throw CommandError.timedOut("WSL command") }
            return CommandResult(
                exitCode: process.terminationStatus,
                standardOutput: String(decoding: outputData, as: UTF8.self),
                standardError: String(decoding: errorData, as: UTF8.self)
            )
        }

        private static func linuxPath(_ directory: URL, _ distribution: String) -> String {
            let path = directory.path.replacingOccurrences(of: "\\", with: "/")
            for host in ["wsl.localhost", "wsl$"] {
                let prefix = "//\(host)/\(distribution)"
                if path.hasPrefix(prefix + "/") { return String(path.dropFirst(prefix.count)) }
            }
            return path
        }

        private static func drain(
            _ handle: FileHandle, onOutput: (@Sendable (String) -> Void)?
        ) -> Data {
            var collected = Data()
            var pending = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                collected.append(chunk)
                guard let onOutput else { continue }
                pending.append(chunk)
                while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                    let line = String(decoding: pending[..<end], as: UTF8.self)
                    pending.removeSubrange(...end)
                    if !line.isEmpty { onOutput(line) }
                }
            }
            if let onOutput, !pending.isEmpty {
                onOutput(String(decoding: pending, as: UTF8.self))
            }
            return collected
        }
    }
}
#endif
