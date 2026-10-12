import DevDeckCore
import Foundation

/// A coding agent on this computer that keeps its own list of MCP servers, and how the deck's
/// server is put on that list and taken off it.
///
/// The shell used to show a command line for the person to paste. Nobody should have to: the
/// setting is the decision, and the engine carries it out with the agents' own command-line
/// tools, which is also the only supported way to edit their configuration. Which agents are
/// known is decided here; the shell shows the outcome in words. See docs/adr/0036-agent-access.md.
public struct AgentClient: Sendable, Equatable {
    public let id: String
    public let name: String
    /// Where the agent's tool may be, in the order to try: its name on the path first, then
    /// where an application that bundles it keeps it. The first that answers is the one used.
    public let executables: [String]
    /// Asks whether the deck's server is on the list. Exit 0 means it is.
    let check: @Sendable (String) -> String
    /// Takes the deck's server off the list. Fails harmlessly when it was not there.
    let remove: @Sendable (String) -> String
    /// Puts the deck's server on the list, given the tool and the server's executable path.
    let add: @Sendable (String, String) -> String

    /// Claude Code keeps servers per project unless told `--scope user`; the deck is about a
    /// person rather than a repository, so user scope is the one that makes sense.
    public static let claude = AgentClient(
        id: "claude",
        name: "Claude Code",
        executables: ["claude"],
        check: { "\(quoted($0)) mcp get devdeck" },
        remove: { "\(quoted($0)) mcp remove --scope user devdeck" },
        add: { "\(quoted($0)) mcp add --scope user devdeck -- \"\($1)\"" }
    )

    /// Codex keeps one global list in `~/.codex/config.toml`, so there is no scope to choose.
    /// The ChatGPT application for the Mac carries the same tool inside it and reads the same
    /// file, so a person with Codex in ChatGPT and no `codex` on the path still gets the row.
    public static let codex = AgentClient(
        id: "codex",
        name: "Codex",
        executables: ["codex", "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"],
        check: { "\(quoted($0)) mcp get devdeck" },
        remove: { "\(quoted($0)) mcp remove devdeck" },
        add: { "\(quoted($0)) mcp add devdeck -- \"\($1)\"" }
    )

    /// A path with a space in it, as the shell needs it; a bare name as it is.
    static func quoted(_ executable: String) -> String {
        executable.contains(" ") ? "\"\(executable)\"" : executable
    }

    public static let all: [AgentClient] = [.claude, .codex]

    public static func == (left: AgentClient, right: AgentClient) -> Bool { left.id == right.id }

    /// How long one of the tools is given. They read and write a file; a minute is already
    /// something wrong.
    static let timeout: TimeInterval = 60

    /// What a tool's answer means for the list.
    public enum Outcome: Equatable {
        case yes
        case no
        /// The tool itself is not on this computer.
        case notInstalled
        case failed(String)

        public init(_ result: CommandResult) {
            let text = (result.standardError + "\n" + result.standardOutput).lowercased()
            // 127 is the shell on the Mac; cmd.exe says it in words and exits with 1.
            let missing = text.contains("not found") || text.contains("no mcp server") || text.contains("no server") || text.contains("does not exist")
            if result.exitCode == 127 || text.contains("command not found") || text.contains("not recognized as an internal")
                || text.contains("no such file or directory") {
                self = .notInstalled
            } else if missing, result.exitCode != 0 || text.contains("error") {
                // Codex says "Error: No MCP server named 'x' found." and exits 0 all the same.
                self = .no
            } else if result.exitCode == 0 {
                self = .yes
            } else {
                let line = result.standardError.split(separator: "\n").first.map(String.init)
                    ?? result.standardOutput.split(separator: "\n").first.map(String.init) ?? ""
                self = .failed(line.trimmingCharacters(in: .whitespaces))
            }
        }
    }
}

/// Where the deck's server stands with one agent, in the words the settings page shows.
public struct DeckAgentClient: Sendable, Equatable, Codable {
    public enum State: String, Sendable, Equatable, Codable {
        case checking
        case registered
        case notRegistered
        case notInstalled
        case failed
    }

    public let id: String
    public let name: String
    public let state: State
    /// The sentence under the name.
    public let detail: String

