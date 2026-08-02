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
    func run(_ command: String, in directory: URL, timeout: TimeInterval) async throws -> CommandResult
}

public enum CommandError: Error, Sendable, Equatable {
    case missingDirectory(String)
    case timedOut(String)
    case launchFailed(String)
}

/// Runs commands through an interactive login shell.
///
/// This is not decoration: an app launched from Finder inherits a bare `PATH` with no
/// Homebrew and no nvm, so a plain `npx` cannot be found and the button appears to do
/// nothing. `zsh -lc` sources the user's profile and gives the command the same environment
/// their terminal has.
public struct ShellCommandRunner: CommandRunning {
    private let shell: String

    public init(shell: String = "/bin/zsh") {
        self.shell = shell
    }

    public func run(
        _ command: String,
        in directory: URL,
        timeout: TimeInterval = 120
    ) async throws -> CommandResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CommandError.missingDirectory(directory.path)
        }

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
                        timeout: timeout
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static let queue = DispatchQueue(label: "com.shumer.devdeck.commands", qos: .userInitiated)

    private static func execute(
        shell: String,
        command: String,
        directory: URL,
        timeout: TimeInterval
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = directory

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
        var outputData = Data()
        var errorData = Data()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            outputData = output.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global().async(group: group) {
            errorData = error.fileHandleForReading.readDataToEndOfFile()
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

    public func run(_ command: String, in directory: URL, timeout: TimeInterval) async throws -> CommandResult {
        commands.append(command)
        guard let match = responses.first(where: { command.contains($0.match) }) else {
            return CommandResult(exitCode: 127, standardOutput: "", standardError: "command not found")
        }
        return match.result
    }
}
