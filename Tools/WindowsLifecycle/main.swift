import DevDeckCore
import DevDeckEngine
import Foundation
import ProjectKit
import WinSDK

final class ProcessIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [DWORD] = []

    func append(_ line: String) {
        guard line.hasPrefix("PID:"), let pid = DWORD(line.dropFirst(4)) else { return }
        lock.lock()
        defer { lock.unlock() }
        values.append(pid)
    }

    var captured: [DWORD] {
        lock.lock()
        defer { lock.unlock() }
        return values
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

func lifecycleService(
    configuration: EngineConfiguration,
    runner: NativeWindowsCommandRunner
) throws -> LocalProjectService {
    guard
        let project = configuration.projects.first(where: {
            if case .windows = $0.executionLocation { return true }
            return false
        })
    else {
        throw CommandError.launchFailed("A Windows project is required.")
    }
    return LocalProjectService(project: project.model, runner: runner)
}

func runProjectAction(
    _ action: LocalProjectAction,
    service: LocalProjectService
) async throws {
    guard let result = await service.perform(action) else {
        throw CommandError.launchFailed("Project action returned no result.")
    }
    guard result.succeeded else {
        throw CommandError.launchFailed(result.standardError)
    }
    let status: LocalProjectStatus
    if action == .start {
        status = await service.waitUntilRunning(timeout: 30, pollInterval: 0.2)
    } else {
        status = await service.status()
    }
    print(status.state.rawValue)
    guard status.isRunning == (action == .start) else {
        throw CommandError.launchFailed("Unexpected project state.")
    }
}

do {
    let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
    let supportedActions = ["start", "status", "stop", "timeout", "cancel", "path"]
    guard supportedActions.contains(arguments.action) else {
        throw CommandError.launchFailed("Unknown lifecycle action.")
    }
    let configuration = try EngineConfiguration.load(from: arguments.configFile)
    guard
        let project = configuration.projects.first(where: {
            if case .windows = $0.executionLocation { return true }
            return false
        })
    else {
        throw CommandError.launchFailed("A Windows project is required.")
    }
    let runner = NativeWindowsCommandRunner()
    let service = try lifecycleService(configuration: configuration, runner: runner)
    switch arguments.action {
    case "start":
        try await runProjectAction(.start, service: service)
        exit(0)
    case "status":
        print(await service.status().state.rawValue)
        exit(0)
    case "stop":
        try await runProjectAction(.stop, service: service)
        exit(0)
    default:
        break
    }

    let node = ProcessInfo.processInfo.environment["DEVDECK_SMOKE_NODE"] ?? "node"
    let script =
        "console.log('PID:'+process.pid);const c=require('child_process').spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'inherit'});console.log('PID:'+c.pid);setInterval(()=>{},1000)"
    let command = "\"" + node + "\" -e \"" + script + "\""
    if arguments.action == "path" {
        let name = Array("Path\0".utf16)
        let empty = Array("C:\\unavailable-demo-path\0".utf16)
        _ = name.withUnsafeBufferPointer { nameBuffer in
            empty.withUnsafeBufferPointer {
                SetEnvironmentVariableW(nameBuffer.baseAddress, $0.baseAddress)
            }
        }
        let result = try await runner.run(
            "node --version",
            in: URL(fileURLWithPath: project.path),
            timeout: 10
        )
        guard result.succeeded else {
            throw CommandError.launchFailed("Registry PATH did not replace the stale process PATH.")
        }
        let version = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.hasPrefix("v") else {
            throw CommandError.launchFailed("Registry PATH did not find Node.")
        }
        print("Windows registry PATH refresh passed.")
        exit(0)
    }

    let processIDs = ProcessIDs()
    let task = Task {
        try await runner.run(
            command,
            in: URL(fileURLWithPath: project.path),
            timeout: arguments.action == "timeout" ? 3 : 15
        ) { processIDs.append($0) }
    }
    if arguments.action == "cancel" {
        for _ in 0..<100 {
            if processIDs.captured.count == 2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        task.cancel()
    }
    do {
        _ = try await task.value
        throw CommandError.launchFailed("The interrupted command completed unexpectedly.")
    } catch is CancellationError {
        guard arguments.action == "cancel" else {
            throw CommandError.launchFailed("Unexpected cancellation.")
        }
    } catch CommandError.timedOut {
        guard arguments.action == "timeout" else {
            throw CommandError.launchFailed("Unexpected timeout.")
        }
    }
    guard processIDs.captured.count == 2 else {
        throw CommandError.launchFailed("Did not capture the command tree.")
    }
    for pid in processIDs.captured {
        if let handle = OpenProcess(DWORD(SYNCHRONIZE), false, pid) {
            defer { CloseHandle(handle) }
            guard WaitForSingleObject(handle, 5000) == DWORD(WAIT_OBJECT_0) else {
                throw CommandError.launchFailed("A command descendant survived.")
            }
        }
    }
    print("Windows \(arguments.action) cleanup passed for the parent and child.")
} catch {
    FileHandle.standardError.write(
        Data(("Windows lifecycle check failed: \(error.localizedDescription)\n").utf8)
    )
    exit(1)
}
