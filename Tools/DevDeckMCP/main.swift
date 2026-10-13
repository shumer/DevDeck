import DevDeckCore
import Foundation

// The deck as a Model Context Protocol server, for a coding agent on this computer.
//
// It holds nothing of its own: every tool is one question to the running deck over its local
// endpoint, and the answer is the deck's, in the deck's words. Which tools there are follows the
// setting in DevDeck, Settings, General, Agents (MCP): reading tools while it allows reading, and the
// project and inbox commands as well while it allows control. The agent's client asks the person
// before a tool runs; the deck decides whether the command may run at all.
//
//   claude mcp add --scope user devdeck -- /Applications/DevDeck.app/Contents/Helpers/DevDeckMCP
//   codex mcp add devdeck -- /Applications/DevDeck.app/Contents/Helpers/DevDeckMCP
//
// See docs/mcp.md and docs/adr/0036-agent-access.md.

let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

/// A tool as `tools/list` describes it.
struct Tool {
    let name: String
    let description: String
    let properties: [String: Any]
    let required: [String]
    let controls: Bool

    var listing: [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required,
            ] as [String: Any],
        ]
    }
}

let cardProperty = ["type": "string", "description": "The card's id, as the cards tool lists it: project.<id>, arc.project.<id>, ddev.project.<id>."]
let folderProperty = ["type": "string", "description": "An absolute path to the project's folder on this computer, spelled the platform's way."]
let linksProperty: [String: Any] = [
    "type": "array",
    "description": "Links on the card. label matches an existing slot (Test, UAT, Prod; Sandbox, Prod on Arc) or names a new one; url is the address, empty to clear; kind is site for an environment (default) or tool for something you work in, such as an admin page.",
    "items": ["type": "object", "properties": ["label": ["type": "string"], "url": ["type": "string"], "kind": ["type": "string"]], "required": ["label", "url"]],
]

