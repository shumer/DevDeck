import Foundation

/// The `PATH` the user's terminal has, resolved once and reused.
///
/// An app launched from Finder inherits a bare environment, and `zsh -lc` does not fix it: a
/// login shell that is not interactive reads `.zprofile` but never `.zshrc`, which is where
/// nvm, rbenv, pyenv and every other version manager put themselves. The symptom is precise and
/// baffling — `ddev` and `docker` work, because they live in `/usr/local/bin` and come from
/// `/etc/paths`, while `npx` and `pnpm` report "command not found" from a machine where they
/// obviously exist.
///
/// The fix is to ask an interactive login shell what its `PATH` is, once, and hand that to every
/// command afterwards. Running the commands themselves interactively would work too and is what
/// most apps do, but an interactive `.zshrc` prints things — this one prints `exec zsh` — and
/// that lands in the middle of output something is trying to parse.
public actor ShellPath {
    public static let shared = ShellPath()

    /// Printed around the value so the answer can be found among whatever the profile says on
    /// its way past.
    public static let marker = "__DEVDECK_PATH__"
    public static let command = "printf '\\n%s%s\\n' '\(marker)' \"$PATH\""

    /// Where things live when the shell cannot be asked at all. Both Homebrew prefixes, because
    /// an Apple-silicon Mac and an Intel one disagree.
    public static let fallback = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    private var resolved: String?
    private var isResolving = false

    private init() {}

    /// Asks the shell the first time and remembers the answer.
    ///
    /// Not refreshed afterwards: a `PATH` that changes mid-session is a machine being set up,
    /// not one being worked on, and re-asking would cost an interactive shell per command.
    public func value(runner: any CommandRunning = ShellCommandRunner()) async -> String {
        if let resolved { return resolved }
        // Only one resolution at a time; the deck starts several commands at once on launch.
        guard !isResolving else { return Self.fallback }
        isResolving = true
        defer { isResolving = false }

        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let result = try? await runner.run(Self.command, in: home, timeout: 20, isInteractive: true)
        let value = result.flatMap { Self.parse($0.standardOutput) } ?? Self.fallback
        resolved = value
        return value
    }

    /// Finds the marked line and takes what follows the marker.
    public static func parse(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            guard let range = line.range(of: marker) else { continue }
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            // A PATH with no separator is a single directory, which no shell has; that is a
            // banner that happened to contain the marker.
            guard value.contains("/") else { continue }
            return value
        }
        return nil
    }

    /// For the suite, and for the settings screen if it ever wants to show what was found.
    public func override(_ value: String?) {
        resolved = value
    }
}
