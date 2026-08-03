import Foundation

/// What a folder looks like it wants to be run with.
public struct ProjectSuggestion: Sendable, Equatable {
    public var subtitle: String
    public var startCommand: String
    public var stopCommand: String
    public var holdsProcess: Bool
    public var requiresDocker: Bool
    public var healthURL: String

    public init(
        subtitle: String,
        startCommand: String,
        stopCommand: String = "",
        holdsProcess: Bool = false,
        requiresDocker: Bool = false,
        healthURL: String = ""
    ) {
        self.subtitle = subtitle
        self.startCommand = startCommand
        self.stopCommand = stopCommand
        self.holdsProcess = holdsProcess
        self.requiresDocker = requiresDocker
        self.healthURL = healthURL
    }
}

/// Reads a folder and guesses how the project in it is started.
///
/// A guess, offered once when the project is added, and never applied again behind the user's
/// back. It exists because the alternative is an empty form and a trip to the terminal to
/// remember what the command was — and because the answer is written down in the folder in
/// almost every case.
public enum ProjectProbe {
    private static let composeFiles = [
        "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml",
    ]

    /// Ports the common dev servers use. A wrong guess shows up immediately as a card that
    /// never leaves "starting…", which is why the field is right there in settings.
    private static let knownPorts: [(dependency: String, port: Int)] = [
        ("vite", 5173),
        ("astro", 4321),
        ("next", 3000),
        ("nuxt", 3000),
        ("react-scripts", 3000),
        ("@angular/cli", 4200),
        ("vue-cli-service", 8080),
    ]

    public static func suggestion(for folder: URL) -> ProjectSuggestion? {
        if let compose = composeSuggestion(in: folder) { return compose }
        if let node = nodeSuggestion(in: folder, script: "dev") { return node }
        if let make = makeSuggestion(in: folder) { return make }
        if let node = nodeSuggestion(in: folder, script: "start") { return node }
        return nil
    }

    // MARK: Compose

    private static func composeSuggestion(in folder: URL) -> ProjectSuggestion? {
        guard composeFiles.contains(where: { exists(folder, $0) }) else { return nil }
        return ProjectSuggestion(
            subtitle: "docker compose",
            // Detached, because a card cannot hold a foreground compose session and there is
            // no reason to: this is exactly the case the "keeps running" checkbox is off for.
            startCommand: "docker compose up -d",
            stopCommand: "docker compose down",
            holdsProcess: false,
            requiresDocker: true
        )
    }

    // MARK: Node

    private static func nodeSuggestion(in folder: URL, script: String) -> ProjectSuggestion? {
        let manifest = folder.appendingPathComponent("package.json")
        guard
            let data = try? Data(contentsOf: manifest),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scripts = root["scripts"] as? [String: String],
            scripts[script] != nil
        else { return nil }

        let manager = packageManager(in: folder)
        let command = script == "start" ? "\(manager) start" : "\(manager) run \(script)"
        let dependencies = Set(
            Array((root["dependencies"] as? [String: Any])?.keys ?? [:].keys)
                + Array((root["devDependencies"] as? [String: Any])?.keys ?? [:].keys)
        )
        // The script line is checked as well: a project can run vite through a wrapper without
        // ever listing it as a dependency of its own.
        let scriptLine = scripts[script] ?? ""
        let port = knownPorts.first {
            dependencies.contains($0.dependency) || scriptLine.contains($0.dependency)
        }?.port

        return ProjectSuggestion(
            subtitle: manager,
            startCommand: command,
            stopCommand: "",
            // A dev server holds its terminal — that is the whole point of it.
            holdsProcess: true,
            requiresDocker: false,
            healthURL: port.map { "http://localhost:\($0)" } ?? ""
        )
    }

    private static func packageManager(in folder: URL) -> String {
        if exists(folder, "pnpm-lock.yaml") { return "pnpm" }
        if exists(folder, "yarn.lock") { return "yarn" }
        return "npm"
    }

    // MARK: Make

    private static func makeSuggestion(in folder: URL) -> ProjectSuggestion? {
        let candidates = ["Makefile", "makefile"]
        guard
            let name = candidates.first(where: { exists(folder, $0) }),
            let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        else { return nil }

        let targets = makeTargets(in: text)
        guard let start = ["up", "start", "dev"].first(where: { targets.contains($0) }) else { return nil }
        let stop = ["down", "stop"].first { targets.contains($0) }

        return ProjectSuggestion(
            subtitle: "make",
            startCommand: "make \(start)",
            stopCommand: stop.map { "make \($0)" } ?? "",
            // `make dev` usually fronts a dev server; `make up` usually fronts compose.
            holdsProcess: start == "dev",
            requiresDocker: text.contains("docker")
        )
    }

    /// Target names from a Makefile: the word at the start of a line before its colon.
    public static func makeTargets(in text: String) -> Set<String> {
        var targets: Set<String> = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard !line.hasPrefix("\t"), !line.hasPrefix("#") else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(" "), !name.contains("="), !name.hasPrefix(".") else { continue }
            targets.insert(name)
        }
        return targets
    }

    private static func exists(_ folder: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
    }
}
