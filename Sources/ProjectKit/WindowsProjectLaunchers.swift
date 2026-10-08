#if os(Windows)
import DevDeckCore
import Foundation

/// Runs a plain project inside a WSL distribution, driven from Windows.
///
/// The project gets a WSL client of its own, started detached from the engine, with the project
/// command in that client's foreground. WSL stops a distribution once no client is attached, and a
/// process put down with `nohup` does not count as one, so a project started the Mac way died
/// shortly after the engine exited. See docs/adr/0023-project-process-lifetime.md.
struct WSLProjectLauncher: ProjectProcessLauncher {
    let project: LocalProject
    let runner: any CommandRunning

    // Runtime files belong to the Linux process and survive an engine restart.
    static let runtimeDirectory = "\"$HOME/.local/share/DevDeck/projects\""

    /// Tags every process of the project, so a child that left the process group is still found.
    static let ownerVariable = "DEVDECK_PROJECT"

    private var logPath: String { "\(Self.runtimeDirectory)/\(LocalProjectService.shellQuoted(project.id + ".log"))" }
    private var pidPath: String { "\(Self.runtimeDirectory)/\(LocalProjectService.shellQuoted(project.id + ".pid"))" }
    private var cancellationPath: String {
        "\(Self.runtimeDirectory)/\(LocalProjectService.shellQuoted(project.id + ".cancel"))"
    }

    /// The recorded process, checked in one WSL invocation against the boot it was recorded in
    /// and the start time it had, so a reused process id is never taken for the project.
    func livePID(in folder: URL) async -> Int32? {
        let check = "read -r pid boot started < \(pidPath) || exit 1; "
            + "case $pid in ''|*[!0-9]*) exit 1 ;; esac; test $pid -gt 1 && "
            + "test \"$boot\" = \"$(cat /proc/sys/kernel/random/boot_id)\" && "
            + "test \"$started\" = \"$(awk '{print $22}' /proc/$pid/stat 2>/dev/null)\" && "
            + "test \"$(awk '{print $3}' /proc/$pid/stat 2>/dev/null)\" != Z && "
            + "kill -0 $pid 2>/dev/null && printf '%s' $pid"
        guard let result = try? await runner.run(check, in: folder, timeout: 3), result.succeeded else {
            return nil
        }
        guard let pid = Int32(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else { return nil }
        return pid
    }

    func start(in folder: URL) async -> CommandResult? {
        guard project.holdsProcess else {
            let command = "mkdir -p \(Self.runtimeDirectory) && { \(project.startCommand); } > \(logPath) 2>&1"
            return try? await runner.run(command, in: folder, timeout: 900)
        }
        guard let launcher = runner as? any DetachedProjectLaunching else { return nil }
        let preparation = "mkdir -p \(Self.runtimeDirectory) && rm -f \(pidPath) \(cancellationPath)"
        guard let prepared = try? await runner.run(preparation, in: folder, timeout: 30),
              prepared.succeeded, !Task.isCancelled else { return nil }

        let launchScript = """
        {
            export \(Self.ownerVariable)=\(LocalProjectService.shellQuoted(project.id))
            pid=$$
            boot=$(cat /proc/sys/kernel/random/boot_id)
            started=$(awk '{print $22}' /proc/$pid/stat)
            printf '%s %s %s\\n' $pid $boot $started > \(pidPath).tmp || exit $?
            mv \(pidPath).tmp \(pidPath) || exit $?
            test ! -e \(cancellationPath) || exit 125
            exec /bin/bash -lc \(LocalProjectService.shellQuoted(project.startCommand))
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
                await cleanFailedStart(client, readiness: readiness, in: folder)
            }
            return result
        } catch {
            await cleanFailedStart(client, readiness: readiness, in: folder)
            return nil
        }
    }

    func stop(in folder: URL) async -> CommandResult? {
        let trimmed = project.stopCommand.trimmingCharacters(in: .whitespaces)
        let command: String
        if !trimmed.isEmpty {
            command = trimmed
        } else {
            guard let pid = await livePID(in: folder) else { return nil }
            command = Self.killTreeCommand(pid: pid, projectID: project.id)
        }
        let result = try? await runner.run(command, in: folder, timeout: 30)
        if result?.succeeded == true {
            _ = try? await runner.run("rm -f \(pidPath)", in: folder, timeout: 3)
        }
        return result
    }

    private func cleanFailedStart(_ client: DetachedProjectClient, readiness: String, in folder: URL) async {
        // Cleanup gets a cancellation context of its own: it often runs because the engine's own
        // task was cancelled, and a cancelled cleanup would leave the project running.
        let launcher = self
        let marker = cancellationPath
        await Task.detached {
            _ = try? await launcher.runner.run("touch \(marker); \(readiness)", in: folder, timeout: 5)
            _ = await launcher.stop(in: folder)
            client.terminate()
        }.value
    }

    /// Stops a project's whole Linux tree.
    ///
    /// Every process is frozen and collected before any is signalled, so a wrapper cannot exit
    /// and hand its children to init while the tree is being walked. Processes that left the
    /// group are found by the owner variable in their environment.
    static func killTreeCommand(pid: Int32, projectID: String) -> String {
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
            if grep -azqFx \(LocalProjectService.shellQuoted(ownerVariable + "=" + projectID)) "$directory/environ" 2>/dev/null; then
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
}

/// Runs a plain project in a Windows folder, natively.
///
/// The process host and the named Job Object live in `NativeWindowsCommandRunner`; this only
/// connects them to the project. See docs/adr/0023-project-process-lifetime.md.
struct NativeWindowsProjectLauncher: ProjectProcessLauncher {
    let project: LocalProject
    let runner: NativeWindowsCommandRunner

    func livePID(in folder: URL) async -> Int32? {
        runner.projectPID(project.id)
    }

    func start(in folder: URL) async -> CommandResult? {
        try? runner.startProject(project.id, command: project.startCommand, in: folder)
    }

    func stop(in folder: URL) async -> CommandResult? {
        try? await runner.stopProject(project.id)
    }
}
#endif
