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

    /// The most useful line to show when something failed: the last non-empty line of stderr,
    /// falling back to stdout for tools that report failures on the wrong stream.
    public var failureLine: String? {
        let candidates = [standardError, standardOutput]
        for stream in candidates {
            let line = stream
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last { !$0.isEmpty }
            if let line, !line.isEmpty { return line }
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = directory

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(error.localizedDescription)
        }

        let watchdog = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning { process.terminate() }
        }

        // Both pipes have to be drained before waiting: a command that writes more than the
        // pipe buffer holds would block forever otherwise.
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
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
