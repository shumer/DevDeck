import DevDeckCore
import DevDeckEngine
import Foundation
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

do {
    let mode = CommandLine.arguments.dropFirst().first ?? "timeout"
    guard ["timeout", "cancel", "path"].contains(mode) else { exit(1) }
    let file = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LOCALAPPDATA"]!)
        .appendingPathComponent("DevDeckPOC/config.json")
    let configuration = try EngineConfiguration.load(from: file)
    guard
        let project = configuration.projects.first(where: {
            if case .windows = $0.executionLocation { return true }
            return false
        })
    else { exit(1) }
    let node = ProcessInfo.processInfo.environment["DEVDECK_SMOKE_NODE"] ?? "node"
    let script =
        "console.log('PID:'+process.pid);const c=require('child_process').spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'inherit'});console.log('PID:'+c.pid);setInterval(()=>{},1000)"
    let command = "\"" + node + "\" -e \"" + script + "\""
    let runner = NativeWindowsCommandRunner()
    if mode == "path" {
        let name = Array("Path\0".utf16)
        let empty = Array("C:\\unavailable-demo-path\0".utf16)
        _ = name.withUnsafeBufferPointer { nameBuffer in
            empty.withUnsafeBufferPointer { SetEnvironmentVariableW(nameBuffer.baseAddress, $0.baseAddress) }
        }
        let result = try await runner.run(
            "node --version", in: URL(fileURLWithPath: project.path), timeout: 10)
        guard result.succeeded,
            result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("v")
        else {
            throw CommandError.launchFailed("Registry PATH did not replace the stale process PATH.")
        }
        print("Windows registry PATH refresh passed.")
        exit(0)
    }
    let pids = ProcessIDs()
    let task = Task {
        try await runner.run(
            command, in: URL(fileURLWithPath: project.path), timeout: mode == "timeout" ? 3 : 15
        ) { pids.append($0) }
    }
    if mode == "cancel" {
        for _ in 0..<100 {
            if pids.captured.count == 2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        task.cancel()
    }
    do {
        _ = try await task.value
        throw CommandError.launchFailed("The interrupted command completed unexpectedly.")
    } catch is CancellationError {
        guard mode == "cancel" else { throw CommandError.launchFailed("Unexpected cancellation.") }
    } catch CommandError.timedOut {
        guard mode == "timeout" else { throw CommandError.launchFailed("Unexpected timeout.") }
    }
    guard pids.captured.count == 2 else {
        throw CommandError.launchFailed("Did not capture the command tree.")
    }
    for pid in pids.captured {
        if let handle = OpenProcess(DWORD(SYNCHRONIZE), false, pid) {
            defer { CloseHandle(handle) }
            guard WaitForSingleObject(handle, 5000) == DWORD(WAIT_OBJECT_0) else {
                throw CommandError.launchFailed("A command descendant survived.")
            }
        }
    }
    print("Windows \(mode) cleanup passed for the parent and child.")
} catch CommandError.launchFailed(let message) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("Windows lifecycle check failed.\n".utf8))
    exit(1)
}
