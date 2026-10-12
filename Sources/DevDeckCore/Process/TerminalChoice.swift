import Foundation

/// The user's interactive terminal, separate from the runner that launches projects.
public struct TerminalChoice: Codable, Equatable, Sendable {
    public var application: String?
    public var profile: String?

    public init(application: String? = nil, profile: String? = nil) {
        self.application = application
        self.profile = profile
    }
}

public struct TerminalProfile: Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct TerminalApplication: Equatable, Sendable {
    public let id: String
    public let profiles: [TerminalProfile]

    public init(id: String, profiles: [TerminalProfile] = []) {
        self.id = id
        self.profiles = profiles
    }
}

/// Terminal settings allow comments and trailing commas, unlike ordinary JSON.
public enum TerminalProfiles {
    public static func parse(_ text: String) -> [TerminalProfile] {
        guard let data = json(text).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        let profiles = root["profiles"] as? [String: Any]
        let entries = profiles?["list"] as? [[String: Any]] ?? root["profiles"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard entry["hidden"] as? Bool != true,
                  let guid = entry["guid"] as? String,
                  let uuid = UUID(uuidString: guid.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))),
                  let name = entry["name"] as? String, !name.isEmpty
            else { return nil }
            let id = "{" + uuid.uuidString.lowercased() + "}"
            guard seen.insert(id).inserted else { return nil }
            return TerminalProfile(id: id, name: name)
        }
    }

    private static func json(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        var index = 0
        var quoted = false
        var escaped = false
        while index < characters.count {
            let character = characters[index]
            if quoted {
                result.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
                index += 1
                continue
            }
            if character == "\"" { quoted = true }
            if character == "/", index + 1 < characters.count {
                if characters[index + 1] == "/" {
                    while index < characters.count, characters[index] != "\n" { index += 1 }
                    continue
                }
                if characters[index + 1] == "*" {
                    index += 2
                    while index + 1 < characters.count,
                          !(characters[index] == "*" && characters[index + 1] == "/") { index += 1 }
                    index += 2
                    result.append(" ")
                    continue
                }
            }
            if character == "," {
                var next = index + 1
                while next < characters.count {
                    if characters[next].isWhitespace {
                        next += 1
                        continue
                    }
                    if characters[next] == "/", next + 1 < characters.count {
                        if characters[next + 1] == "/" {
                            while next < characters.count, characters[next] != "\n" { next += 1 }
                            continue
                        }
                        if characters[next + 1] == "*" {
                            next += 2
                            while next + 1 < characters.count,
                                  !(characters[next] == "*" && characters[next + 1] == "/") { next += 1 }
                            next += 2
                            continue
                        }
                    }
                    break
                }
                if next < characters.count, characters[next] == "]" || characters[next] == "}" {
                    index += 1
                    continue
                }
            }
            result.append(character)
            index += 1
        }
        return result
    }
}
