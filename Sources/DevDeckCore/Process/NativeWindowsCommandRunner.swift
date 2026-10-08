#if os(Windows)
import Foundation
import WinSDK

private struct WindowsProjectRecord: Codable {
    let pid: DWORD
    let creationTime: UInt64
}

private final class WindowsCommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var job: WindowsHandle?
    private var cancelled = false

    func install(_ job: WindowsHandle) {
        lock.lock()
        defer { lock.unlock() }
        self.job = job
        if cancelled { TerminateJobObject(job.raw, 125) }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let job { TerminateJobObject(job.raw, 125) }
    }
}

public struct NativeWindowsCommandRunner: CommandRunning {
    private let runtimeDirectory: URL
    private let processHost: URL

    public init(runtimeDirectory: URL? = nil, processHost: URL? = nil) {
        let local = ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? NSTemporaryDirectory()
        self.runtimeDirectory =
            runtimeDirectory ?? URL(fileURLWithPath: local).appendingPathComponent("DevDeck/projects")
        self.processHost =
            processHost
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .appendingPathComponent("DevDeckProcessHost.exe")
    }

    private func jobName(_ id: String) -> String { "Local\\DevDeck-project-" + id }
    private func recordURL(_ id: String) -> URL { runtimeDirectory.appendingPathComponent(id + ".pid.json") }
    private var commandInterpreter: String {
        (ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows") + "\\System32\\cmd.exe"
    }

    public func projectPID(_ id: String) -> Int32? {
        guard let data = try? Data(contentsOf: recordURL(id)),
            let record = try? JSONDecoder().decode(WindowsProjectRecord.self, from: data),
            let process = try? WindowsHandle(
                OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE), false, record.pid)),
            WaitForSingleObject(process.raw, 0) == DWORD(WAIT_TIMEOUT),
            let job = try? WindowsProcessSupport.openJob(named: jobName(id))
        else { return nil }
        var member = WindowsBool(false)
        guard IsProcessInJob(process.raw, job.raw, &member), member.boolValue else { return nil }
        var created = FILETIME()
        var exited = FILETIME()
        var kernel = FILETIME()
        var user = FILETIME()
        guard GetProcessTimes(process.raw, &created, &exited, &kernel, &user),
            UInt64(created.dwHighDateTime) << 32 | UInt64(created.dwLowDateTime) == record.creationTime
        else { return nil }
        return Int32(bitPattern: record.pid)
    }

    public func startProject(_ id: String, command: String, in directory: URL) throws -> CommandResult {
        try Task.checkCancellation()
        if projectPID(id) != nil { return CommandResult(exitCode: 0, standardOutput: "", standardError: "") }
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        let job = try WindowsProcessSupport.job(named: jobName(id), killOnClose: false)
        let input = try WindowsProcessSupport.pipe()
        let log = try WindowsProcessSupport.file(
            runtimeDirectory.appendingPathComponent(id + ".log").path, writing: true)
        let child = try WindowsProcessSupport.create(
            executable: processHost.path,
            commandLine: WindowsProcessSupport.quote(processHost.path) + " --supervise",
            directory: directory.path,
            flags: DWORD(DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_SUSPENDED),
            input: input.read, output: log, error: log, job: job, environment: WindowsEnvironment.current(),
            inheritJobHandle: true)
        do {
            guard let creationTime = child.creationTime else {
                throw CommandError.launchFailed("Could not identify the project process.")
            }
            let record = WindowsProjectRecord(pid: child.pid, creationTime: creationTime)
            try JSONEncoder().encode(record).write(to: recordURL(id), options: .atomic)
            guard ResumeThread(child.thread.raw) != DWORD.max else {
                throw CommandError.launchFailed("Could not resume the project process.")
            }
            child.thread.close()
            input.read.close()
            try WindowsProcessSupport.write(
                JSONEncoder().encode(
                    WindowsProjectStartup(
                        command: command, directory: directory.path, jobName: jobName(id),
                        jobHandle: UInt64(UInt(bitPattern: job.raw)))), to: input.write)
            input.write.close()
            try Task.checkCancellation()
            return CommandResult(exitCode: 0, standardOutput: "", standardError: "")
        } catch {
            TerminateJobObject(job.raw, 125)
            WaitForSingleObject(child.process.raw, 5000)
            try? FileManager.default.removeItem(at: recordURL(id))
            throw error
        }
    }

    public func stopProject(_ id: String) async throws -> CommandResult {
        guard let pid = projectPID(id) else {
            return CommandResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let job = try WindowsProcessSupport.openJob(named: jobName(id))
        let controller = Process()
        controller.executableURL = processHost
        controller.arguments = ["--interrupt", String(UInt32(bitPattern: pid))]
        controller.standardInput = FileHandle.nullDevice
        controller.standardOutput = FileHandle.nullDevice
        controller.standardError = FileHandle.nullDevice
        try? controller.run()
        for _ in 0..<20 {
            if WindowsProcessSupport.activeProcesses(job) == 0 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if controller.isRunning { controller.terminate() }
        let requiredTermination = WindowsProcessSupport.activeProcesses(job) != 0
        if WindowsProcessSupport.activeProcesses(job) != 0 {
            guard TerminateJobObject(job.raw, 0) else {
                throw CommandError.launchFailed("Could not stop the project job.")
            }
        }
        for _ in 0..<100 {
            if WindowsProcessSupport.activeProcesses(job) == 0 {
                try? FileManager.default.removeItem(at: recordURL(id))
                return CommandResult(
                    exitCode: 0,
                    standardOutput: requiredTermination
                        ? "Job termination verified." : "Console interruption verified.", standardError: "")
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        throw CommandError.launchFailed("Project processes did not exit.")
    }

    public func run(
        _ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> CommandResult {
        let cancellation = WindowsCommandCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result: CommandResult = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    do {
                        let result = try execute(
                            command, in: directory, timeout: timeout, onOutput: onOutput,
                            cancellation: cancellation)
                        continuation.resume(returning: result)
                    } catch { continuation.resume(throwing: error) }
                }
            }
            try Task.checkCancellation()
            return result
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func execute(
        _ command: String, in directory: URL, timeout: TimeInterval, onOutput: (@Sendable (String) -> Void)?,
        cancellation: WindowsCommandCancellation
    ) throws -> CommandResult {
        let job = try WindowsProcessSupport.job(named: nil, killOnClose: true)
        let input = try WindowsProcessSupport.file("NUL", writing: false)
        let output = try WindowsProcessSupport.pipe()
        let error = try WindowsProcessSupport.pipe()
        let child = try WindowsProcessSupport.create(
            executable: commandInterpreter,
            commandLine: WindowsProcessSupport.quote(commandInterpreter) + " /d /s /c \"" + command + "\"",
            directory: directory.path, flags: DWORD(CREATE_NO_WINDOW), input: input, output: output.write,
            error: error.write,
            job: job, environment: WindowsEnvironment.current())
        child.thread.close()
        output.write.close()
        error.write.close()
        cancellation.install(job)
        nonisolated(unsafe) var outputData = Data()
        nonisolated(unsafe) var errorData = Data()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            outputData = WindowsProcessSupport.drain(output.read, onOutput: onOutput)
        }
        DispatchQueue.global().async(group: group) {
            errorData = WindowsProcessSupport.drain(error.read, onOutput: onOutput)
        }
        let waited = WaitForSingleObject(
            child.process.raw, DWORD(min(max(timeout * 1000, 1), Double(DWORD.max - 1))))
        // A command returning does not make its background descendants safe to leave running.
        TerminateJobObject(job.raw, waited == DWORD(WAIT_TIMEOUT) ? 124 : 0)
        WaitForSingleObject(child.process.raw, 5000)
        group.wait()
        for _ in 0..<250 {
            if WindowsProcessSupport.activeProcesses(job) == 0 { break }
            Sleep(20)
        }
        guard WindowsProcessSupport.activeProcesses(job) == 0 else {
            throw CommandError.launchFailed("Command descendants did not exit.")
        }
        if waited == DWORD(WAIT_TIMEOUT) { throw CommandError.timedOut("Windows command timed out.") }
        var code: DWORD = 0
        GetExitCodeProcess(child.process.raw, &code)
        return CommandResult(
            exitCode: Int32(bitPattern: code), standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self))
    }
}
#endif
