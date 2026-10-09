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

    /// How long asking WSL about the process may take. Every command goes through login shells,
    /// and a profile that loads nvm or conda costs seconds on its own: a tighter limit read a busy
    /// WSL as "nothing is running", and Stop then did nothing.
    static let livenessTimeout: TimeInterval = 10

    /// How long a started project has to write down its process. The client reaches that line only
    /// after its own login shell, so this is the same slow profile again.
    static let recordingSeconds = 15

    private var logPath: String { "\(Self.runtimeDirectory)/\(LocalProjectService.shellQuoted(project.id + ".log"))" }
    private var pidPath: String { "\(Self.runtimeDirectory)/\(LocalProjectService.shellQuoted(project.id + ".pid"))" }
    private var cancellationPath: String {
        "\(Self.runtimeDirectory)/\(LocalProjectService.shellQuoted(project.id + ".cancel"))"
    }

    func livePID(in folder: URL) async -> Int32? {
        do {
            return try await recordedPID(in: folder)
        } catch {
            Log.app.debug("project \(project.id): could not ask WSL for its process: \(error)")
            return nil
        }
    }

    /// The recorded process, checked in one WSL invocation against the boot it was recorded in
    /// and the start time it had, so a reused process id is never taken for the project.
    ///
    /// Nil means there is no such process. Not being able to ask throws instead, because Stop
    /// must not read "WSL did not answer" as "nothing to stop".
    private func recordedPID(in folder: URL) async throws -> Int32? {
        let check = "read -r pid boot started < \(pidPath) || exit 1; "
            + "case $pid in ''|*[!0-9]*) exit 1 ;; esac; test $pid -gt 1 && "
            + "test \"$boot\" = \"$(cat /proc/sys/kernel/random/boot_id)\" && "
            + "test \"$started\" = \"$(awk '{print $22}' /proc/$pid/stat 2>/dev/null)\" && "
            + "test \"$(awk '{print $3}' /proc/$pid/stat 2>/dev/null)\" != Z && "
            + "kill -0 $pid 2>/dev/null && printf '%s' $pid"
        let result = try await runner.run(check, in: folder, timeout: Self.livenessTimeout)
        guard result.succeeded else { return nil }
        guard let pid = Int32(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else { return nil }
        return pid
    }

    func start(in folder: URL) async -> CommandResult? {
        guard project.holdsProcess else {
            let command = "mkdir -p \(Self.runtimeDirectory) && { \(project.startCommand); } > \(logPath) 2>&1"
            do {
                return try await runner.run(command, in: folder, timeout: 900)
            } catch {
                return failure("start did not finish", error)
            }
        }
        guard let launcher = runner as? any DetachedProjectLaunching else { return nil }
        let preparation = "mkdir -p \(Self.runtimeDirectory) && rm -f \(pidPath) \(cancellationPath)"
        do {
            let prepared = try await runner.run(preparation, in: folder, timeout: 30)
            guard prepared.succeeded else { return prepared }
        } catch {
            return failure("could not prepare the project in WSL", error)
        }
        guard !Task.isCancelled else { return nil }

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
        let client: DetachedProjectClient
        do {
            client = try launcher.launchProject(launchScript, in: folder)
        } catch {
            return failure("could not start a WSL client for the project", error)
        }
        let readiness = """
        for attempt in $(seq 1 \(Self.recordingSeconds * 10)); do
            test -s \(pidPath) && exit 0
            sleep 0.1
        done
        exit 1
        """
        // Long enough for the slow profile twice over, the client's and this check's own: giving
        // up early is not harmless here, because a start that gives up takes the project down.
        let readinessTimeout = TimeInterval(Self.recordingSeconds) + Self.livenessTimeout
        do {
            let result = try await runner.run(readiness, in: folder, timeout: readinessTimeout)
            if !result.succeeded {
                await cleanFailedStart(client, readiness: readiness, in: folder)
                return CommandResult(
                    exitCode: result.exitCode, standardOutput: result.standardOutput,
                    standardError: "the project did not record its process within \(Self.recordingSeconds) s"
                )
            }
            return result
        } catch {
            await cleanFailedStart(client, readiness: readiness, in: folder)
            return failure("could not confirm the project started", error)
        }
    }

    func stop(in folder: URL) async -> CommandResult? {
        let trimmed = project.stopCommand.trimmingCharacters(in: .whitespaces)
        let command: String
        if !trimmed.isEmpty {
            command = trimmed
        } else {
            let pid: Int32?
            do {
                pid = try await recordedPID(in: folder)
            } catch {
                return failure("could not ask WSL for the project's process", error)
            }
            guard let pid else { return nil }
            command = Self.killTreeCommand(pid: pid, projectID: project.id)
        }
        let result: CommandResult
        do {
            result = try await runner.run(command, in: folder, timeout: 30)
        } catch {
            return failure("stop did not finish", error)
        }
        if result.succeeded {
            _ = try? await runner.run("rm -f \(pidPath)", in: folder, timeout: Self.livenessTimeout)
        }
        return result
    }

    private func failure(_ what: String, _ error: any Error) -> CommandResult? {
        projectFailure(project.id, what, error)
    }

    private func cleanFailedStart(_ client: DetachedProjectClient, readiness: String, in folder: URL) async {
        // Cleanup gets a cancellation context of its own: it often runs because the engine's own
        // task was cancelled, and a cancelled cleanup would leave the project running.
        let launcher = self
        let marker = cancellationPath
        await Task.detached {
            let timeout = TimeInterval(Self.recordingSeconds) + Self.livenessTimeout
            _ = try? await launcher.runner.run("touch \(marker); \(readiness)", in: folder, timeout: timeout)
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
        do {
            return try runner.startProject(project.id, command: project.startCommand, in: folder)
        } catch {
            return projectFailure(project.id, "could not start the project", error)
        }
    }

    func stop(in folder: URL) async -> CommandResult? {
        do {
            return try await runner.stopProject(project.id)
        } catch {
            return projectFailure(project.id, "stop did not finish", error)
        }
    }
}

/// An action that could not be carried out, said on the card rather than swallowed. A stop that
/// fails silently leaves a project running behind a card that looks like nothing happened.
private func projectFailure(_ projectID: String, _ what: String, _ error: any Error) -> CommandResult? {
    // A cancelled action is the caller changing its mind, not something to report.
    if error is CancellationError { return nil }
    Log.app.debug("project \(projectID): \(what): \(error)")
    return CommandResult(exitCode: -1, standardOutput: "", standardError: "\(what): \(error)")
}
#endif
