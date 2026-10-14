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

    /// A process running this project's start command from this project's folder, started
    /// somewhere else, taken on record so Stop can reach it. Nil when there is none, or more
    /// than one and so no telling which.
    func adopt(in folder: URL) async -> Int32?
}

extension ProjectProcessLauncher {
    func adopt(in folder: URL) async -> Int32? { nil }
}

/// How a process found in the process table is recognised as this project's: the same program
/// as the start command, running from exactly the project's folder. Never a port and never a
/// name alone, because either could be anybody's server.
enum ProcessAdoption {
    struct Entry: Equatable {
        let pid: Int32
        let ppid: Int32
        let command: String
    }

    /// The program a start command runs: `dotnet` for `dotnet run --launch-profile https`,
    /// `npm` for `PORT=3000 npm run dev`. Environment assignments in front are skipped.
    static func program(of command: String) -> String? {
        command.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first { !$0.contains("=") }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// Whether a running command line is that program. The first two words are looked at,
    /// because a script runs as its interpreter: `node /opt/homebrew/bin/pnpm run dev`.
    static func runs(_ program: String, _ commandLine: String) -> Bool {
        commandLine.split(whereSeparator: \.isWhitespace).prefix(2)
            .contains { URL(fileURLWithPath: String($0)).lastPathComponent == program }
    }

    /// `ps -axo pid=,ppid=,command=`, one process a line.
    static func processes(_ output: String) -> [Entry] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard parts.count == 3, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { return nil }
            return Entry(pid: pid, ppid: ppid, command: String(parts[2]))
        }
    }

    /// `lsof -Fpn` output: a `p` line names a process, the `n` line after it its directory.
    static func directories(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var current: Int32?
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p") { current = Int32(line.dropFirst()) }
            if line.hasPrefix("n"), let pid = current { result[pid] = String(line.dropFirst()) }
        }
        return result
    }

    /// The one process that heads this project's tree: running the program, in the folder,
    /// with no parent that does too. Nil for none, and for two separate copies.
    static func owner(program: String, folder: String, processes: [Entry], directories: [Int32: String]) -> Int32? {
        let wanted = canonical(folder)
        let matching = processes.filter { runs(program, $0.command) && directories[$0.pid].map(canonical) == wanted }
        let pids = Set(matching.map(\.pid))
        let heads = matching.filter { !pids.contains($0.ppid) }
        return heads.count == 1 ? heads[0].pid : nil
    }

    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
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

    /// Takes on record a copy of this project started from a terminal or by an agent's own
    /// shell, so Stop can reach it. Only a process that holds the start command's program and
    /// runs from exactly this folder: a server on the port alone could be anybody's.
    func adopt(in folder: URL) async -> Int32? {
        guard project.holdsProcess, let program = ProcessAdoption.program(of: project.startCommand),
              let listed = try? await runner.run("ps -axo pid=,ppid=,command=", in: folder, timeout: 10)
        else { return nil }
        let candidates = ProcessAdoption.processes(listed.standardOutput).filter { ProcessAdoption.runs(program, $0.command) }
        guard !candidates.isEmpty else { return nil }
        let list = candidates.map { String($0.pid) }.joined(separator: ",")
        // lsof says nothing for a pid that went away meanwhile and exits non-zero for it; what
        // it did print is still true.
        guard let found = try? await runner.run("lsof -a -d cwd -Fpn -p \(list) 2>/dev/null", in: folder, timeout: 10) else { return nil }
        guard let pid = ProcessAdoption.owner(
            program: program, folder: folder.path,
            processes: candidates, directories: ProcessAdoption.directories(found.standardOutput)
        ) else { return nil }
        try? FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try? "\(pid)".write(to: pidURL, atomically: true, encoding: .utf8)
        // The output goes wherever it was started; the log here says so rather than showing
        // the last run of the deck's own as if it were this one.
        // The pid as it is: a number formatted for the locale reads "11,742".
        try? (L("project.log.adopted", String(pid)) + "\n").write(to: logURL, atomically: true, encoding: .utf8)
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
