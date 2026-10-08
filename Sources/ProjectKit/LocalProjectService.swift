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
/// Both are handled the same way - output goes to a log file, the process id is written down -
/// so that "is it up" can always be answered by asking the health URL rather than by
/// remembering what kind of command it was.
public struct LocalProjectService: Sendable {
    private let project: LocalProject
    private let runner: any CommandRunning
    private let httpClient: any HTTPClient
    private let clock: any DateProvider
    private let sleeper: any Sleeper
    private let files: ProjectRuntimeFiles

    #if os(Windows)
    public init(
        project: LocalProject,
        runner: any CommandRunning,
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

    #else
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

    #endif

    public var logURL: URL { files.log(project.id) }

    /// The tail of the log the detached start writes.
    ///
    /// Read straight off disk rather than through `tail`, because there is no reason to spawn a
    /// shell for something Foundation does, and because this runs on every refresh while the
    /// tray is open.
    public func logs(limit: Int = LogTail.lineLimit) async -> LogLines {
        let name = logURL.lastPathComponent
        let bytes = limit > LogTail.lineLimit ? LogTail.windowTailBytes : LogTail.fileTailBytes
        guard let text = LogTail.tail(of: logURL, bytes: bytes) else {
            return LogLines(
                source: "tail \(name)",
                detail: L("project.log.nothingStarted"),
                fetchedAt: clock.now,
                fileURL: nil
            )
        }
        let lines = LogTail.lines(from: text, limit: limit)
        return LogLines(
            lines: lines,
            source: "tail \(name)",
            detail: lines.isEmpty ? L("project.log.empty") : nil,
            fetchedAt: clock.now,
            fileURL: logURL
        )
    }
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
        #if os(Windows)
        let pid = await windowsStoredPID(in: folder)
        let isAlive = pid != nil
        #else
        let pid = storedPID()
        let isAlive = pid.map(ProcessLiveness.isAlive) ?? false
        #endif
        let hasLog = FileManager.default.fileExists(atPath: logURL.path)

        guard let healthURL = project.healthCheckURL else {
            // Nothing to ask, so the process we started is the whole answer.
            return LocalProjectStatus(
                state: isAlive ? .running : .stopped,
                detail: isAlive ? nil : L("project.noHealthURL"),
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
                    detail: response.isSuccess ? nil : L("project.answered", response.statusCode),
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
                detail: L("project.urlAnswered", healthURL.absoluteString, response.statusCode),
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
    /// server - and a 500 is not something you can open either.
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

        while !latest.isRunning, clock.now < deadline, !Task.isCancelled {
            // A process that died on its own is a failure, not something to keep waiting on.
            if latest.state == .stopped, project.holdsProcess { break }
            try? await sleeper.sleep(seconds: pollInterval)
            latest = await status()
        }

        guard !latest.isRunning else { return latest }
        return LocalProjectStatus(
            state: .stopped,
            detail: project.healthCheckURL.map { L("project.started.noAnswer", $0.absoluteString) }
                ?? L("project.didNotStayUp"),
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
        let currentStatus = await status()
        if currentStatus.isRunning || currentStatus.pid != nil {
            return CommandResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        guard !Task.isCancelled else { return nil }
        #if os(Windows)
        if let native = runner as? NativeWindowsCommandRunner {
            return try? native.startProject(project.id, command: project.startCommand, in: folder)
        }
        let runtimeDirectory = Self.windowsRuntimeDirectory
        let logPath = "\(runtimeDirectory)/\(Self.shellQuoted(project.id + ".log"))"
        guard project.holdsProcess else {
            let command = "mkdir -p \(runtimeDirectory) && { \(project.startCommand); } > \(logPath) 2>&1"
            return try? await runner.run(command, in: folder, timeout: 900)
        }
        guard let launcher = runner as? any DetachedProjectLaunching else { return nil }
        let pidPath = "\(runtimeDirectory)/\(Self.shellQuoted(project.id + ".pid"))"
        let cancellationPath = "\(runtimeDirectory)/\(Self.shellQuoted(project.id + ".cancel"))"
        let preparation = "mkdir -p \(runtimeDirectory) && rm -f \(pidPath) \(cancellationPath)"
        guard let prepared = try? await runner.run(preparation, in: folder, timeout: 30),
              prepared.succeeded, !Task.isCancelled else { return nil }

        // Keeping the WSL client alive prevents idle shutdown without changing global settings.
        let launchScript = """
        {
            export DEVDECK_POC_PROJECT=\(Self.shellQuoted(project.id))
            pid=$$
            boot=$(cat /proc/sys/kernel/random/boot_id)
            started=$(awk '{print $22}' /proc/$pid/stat)
            printf '%s %s %s\\n' $pid $boot $started > \(pidPath).tmp || exit $?
            mv \(pidPath).tmp \(pidPath) || exit $?
            test ! -e \(cancellationPath) || exit 125
            exec /bin/bash -lc \(Self.shellQuoted(project.startCommand))
        } > \(logPath) 2>&1 < /dev/null
        """
        guard let client = try? launcher.launchProject(launchScript, in: folder) else { return nil }
        let readiness = """
        for attempt in $(seq 1 30); do
            test -s \(pidPath) && exit 0
            sleep 0.1
        done
        exit 1
        """
        do {
            let result = try await runner.run(readiness, in: folder, timeout: 5)
            if !result.succeeded {
                await cleanFailedWindowsStart(client, cancelFile: cancellationPath, readiness: readiness, in: folder)
            }
            return result
        } catch {
            await cleanFailedWindowsStart(client, cancelFile: cancellationPath, readiness: readiness, in: folder)
            return nil
        }
        #else
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
        #endif
    }

    private func stop(in folder: URL) async -> CommandResult? {
        #if os(Windows)
        if let native = runner as? NativeWindowsCommandRunner {
            return try? await native.stopProject(project.id)
        }
        let trimmed = project.stopCommand.trimmingCharacters(in: .whitespaces)
        let command: String
        if !trimmed.isEmpty {
            command = trimmed
        } else {
            guard let pid = await windowsStoredPID(in: folder) else { return nil }
            command = Self.killWindowsTreeCommand(pid: pid, projectID: project.id)
        }
        let result = try? await runner.run(command, in: folder, timeout: 30)
        if result?.succeeded == true {
            _ = try? await runner.run(
                "rm -f \(Self.windowsRuntimeDirectory)/\(Self.shellQuoted(project.id + ".pid"))", in: folder, timeout: 3
            )
        }
        return result
        #else
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
        #endif
    }

    #if os(Windows)
    // Runtime files belong to the Linux process and survive a Windows engine restart.
    private static let windowsRuntimeDirectory = "\"$HOME/.local/share/DevDeckPOC/projects\""

    private func cleanFailedWindowsStart(
        _ client: DetachedProjectClient, cancelFile: String, readiness: String, in folder: URL
    ) async {
        // Cleanup must have its own cancellation context after the engine closes stdin.
        await Task.detached {
            _ = try? await runner.run("touch \(cancelFile); \(readiness)", in: folder, timeout: 5)
            _ = await stop(in: folder)
            client.terminate()
        }.value
    }

    private static func killWindowsTreeCommand(pid: Int32, projectID: String) -> String {
        // Freeze and collect ownership before a wrapper can exit and reparent its children.
        """
        targets=""
        freeze_tree() {
            local target=$1 child
            kill -STOP "$target" 2>/dev/null || return 0
            targets="$target $targets"
            for child in $(pgrep -P "$target" 2>/dev/null); do
                freeze_tree "$child"
            done
        }
        freeze_tree \(pid)
        for target in $(ps -eo pid=,pgid= | awk '$2 == \(pid) { print $1 }'); do
            freeze_tree "$target"
        done
        for directory in /proc/[0-9]*; do
            if grep -azqFx \(Self.shellQuoted("DEVDECK_POC_PROJECT=" + projectID)) "$directory/environ" 2>/dev/null; then
                freeze_tree "${directory##*/}"
            fi
        done
        for target in $targets; do kill -TERM "$target" 2>/dev/null || true; done
        for target in $targets; do kill -CONT "$target" 2>/dev/null || true; done
        sleep 0.3
        kill -KILL -- -\(pid) 2>/dev/null || true
        for target in $targets; do kill -KILL "$target" 2>/dev/null || true; done
        for attempt in $(seq 1 10); do
            live=0
            for target in $targets; do
                if test -r /proc/$target/stat && test "$(awk '{print $3}' /proc/$target/stat)" != Z; then
                    live=1
                fi
            done
            if test "$live" = 0 && ! ps -eo pgid=,stat= | awk '$1 == \(pid) && $2 !~ /^Z/ { found=1 } END { exit !found }'; then
                exit 0
            fi
            sleep 0.1
        done
        exit 1
        """
    }

    private func windowsStoredPID(in folder: URL) async -> Int32? {
        if let native = runner as? NativeWindowsCommandRunner {
            return native.projectPID(project.id)
        }
        guard let result = try? await runner.run(
            "read -r pid boot started < \(Self.windowsRuntimeDirectory)/\(Self.shellQuoted(project.id + ".pid")) || exit 1; "
                + "case $pid in ''|*[!0-9]*) exit 1 ;; esac; test $pid -gt 1 && "
                + "test \"$boot\" = \"$(cat /proc/sys/kernel/random/boot_id)\" && "
                + "test \"$started\" = \"$(awk '{print $22}' /proc/$pid/stat 2>/dev/null)\" && "
                + "test \"$(awk '{print $3}' /proc/$pid/stat 2>/dev/null)\" != Z && "
                + "kill -0 $pid 2>/dev/null && printf '%s' $pid",
            in: folder, timeout: 3
        ), result.succeeded else { return nil }
        guard let pid = Int32(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else { return nil }
        return pid
    }
    #endif

    // MARK: The commands

    /// Runs the command in the background, with its output in the log and its process id
    /// written down.
    ///
    /// Everything here is load-bearing. The redirection is what lets the caller return at all -
    /// a background child holding the runner's pipes keeps the read open until it exits, which
    /// for a dev server is forever. `nohup` is what lets it outlive this app.
    public static func detachedCommand(_ command: String, log: URL, pidFile: URL) -> String {
        let quoted = shellQuoted(command)
        #if os(Windows)
        let shell = "/bin/bash"
        #else
        let shell = "/bin/zsh"
        #endif
        return ": > \(shellQuoted(log.path)); "
            + "nohup \(shell) -lc \(quoted) >> \(shellQuoted(log.path)) 2>&1 & "
            + "echo $! > \(shellQuoted(pidFile.path))"
    }

    /// Runs the command and waits for it, keeping a copy of the output in the log.
    public static func foregroundCommand(_ command: String, log: URL) -> String {
        "{ \(command) ; } >> \(shellQuoted(log.path)) 2>&1"
    }

    /// Kills a process and everything under it.
    ///
    /// Killing the recorded pid alone is not enough: `npm run dev` is a wrapper, and stopping
    /// it leaves the server it spawned holding the port - which then makes the next start fail
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
