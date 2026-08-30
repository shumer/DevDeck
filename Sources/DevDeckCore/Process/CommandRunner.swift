import Foundation

public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool { exitCode == 0 }

    /// Boilerplate that tools print after the actual failure. Taking the last line blindly
    /// puts "a complete log can be found in …" on the card instead of the reason.
    private static let noise = [
        "a complete log of this run",
        "for more information",
        "see the full log",
    ]

    /// The most useful line to show when something failed.
    ///
    /// Prefers the first line that names an error, because tools print the cause first and
    /// then footer noise; falls back to the last real line, and to stdout for tools that
    /// report failures on the wrong stream.
    public var failureLine: String? {
        for stream in [standardError, standardOutput] {
            let lines = stream
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { line in
                    guard !line.isEmpty else { return false }
                    let lowercased = line.lowercased()
                    return !Self.noise.contains { lowercased.contains($0) }
                }

            if let named = lines.first(where: { line in
                let lowercased = line.lowercased()
                return lowercased.contains("error") || lowercased.contains("fatal")
                    || lowercased.contains("cannot") || lowercased.contains("denied")
            }) {
                return named
            }
            if let last = lines.last { return last }
        }
        return nil
    }
}

/// Runs a shell command in a directory.
public protocol CommandRunning: Sendable {
    /// `isInteractive` is for the one command that has to be: asking the shell what its `PATH`
    /// is. Everything else runs non-interactively, because an interactive profile prints things
    /// and those things land in output somebody is parsing.
    /// `onOutput` receives each line as it arrives, which is the only way to say anything about
    /// a command that takes a minute: waiting for it to exit and then reporting is exactly the
    /// silence that makes a button look broken.
    func run(
        _ command: String,
        in directory: URL,
        timeout: TimeInterval,
        isInteractive: Bool,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> CommandResult
}

public extension CommandRunning {
    func run(_ command: String, in directory: URL, timeout: TimeInterval) async throws -> CommandResult {
        try await run(command, in: directory, timeout: timeout, isInteractive: false, onOutput: nil)
    }

    func run(
        _ command: String,
        in directory: URL,
        timeout: TimeInterval,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult {
        try await run(command, in: directory, timeout: timeout, isInteractive: false, onOutput: onOutput)
    }

    func run(
        _ command: String,
        in directory: URL,
        timeout: TimeInterval,
        isInteractive: Bool
    ) async throws -> CommandResult {
        try await run(command, in: directory, timeout: timeout, isInteractive: isInteractive, onOutput: nil)
    }
}

public enum CommandError: Error, Sendable, Equatable {
    case missingDirectory(String)
    case timedOut(String)
    case launchFailed(String)
}

/// Runs commands through a login shell, with the `PATH` the user's terminal actually has.
///
/// Neither half is decoration. An app launched from Finder inherits a bare environment, so a
/// plain `npx` cannot be found and the button appears to do nothing; `zsh -lc` sources the
/// profile and fixes most of that. What it does not fix is anything installed by a version
/// manager: a login shell that is not interactive never reads `.zshrc`, which is where nvm,
/// rbenv and pyenv live. That produced the most confusing possible symptom - `ddev` and
/// `docker` working, both being in `/usr/local/bin`, while `npx` reported "command not found"
/// from a machine that plainly has it. `ShellPath` asks an interactive shell once and every
/// command gets the answer.
public struct ShellCommandRunner: CommandRunning {
    private let shell: String

    public init(shell: String = "/bin/zsh") {
        self.shell = shell
    }

    public func run(
        _ command: String,
        in directory: URL,
        timeout: TimeInterval = 120,
        isInteractive: Bool = false,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> CommandResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CommandError.missingDirectory(directory.path)
        }

        // Resolved once per launch and reused. A command that needs nvm - `npx`, `pnpm` - is
        // otherwise not found at all when the app was launched from Finder.
        let path = isInteractive ? nil : await ShellPath.shared.value(runner: self)

        // Everything below blocks, and the caller is on the main actor: without hopping to a
        // background queue the app freezes for as long as the command runs, which for a stack
        // that takes a minute to come up looks exactly like a button that does nothing.
        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                do {
                    continuation.resume(returning: try Self.execute(
                        shell: shell,
                        command: command,
                        directory: directory,
                        timeout: timeout,
                        isInteractive: isInteractive,
                        path: path,
                        onOutput: onOutput
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static let queue = DispatchQueue(label: "com.shumer.devdeck.commands", qos: .userInitiated)

    /// Reads to the end, handing over whole lines as they arrive.
    ///
    /// Still one read loop per pipe, so the deadlock the two-reader design exists to avoid stays
    /// avoided; the only difference is that the caller hears about a line before the process
    /// exits. Tools that draw progress with carriage returns - compose does - are split on those
    /// too, or the whole run arrives as one enormous line at the end.
    private static func drain(
        _ handle: FileHandle,
        onOutput: (@Sendable (String) -> Void)?
    ) -> Data {
        var collected = Data()
        var pending = Data()

        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            collected.append(chunk)
            guard let onOutput else { continue }

            pending.append(chunk)
            while let index = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let line = String(decoding: pending[pending.startIndex..<index], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...index)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { onOutput(trimmed) }
            }
        }

        if let onOutput, !pending.isEmpty {
            let line = String(decoding: pending, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { onOutput(line) }
        }
        return collected
    }

    private static func execute(
        shell: String,
        command: String,
        directory: URL,
        timeout: TimeInterval,
        isInteractive: Bool,
        path: String?,
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // `-i` only for the PATH probe: a login shell alone never reads `.zshrc`, which is where
        // version managers install themselves.
        process.arguments = [isInteractive ? "-ilc" : "-lc", command]
        process.currentDirectoryURL = directory
        if let path {
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = path
            process.environment = environment
        }

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        // No stdin at all. `npx` asks "Ok to proceed?" when a package is missing, and a
        // command waiting on an answer nobody can give never returns.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(error.localizedDescription)
        }

        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // Both pipes are drained at once: reading one to the end first deadlocks as soon as
        // the other fills its buffer, and build output fills it easily.
        // The group is the synchronisation: nothing reads these until both blocks have
        // finished, which the compiler cannot see from here.
        nonisolated(unsafe) var outputData = Data()
        nonisolated(unsafe) var errorData = Data()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            outputData = drain(output.fileHandleForReading, onOutput: onOutput)
        }
        DispatchQueue.global().async(group: group) {
            errorData = drain(error.fileHandleForReading, onOutput: onOutput)
        }
        group.wait()

        process.waitUntilExit()
        watchdog.cancel()

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }
}

/// Test double: answers from a script of prefixes without touching the shell.
public actor StubCommandRunner: CommandRunning {
    private let responses: [(match: String, result: CommandResult)]
    public private(set) var commands: [String] = []

    public init(_ responses: [(String, CommandResult)]) {
        self.responses = responses.map { (match: $0.0, result: $0.1) }
    }

    public func run(
        _ command: String,
        in directory: URL,
        timeout: TimeInterval,
        isInteractive: Bool,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> CommandResult {
        commands.append(command)
        guard let match = responses.first(where: { command.contains($0.match) }) else {
            return CommandResult(exitCode: 127, standardOutput: "", standardError: "command not found")
        }
        // Replayed a line at a time, so a test can assert on what a card would have shown while
        // the command was still running.
        if let onOutput {
            for line in match.result.standardOutput.split(separator: "\n") {
                onOutput(String(line).trimmingCharacters(in: .whitespaces))
            }
        }
        return match.result
    }
}
