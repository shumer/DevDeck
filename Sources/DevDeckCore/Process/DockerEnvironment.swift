import Foundation

/// Whether the container runtime everything local depends on is there.
public enum DockerState: String, Sendable, Equatable, Codable {
    /// The daemon answered.
    case running
    /// The CLI is installed but nothing is listening on the socket.
    case notRunning
    /// No `docker` on the PATH a login shell sees.
    case notInstalled
    /// Launched from a card, not up yet.
    case starting
    /// Not asked yet. Deliberately not the same as "not running": a card must not accuse
    /// Docker of being down during the first second of a launch.
    case unknown
}

/// What the deck knows about the container runtime.
public struct DockerStatus: Sendable, Equatable {
    public var state: DockerState
    /// Server version, when the daemon answered with one.
    public var serverVersion: String?
    public var checkedAt: Date?

    public init(state: DockerState, serverVersion: String? = nil, checkedAt: Date? = nil) {
        self.state = state
        self.serverVersion = serverVersion
        self.checkedAt = checkedAt
    }

    public var isReady: Bool { state == .running }

    /// Whether pressing Start on a project that needs Docker could possibly work.
    ///
    /// `unknown` allows it: not having asked yet is not evidence of anything, and blocking on
    /// it would grey out every button for the first poll of every launch.
    public var allowsStart: Bool { state == .running || state == .unknown }

    /// The sentence a card puts where its own state would go. Nil when Docker is not in the
    /// way.
    public var blockingReason: String? {
        switch state {
        case .running, .unknown: return nil
        case .notRunning: return "Docker is not running"
        case .notInstalled: return "Docker is not installed"
        case .starting: return "starting Docker…"
        }
    }
}

/// Asks Docker whether it is there.
///
/// One probe for the whole deck, on the same loop as `ddev list`: every containerised project
/// has the same answer, and the question costs a subprocess.
///
/// It asks the daemon rather than looking for a running `Docker.app`, for the same reason the
/// rest of the deck asks the thing itself: Colima, OrbStack, Rancher and a remote context all
/// serve `docker` with no Docker Desktop anywhere, and a process-table check would call every
/// one of them "not running".
public struct DockerEnvironment: Sendable {
    /// Server version only - it fails fast and says nothing when the daemon is down, which is
    /// exactly the two answers this needs.
    public static let probeCommand = "docker version --format '{{.Server.Version}}'"

    private let runner: any CommandRunning
    private let clock: any DateProvider
    private let workingDirectory: URL

    public init(
        runner: any CommandRunning = ShellCommandRunner(),
        clock: any DateProvider = SystemDateProvider(),
        workingDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) {
        self.runner = runner
        self.clock = clock
        self.workingDirectory = workingDirectory
    }

    public func status() async -> DockerStatus {
        guard let result = try? await runner.run(Self.probeCommand, in: workingDirectory, timeout: 20) else {
            // The probe could not be run at all - treat it as unknown rather than blaming
            // Docker for something that went wrong on this side.
            return DockerStatus(state: .unknown, checkedAt: clock.now)
        }
        return Self.status(from: result, now: clock.now)
    }

    /// Reads the probe's answer. Separated from running it so the mapping is covered by the
    /// suite, which cannot spawn a shell.
    public static func status(from result: CommandResult, now: Date) -> DockerStatus {
        if result.succeeded {
            let version = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return DockerStatus(
                state: .running,
                serverVersion: version.isEmpty ? nil : version,
                checkedAt: now
            )
        }

        // 127 is the shell's own "no such command"; the message is checked too because a login
        // shell that fails on a profile line can return something else entirely.
        let missing = result.exitCode == 127
            || result.standardError.lowercased().contains("command not found")
        return DockerStatus(state: missing ? .notInstalled : .notRunning, checkedAt: now)
    }
}
