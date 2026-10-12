import Foundation

/// The host aliases in the user's `~/.ssh/config`, as ssh itself resolves them.
///
/// A remote such as `git@github-work:org/repo.git` names a `Host` block, not a server: ssh looks
/// up `HostName` there and connects to `github.com`. A page built from the alias is
/// `https://github-work/org/repo`, which goes nowhere. This answers the one question the cards
/// need, which real host an alias stands for, by ssh's own rules: blocks in file order, the
/// first value found for a keyword wins, `*` and `?` in patterns, `!` to exclude, `%h` for the
/// name asked about, and `Include` read where it stands.
///
/// Read from the file rather than by running `ssh -G`: the cards ask every ten seconds, and the
/// file is reread only when it changes.
public struct SSHConfig: Sendable, Equatable {
    /// One `Host` block: its patterns, and its `HostName` when it has one.
    struct Block: Sendable, Equatable {
        let patterns: [String]
        let hostName: String?
    }

    let blocks: [Block]

    /// The real host behind `alias`, or nil when no block gives it a `HostName`.
    public func hostName(for alias: String) -> String? {
        let name = alias.lowercased()
        for block in blocks where Self.matches(name, patterns: block.patterns) {
            guard let hostName = block.hostName else { continue }
            return hostName.replacingOccurrences(of: "%h", with: alias)
        }
        return nil
    }

    // MARK: Reading

    /// Parses a config. `include` reads an `Include` line's files, relative paths being under
    /// `~/.ssh` the way ssh reads them; it is given the path as written.
    public static func parse(_ contents: String, include: (String) -> [String] = { _ in [] }, depth: Int = 0) -> SSHConfig {
        var blocks: [Block] = []
        // Lines before any Host apply to every host, as `Host *` would.
        var patterns: [String] = ["*"]
        var hostName: String?
        var isMatchBlock = false

        func close() {
            guard !isMatchBlock else { return }
            blocks.append(Block(patterns: patterns, hostName: hostName))
        }

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let (keyword, value) = split(line)
            switch keyword {
            case "host":
                close()
                patterns = value.split(whereSeparator: \.isWhitespace).map { unquote(String($0)).lowercased() }
                hostName = nil
                isMatchBlock = false
            case "match":
                // Conditions on the user, the command or the network are not something a card
                // can answer; such a block is skipped rather than guessed at.
                close()
                patterns = []
                hostName = nil
                isMatchBlock = true
            case "hostname":
                if hostName == nil { hostName = unquote(value) }
            case "include" where depth < 8:
                // Read where it stands, as ssh does: the lines before the file's own first Host
                // continue the block the Include is in, its Host blocks come next in order, and
                // after the file the outer block goes on where it left off.
                for text in value.split(whereSeparator: \.isWhitespace).flatMap({ include(unquote(String($0))) }) {
                    let inner = parse(text, include: include, depth: depth + 1)
                    if let first = inner.blocks.first, hostName == nil {
                        hostName = first.hostName
                    }
                    guard inner.blocks.count > 1 else { continue }
                    close()
                    blocks.append(contentsOf: inner.blocks.dropFirst())
                    // What the outer block said before is in the block just closed, and the
                    // first value wins, so it goes on with nothing said yet.
                    hostName = nil
                }
            default:
                continue
            }
        }
        close()
        return SSHConfig(blocks: blocks)
    }

    /// `Keyword value`, `Keyword=value` or `Keyword = value`, with the keyword lowercased.
    private static func split(_ line: String) -> (String, String) {
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "="))
        guard let end = line.rangeOfCharacter(from: separators) else { return (line.lowercased(), "") }
        let keyword = line[..<end.lowerBound].lowercased()
        let value = line[end.lowerBound...].trimmingCharacters(in: separators)
        return (keyword, value)
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        return String(text.dropFirst().dropLast())
    }

    // MARK: Matching

    /// ssh's rule: some pattern matches and no `!pattern` does.
    static func matches(_ name: String, patterns: [String]) -> Bool {
        var matched = false
        for pattern in patterns {
            if pattern.hasPrefix("!") {
                if wildcard(String(pattern.dropFirst()), matches: name) { return false }
            } else if wildcard(pattern, matches: name) {
                matched = true
            }
        }
        return matched
    }

    /// `*` for any run of characters, `?` for one.
    static func wildcard(_ pattern: String, matches name: String) -> Bool {
        let pattern = Array(pattern)
        let name = Array(name)
        var p = 0
        var n = 0
        var star = -1
        var resume = 0
        while n < name.count {
            if p < pattern.count, pattern[p] == "?" || pattern[p] == name[n] {
                p += 1
                n += 1
            } else if p < pattern.count, pattern[p] == "*" {
                star = p
                resume = n
                p += 1
            } else if star >= 0 {
                p = star + 1
                resume += 1
                n = resume
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == "*" { p += 1 }
        return p == pattern.count
    }

    // MARK: The user's own

    /// `~/.ssh` for this user, on either platform.
    public static var directory: URL {
        #if os(Windows)
        let home = ProcessInfo.processInfo.environment["USERPROFILE"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".ssh", isDirectory: true)
        #else
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh", isDirectory: true)
        #endif
    }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var modified: Date?
        var config = SSHConfig(blocks: [])
    }

    private static let cache = Cache()

    /// The user's config, reread only when the file has changed.
    public static func current() -> SSHConfig {
        let file = directory.appendingPathComponent("config")
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if modified == cache.modified { return cache.config }
        let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        cache.config = parse(contents, include: readIncluded)
        cache.modified = modified
        return cache.config
    }

    /// An `Include` path's files: `~` expanded, relative paths under `~/.ssh`, and a `*` in the
    /// last component matched against that folder, in name order as ssh reads them.
    private static func readIncluded(_ path: String) -> [String] {
        var expanded = path
        if expanded.hasPrefix("~/") {
            expanded = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(String(expanded.dropFirst(2))).path
        } else if !expanded.hasPrefix("/"), !(expanded.count > 1 && expanded.dropFirst().first == ":") {
            expanded = directory.appendingPathComponent(expanded).path
        }
        let url = URL(fileURLWithPath: expanded)
        let last = url.lastPathComponent
        guard last.contains("*") || last.contains("?") else {
            return (try? String(contentsOf: url, encoding: .utf8)).map { [$0] } ?? []
        }
        let folder = url.deletingLastPathComponent()
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { wildcard(last, matches: $0) }
            .sorted()
        return names.compactMap { try? String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8) }
    }
}
