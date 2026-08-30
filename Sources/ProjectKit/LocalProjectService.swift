import DevDeckCore
import Foundation

/// Where a project's log, pid and other runtime leftovers live.
///
/// Under Application Support rather than in the checkout: a log file appearing inside someone's
/// repository is a change to their working tree, and this app has no business making one.
public struct ProjectRuntimeFiles: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func standard() -> ProjectRuntimeFiles {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return ProjectRuntimeFiles(
            directory: base.appendingPathComponent("DevDeck/projects", isDirectory: true)
        )
    }

    public func log(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).log")
    }

    public func pid(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).pid")
    }
}

/// Runs a plain project and reports whether it is up.
///
/// The awkward part of a project like this is that its start command may or may not return.
/// Both are handled the same way — output goes to a log file, the process id is written down —
/// so that "is it up" can always be answered by asking the health URL rather than by
/// remembering what kind of command it was.
public struct LocalProjectService: Sendable {
    private let project: LocalProject
    private let runner: any CommandRunning
    private let httpClient: any HTTPClient
    private let clock: any DateProvider
    private let sleeper: any Sleeper
    private let files: ProjectRuntimeFiles

    public init(
        project: LocalProject,
        runner: any CommandRunning = ShellCommandRunner(),
        httpClient: any HTTPClient = URLSessionHTTPClient.makeDefault(timeout: 3),
        clock: any DateProvider = SystemDateProvider(),
        sleeper: any Sleeper = TaskSleeper(),
        files: ProjectRuntimeFiles = .standard()
    ) {
        self.project = project
        self.runner = runner
        self.httpClient = httpClient
        self.clock = clock
        self.sleeper = sleeper
        self.files = files
    }

    public var logURL: URL { files.log(project.id) }
    public var pidURL: URL { files.pid(project.id) }

    // MARK: Status

    /// Asks the health URL first and the process table second.
    ///
    /// The order matters: a stack started by hand in a terminal has no pid here, and a card
    /// that calls it stopped while the site serves is worse than no card at all.
    public func status() async -> LocalProjectStatus {
        guard project.supportsCommands, let folder = project.folderURL else {
            return .unavailable
        }

        let branch = GitCheckout.branch(in: folder)
        let repositoryURL = GitCheckout.originWebURL(in: folder)
        let pid = storedPID()
        let isAlive = pid.map(ProcessLiveness.isAlive) ?? false
        let hasLog = FileManager.default.fileExists(atPath: logURL.path)

        guard let healthURL = project.healthCheckURL else {
            // Nothing to ask, so the process we started is the whole answer.
            return LocalProjectStatus(
                state: isAlive ? .running : .stopped,
                detail: isAlive ? nil : "no health URL, nothing running from here",
                checkedAt: clock.now,
                pid: isAlive ? pid : nil,
                branch: branch,
                repositoryURL: repositoryURL,
                hasLog: hasLog
            )
        }

        do {
            let response = try await httpClient.send(HTTPRequest(url: healthURL))
            if Self.isServing(response.statusCode) {
                return LocalProjectStatus(
                    state: .running,
                    detail: response.isSuccess ? nil : "answered \(response.statusCode)",
                    checkedAt: clock.now,
                    pid: isAlive ? pid : nil,
                    branch: branch,
                    repositoryURL: repositoryURL,
                    hasLog: hasLog
                )
            }
            // Something answered, and it was not this project. Treated exactly like silence,
            // with the code kept so the card can say which.
            return LocalProjectStatus(
                state: isAlive ? .starting : .stopped,
                detail: "\(healthURL.absoluteString) answered \(response.statusCode)",
                checkedAt: clock.now,
                pid: isAlive ? pid : nil,
                branch: branch,
                repositoryURL: repositoryURL,
                hasLog: hasLog
            )
        } catch {
            return LocalProjectStatus(
                state: isAlive ? .starting : .stopped,
                detail: isAlive
                    ? "process up, \(healthURL.absoluteString) not answering yet"
                    : nil,
                checkedAt: clock.now,
                pid: isAlive ? pid : nil,
                branch: branch,
                repositoryURL: repositoryURL,
                hasLog: hasLog
            )
        }
    }

    /// Whether an answer means "this project is up".
    ///
    /// Not simply "anything answered", which is what this used to say. A local port is a shared
    /// resource: a Docker container from another project held 8080, answered the configured
    /// `/health` with a 404, and the card reported a backend nobody had started as running. A
    /// 404 is a server saying it does not know this path, which is the answer of somebody else's
    /// server — and a 500 is not something you can open either.
    ///
    /// Redirects count, and so do 401 and 403: those are this project's own server saying "yes,
    /// and you need to sign in", which is a normal thing for a health path to do.
    public static func isServing(_ statusCode: Int) -> Bool {
        if (200..<400).contains(statusCode) { return true }
        return statusCode == 401 || statusCode == 403
    }

