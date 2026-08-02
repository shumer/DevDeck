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
