#if !os(Windows)
import Foundation
import OSLog

/// Shared loggers. Subsystem is fixed so `log stream --predicate` filters work in development.
public enum Log {
    public static let subsystem = "com.shumer.devdeck"

    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let refresh = Logger(subsystem: subsystem, category: "refresh")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
#else
import Foundation

/// Windows diagnostics use stderr because stdout belongs to the engine protocol.
public enum Log {
    public static let network = WindowsLogger()
    public static let refresh = WindowsLogger()
    public static let storage = WindowsLogger()
    public static let app = WindowsLogger()
}

public struct WindowsLogger: Sendable {
    public func debug(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
#endif
