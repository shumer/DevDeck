import DevDeckCore
import Foundation

/// The engine supplies every row, option, selection and word in the terminal group.
public struct DeckTerminalSettings: Sendable, Equatable, Codable {
    public struct Option: Sendable, Equatable, Codable {
        public let value: String?
        public let title: String
        public var isEnabled = true
    }

    public struct Field: Sendable, Equatable, Codable {
        public let request: String
        public let label: String
        public let options: [Option]
        public let selected: String?
    }

    public let title: String
    public let detail: String
    public let fields: [Field]

    public static func make(choice: TerminalChoice, applications: [TerminalApplication]) -> DeckTerminalSettings {
        guard !applications.isEmpty else { return DeckTerminalSettings(title: "", detail: "", fields: []) }
        var options = [Option(value: nil, title: L("terminal.system"))]
        for application in applications {
            let title: String
            switch application.id {
            case "windowsTerminal": title = L("terminal.windowsTerminal")
            case "commandPrompt": title = L("terminal.commandPrompt")
            case "windowsPowerShell": title = L("terminal.windowsPowerShell")
            case "powerShell": title = L("terminal.powerShell")
            default: continue
            }
            options.append(Option(value: application.id, title: title))
        }
        if let saved = choice.application, !options.contains(where: { $0.value == saved }) {
            options.append(Option(value: saved, title: L("terminal.unavailable"), isEnabled: false))
        }
        var fields = [Field(request: "setTerminalApplication", label: L("terminal.application"), options: options, selected: choice.application)]
        let effective = choice.application ?? (applications.contains { $0.id == "windowsTerminal" } ? "windowsTerminal" : "commandPrompt")
        if effective == "windowsTerminal", let application = applications.first(where: { $0.id == effective }) {
            var profiles = [Option(value: nil, title: L("terminal.defaultProfile"))]
            profiles += application.profiles.map { Option(value: $0.id, title: $0.name) }
            if let saved = choice.profile, !profiles.contains(where: { $0.value == saved }) {
                profiles.append(Option(value: saved, title: L("terminal.unavailable"), isEnabled: false))
            }
            fields.append(Field(request: "setTerminalProfile", label: L("terminal.profile"), options: profiles, selected: choice.profile))
        }
        return DeckTerminalSettings(title: L("terminal.title"), detail: L("terminal.detail"), fields: fields)
    }
}

extension DeckRuntime {
    var terminalForOpen: TerminalChoice? {
        let choice = preferences.terminalWindows
        if choice.application != nil { return choice }
        let applications = terminalApplications()
        guard !applications.isEmpty else { return choice == TerminalChoice() ? nil : choice }
        let application = applications.contains(where: { $0.id == "windowsTerminal" }) ? "windowsTerminal" : "commandPrompt"
        return TerminalChoice(application: application, profile: application == "windowsTerminal" ? choice.profile : nil)
    }

    public func terminalSettings() -> DeckTerminalSettings {
        DeckTerminalSettings.make(choice: preferences.terminalWindows, applications: terminalApplications())
    }

    func setTerminalApplication(_ value: String?) {
        guard value == nil || terminalApplications().contains(where: { $0.id == value }) else { return }
        preferences.terminalWindows = TerminalChoice(application: value)
    }

    func setTerminalProfile(_ value: String?) {
        var choice = preferences.terminalWindows
        guard (choice.application == nil || choice.application == "windowsTerminal"),
              value == nil || terminalApplications().first(where: { $0.id == "windowsTerminal" })?.profiles.contains(where: { $0.id == value }) == true
        else { return }
        choice.profile = value
        preferences.terminalWindows = choice
    }
}
