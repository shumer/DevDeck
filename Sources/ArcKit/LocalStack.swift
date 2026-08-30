import DevDeckCore
import Foundation

public enum LocalStackState: String, Sendable, Equatable, Codable {
    /// The engine answered its health URL.
    case running
    /// Nothing is answering.
    case stopped
    /// A command issued from the card is still going.
    case working
    /// No folder configured, so there is nothing to run or check.
    case unavailable
}

public struct LocalStackStatus: Sendable, Equatable, Codable {
    public var state: LocalStackState
    /// Engine version, when the health endpoint reports one.
    public var engineVersion: String?
    public var containers: Int?
    /// What is going on, or why the last command failed.
    public var detail: String?
    public var checkedAt: Date?
    /// The URL actually used, resolved from `.env`. The card shows the real port from here
    /// rather than from the setting, which is usually empty.
    public var siteURL: URL?
    /// Branch the checkout is on - what the local stack is actually serving.
    public var branch: String?
    /// The repository this checkout came from, when it has an origin.
    public var repositoryURL: URL?
    /// The last line the running command printed. A start takes a minute and says plenty on the
    /// way; showing none of it is what made the card look asleep.
    public var progressLine: String?

    public init(
        state: LocalStackState,
        engineVersion: String? = nil,
        containers: Int? = nil,
        detail: String? = nil,
        checkedAt: Date? = nil,
        siteURL: URL? = nil,
        branch: String? = nil,
        repositoryURL: URL? = nil,
        progressLine: String? = nil
    ) {
        self.state = state
        self.engineVersion = engineVersion
        self.containers = containers
        self.detail = detail
        self.checkedAt = checkedAt
        self.siteURL = siteURL
        self.branch = branch
        self.repositoryURL = repositoryURL
        self.progressLine = progressLine
    }

    public static let unavailable = LocalStackStatus(state: .unavailable, detail: "No project folder set")

    public var isRunning: Bool { state == .running }
    public var isBusy: Bool { state == .working }
}

/// What the card's buttons do.
public enum LocalStackAction: String, Sendable, CaseIterable {
    case start
    case stop
    case restart
    case rebuild
    case teardown

    public var title: String {
        switch self {
        case .start: return "Start"
        case .stop: return "Stop"
        case .restart: return "Restart"
        case .rebuild: return "Rebuild"
        case .teardown: return "Down (remove containers)"
        }
    }

    /// What the card says while it runs.
    public var progressText: String {
        switch self {
        case .start: return "starting…"
        case .stop: return "stopping…"
        case .restart: return "restarting…"
        case .rebuild: return "rebuilding…"
        case .teardown: return "removing…"
        }
    }
}

/// Runs the local Fusion stack for one project and reports whether it is up.
public struct LocalStackService: Sendable {
    private let project: ArcProject
    private let runner: any CommandRunning
    private let httpClient: any HTTPClient
    private let clock: any DateProvider
    private let sleeper: any Sleeper

    public init(
        project: ArcProject,
        runner: any CommandRunning = ShellCommandRunner(),
        httpClient: any HTTPClient = URLSessionHTTPClient.makeDefault(timeout: 3),
        clock: any DateProvider = SystemDateProvider(),
        sleeper: any Sleeper = TaskSleeper()
    ) {
        self.project = project
        self.runner = runner
        self.httpClient = httpClient
        self.clock = clock
        self.sleeper = sleeper
    }

    /// Waits for the engine to answer after a start.
    ///
    /// `fusion daemon` returns as soon as the containers are up, but the engine needs a while
    /// longer before it serves anything. Checking once and giving up is how a stack that is
    /// still warming reads as "did not start".
    /// `hint` is what the start command said. When the engine never answers, that line is the
    /// answer - `fusion daemon` prints "ports are not available … address already in use" and
    /// then exits zero, so without carrying it the card can only report the silence and not its
    /// cause.
    public func waitUntilRunning(
        timeout: TimeInterval = 180,
        pollInterval: TimeInterval = 3,
        hint: String? = nil
    ) async -> LocalStackStatus {
        let deadline = clock.now.addingTimeInterval(timeout)
        var latest = await status()

        while !latest.isRunning, clock.now < deadline {
            try? await sleeper.sleep(seconds: pollInterval)
            latest = await status()
        }

        guard !latest.isRunning else { return latest }
        // The command exited and nothing answers. What it printed on the way out is worth far
        // more than the fact of the silence.
        return LocalStackStatus(
            state: .stopped,
            detail: hint ?? "started, but \(project.healthURL?.absoluteString ?? "the health URL") never answered",
            checkedAt: clock.now,
            branch: latest.branch,
            repositoryURL: latest.repositoryURL
        )
    }

