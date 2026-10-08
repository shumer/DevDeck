import DevDeckCore
import Foundation
import ProjectKit

struct Configuration: Decodable {
    struct Project: Decodable {
        let id: String
        let title: String
        let distribution: String
        let path: String
        let startCommand: String
        let healthURL: String
    }
    let project: Project
}

actor Readiness {
    private var ready = false
    private var waiter: CheckedContinuation<Void, Never>?
    func signal() { ready = true; waiter?.resume(); waiter = nil }
    func wait() async {
        if ready { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

do {
    let configFile = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LOCALAPPDATA"]!)
        .appendingPathComponent("DevDeckPOC/config.json")
    let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configFile)).project
    guard !config.distribution.isEmpty, config.path.hasPrefix("/") else {
        throw CommandError.launchFailed("Project distribution and Linux path are required.")
    }
    let runner = ShellCommandRunner(distribution: config.distribution)
    let folder = URL(fileURLWithPath: config.path, isDirectory: true)
    let project = LocalProject(
        id: config.id, title: config.title, folder: config.path,
        startCommand: config.startCommand, holdsProcess: true, healthURL: config.healthURL
    )
    let service = LocalProjectService(project: project, runner: runner)
    let action = CommandLine.arguments.dropFirst().first ?? "status"
    switch action {
    case "start", "stop":
        guard let result = await service.perform(action == "start" ? .start : .stop), result.succeeded else {
            throw CommandError.launchFailed("Project action failed.")
        }
        let status = action == "start" ? await service.waitUntilRunning(timeout: 15, pollInterval: 0.2) : await service.status()
        print(status.state.rawValue)
        if status.isRunning != (action == "start") { throw CommandError.launchFailed("Unexpected project state.") }
    case "status":
        print(await service.status().state.rawValue)
    case "cancel", "timeout":
        let readiness = Readiness()
        let pidFile = LocalProjectService.shellQuoted(config.path + "/smoke.pid")
        let childFile = LocalProjectService.shellQuoted(config.path + "/smoke-child.pid")
        let command = "echo $$ > \(pidFile); trap '' TERM; setsid sleep 300 & echo $! > \(childFile); echo READY; wait"
        let task = Task {
            defer { Task { await readiness.signal() } }
            return try await runner.run(command, in: folder, timeout: action == "cancel" ? 15 : 2) { line in
                if line == "READY" { Task { await readiness.signal() } }
            }
        }
        if action == "cancel" {
            await readiness.wait()
            task.cancel()
        }
        do {
            _ = try await task.value
            throw CommandError.launchFailed("Expected interruption.")
        } catch is CancellationError {
            guard action == "cancel" else { throw CommandError.launchFailed("Unexpected cancellation.") }
        } catch CommandError.timedOut {
            guard action != "cancel" else { throw CommandError.launchFailed("Unexpected timeout.") }
        }
        let verification = try await runner.run(
            "pid=$(cat \(pidFile)); child=$(cat \(childFile)); "
                + "if test -r /proc/$child/stat && test \"$(awk '{print $3}' /proc/$child/stat)\" != Z; then exit 1; fi; "
                + "ps -eo pgid=,stat= | awk -v group=$pid '$1 == group && $2 !~ /^Z/ { found=1 } END { exit found }'",
            in: folder, timeout: 5
        )
        guard verification.succeeded else { throw CommandError.launchFailed("Live Linux descendants remain.") }
        print("No live Linux processes remain after \(action).")
    default:
        throw CommandError.launchFailed("Unknown smoke action.")
    }
} catch {
    FileHandle.standardError.write(Data("WSL smoke check failed.\n".utf8))
    exit(1)
}
