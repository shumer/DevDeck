import DevDeckCore
import DevDeckEngine
import Foundation
import ProjectKit

actor Readiness {
    private var ready = false
    private var waiter: CheckedContinuation<Void, Never>?
    func signal() {
        ready = true
        waiter?.resume()
        waiter = nil
    }
    func wait() async {
        if ready { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

struct Arguments {
    let action: String
    let configFile: URL

    init(_ values: [String]) throws {
        var remaining = values
        if let index = remaining.firstIndex(of: "--config") {
            guard remaining.indices.contains(index + 1) else {
                throw CommandError.launchFailed("--config requires a file path.")
            }
            configFile = URL(fileURLWithPath: remaining[index + 1])
            remaining.removeSubrange(index...(index + 1))
        } else {
            configFile = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LOCALAPPDATA"]!)
                .appendingPathComponent("DevDeck/config.json")
        }
        guard remaining.count <= 1 else {
            throw CommandError.launchFailed("Too many arguments.")
        }
        action = remaining.first ?? "status"
    }
}

do {
    let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
    let configuration = try EngineConfiguration.load(from: arguments.configFile)
    guard
        let config = configuration.projects.first(where: {
            if case .wsl = $0.executionLocation { return true }
            return false
        }),
        case .wsl(let distribution, let path) = config.executionLocation
    else {
        throw CommandError.launchFailed("Project distribution and Linux path are required.")
    }
    let runner = WSLCommandRunner(distribution: distribution)
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    let project = LocalProject(
        id: config.id, title: config.title, folder: path,
        startCommand: config.startCommand, holdsProcess: true, healthURL: config.healthURL
    )
    let service = LocalProjectService(project: project, runner: runner)
    let action = arguments.action
    switch action {
    case "start", "stop":
        guard let result = await service.perform(action == "start" ? .start : .stop) else {
            throw CommandError.launchFailed("Project action returned no result.")
        }
        guard result.succeeded else {
            throw CommandError.launchFailed(result.standardError)
        }
        let status =
            action == "start"
            ? await service.waitUntilRunning(timeout: 15, pollInterval: 0.2) : await service.status()
        print(status.state.rawValue)
        if status.isRunning != (action == "start") {
            throw CommandError.launchFailed("Unexpected project state.")
        }
    case "status":
        print(await service.status().state.rawValue)
    case "cancel", "timeout":
        let readiness = Readiness()
        let pidFile = LocalProjectService.shellQuoted(path + "/smoke.pid")
        let childFile = LocalProjectService.shellQuoted(path + "/smoke-child.pid")
        // A cold WSL boot must finish before the short timeout measures the command itself.
        let preparation = try await runner.run("rm -f \(pidFile) \(childFile)", in: folder, timeout: 30)
        guard preparation.succeeded else {
            throw CommandError.launchFailed("Could not prepare the WSL interruption check.")
        }
        let command =
            "echo $$ > \(pidFile); trap '' TERM; setsid sleep 300 & echo $! > \(childFile); echo READY; wait"
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
        guard verification.succeeded else {
            throw CommandError.launchFailed("Live Linux descendants remain.")
        }
        print("No live Linux processes remain after \(action).")
    default:
        throw CommandError.launchFailed("Unknown smoke action.")
    }
} catch {
    FileHandle.standardError.write(Data(("WSL smoke check failed: \(error.localizedDescription)\n").utf8))
    exit(1)
}
