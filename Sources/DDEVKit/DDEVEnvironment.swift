import DevDeckCore
import Foundation

/// Talks to the `ddev` CLI.
///
/// One `ddev list -j` answers for every project at once, so a deck with six cards costs the
/// same as a deck with one — which is the reason this is a shared environment rather than a
/// service per project, the way Arc's local stack is.
public struct DDEVEnvironment: Sendable {
    private let runner: any CommandRunning
    private let clock: any DateProvider
    /// Where commands run when they are not about one project in particular.
    private let workingDirectory: URL

    public init(
        runner: any CommandRunning = ShellCommandRunner(),
        clock: any DateProvider = SystemDateProvider(),
        workingDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) {
        self.runner = runner
        self.clock = clock
        self.workingDirectory = workingDirectory
    }

    // MARK: Listing

    /// Every project DDEV knows about, keyed by name.
    ///
    /// Returns nil when `ddev` could not be asked at all — a missing binary or a daemon that
    /// is down — which is different from "it answered and there are no projects".
    public func list() async -> [DDEVListEntry]? {
        guard
            let result = try? await runner.run("ddev list -j", in: workingDirectory, timeout: 30),
            result.succeeded
        else { return nil }
        return Self.parseList(result.standardOutput)
    }

    /// `ddev list -j` wraps its payload in a log envelope; the projects are under `raw`.
    public static func parseList(_ output: String) -> [DDEVListEntry] {
        // The command prints a JSON object per line in some versions, so the payload is found
        // rather than assumed to be the whole of stdout.
        guard let data = jsonPayload(in: output) else { return [] }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let raw = root["raw"] as? [[String: Any]]
        else { return [] }

        return raw.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            return DDEVListEntry(
                name: name,
                approot: entry["approot"] as? String ?? "",
                type: entry["type"] as? String ?? "",
                state: DDEVState(apiValue: entry["status"] as? String ?? ""),
                statusDescription: entry["status_desc"] as? String,
                primaryURL: (entry["primary_url"] as? String).flatMap(URL.init(string:)),
                mailpitURL: (entry["mailpit_https_url"] as? String ?? entry["mailpit_url"] as? String)
                    .flatMap(URL.init(string:)),
                xhguiURL: (entry["xhgui_https_url"] as? String ?? entry["xhgui_url"] as? String)
                    .flatMap(URL.init(string:)),
                mutagenEnabled: entry["mutagen_enabled"] as? Bool ?? false,
                mutagenStatus: entry["mutagen_status"] as? String
            )
        }
    }

    private static func jsonPayload(in output: String) -> Data? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), trimmed.contains("\"raw\"") else { continue }
            return Data(trimmed.utf8)
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") ? Data(trimmed.utf8) : nil
    }

    /// Combines what DDEV reports with what the checkout says about itself.
    public func status(for project: DDEVProject, entries: [DDEVListEntry]?) -> DDEVStatus {
        let config = DDEVConfig.load(in: project.folderURL)
        let branch = GitCheckout.branch(in: project.folderURL)

        guard let entries else {
            return DDEVStatus(
                state: .unknown,
                config: config,
                branch: branch,
                detail: "ddev did not answer",
                checkedAt: clock.now
            )
        }

        // Matched by name first and by folder second: renaming a project in `.ddev/config.yaml`
        // is a normal thing to do, and the folder is what the user actually chose.
        let entry = entries.first { $0.name == project.name }
            ?? entries.first { entry in
                guard let folder = project.folderURL else { return false }
                // Compared as paths: one side is built as a directory URL and the other is
                // not, so the trailing slash would make two names for the same folder.
                return URL(fileURLWithPath: entry.approot).standardizedFileURL.path
                    == folder.standardizedFileURL.path
            }

        guard let entry else {
            return DDEVStatus(
                state: .unknown,
                config: config,
                branch: branch,
                detail: "ddev does not know this project",
                checkedAt: clock.now
            )
        }

        return DDEVStatus(
            state: entry.state,
            entry: entry,
            config: config,
            branch: branch,
            detail: entry.state == .running ? nil : entry.statusDescription,
            checkedAt: clock.now
        )
    }

    // MARK: Actions

    public func perform(_ action: DDEVAction, for project: DDEVProject) async -> CommandResult? {
        guard let folder = project.folderURL else { return nil }
        // Long by design: a first start pulls images, and being killed halfway leaves a
        // half-built project behind.
        return try? await runner.run(action.command, in: folder, timeout: 900)
    }

    /// Stops every project and the router — the "give me my memory back" button.
    public func powerOff() async -> CommandResult? {
        try? await runner.run("ddev poweroff", in: workingDirectory, timeout: 300)
    }

    /// Whether the CLI is there at all, for the settings screen to say so plainly.
    public func isInstalled() async -> Bool {
        guard let result = try? await runner.run("command -v ddev", in: workingDirectory, timeout: 15) else {
            return false
        }
        return result.succeeded
    }
}
