#if os(Windows)
import Foundation
import WinSDK

public enum WindowsTerminalCatalog {
    public static func current() -> [TerminalApplication] {
        let environment = WindowsEnvironment.current()
        // Application discovery follows the registered user folder, even with isolated preferences.
        let local = WindowsEnvironment.localAppData ?? environment["LOCALAPPDATA"] ?? ""
        let system = environment["SystemRoot"] ?? "C:\\Windows"
        let path = environment["Path"] ?? ""
        let folders = path.split(separator: ";").map(String.init)
        func exists(_ name: String) -> Bool {
            folders.contains { applicationExists(atPath: ($0 as NSString).appendingPathComponent(name)) }
        }
        var applications: [TerminalApplication] = []
        if exists("wt.exe") || applicationExists(atPath: local + "\\Microsoft\\WindowsApps\\wt.exe") {
            // These are the stable, preview, canary and unpackaged settings locations.
            let locations = [
                "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json",
                "Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json",
                "Packages/Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe/LocalState/settings.json",
                "Microsoft/Windows Terminal/settings.json",
            ]
            let root = URL(fileURLWithPath: local)
            let profiles = locations.compactMap { relative -> String? in
                try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            }.first.map(TerminalProfiles.parse) ?? []
            applications.append(TerminalApplication(id: "windowsTerminal", profiles: profiles))
        }
        if FileManager.default.fileExists(atPath: system + "\\System32\\cmd.exe") {
            applications.append(TerminalApplication(id: "commandPrompt"))
        }
        if FileManager.default.fileExists(atPath: system + "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe") {
            applications.append(TerminalApplication(id: "windowsPowerShell"))
        }
        let programFiles = environment["ProgramFiles"] ?? "C:\\Program Files"
        if exists("pwsh.exe") || FileManager.default.fileExists(atPath: programFiles + "\\PowerShell\\7\\pwsh.exe") {
            applications.append(TerminalApplication(id: "powerShell"))
        }
        return applications
    }

    public static func applicationExists(atPath path: String, readAttributes: (@Sendable (String) -> UInt32)? = nil) -> Bool {
        // Foundation reports false for an App Execution Alias; attributes do not open its target.
        let name = Array((path + "\0").utf16)
        let attributes = readAttributes?(path) ?? name.withUnsafeBufferPointer { GetFileAttributesW($0.baseAddress) }
        return attributes != INVALID_FILE_ATTRIBUTES && attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) == 0
    }
}
#endif