let tools = [
    Tool(
        name: "what_needs_me",
        description: "What the deck wants the person's attention for, most urgent first: reviews and mentions waiting on them, things to fix on this computer, their own stuck work, and what is good to know. The same rows as DevDeck's menu.",
        properties: [:], required: [], controls: false
    ),
    Tool(
        name: "what_changed",
        description: "What is new since you last asked what_needs_me or what_changed in this session: rows that appeared, rows that went away because they were dealt with, and projects whose state changed (started, stopped, failed). The first call in a session reports everything as new. Cheap to call often.",
        properties: [:], required: [], controls: false
    ),
    Tool(
        name: "open",
        description: "Opens something on the person's screen. Give url to open a page in the browser of the account it belongs to (a GitHub, GitLab or Azure DevOps address opens signed in as the right person). Or give card and target: card brings the deck up on that card with its log, folder shows the project's folder, terminal opens a terminal in it, site opens the project's local site when it is up or its first published site.",
        properties: [
            "url": ["type": "string", "description": "A web address, http or https."],
            "card": cardProperty,
            "target": ["type": "string", "description": "With card: card (default), folder, terminal or site."],
        ],
        required: [], controls: true
    ),
    Tool(
        name: "wait_for",
        description: "Waits until something settles, then returns it: a project card until it is running, stopped or healthy (until: running, stopped, healthy, or changed for any change of state), or a pull request by url until its checks are no longer running (until: checks). Polls the deck every few seconds up to timeout seconds (default 180, at most 600). satisfied says whether the condition was met before the timeout.",
        properties: [
            "card": cardProperty,
            "url": ["type": "string", "description": "A pull request's web address, as what_needs_me or cards give it."],
            "until": ["type": "string", "description": "running, stopped, healthy or changed for a card; checks for a pull request."],
            "timeout": ["type": "number", "description": "Seconds to wait, at most 600. Default 180."],
        ],
        required: ["until"], controls: false
    ),
    Tool(
        name: "project_time",
        description: "How long each project on the deck has been running today and over the last seven days, as DevDeck observed it, for keeping track of time per client.",
        properties: [:], required: [], controls: false
    ),
    Tool(
        name: "cards",
        description: "Every card on the deck as DevDeck draws it: pull requests, merge requests, the inbox, Actions, and each project's state, branch, links and buttons. Give a card id for one card.",
        properties: ["card": cardProperty], required: [], controls: false
    ),
    Tool(
        name: "project_log",
        description: "The last lines of a project's log, as its log window shows them: the dev server, docker compose, ddev or the Arc engine.",
        properties: ["card": cardProperty], required: ["card"], controls: false
    ),
    Tool(
        name: "start_project",
        description: "Starts a project the way its Start button does, waits for it to answer or fail, and returns its card. Arc XP: Fusion runs one local stack at a time, so starting an Arc project while another is running is refused with the other's name; pass replace true to stop that one first and start this one.",
        properties: ["card": cardProperty, "replace": ["type": "boolean", "description": "Arc only: stop the other running Arc stack first. Default false, which refuses rather than stops."]],
        required: ["card"], controls: true
    ),
    Tool(
        name: "stop_project",
        description: "Stops a project the way its Stop button does and returns its card. A project started outside DevDeck is not stopped; the card says why.",
        properties: ["card": cardProperty], required: ["card"], controls: true
    ),
    Tool(
        name: "restart_project",
        description: "Restarts a project the way its Restart button does, waits for it, and returns its card. Arc XP: as with start_project, another running Arc stack is refused unless replace is true.",
        properties: ["card": cardProperty, "replace": ["type": "boolean", "description": "Arc only: stop the other running Arc stack first."]],
        required: ["card"], controls: true
    ),
    Tool(
        name: "detect_project",
        description: "What DevDeck would make of a folder before adding it. kind is arc for an Arc XP Fusion checkout (package.json lists @arc-fusion/cli), ddev for a DDEV project (.ddev/config.yaml), plain otherwise; for a plain one, the start command, whether it holds its process, whether it needs Docker and the health URL, read from the folder's files. Says if the folder is already on the deck, as which card.",
        properties: ["folder": folderProperty], required: ["folder"], controls: false
    ),
    Tool(
        name: "add_project",
        description: "Adds a project card for a folder, usually the one you are working in. Call detect_project first. An Arc XP checkout becomes an Arc card: pass organization (the host label, sandbox.acme for the sandbox, acme for production); Start, Stop and the health check are the Fusion CLI's, and the Sandbox and Prod links take the published sites. A DDEV project becomes a DDEV card from what ddev list knows. Anything else is a plain card: DevDeck reads the folder and fills in what it can, and what you pass wins: start_command, health_url for the address that answers once it is up, local_site_url when the page to open differs, holds_process false and stop_command for a command that returns on its own such as docker compose up -d. links fills the card's link slots by label (Test, UAT, Prod on a plain card; Sandbox, Prod on an Arc card) or adds new ones. Returns the new card.",
        properties: [
            "folder": folderProperty,
            "kind": ["type": "string", "description": "plain, arc or ddev. Default: what detect_project says."],
            "title": ["type": "string", "description": "The card's name. Default: the folder's name."],
            "organization": ["type": "string", "description": "Arc only, required: the organisation as the host names it, sandbox.acme or acme."],
            "site": ["type": "string", "description": "Arc only: the site id inside the organisation, for a multisite."],
            "start_command": ["type": "string", "description": "Plain: run in the folder to start the project, for example npm run dev or docker compose up -d. Arc: leave to the default npx fusion daemon."],
            "stop_command": ["type": "string", "description": "Plain: run to stop it; leave empty for a command that holds its process, DevDeck stops what it started. Arc: leave to the default npx fusion stop."],
            "holds_process": ["type": "boolean", "description": "Plain: whether the start command keeps running (npm run dev) rather than returning (docker compose up -d)."],
            "requires_docker": ["type": "boolean", "description": "Plain: whether the project cannot start without Docker."],
            "health_url": ["type": "string", "description": "Plain: the URL that answers when the project is up, for example http://localhost:3000. Empty: the started process being alive counts."],
            "local_site_url": ["type": "string", "description": "What the Local site link opens when it is not the health URL; for Arc, the local address when the checkout's .env PORT is not it."],
            "links": linksProperty,
        ],
        required: ["folder"], controls: true
    ),
    Tool(
        name: "update_project",
        description: "Changes a project card that is on the deck: its title, commands, addresses, organisation and links, the same fields as add_project. Fields you leave out stay as they are; links are matched by label, so passing Prod fills the Prod slot. Removing a card stays in DevDeck's settings.",
        properties: [
            "card": cardProperty,
            "title": ["type": "string", "description": "The card's name."],
            "organization": ["type": "string", "description": "Arc: the organisation as the host names it."],
            "site": ["type": "string", "description": "Arc: the site id."],
            "start_command": ["type": "string", "description": "Plain and Arc: the start command."],
            "stop_command": ["type": "string", "description": "Plain and Arc: the stop command."],
            "holds_process": ["type": "boolean", "description": "Plain: whether the start command keeps running."],
            "requires_docker": ["type": "boolean", "description": "Plain: whether the project needs Docker."],
            "health_url": ["type": "string", "description": "Plain: the URL that answers when the project is up."],
            "local_site_url": ["type": "string", "description": "Plain and Arc: what the Local site link opens."],
            "links": linksProperty,
        ],
        required: ["card"], controls: true
    ),
    Tool(
        name: "mark_inbox_read",
        description: "Marks one inbox notification read, by the thread id what_needs_me gives; without one, marks read everything in the inbox that is not addressed to the person, like the inbox card's button.",
        properties: ["thread": ["type": "string", "description": "The inbox thread id."]], required: [], controls: true
    ),
]