    /// Said again in the current language: the state is kept, the words are asked for when the
    /// page is drawn.
    static func describe(_ client: AgentClient, executable: String, state: State, server: String, failure: String) -> DeckAgentClient {
        let detail: String
        switch state {
        case .checking: detail = L("settings.agents.client.checking")
        case .registered: detail = L("settings.agents.client.registered")
        case .notRegistered: detail = L("settings.agents.client.notRegistered")
        case .notInstalled: detail = L("settings.agents.client.notInstalled", client.add(executable, server))
        case .failed: detail = L("settings.agents.client.failed", failure.isEmpty ? client.add(executable, server) : failure)
        }
        return DeckAgentClient(id: client.id, name: client.name, state: state, detail: detail)
    }
}

/// Keeps the agents' lists in step with the setting, through their own tools.
@MainActor
final class AgentRegistrar {
    private let clients: [AgentClient]
    private let server: String
    private let runner: any CommandRunning
    private let onChange: () -> Void
    /// The last outcome per client, with the message a failure carried.
    private var states: [String: (state: DeckAgentClient.State, failure: String)] = [:]
    /// Which of a client's executables answered, once one has.
    private var executables: [String: String] = [:]
    /// Serialises the work: a setting flipped twice is two jobs in order, not two at once.
    private var queue: Task<Void, Never>?

    init(clients: [AgentClient] = AgentClient.all, server: String, runner: any CommandRunning, onChange: @escaping () -> Void) {
        self.clients = clients
        self.server = server
        self.runner = runner
        self.onChange = onChange
    }

    var current: [DeckAgentClient] {
        clients.map { client in
            let entry = states[client.id] ?? (state: .checking, failure: "")
            return DeckAgentClient.describe(client, executable: executable(of: client), state: entry.state, server: server, failure: entry.failure)
        }
    }

    private func executable(of client: AgentClient) -> String {
        executables[client.id] ?? client.executables.first ?? client.id
    }

    /// Puts the server on every list that is missing it, without touching one that has it.
    /// For a launch with the setting already on, and the repair after an upgrade.
    func ensureRegistered() {
        enqueue { [self] in
            for client in clients {
                switch await check(client) {
                case .yes: set(client, .registered)
                case .no: await register(client)
                case .notInstalled: set(client, .notInstalled)
                case .failed(let message): set(client, .failed, message)
                }
            }
        }
    }

    /// Asks each of the client's executables in turn until one is there, and remembers it.
    private func check(_ client: AgentClient) async -> AgentClient.Outcome {
        if let known = executables[client.id] {
            return await run(client.check(known))
        }
        var outcome = AgentClient.Outcome.notInstalled
        for executable in client.executables {
            outcome = await run(client.check(executable))
            if outcome != .notInstalled {
                executables[client.id] = executable
                break
            }
        }
        return outcome
    }

    /// Puts the server on every list, replacing an entry that is there so the path is current.
    func register() {
        enqueue { [self] in
            for client in clients {
                set(client, .checking)
                await register(client)
            }
        }
    }

    /// Takes the server off every list.
    func unregister() {
        enqueue { [self] in
            for client in clients {
                set(client, .checking)
                if executables[client.id] == nil, await check(client) == .notInstalled {
                    set(client, .notInstalled)
                    continue
                }
                switch await run(client.remove(executable(of: client))) {
                case .yes, .no: set(client, .notRegistered)
                case .notInstalled: set(client, .notInstalled)
                case .failed(let message): set(client, .failed, message)
                }
            }
        }
    }

    /// Waits for whatever is under way, for the suite.
    func settle() async {
        await queue?.value
    }

    private func register(_ client: AgentClient) async {
        if executables[client.id] == nil, await check(client) == .notInstalled {
            set(client, .notInstalled)
            return
        }
        let executable = executable(of: client)
        // The tools refuse to add a name that exists, and the path may have moved with an
        // upgrade: off first, then on. A remove that found nothing is nothing.
        let removed = await run(client.remove(executable))
        if removed == .notInstalled {
            set(client, .notInstalled)
            return
        }
        switch await run(client.add(executable, server)) {
        case .yes: set(client, .registered)
        case .no, .failed(""): set(client, .failed, "")
        case .notInstalled: set(client, .notInstalled)
        case .failed(let message): set(client, .failed, message)
        }
    }

    private func run(_ command: String) async -> AgentClient.Outcome {
        do {
            let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["USERPROFILE"] ?? NSHomeDirectory())
            return AgentClient.Outcome(try await runner.run(command, in: home, timeout: AgentClient.timeout))
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func set(_ client: AgentClient, _ state: DeckAgentClient.State, _ failure: String = "") {
        states[client.id] = (state, failure)
        onChange()
    }

    private func enqueue(_ job: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await job()
        }
    }
}
