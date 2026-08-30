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
