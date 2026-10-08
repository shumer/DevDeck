#if os(Windows)
import Foundation

/// Linux process identifiers are checked inside their owning WSL distribution.
public enum ProcessLiveness {
    public static func isAlive(_ pid: Int32, distribution: String) -> Bool {
        guard pid > 0 else { return false }
        let process = Process()
        let systemRoot = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
        process.executableURL = URL(fileURLWithPath: systemRoot).appendingPathComponent("System32/wsl.exe")
        process.arguments = ["-d", distribution, "--", "kill", "-0", String(pid)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        return process.terminationStatus == 0
    }
}
#else
import Darwin
import Foundation

/// Whether a process id is still alive.
///
/// A syscall rather than a shell out to `kill -0`: this is asked for every project on every
/// poll, and spawning a login shell ten times a minute to learn one bit is absurd.
public enum ProcessLiveness {
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        // EPERM means it exists and belongs to someone else - still alive. Only ESRCH is a
        // genuine "no such process".
        return errno == EPERM
    }
}
#endif
