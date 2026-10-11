import DevDeckCore
import Foundation

/// Where a plain project's process runs, and how it is started, found and stopped there.
///
/// `LocalProjectService` owns everything that is the same on every platform: asking the health
/// URL, waiting for a start to answer, the order of a restart, the log. What differs is only how
/// a process is put down so it outlives the app, how the deck finds it again, and how its whole
/// tree is taken away, and that is all a launcher does. The Mac runs it through the login shell;
/// Windows has one launcher for projects inside WSL and one for projects in Windows folders.
protocol ProjectProcessLauncher: Sendable {
    /// The process this project started, if it is still alive. Nil when there is none, or when
    /// the one on record has since gone.
    func livePID(in folder: URL) async -> Int32?

    func start(in folder: URL) async -> CommandResult?

    func stop(in folder: URL) async -> CommandResult?
}

#if !os(Windows)
/// Runs a plain project through the login shell on this machine.
///
/// The process id goes into a file under Application Support, the output into a log beside it,
/// and `nohup` is what lets the process outlive the app. Stopping walks the process tree from the
/// recorded id, because the recorded process is usually a wrapper such as `npm run dev`.
struct ShellProjectLauncher: ProjectProcessLauncher {
    let project: LocalProject
    let runner: any CommandRunning
    let files: ProjectRuntimeFiles
    let sleeper: any Sleeper
    /// Whether a process id is still somebody's. Injected so the suite can decide.
    let isAlive: @Sendable (Int32) -> Bool

    private var logURL: URL { files.log(project.id) }
    private var pidURL: URL { files.pid(project.id) }

    func livePID(in folder: URL) async -> Int32? {
        guard let pid = Self.readPID(at: pidURL), ProcessLiveness.isAlive(pid) else { return nil }
        return pid
    }

    func start(in folder: URL) async -> CommandResult? {
        try? FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)

        guard project.holdsProcess else {
            // A command that returns on its own is simply run and waited for; its output still
            // goes to the log, because that is where the card's Logs button looks.
            return try? await runner.run(
                LocalProjectService.foregroundCommand(project.startCommand, log: logURL),
                in: folder,
                timeout: 900
            )
        }

        return try? await runner.run(
            LocalProjectService.detachedCommand(project.startCommand, log: logURL, pidFile: pidURL),
            in: folder,
            timeout: 30
        )
    }

    func stop(in folder: URL) async -> CommandResult? {
        let trimmed = project.stopCommand.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let result = try? await runner.run(
                LocalProjectService.foregroundCommand(trimmed, log: logURL),
                in: folder,
                timeout: 300
            )
            forgetPID()
            return result
        }

        guard let pid = Self.readPID(at: pidURL) else { return nil }
        let result = try? await runner.run(LocalProjectService.killTreeCommand(pid: pid), in: folder, timeout: 30)
        // The tree as it stood before the signal, from the command's own output: once the
        // wrapper is gone its children belong to launchd and cannot be found from the record.
        var tree = Set((result?.standardOutput ?? "").split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) })
        tree.insert(pid)
        // Asked politely, not every tree goes: `dotnet run` sits on TERM, and so does anything
        // mid-shutdown waiting on a database. Wait a little, then insist, and forget the record
        // only once nothing is left of the tree. A record forgotten over a living tree is a
        // project the deck can never stop again: three servers read "started outside DevDeck"
        // the morning after a Stop that did not take, with Stop pointing at a terminal.
        if result?.succeeded == true {
            var survivors = await waitUntilGone(tree, attempts: 20)
            if !survivors.isEmpty {
                let list = survivors.sorted().map(String.init).joined(separator: " ")
                _ = try? await runner.run("kill -KILL \(list) 2>/dev/null", in: folder, timeout: 10)
                survivors = await waitUntilGone(survivors, attempts: 8)
            }
            if survivors.isEmpty { forgetPID() }
        } else if !isAlive(pid) {
            forgetPID()
        }
        return result
    }

    /// The processes of `pids` still alive after up to `attempts` quarter seconds.
    private func waitUntilGone(_ pids: Set<Int32>, attempts: Int) async -> Set<Int32> {
        var left = pids.filter(isAlive)
        var tries = 0
        while !left.isEmpty, tries < attempts {
            try? await sleeper.sleep(seconds: 0.25)
            left = left.filter(isAlive)
            tries += 1
        }
        return left
    }

    static func readPID(at url: URL) -> Int32? {
        guard
            let text = try? String(contentsOf: url, encoding: .utf8),
            let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return value
    }

    private func forgetPID() {
        try? FileManager.default.removeItem(at: pidURL)
    }
}
#endif
