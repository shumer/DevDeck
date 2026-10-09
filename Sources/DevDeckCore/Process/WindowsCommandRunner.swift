#if os(Windows)
import Foundation

/// Runs project commands in one explicitly selected WSL distribution.
public struct WSLCommandRunner: CommandRunning, DetachedProjectLaunching {
    public let distribution: String

    public init(distribution: String) {
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
        private var finished = false
        private var cleanupStarted = false
        private var cleanupFailed = false
        private var launched = false
        private let cleanupGroup = DispatchGroup()
        private var distribution = ""
        private let operation = UUID().uuidString

        func cancel(timeout: Bool = false) {
            lock.lock()
            if finished {
                lock.unlock()
                return
            }
            if timeout { timedOut = true } else { cancelled = true }
            let shouldClean = launched && !cleanupStarted
            if shouldClean {
                cleanupStarted = true
                cleanupGroup.enter()
            }
            lock.unlock()
            guard shouldClean else { return }
            DispatchQueue.global().async {
                let succeeded = self.cleanupLinuxProcesses()
                self.lock.lock()
                self.cleanupFailed = !succeeded
                if self.process.isRunning { self.process.terminate() }
                self.lock.unlock()
                self.cleanupGroup.leave()
            }
        }

        func run(
            _ command: String, directory: URL, distribution: String,
            timeout: TimeInterval, onOutput: (@Sendable (String) -> Void)?
        ) throws -> CommandResult {
            let systemRoot = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
            process.executableURL = URL(fileURLWithPath: systemRoot)
                .appendingPathComponent("System32/wsl.exe")
            let state = "\"$HOME/.local/share/DevDeck/commands/\(operation)\""
            let child =
                "export DEVDECK_OPERATION=\(operation); echo $$ > \(state)/pid; test ! -e \(state)/cancel || exit 125; exec bash -lc \(Self.quoted(command))"
            let supervisor =
                "mkdir -p \(state) && { setsid bash -lc \(Self.quoted(child)) & child=$!; wait $child; code=$?; rm -rf \(state); exit $code; }"
            process.arguments = [
                "-d", distribution, "--cd", Self.linuxPath(directory, distribution),
                "--exec", "bash", "-lc", supervisor,
            ]
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            process.standardInput = FileHandle.nullDevice
            lock.lock()
            self.distribution = distribution
            if cancelled {
                lock.unlock()
                throw CancellationError()
            }
            do { try process.run() } catch {
                lock.unlock()
                throw CommandError.launchFailed(error.localizedDescription)
            }
            launched = true
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
            lock.lock()
            finished = true
            lock.unlock()
            cleanupGroup.wait()
            watchdog.cancel()
            lock.lock()
            let wasCancelled = cancelled
            let wasTimedOut = timedOut
            let didFailCleanup = cleanupFailed
            lock.unlock()
            if wasCancelled { throw CancellationError() }
            if wasTimedOut {
                let message = didFailCleanup
                    ? "WSL command timed out; its cleanup could not be verified"
                    : "WSL command"
                throw CommandError.timedOut(message)
            }
            if didFailCleanup { throw CommandError.launchFailed("Could not verify WSL process cleanup.") }
            return CommandResult(
                exitCode: process.terminationStatus,
                standardOutput: String(decoding: outputData, as: UTF8.self),
                standardError: String(decoding: errorData, as: UTF8.self)
            )
        }

        private func cleanupLinuxProcesses() -> Bool {
            let state = "\"$HOME/.local/share/DevDeck/commands/\(operation)\""
            let script = """
                state=\(state)
                mkdir -p "$state"; touch "$state/cancel"
                for attempt in $(seq 1 30); do
                    test -s "$state/pid" && break
                    sleep 0.1
                done
                pid=$(cat "$state/pid" 2>/dev/null || true)
                case "$pid" in ''|*[!0-9]*) pid=0 ;; esac
                test "$pid" -gt 1 || pid=0
                targets=""
                freeze_tree() {
                    local target=$1 child
                    kill -STOP "$target" 2>/dev/null || return 0
                    targets="$target $targets"
                    for child in $(pgrep -P "$target" 2>/dev/null); do freeze_tree "$child"; done
                }
                if test "$pid" -gt 1; then freeze_tree "$pid"; fi
                for target in $(ps -eo pid=,pgid= | awk -v group="$pid" '$2 == group { print $1 }'); do
                    freeze_tree "$target"
                done
                for directory in /proc/[0-9]*; do
                    if grep -azqFx 'DEVDECK_OPERATION=\(operation)' "$directory/environ" 2>/dev/null; then
                        freeze_tree "${directory##*/}"
                    fi
                done
                if test "$pid" -gt 1; then kill -TERM -- "-$pid" 2>/dev/null || true; fi
                for target in $targets; do kill -TERM "$target" 2>/dev/null || true; done
                for target in $targets; do kill -CONT "$target" 2>/dev/null || true; done
                sleep 0.3
                if test "$pid" -gt 1; then kill -KILL -- "-$pid" 2>/dev/null || true; fi
                for target in $targets; do kill -KILL "$target" 2>/dev/null || true; done
                for attempt in $(seq 1 10); do
                    live=0
                    for target in $targets; do
                        if test -r /proc/$target/stat && test "$(awk '{print $3}' /proc/$target/stat)" != Z; then live=1; fi
                    done
                    if test "$live" = 0 && ! ps -eo pgid=,stat= | awk -v group="$pid" '$1 == group && $2 !~ /^Z/ { found=1 } END { exit !found }'; then
                        if test "$pid" -gt 1; then rm -rf "$state"; fi
                        exit 0
                    fi
                    sleep 0.1
                done
                exit 1
                """
            let cleanup = Process()
            cleanup.executableURL = process.executableURL
            cleanup.arguments = ["-d", distribution, "--exec", "bash", "-lc", script]
            cleanup.standardInput = FileHandle.nullDevice
            cleanup.standardOutput = FileHandle.nullDevice
            cleanup.standardError = FileHandle.nullDevice
            do { try cleanup.run() } catch { return false }
            let watchdog = DispatchWorkItem { if cleanup.isRunning { cleanup.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
            cleanup.waitUntilExit()
            watchdog.cancel()
            return cleanup.terminationStatus == 0
        }

        private static func quoted(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