    /// Waits for the site to answer after a start.
    ///
    /// A dev server compiles for a few seconds and a compose stack pulls images; checking once
    /// and giving up is how a project that is coming up fine reads as "did not start".
    public func waitUntilRunning(
        timeout: TimeInterval = 90,
        pollInterval: TimeInterval = 2
    ) async -> LocalProjectStatus {
        let deadline = clock.now.addingTimeInterval(timeout)
        var latest = await status()

        while !latest.isRunning, clock.now < deadline {
            // A process that died on its own is a failure, not something to keep waiting on.
            if latest.state == .stopped, project.holdsProcess { break }
            try? await sleeper.sleep(seconds: pollInterval)
            latest = await status()
        }

        guard !latest.isRunning else { return latest }
        return LocalProjectStatus(
            state: .stopped,
            detail: project.healthCheckURL.map { "started, but \($0.absoluteString) never answered" }
                ?? "the process did not stay up",
            checkedAt: clock.now,
            branch: latest.branch,
            hasLog: latest.hasLog
        )
    }

    // MARK: Actions

    public func perform(_ action: LocalProjectAction) async -> CommandResult? {
        guard let folder = project.folderURL else { return nil }

        switch action {
        case .start:
            return await start(in: folder)
        case .stop:
            return await stop(in: folder)
        case .restart:
            // Sequential on purpose: starting before the old process releases its port fails in
            // a way that looks like the project is broken.
            _ = await stop(in: folder)
            return await start(in: folder)
        }
    }

    private func start(in folder: URL) async -> CommandResult? {
        try? FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)

        guard project.holdsProcess else {
            // A command that returns on its own is simply run and waited for; its output still
            // goes to the log, because that is where the card's Logs button looks.
            return try? await runner.run(
                Self.foregroundCommand(project.startCommand, log: logURL),
                in: folder,
                timeout: 900
            )
        }

        return try? await runner.run(
            Self.detachedCommand(project.startCommand, log: logURL, pidFile: pidURL),
            in: folder,
            timeout: 30
        )
    }

    private func stop(in folder: URL) async -> CommandResult? {
        let trimmed = project.stopCommand.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let result = try? await runner.run(
                Self.foregroundCommand(trimmed, log: logURL),
                in: folder,
                timeout: 300
            )
            forgetPID()
            return result
        }

        guard let pid = storedPID() else { return nil }
        let result = try? await runner.run(Self.killTreeCommand(pid: pid), in: folder, timeout: 30)
        forgetPID()
        return result
    }

    // MARK: The commands

    /// Runs the command in the background, with its output in the log and its process id
    /// written down.
    ///
    /// Everything here is load-bearing. The redirection is what lets the caller return at all —
    /// a background child holding the runner's pipes keeps the read open until it exits, which
    /// for a dev server is forever. `nohup` is what lets it outlive this app.
    public static func detachedCommand(_ command: String, log: URL, pidFile: URL) -> String {
        let quoted = shellQuoted(command)
        return ": > \(shellQuoted(log.path)); "
            + "nohup /bin/zsh -lc \(quoted) >> \(shellQuoted(log.path)) 2>&1 & "
            + "echo $! > \(shellQuoted(pidFile.path))"
    }

    /// Runs the command and waits for it, keeping a copy of the output in the log.
    public static func foregroundCommand(_ command: String, log: URL) -> String {
        "{ \(command) ; } >> \(shellQuoted(log.path)) 2>&1"
    }

    /// Kills a process and everything under it.
    ///
    /// Killing the recorded pid alone is not enough: `npm run dev` is a wrapper, and stopping
    /// it leaves the server it spawned holding the port — which then makes the next start fail
    /// for a reason nobody can see.
    public static func killTreeCommand(pid: Int32) -> String {
        "kt() { local child; for child in $(pgrep -P $1 2>/dev/null); do kt $child; done; "
            + "kill -TERM $1 2>/dev/null; }; kt \(pid)"
    }

    /// Wraps a string so the shell sees it exactly as written, quotes and all.
    public static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: The pid file

    public func storedPID() -> Int32? {
        guard
            let text = try? String(contentsOf: pidURL, encoding: .utf8),
            let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return value
    }

    private func forgetPID() {
        try? FileManager.default.removeItem(at: pidURL)
    }
}
