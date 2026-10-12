import DevDeckCore
import Foundation

/// The deck as an agent on this computer reaches it: the local endpoint, opened while agent
/// access is on, and the answers it gives.
///
/// Read and control are the same deck. The answers are the models and attention rows the cards
/// and the menu are drawn from, in the deck's words; a command is one the cards' own buttons
/// send, run through the same `perform`, so whatever a button may not do, an agent may not do
/// either. Which commands an agent may send at all, and whether it may send any, is decided
/// here and nowhere else. See docs/adr/0036-agent-access.md.
@MainActor
public final class DeckAgents {
    /// How long a command's answer waits for the work it started: a Fusion start takes minutes.
    public static let commandWait: TimeInterval = 180

    private unowned let runtime: DeckRuntime
    private let version: String
    private let address: String
    private var server: LocalEndpointServer?
    /// A sentence for the host's diagnostics when the endpoint could not open.
    public var onDiagnostic: ((String) -> Void)?

    init(runtime: DeckRuntime, version: String, address: String) {
        self.runtime = runtime
        self.version = version
        self.address = address
    }

    /// Whether an agent can reach the deck right now.
    public var isListening: Bool { server?.running ?? false }

    /// Opens or closes the endpoint to match the setting. Switching between read and control
    /// changes nothing here: every request reads the setting as it is.
    public func applyPreferences() {
        let wanted = runtime.preferences.agentAccess != .off
        if wanted, server == nil {
            let server = LocalEndpointServer(address: address) { [weak self] line in
                await self?.answer(line) ?? Self.encode(["error": L("agents.error.off")])
            }
            do {
                try server.start()
                self.server = server
            } catch {
                onDiagnostic?("The agent endpoint could not open: \(error)")
            }
        } else if !wanted, let server {
            server.stop()
            self.server = nil
        }
    }

    /// Closes the endpoint, when the deck quits.
    public func stop() {
        server?.stop()
        server = nil
    }

    // MARK: Answers

    private struct Request: Decodable {
        var id: String?
        var request: String
        var card: CardID?
        var command: DeckCommand?
    }

    /// One request, one answer, as the endpoint carries them. Public for the suite.
    public func answer(_ line: String) async -> String {
        guard let request = try? JSONDecoder().decode(Request.self, from: Data(line.utf8)) else {
            return Self.encode(["error": L("agents.error.badRequest")])
        }
        var reply = Reply(id: request.id)
        let access = runtime.preferences.agentAccess
        guard access != .off else {
            reply.error = L("agents.error.off")
            return Self.encode(reply)
        }
        switch request.request {
        case "hello":
            reply.access = access.rawValue
            reply.version = version
        case "attention":
            reply.attention = attention()
        case "cards":
            reply.cards = runtime.cards.visible.compactMap { card in
                runtime.model(for: card).map { AgentCard(card: card, model: $0) }
            }
        case "log":
            guard let card = request.card, runtime.hasLogSource(card) else {
                reply.error = L("agents.error.noLog", request.card?.rawValue ?? "")
                break
            }
            reply.log = await runtime.readLogs(for: card).map { AgentLog(card: card, lines: $0) }
        case "command":
            guard access == .control else {
                reply.error = L("agents.error.readOnly")
                break
            }
            guard let command = request.command, Self.isAllowed(command) else {
                reply.error = L("agents.error.notAllowed")
                break
            }
            if case .project(let card, _) = command, runtime.model(for: card) == nil {
                reply.error = L("agents.error.unknownCard", card.rawValue)
                break
            }
            runtime.perform(command)
            reply.done = await waitForWork()
            if case .project(let card, _) = command {
                reply.cards = runtime.model(for: card).map { [AgentCard(card: card, model: $0)] }
            } else {
                reply.attention = attention()
            }
        default:
            reply.error = L("agents.error.unknownRequest", request.request)
        }
        return Self.encode(reply)
    }

    /// What an agent may ask the deck to do: what a project card's buttons and the inbox's
    /// read buttons do. Opening things, settings, the deck's layout and quitting stay with the
    /// person in front of it.
    public static func isAllowed(_ command: DeckCommand) -> Bool {
        switch command {
        case .project, .markRead, .markRestRead: return true
        default: return false
        }
    }

    /// Waits for the work a command started, up to `commandWait`. False when it is still going.
    private func waitForWork() async -> Bool {
        let deadline = Date().addingTimeInterval(Self.commandWait)
        while runtime.hasPendingWork {
            guard Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return true
    }

    private func attention() -> [AgentAttention] {
        runtime.attention(update: runtime.updates?.offer()?.item).items.map(AgentAttention.init)
    }

    // MARK: Wire

    private struct Reply: Encodable {
        var id: String?
        var error: String?
        var access: String?
        var version: String?
        var attention: [AgentAttention]?
        var cards: [AgentCard]?
        var log: AgentLog?
        /// After a command: whether the work it started has finished.
        var done: Bool?
    }

    private struct AgentCard: Encodable {
        let card: CardID
        let model: DeckCardModel
    }

    private struct AgentLog: Encodable {
        let card: CardID
        let lines: [String]
        let source: String?
        let detail: String?

        init(card: CardID, lines: LogLines) {
            self.card = card
            self.lines = lines.lines
            source = lines.source
            detail = lines.detail
        }
    }

    /// One row of what needs the person, as the menu words it.
    private struct AgentAttention: Encodable {
        let id: String
        /// `waiting`, `needsFixing`, `stuck`, `goodToKnow`, most urgent first.
        let tier: String
        /// The menu's header for the tier, in the deck's language.
        let tierTitle: String
        let title: String
        let subtitle: String
        let since: Date?
        /// The card the row is about, when it is about one.
        let card: CardID?
        /// Where the row leads, when it leads to a page.
        let url: String?
        /// The inbox thread behind it, which `markRead` takes.
        let thread: String?

        init(_ item: AttentionItem) {
            id = item.id
            switch item.tier {
            case .waiting: tier = "waiting"
            case .needsFixing: tier = "needsFixing"
            case .stuck: tier = "stuck"
            case .goodToKnow: tier = "goodToKnow"
            }
            tierTitle = item.tier.title
            title = item.title
            subtitle = item.subtitle
            since = item.since
            switch item.action {
            case .showCard(let card): self.card = card
            default: card = nil
            }
            switch item.action {
            case .open(let url, _, _): self.url = url.absoluteString
            default: url = nil
            }
            thread = item.inboxThreadID
        }
    }

    private nonisolated static func encode<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return #"{"error":"encoding"}"# }
        return String(decoding: data, as: UTF8.self)
    }
}

extension DeckRuntime {
    /// Opens the deck to agents on this computer while the setting allows it. Call once; the
    /// endpoint follows the setting from then on through `agents?.applyPreferences()`.
    @discardableResult
    public func serveAgents(
        version: String, address: String = LocalEndpoint.address, onDiagnostic: ((String) -> Void)? = nil
    ) -> DeckAgents {
        let agents = DeckAgents(runtime: self, version: version, address: address)
        agents.onDiagnostic = onDiagnostic
        self.agents = agents
        agents.applyPreferences()
        return agents
    }
}
