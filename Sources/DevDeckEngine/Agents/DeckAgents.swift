import ArcKit
import DDEVKit
import DevDeckCore
import Foundation
import ProjectKit

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
    /// Keeps the agents' own server lists in step with the setting. Nil when the host did not
    /// say where the MCP server executable is, as the Mac's development host does not.
    private let registrar: AgentRegistrar?
    /// What the setting said the last time it was applied, so a change is told from a repeat.
    private var wasWanted: Bool?

    init(runtime: DeckRuntime, version: String, address: String, serverExecutable: String? = nil) {
        self.runtime = runtime
        self.version = version
        self.address = address
        self.registrar = serverExecutable.map { server in
            AgentRegistrar(server: server, runner: runtime.commandRunner) { [weak runtime] in
                runtime?.effect(.agentClientsChanged)
            }
        }
    }

    /// Where the deck's server stands with each agent on this computer, for the settings page.
    /// Empty when the host keeps no server to register.
    public var clients: [DeckAgentClient] { registrar?.current ?? [] }

    /// Waits for registration work under way, for the suite.
    public func settle() async { await registrar?.settle() }

    /// Whether an agent can reach the deck right now.
    public var isListening: Bool { server?.running ?? false }

    /// Opens or closes the endpoint to match the setting. Switching between read and control
    /// changes nothing here: every request reads the setting as it is.
    public func applyPreferences() {
        let wanted = runtime.preferences.agentAccess != .off
        // The agents' lists follow the setting: on puts the server on them, off takes it off,
        // and a launch with it already on only repairs what is missing.
        switch (wasWanted, wanted) {
        case (nil, true): registrar?.ensureRegistered()
        case (false, true): registrar?.register()
        case (true, false): registrar?.unregister()
        default: break
        }
        wasWanted = wanted
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
        /// `open`: a web address, in the browser of the account it belongs to.
        var url: String?
        /// `open` with a card: `card` (default), `folder`, `terminal` or `site`.
        var target: String?
        /// `detect` and `addProject`: the folder, in the platform's own spelling.
        var folder: String?
        /// `addProject`: `plain`, `arc` or `ddev`; absent, what the folder says it is.
        var kind: String?
        /// `addProject` and `updateProject`: what the agent knows that the folder does not say.
        /// Absent fields are taken from the folder the way the settings window takes them, or
        /// left as they are on an update.
        var title: String?
        var startCommand: String?
        var stopCommand: String?
        var holdsProcess: Bool?
        var requiresDocker: Bool?
        var healthURL: String?
        var localSiteURL: String?
        /// Arc: the organisation as the host names it, `sandbox.acme`, and the site.
        var organization: String?
        var site: String?
        /// Links on the card, by label: an existing label is filled in, a new one appended.
        var links: [LinkRequest]?
    }

    private struct LinkRequest: Decodable {
        var label: String
        var url: String
        /// `site` for an environment, `tool` for something you work in. Default `site`.
        var kind: String?
        var isTool: Bool { kind?.lowercased() == "tool" }
    }

    /// What a folder is to the deck.
    enum ProjectKind: String {
        case plain, arc, ddev

        static func detect(_ folder: URL) -> ProjectKind {
            if ArcCheckout.isFusionCheckout(folder) { return .arc }
            if DDEVConfig.isProject(folder) { return .ddev }
            return .plain
        }
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
        case "detect":
            guard let folder = request.folder.flatMap(Self.folderURL) else {
                reply.error = L("agents.error.noFolder", request.folder ?? "")
                break
            }
            let kind = ProjectKind.detect(folder)
            reply.kind = kind.rawValue
            if kind == .plain { reply.detection = runtime.detect(folder: folder) }
            if let existing = runtime.cardInFolder(folder) { reply.card = existing.card }
        case "addProject":
            guard access == .control else {
                reply.error = L("agents.error.readOnly")
                break
            }
            guard let folder = request.folder.flatMap(Self.folderURL) else {
                reply.error = L("agents.error.noFolder", request.folder ?? "")
                break
            }
            if let existing = runtime.cardInFolder(folder) {
                reply.error = L("agents.error.alreadyOnDeck", existing.title)
                reply.card = existing.card
                break
            }
            let kind = request.kind.flatMap(ProjectKind.init(rawValue:)) ?? ProjectKind.detect(folder)
            reply.kind = kind.rawValue
            switch kind {
            case .plain:
                // The folder is read first, the way the settings window reads it, and what
                // the agent said on top: it knows the command it has been running all afternoon.
                let id = runtime.addLocalProject(folder: folder)
                guard var project = runtime.localProject(forCard: CardID(rawValue: "project.\(id)")) else {
                    reply.error = L("agents.error.badRequest")
                    break
                }
                apply(request, to: &project)
                runtime.saveLocalProject(project)
                reply.project = project
                await added(project.cardID, into: &reply)
            case .arc:
                // Nothing in a checkout names the organisation; the agent has to say it, and
                // without it no link on the card would resolve.
                guard let organization = request.organization?.trimmingCharacters(in: .whitespaces), !organization.isEmpty else {
                    reply.error = L("agents.error.needsOrganization")
                    break
                }
                let title = request.title?.trimmingCharacters(in: .whitespaces).nonEmpty ?? folder.lastPathComponent
                let existing = runtime.arcProjects().map(\.id)
                var project = ArcProject(id: ArcProject.makeID(from: title, existing: existing), title: title, organization: organization, site: request.site?.nonEmpty, folder: folder.path)
                apply(request, to: &project)
                runtime.saveArcProject(project)
                runtime.cards.setEnabled(true, for: project.cardID)
                reply.arcProject = project
                await added(project.cardID, into: &reply)
            case .ddev:
                // DDEV names the project; the deck adds what `ddev list` knows, as Settings does.
                let wanted = folder.standardizedFileURL.path
                guard let entry = await runtime.ddevList()?.first(where: { URL(fileURLWithPath: $0.approot).standardizedFileURL.path == wanted }) else {
                    reply.error = L("agents.error.ddevNotListed", folder.path)
                    break
                }
                let id = runtime.addDDEVProject(entry)
                guard var project = runtime.ddevProject(forCard: CardID(rawValue: "ddev.project.\(id)")) else {
                    reply.error = L("agents.error.badRequest")
                    break
                }
                apply(request, to: &project)
                runtime.saveDDEVProject(project)
                reply.ddevProject = project
                await added(project.cardID, into: &reply)
            }
        case "updateProject":
            guard access == .control else {
                reply.error = L("agents.error.readOnly")
                break
            }
            guard let card = request.card else {
                reply.error = L("agents.error.unknownCard", "")
                break
            }
            if var project = runtime.localProject(forCard: card) {
                apply(request, to: &project)
                runtime.saveLocalProject(project)
                reply.kind = ProjectKind.plain.rawValue
                reply.project = project
            } else if var project = runtime.project(forCard: card) {
                apply(request, to: &project)
                runtime.saveArcProject(project)
                reply.kind = ProjectKind.arc.rawValue
                reply.arcProject = project
            } else if var project = runtime.ddevProject(forCard: card) {
                apply(request, to: &project)
                runtime.saveDDEVProject(project)
                reply.kind = ProjectKind.ddev.rawValue
                reply.ddevProject = project
            } else {
                reply.error = L("agents.error.notEditable", card.rawValue)
                break
            }
            await added(card, into: &reply)
        case "log":
            guard let card = request.card, runtime.hasLogSource(card) else {
                reply.error = L("agents.error.noLog", request.card?.rawValue ?? "")
                break
            }
            reply.log = await runtime.readLogs(for: card).map { AgentLog(card: card, lines: $0) }
        case "open":
            // Opening things is the person's screen, so it takes control, like a button.
            guard access == .control else {
                reply.error = L("agents.error.readOnly")
                break
            }
            open(request, into: &reply)
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

    /// What "open" opens: a page in the right browser, or one of a card's own places. The
    /// address decides the browser the way a row would: the account whose host it is.
    private func open(_ request: Request, into reply: inout Reply) {
        if let text = request.url?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
                reply.error = L("agents.error.badURL", text)
                return
            }
            runtime.effect(.openURL(url, runtime.browser(forLink: url)))
            reply.opened = url.absoluteString
            return
        }
        guard let card = request.card, let model = runtime.model(for: card) else {
            reply.error = L("agents.error.unknownCard", request.card?.rawValue ?? "")
            return
        }
        switch request.target?.lowercased() ?? "card" {
        case "folder":
            runtime.perform(.revealFolder(card))
        case "terminal":
            runtime.perform(.openTerminal(card))
        case "site":
            // The first environment the card offers that is not greyed out: the local site when
            // the project is up, otherwise the first published one.
            guard case .project(let project) = model, let chip = project.environments.first(where: { $0.command != nil }), let command = chip.command else {
                reply.error = L("agents.error.nothingToOpen", card.rawValue)
                return
            }
            runtime.perform(command)
        default:
            runtime.perform(.showCard(card))
        }
        reply.opened = card.rawValue
    }

    /// The deck learns a card came or changed, its data is fetched, and the answer is the card.
    private func added(_ card: CardID, into reply: inout Reply) async {
        runtime.effect(.cardsChanged)
        await runtime.refreshLocalOnce()
        reply.card = card
        reply.cards = runtime.model(for: card).map { [AgentCard(card: card, model: $0)] }
    }

    private func apply(_ request: Request, to project: inout LocalProject) {
        if let title = request.title?.trimmingCharacters(in: .whitespaces).nonEmpty { project.title = title }
        if let command = request.startCommand { project.startCommand = command }
        if let command = request.stopCommand { project.stopCommand = command }
        if let holds = request.holdsProcess { project.holdsProcess = holds }
        if let docker = request.requiresDocker { project.requiresDocker = docker }
        if let health = request.healthURL { project.healthURL = health }
        if let site = request.localSiteURL { project.localSiteURL = site }
        for link in request.links ?? [] {
            if let index = project.links.firstIndex(where: { $0.label.caseInsensitiveCompare(link.label) == .orderedSame }) {
                project.links[index].urlTemplate = link.url
                project.links[index].isEnabled = !link.url.isEmpty
                if link.kind != nil { project.links[index].kind = link.isTool ? .tool : .site }
            } else {
                project.links.append(LocalProjectLink(label: link.label, urlTemplate: link.url, isEnabled: !link.url.isEmpty, kind: link.isTool ? .tool : .site))
            }
        }
    }

    private func apply(_ request: Request, to project: inout ArcProject) {
        if let title = request.title?.trimmingCharacters(in: .whitespaces).nonEmpty { project.title = title }
        if let organization = request.organization?.trimmingCharacters(in: .whitespaces).nonEmpty { project.organization = organization }
        if let site = request.site { project.site = site.nonEmpty }
        if let command = request.startCommand { project.startCommand = command }
        if let command = request.stopCommand { project.stopCommand = command }
        // The local address is read from the checkout's .env unless the agent names one.
        if let site = request.localSiteURL { project.localURL = site }
        for link in request.links ?? [] {
            if let index = project.links.firstIndex(where: { $0.label.caseInsensitiveCompare(link.label) == .orderedSame }) {
                project.links[index].urlTemplate = link.url
                project.links[index].isEnabled = !link.url.isEmpty
                if link.kind != nil { project.links[index].kind = link.isTool ? .admin : .site }
            } else {
                project.links.append(ArcLink(label: link.label, urlTemplate: link.url, isEnabled: !link.url.isEmpty, kind: link.isTool ? .admin : .site))
            }
        }
    }

    private func apply(_ request: Request, to project: inout DDEVProject) {
        if let title = request.title?.trimmingCharacters(in: .whitespaces).nonEmpty { project.title = title }
        for link in request.links ?? [] {
            if let index = project.customLinks.firstIndex(where: { $0.label.caseInsensitiveCompare(link.label) == .orderedSame }) {
                project.customLinks[index].urlTemplate = link.url
                project.customLinks[index].isEnabled = !link.url.isEmpty
                if link.kind != nil { project.customLinks[index].kind = link.isTool ? .tool : .site }
            } else {
                project.customLinks.append(DDEVCustomLink(label: link.label, urlTemplate: link.url, isEnabled: !link.url.isEmpty, kind: link.isTool ? .tool : .site))
            }
        }
    }

    /// A folder that is there. Nil for a path that is not one, so a typo does not become a card.
    private static func folderURL(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: trimmed, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return url
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
        /// `open`: what was opened, the address or the card.
        var opened: String?
        /// `detect`: what kind of project the folder holds, and for a plain one what its files say.
        var kind: String?
        var detection: DeckDetection?
        /// `addProject` and `updateProject`: the card, and the project as it was written down.
        var card: CardID?
        var project: LocalProject?
        var arcProject: ArcProject?
        var ddevProject: DDEVProject?
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
        version: String, address: String = LocalEndpoint.address, serverExecutable: String? = nil,
        onDiagnostic: ((String) -> Void)? = nil
    ) -> DeckAgents {
        let agents = DeckAgents(runtime: self, version: version, address: address, serverExecutable: serverExecutable)
        agents.onDiagnostic = onDiagnostic
        self.agents = agents
        agents.applyPreferences()
        return agents
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