/// Who this server speaks for, as the client named itself at `initialize`. Every command the
/// deck runs for it is written down as this.
var agentName = "an agent"

/// `claude-code` to `Claude Code`: the few clients that matter, by name; anyone else as given.
func humanized(_ client: String) -> String {
    let lower = client.lowercased()
    if lower.contains("claude") { return "Claude Code" }
    if lower.contains("codex") { return "Codex" }
    if lower.contains("cursor") { return "Cursor" }
    if lower.contains("windsurf") { return "Windsurf" }
    return client.isEmpty ? "an agent" : client
}

// MARK: Talking to the deck

enum DeckAnswer {
    case answer([String: Any])
    case unreachable(String)
}

@MainActor func ask(_ request: [String: Any]) -> DeckAnswer {
    var request = request
    request["agent"] = agentName
    guard let data = try? JSONSerialization.data(withJSONObject: request, options: [.sortedKeys]) else {
        return .unreachable("The request could not be written.")
    }
    do {
        let line = try LocalEndpointClient.request(String(decoding: data, as: UTF8.self))
        guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return .unreachable("DevDeck answered something that is not JSON.")
        }
        return .answer(object)
    } catch LocalEndpointError.notListening {
        return .unreachable("DevDeck is not running, or its MCP server is off. Turn it on in DevDeck: Settings, General, Agents (MCP).")
    } catch {
        return .unreachable("DevDeck could not be reached: \(error)")
    }
}

/// Whether the deck allows control right now. Unreachable reads as no.
@MainActor func allowsControl() -> Bool {
    if case .answer(let hello) = ask(["request": "hello"]), hello["access"] as? String == "control" { return true }
    return false
}

