#if os(Windows)
import Foundation
import WinSDK

struct WindowsProjectStartup: Codable {
    let command: String
    let directory: String
    let jobName: String
    let jobHandle: UInt64
}

public enum WindowsProjectHost {
    public static func supervise() throws {
        let startup = try JSONDecoder().decode(
            WindowsProjectStartup.self, from: FileHandle.standardInput.readDataToEndOfFile())
        // An inherited handle keeps the job name available after the engine closes its own handle.
        let job = try WindowsHandle(HANDLE(bitPattern: UInt(startup.jobHandle)))
        SetHandleInformation(job.raw, DWORD(HANDLE_FLAG_INHERIT), 0)
        let output = try WindowsHandle(GetStdHandle(STD_OUTPUT_HANDLE))
        let error = try WindowsHandle(GetStdHandle(STD_ERROR_HANDLE))
        guard AllocConsole() else { throw CommandError.launchFailed("Could not create the project console.") }
        ShowWindow(GetConsoleWindow(), SW_HIDE)
        // The supervisor stays alive until every descendant leaves the job, including detached children.
        SetConsoleCtrlHandler(nil, false)
        SetConsoleCtrlHandler(
            { event in WindowsBool(event == DWORD(CTRL_C_EVENT) || event == DWORD(CTRL_BREAK_EVENT)) }, true)
        let input = try WindowsProcessSupport.file("NUL", writing: false)
        let executable =
            (ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows") + "\\System32\\cmd.exe"
        let child = try WindowsProcessSupport.create(
            executable: executable,
            commandLine: WindowsProcessSupport.quote(executable) + " /d /s /c \"" + startup.command + "\"",
            directory: startup.directory, flags: 0, input: input, output: output, error: error,
            job: nil, environment: WindowsEnvironment.current())
        child.thread.close()
        WaitForSingleObject(child.process.raw, DWORD(INFINITE))
        while let count = WindowsProcessSupport.activeProcesses(job), count > 1 { Sleep(50) }
    }

    public static func interrupt(pid: DWORD) -> Bool {
        FreeConsole()
        guard AttachConsole(pid) else { return false }
        defer { FreeConsole() }
        SetConsoleCtrlHandler(nil, true)
        let delivered = GenerateConsoleCtrlEvent(DWORD(CTRL_C_EVENT), 0)
        Sleep(200)
        return delivered
    }
}
#endif
