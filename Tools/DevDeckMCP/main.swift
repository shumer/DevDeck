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
//
// See docs/mcp.md and docs/adr/0036-agent-access.md.

let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

/// A tool as `tools/list` describes it.
struct Tool {
    let name: String
    let description: String
    let properties: [String: [String: String]]
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

let tools = [
    Tool(
        name: "what_needs_me",
        description: "What the deck wants the person's attention for, most urgent first: reviews and mentions waiting on them, things to fix on this computer, their own stuck work, and what is good to know. The same rows as DevDeck's menu.",
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
        description: "Starts a project the way its Start button does, waits for it to answer or fail, and returns its card.",
        properties: ["card": cardProperty], required: ["card"], controls: true
    ),
    Tool(
        name: "stop_project",
        description: "Stops a project the way its Stop button does and returns its card. A project started outside DevDeck is not stopped; the card says why.",
        properties: ["card": cardProperty], required: ["card"], controls: true
    ),
    Tool(
        name: "restart_project",
        description: "Restarts a project the way its Restart button does, waits for it, and returns its card.",
        properties: ["card": cardProperty], required: ["card"], controls: true
    ),
    Tool(
        name: "mark_inbox_read",
        description: "Marks one inbox notification read, by the thread id what_needs_me gives; without one, marks read everything in the inbox that is not addressed to the person, like the inbox card's button.",
        properties: ["thread": ["type": "string", "description": "The inbox thread id."]], required: [], controls: true
    ),
]

// MARK: Talking to the deck

enum DeckAnswer {
    case answer([String: Any])
    case unreachable(String)
}

func ask(_ request: [String: Any]) -> DeckAnswer {
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
func allowsControl() -> Bool {
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

func call(_ name: String, arguments: [String: Any]) -> [String: Any] {
    let card = arguments["card"] as? String
    func project(_ action: String) -> [String: Any] {
        guard let card else { return toolResult(.unreachable("A card id is needed.")) }
        return toolResult(ask(["request": "command", "command": ["project": ["_0": card, "_1": action]]]))
    }
    switch name {
    case "what_needs_me": return toolResult(ask(["request": "attention"]))
    case "cards": return toolResult(ask(["request": "cards"]), filterCard: card)
    case "project_log":
        guard let card else { return toolResult(.unreachable("A card id is needed.")) }
        return toolResult(ask(["request": "log", "card": card]))
    case "start_project": return project("start")
    case "stop_project": return project("stop")
    case "restart_project": return project("restart")
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

func handle(_ message: [String: Any]) {
    guard let method = message["method"] as? String else { return }
    // A notification has no id and wants no answer.
    guard let id = message["id"] else { return }
    let params = message["params"] as? [String: Any] ?? [:]
    switch method {
    case "initialize":
        let asked = params["protocolVersion"] as? String
        var version = "unknown"
        if case .answer(let hello) = ask(["request": "hello"]), let theirs = hello["version"] as? String { version = theirs }
        reply(id, result: [
            "protocolVersion": supportedVersions.contains(asked ?? "") ? asked! : supportedVersions[0],
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "devdeck", "version": version],
            "instructions": "DevDeck is the developer's desk: pull requests, reviews, the GitHub inbox, CI, and local projects with their state and logs. Ask what_needs_me first. Project tools take card ids from cards.",
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
