import Foundation

/// What a checkout can say about itself without being asked twice.
///
/// Read straight from the files in `.git` rather than by running `git`: the cards poll every ten
/// seconds, and spawning a shell that often to learn two lines is waste. `HEAD` is the same
/// thing `git branch --show-current` prints and `config` the same thing `git remote get-url`
/// does, minus the process.
public enum GitCheckout {
    public static func branch(in directory: URL?) -> String? {
        guard let directory, let head = gitFile("HEAD", in: directory) else { return nil }
        guard let contents = try? String(contentsOf: head, encoding: .utf8) else { return nil }

        let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        if let range = line.range(of: "ref: refs/heads/") {
            let branch = String(line[range.upperBound...])
            return branch.isEmpty ? nil : branch
        }

        // Detached HEAD holds a bare commit. The short form is what a prompt would show, and
        // what someone glancing at the card can compare against.
        guard line.count >= 7, line.allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(line.prefix(7))
    }

    /// Where this checkout came from, as a page a browser can open.
    ///
    /// The card already reads the branch, so the repository is one more line of the same file —
    /// and it turns the branch into the link it always looked like.
    public static func originWebURL(in directory: URL?) -> URL? {
        guard let directory, let config = gitFile("config", in: directory) else { return nil }
        guard let contents = try? String(contentsOf: config, encoding: .utf8) else { return nil }
        guard let remote = originURL(inConfig: contents) else { return nil }
        return webURL(fromRemote: remote)
    }

    /// The page for one branch of that repository, where the host has a shape for it.
    public static func branchWebURL(in directory: URL?, branch: String?) -> URL? {
        guard let repository = originWebURL(in: directory) else { return nil }
        guard let branch, !branch.isEmpty else { return repository }
        return branchWebURL(repository: repository, branch: branch)
    }

    /// `url = …` from the `[remote "origin"]` section, and nothing from any other section.
    ///
    /// Parsed rather than regexed over the whole file: a repository with several remotes has
    /// several `url =` lines, and the first one is not reliably origin's.
    public static func originURL(inConfig contents: String) -> String? {
        var isInOrigin = false
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                // Both `[remote "origin"]` and the subsection-free spelling git writes.
                isInOrigin = line.replacingOccurrences(of: " ", with: "") == "[remote\"origin\"]"
                continue
            }
            guard isInOrigin, line.hasPrefix("url") else { continue }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Turns a remote into a page. Handles the three ways the same repository is written down.
    ///
    ///     git@github.com:org/repo.git        → https://github.com/org/repo
    ///     ssh://git@github.com/org/repo.git  → https://github.com/org/repo
    ///     https://github.com/org/repo.git    → https://github.com/org/repo
    ///
    /// Host-agnostic on purpose: the same shapes serve GitLab, Bitbucket and a self-hosted
    /// instance, and none of them wants a special case here.
    public static func webURL(fromRemote remote: String) -> URL? {
        var text = remote.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        if let range = text.range(of: "://") {
            // Any scheme, with or without credentials in front of the host.
            var rest = String(text[range.upperBound...])
            if let at = rest.lastIndex(of: "@"), let slash = rest.firstIndex(of: "/"), at < slash {
                rest = String(rest[rest.index(after: at)...])
            }
            text = rest
        } else if let colon = text.firstIndex(of: ":") {
            // scp syntax: `git@host:org/repo.git`.
            var host = String(text[..<colon])
            if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
            let path = text[text.index(after: colon)...]
            text = "\(host)/\(path)"
        } else {
            return nil
        }

        if text.hasSuffix(".git") { text.removeLast(4) }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // A host with no path is not a repository — it is somebody's server.
        guard text.contains("/") else { return nil }
        return URL(string: "https://\(text)")
    }

    /// Every host spells "this branch" differently, and a host nobody here knows gets the
    /// repository itself rather than a guessed path that lands on a 404.
    public static func branchWebURL(repository: URL, branch: String) -> URL {
        let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        let host = repository.host?.lowercased() ?? ""

        if host.contains("github") { return repository.appendingPathComponent("tree/\(encoded)") }
        if host.contains("gitlab") { return repository.appendingPathComponent("-/tree/\(encoded)") }
        if host.contains("bitbucket") { return repository.appendingPathComponent("src/\(encoded)") }
        return repository
    }

    /// Handles both a normal `.git` directory and the `gitdir:` pointer file that worktrees
    /// and submodules leave behind.
    private static func gitFile(_ name: String, in directory: URL) -> URL? {
        let dotGit = directory.appendingPathComponent(".git")

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return dotGit.appendingPathComponent(name)
        }

        guard
            let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
            let range = pointer.range(of: "gitdir:")
        else { return nil }

        let path = pointer[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let resolved = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : directory.appendingPathComponent(path).standardizedFileURL
        // A worktree's own directory has HEAD but shares config with the main checkout, which
        // `commondir` points at.
        if name == "config",
           let common = try? String(contentsOf: resolved.appendingPathComponent("commondir"), encoding: .utf8) {
            let trimmed = common.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = trimmed.hasPrefix("/")
                ? URL(fileURLWithPath: trimmed)
                : resolved.appendingPathComponent(trimmed).standardizedFileURL
            return base.appendingPathComponent(name)
        }
        return resolved.appendingPathComponent(name)
    }
}
