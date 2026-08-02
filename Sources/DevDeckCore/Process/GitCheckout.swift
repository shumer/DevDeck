import Foundation

/// Which branch a checkout is on.
///
/// Read straight from `.git/HEAD` rather than by running `git`: the card polls every ten
/// seconds, and spawning a shell that often to learn one line is waste. The file is the same
/// thing `git branch --show-current` prints, minus the process.
public enum GitCheckout {
    public static func branch(in directory: URL?) -> String? {
        guard let directory, let head = headFile(in: directory) else { return nil }
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

    /// Handles both a normal `.git` directory and the `gitdir:` pointer file that worktrees
    /// and submodules leave behind.
    private static func headFile(in directory: URL) -> URL? {
        let dotGit = directory.appendingPathComponent(".git")

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return dotGit.appendingPathComponent("HEAD")
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
        return resolved.appendingPathComponent("HEAD")
    }
}