    /// Waits for the engine to stop answering after a stop.
    ///
    /// Because a stop that quietly did nothing is the failure this cannot afford. The command
    /// returns before the containers are down, so checking once says "still running" for a stop
    /// that worked; not checking at all lets the next poll say "running" for one that did not,
    /// with no hint that anything was even attempted.
    public func waitUntilStopped(
        timeout: TimeInterval = 30,
        pollInterval: TimeInterval = 2
    ) async -> LocalStackStatus {
        let deadline = clock.now.addingTimeInterval(timeout)
        var latest = await status()

        while latest.isRunning, clock.now < deadline {
            try? await sleeper.sleep(seconds: pollInterval)
            latest = await status()
        }

        guard latest.isRunning else { return latest }
        // Still serving. Said plainly on the card rather than letting the poll paint it green
        // again as though the button had never been pressed.
        return LocalStackStatus(
            state: .running,
            engineVersion: latest.engineVersion,
            containers: latest.containers,
            detail: "stop did not take effect, still answering",
            checkedAt: clock.now,
            siteURL: latest.siteURL,
            branch: latest.branch,
            repositoryURL: latest.repositoryURL
        )
    }

    /// Asks the engine directly rather than inspecting processes.
    ///
    /// The point is that the answer stays true when the stack was started by hand in a
    /// terminal: the card reports what is actually serving, not what this app happened to
    /// launch.
    public func status() async -> LocalStackStatus {
        guard project.supportsLocalStack, let healthURL = project.healthURL else {
            return .unavailable
        }

        let siteURL = project.localSiteURL
        // Read whether the stack is up or not: knowing which branch is checked out matters
        // most when it is running, and is still worth showing before you start it.
        let branch = GitCheckout.branch(in: project.folderURL)
        let repositoryURL = GitCheckout.originWebURL(in: project.folderURL)

        do {
            let response = try await httpClient.send(HTTPRequest(url: healthURL))
            guard response.isSuccess else {
                return LocalStackStatus(
                    state: .stopped,
                    detail: "health check answered \(response.statusCode)",
                    checkedAt: clock.now,
                    siteURL: siteURL,
                    branch: branch,
                    repositoryURL: repositoryURL
                )
            }
            return LocalStackStatus(
                state: .running,
                engineVersion: Self.engineVersion(from: response.body),
                containers: await containerCount(),
                checkedAt: clock.now,
                siteURL: siteURL,
                branch: branch,
                repositoryURL: repositoryURL
            )
        } catch {
            return LocalStackStatus(
                state: .stopped,
                checkedAt: clock.now,
                siteURL: siteURL,
                branch: branch,
                repositoryURL: repositoryURL
            )
        }
    }

    /// `/release` is documented as reporting the engine version; the exact shape differs
    /// between versions, so both a JSON object and a bare string are accepted.
    public static func engineVersion(from body: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            for key in ["version", "engineVersion", "release", "fusionVersion"] {
                if let value = object[key] as? String, !value.isEmpty { return value }
            }
            return nil
        }
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 40, !text.contains("<") else { return nil }
        return text
    }

    /// Best effort: Compose names its project after the directory, so containers can be
    /// counted without knowing anything about the stack's internals. A different naming
    /// scheme simply reports nothing rather than a wrong number.
    private func containerCount() async -> Int? {
        guard let folder = project.folderURL else { return nil }
        let name = folder.lastPathComponent.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        let command = "docker ps --filter label=com.docker.compose.project=\(name) --format '{{.Names}}'"
        guard let result = try? await runner.run(command, in: folder, timeout: 10), result.succeeded else {
            return nil
        }
        let count = result.standardOutput
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        return count > 0 ? count : nil
    }

    // MARK: Actions

    public func perform(
        _ action: LocalStackAction,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async -> CommandResult? {
        guard let folder = project.folderURL else { return nil }

        switch action {
        case .start:
            return try? await runner.run(
                project.startCommand, in: folder, timeout: 600, isInteractive: false, onOutput: onOutput
            )
        case .stop:
            return try? await runner.run(
                project.stopCommand, in: folder, timeout: 300, isInteractive: false, onOutput: onOutput
            )
        case .rebuild:
            return try? await runner.run(
                project.rebuildCommand, in: folder, timeout: 900, isInteractive: false, onOutput: onOutput
            )
        case .teardown:
            return try? await runner.run(
                project.teardownCommand, in: folder, timeout: 300, isInteractive: false, onOutput: onOutput
            )
        case .restart:
            // Sequential on purpose: starting before the old containers release their ports
            // fails in a way that looks like the stack is broken.
            _ = try? await runner.run(
                project.stopCommand, in: folder, timeout: 300, isInteractive: false, onOutput: onOutput
            )
            return try? await runner.run(
                project.startCommand, in: folder, timeout: 600, isInteractive: false, onOutput: onOutput
            )
        }
    }
}