func toolResult(_ answer: DeckAnswer, filterCard: String? = nil) -> [String: Any] {
    switch answer {
    case .unreachable(let reason):
        return ["content": [["type": "text", "text": reason]], "isError": true]
    case .answer(var object):
        if let error = object["error"] as? String {
            return ["content": [["type": "text", "text": error]], "isError": true]
        }
        object["id"] = nil
        if let card = filterCard, let cards = object["cards"] as? [[String: Any]] {
            object["cards"] = cards.filter { $0["card"] as? String == card }
        }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return ["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]]]
    }
}

// MARK: Waiting

/// A project card's state, in the three words the condition names, from its hero's tone.
func projectState(_ entry: [String: Any]) -> (state: String, text: String)? {
    guard let project = (entry["model"] as? [String: Any])?["project"] as? [String: Any],
          let hero = project["hero"] as? [String: Any] else { return nil }
    let tone = hero["tone"] as? String ?? ""
    let text = [hero["text"] as? String, hero["note"] as? String].compactMap { $0 }.joined(separator: " · ")
    switch tone {
    case "good": return ("running", text)
    case "neutral": return ("stopped", text)
    default: return ("busy", text)
    }
}

/// The row for a pull request, by its address, across the review cards.
func reviewRow(_ cards: [[String: Any]], url: String) -> [String: Any]? {
    for entry in cards {
        guard let model = (entry["model"] as? [String: Any])?["reviewList"] as? [String: Any],
              let content = model["content"] as? [String: Any],
              let rows = content["rows"] as? [[String: Any]] else { continue }
        if let row = rows.first(where: { ($0["url"] as? String) == url }) { return row }
    }
    return nil
}

@MainActor func waitFor(_ arguments: [String: Any]) -> [String: Any] {
    guard let until = (arguments["until"] as? String)?.lowercased() else { return toolResult(.unreachable("until is needed.")) }
    let timeout = min(max(arguments["timeout"] as? Double ?? 180, 1), 600)
    let card = arguments["card"] as? String
    let url = arguments["url"] as? String
    guard card != nil || url != nil else { return toolResult(.unreachable("A card id or a url is needed.")) }
    let deadline = Date().addingTimeInterval(timeout)
    var initialState: String?
    var last: [String: Any] = [:]
    while true {
        guard case .answer(let answer) = ask(["request": "cards"]) else { return toolResult(ask(["request": "cards"])) }
        if let error = answer["error"] as? String { return ["content": [["type": "text", "text": error]], "isError": true] }
        let cards = (answer["cards"] as? [[String: Any]]) ?? []
        var satisfied = false
        if let card {
            guard let entry = cards.first(where: { $0["card"] as? String == card }), let state = projectState(entry) else {
                return toolResult(.unreachable("There is no project card \(card) on the deck."))
            }
            if initialState == nil { initialState = state.text }
            last = ["card": card, "state": state.state, "text": state.text]
            switch until {
            case "running", "healthy": satisfied = state.state == "running"
            case "stopped": satisfied = state.state == "stopped"
            case "changed": satisfied = state.text != initialState
            default: return toolResult(.unreachable("until must be running, stopped, healthy or changed for a card."))
            }
        } else if let url {
            guard let row = reviewRow(cards, url: url) else {
                // Gone from every card: merged, closed, or reviewed. That is settled too.
                last = ["url": url, "gone": true]
                satisfied = true
                break
            }
            let code = row["trailing"] as? String ?? ""
            last = ["url": url, "code": code, "help": row["help"] as? String ?? "", "tone": row["tone"] as? String ?? ""]
            switch until {
            case "checks", "changed": satisfied = code != "CP"
            default: return toolResult(.unreachable("until must be checks for a pull request."))
            }
        }
        if satisfied || Date() >= deadline { break }
        Thread.sleep(forTimeInterval: 5)
    }
    last["satisfied"] = (last["gone"] as? Bool == true) || Date() < deadline
    let data = (try? JSONSerialization.data(withJSONObject: last, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    return ["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]]]
}

// MARK: What changed

/// What the agent saw last: the rows by id, and each project's state. Kept here because this
/// process is one agent's session; the deck itself remembers nothing about who asked what.
var seenRows: [String: [String: Any]]?
var seenProjects: [String: (title: String, state: String)] = [:]
var seenAt: Date?

/// The project cards' titles and states, from the cards answer.
func projectStates(_ cards: [[String: Any]]) -> [String: (title: String, state: String)] {
    var states: [String: (title: String, state: String)] = [:]
    for entry in cards {
        // The model is written as `{"project": {...}}`, the fields straight under the kind.
        guard let card = entry["card"] as? String,
              let project = (entry["model"] as? [String: Any])?["project"] as? [String: Any],
              let hero = project["hero"] as? [String: Any]
        else { continue }
        let state = [hero["text"] as? String, hero["note"] as? String].compactMap { $0 }.joined(separator: " · ")
        states[card] = (project["title"] as? String ?? card, state)
    }
    return states
}

/// Reads the rows and the projects now, says what differs from last time, and remembers now.
@MainActor func whatChanged() -> [String: Any] {
    guard case .answer(let attention) = ask(["request": "attention"]) else { return toolResult(ask(["request": "attention"])) }
    if let error = attention["error"] as? String { return ["content": [["type": "text", "text": error]], "isError": true] }
    let rows = (attention["attention"] as? [[String: Any]]) ?? []
    var current: [String: [String: Any]] = [:]
    for row in rows { if let id = row["id"] as? String { current[id] = row } }
    var projects: [String: (title: String, state: String)] = [:]
    if case .answer(let cards) = ask(["request": "cards"]) {
        projects = projectStates((cards["cards"] as? [[String: Any]]) ?? [])
    }

    var result: [String: Any] = [:]
    let formatter = ISO8601DateFormatter()
    if let seenRows {
        result["since"] = seenAt.map(formatter.string(from:)) ?? NSNull()
        result["added"] = rows.filter { seenRows[($0["id"] as? String) ?? ""] == nil }
        result["gone"] = seenRows.filter { current[$0.key] == nil }.map(\.value).sorted { ($0["title"] as? String ?? "") < ($1["title"] as? String ?? "") }
        result["projects"] = projects.compactMap { card, now -> [String: Any]? in
            guard let was = seenProjects[card], was.state != now.state else { return nil }
            return ["card": card, "title": now.title, "was": was.state, "now": now.state]
        }.sorted { ($0["card"] as? String ?? "") < ($1["card"] as? String ?? "") }
        if (result["added"] as? [Any])?.isEmpty == true, (result["gone"] as? [Any])?.isEmpty == true, (result["projects"] as? [Any])?.isEmpty == true {
            result["summary"] = "Nothing changed."
        }
    } else {
        result["firstCall"] = true
        result["added"] = rows
        result["gone"] = [Any]()
        result["projects"] = projects.sorted { $0.key < $1.key }
            .map { card, state -> [String: Any] in ["card": card, "title": state.title, "now": state.state] }
    }
    seenRows = current
    seenProjects = projects
    seenAt = Date()
    let data = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    return ["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]]]
}

/// `what_needs_me` is also a look: what it showed is not news on the next `what_changed`.
@MainActor func remember(_ answer: DeckAnswer) {
    guard case .answer(let object) = answer, object["error"] == nil else { return }
    var current: [String: [String: Any]] = [:]
    for row in (object["attention"] as? [[String: Any]]) ?? [] { if let id = row["id"] as? String { current[id] = row } }
    seenRows = current
    seenAt = Date()
    if case .answer(let cards) = ask(["request": "cards"]) {
        seenProjects = projectStates((cards["cards"] as? [[String: Any]]) ?? [])
    }
}

@MainActor func call(_ name: String, arguments: [String: Any]) -> [String: Any] {
    let card = arguments["card"] as? String
    func project(_ action: String) -> [String: Any] {
        guard let card else { return toolResult(.unreachable("A card id is needed.")) }
        var request: [String: Any] = ["request": "command", "command": ["project": ["_0": card, "_1": action]]]
        if arguments["replace"] as? Bool == true { request["replace"] = true }
        return toolResult(ask(request))
    }
    switch name {
    case "what_needs_me":
        let answer = ask(["request": "attention"])
        remember(answer)
        return toolResult(answer)
    case "what_changed": return whatChanged()
    case "wait_for": return waitFor(arguments)
    case "project_time": return toolResult(ask(["request": "time"]))
    case "open":
        var request: [String: Any] = ["request": "open"]
        if let url = arguments["url"] as? String { request["url"] = url }
        if let card { request["card"] = card }
        if let target = arguments["target"] as? String { request["target"] = target }
        guard request["url"] != nil || card != nil else { return toolResult(.unreachable("A url or a card id is needed.")) }
        return toolResult(ask(request))
    case "cards": return toolResult(ask(["request": "cards"]), filterCard: card)
    case "project_log":
        guard let card else { return toolResult(.unreachable("A card id is needed.")) }
        return toolResult(ask(["request": "log", "card": card]))
    case "start_project": return project("start")
    case "stop_project": return project("stop")
    case "restart_project": return project("restart")
    case "detect_project":
        guard let folder = arguments["folder"] as? String else { return toolResult(.unreachable("A folder is needed.")) }
        return toolResult(ask(["request": "detect", "folder": folder]))
    case "add_project", "update_project":
        var request: [String: Any] = [:]
        if name == "add_project" {
            guard let folder = arguments["folder"] as? String else { return toolResult(.unreachable("A folder is needed.")) }
            request = ["request": "addProject", "folder": folder]
        } else {
            guard let card else { return toolResult(.unreachable("A card id is needed.")) }
            request = ["request": "updateProject", "card": card]
        }
        let names = [
            "kind": "kind", "title": "title", "organization": "organization", "site": "site",
            "start_command": "startCommand", "stop_command": "stopCommand",
            "holds_process": "holdsProcess", "requires_docker": "requiresDocker",
            "health_url": "healthURL", "local_site_url": "localSiteURL", "links": "links",
        ]
        for (argument, field) in names {
            if let value = arguments[argument] { request[field] = value }
        }
        return toolResult(ask(request))
    case "mark_inbox_read":
        if let thread = arguments["thread"] as? String {
            return toolResult(ask(["request": "command", "command": ["markRead": ["threadID": thread]]]))
        }
        return toolResult(ask(["request": "command", "command": ["markRestRead": [String: Any]()]]))
    default:
        return toolResult(.unreachable("There is no tool \(name)."))
    }
}

// MARK: The protocol

func send(_ message: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
    data.append(10)
    FileHandle.standardOutput.write(data)
}

func reply(_ id: Any, result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func fail(_ id: Any, code: Int, message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

@MainActor func handle(_ message: [String: Any]) {
    guard let method = message["method"] as? String else { return }
    // A notification has no id and wants no answer.
    guard let id = message["id"] else { return }
    let params = message["params"] as? [String: Any] ?? [:]
    switch method {
    case "initialize":
        if let client = (params["clientInfo"] as? [String: Any])?["name"] as? String { agentName = humanized(client) }
        let asked = params["protocolVersion"] as? String
        var version = "unknown"
        if case .answer(let hello) = ask(["request": "hello"]), let theirs = hello["version"] as? String { version = theirs }
        reply(id, result: [
            "protocolVersion": supportedVersions.contains(asked ?? "") ? asked! : supportedVersions[0],
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "devdeck", "version": version],
            "instructions": "DevDeck is the developer's desk: pull requests, reviews, the GitHub inbox, CI, and local projects with their state and logs. Ask what_needs_me first, and what_changed later in the session rather than asking again. Project tools take card ids from cards. open puts a page or a project's place on the person's screen.",
        ])
    case "ping":
        reply(id, result: [:])
    case "tools/list":
        let control = allowsControl()
        reply(id, result: ["tools": tools.filter { !$0.controls || control }.map(\.listing)])
    case "tools/call":
        guard let name = params["name"] as? String else {
            fail(id, code: -32602, message: "tools/call needs a name")
            return
        }
        reply(id, result: call(name, arguments: params["arguments"] as? [String: Any] ?? [:]))
    default:
        fail(id, code: -32601, message: "Method not found: \(method)")
    }
}

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { continue }
    guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) else {
        send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        continue
    }
    if let batch = object as? [[String: Any]] {
        batch.forEach(handle)
    } else if let message = object as? [String: Any] {
        handle(message)
    }
}
