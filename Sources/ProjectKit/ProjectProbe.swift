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
/// remember what the command was - and because the answer is written down in the folder in
/// almost every case.
public enum ProjectProbe {
    private static let composeFiles = [
        "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml",
    ]

    /// The frameworks worth naming, with the port each listens on when nothing says otherwise.
    ///
    /// The order is the order the site is looked for in a repo that holds several: the health
    /// URL is meant to be the thing you open, so a front end wins over an API. Nest is last for
    /// exactly that reason, and it is still in the list because a repo that is only an API
    /// should say so on its card.
    private static let frameworks: [(dependency: String, name: String, port: Int)] = [
        ("next", "next", 3000),
        ("nuxt", "nuxt", 3000),
        ("vite", "vite", 5173),
        ("astro", "astro", 4321),
        ("react-scripts", "react", 3000),
        ("@angular/cli", "angular", 4200),
        ("vue-cli-service", "vue", 8080),
        ("@nestjs/core", "nest", 3000),
    ]

    /// A monorepo can hold a lot of packages, and this runs while somebody waits for a file
    /// dialog to close. The site is in the first handful or it is not being guessed at all.
    private static let workspaceLimit = 40

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

    /// One package.json, read for the four things this file cares about.
    private struct Manifest {
        var scripts: [String: String] = [:]
        var dependencies: Set<String> = []
        var workspaces: [String] = []
        var packageManager: String?
    }

    /// A package inside the project: the root itself, and every workspace under it.
    private struct Package {
        let folder: URL
        let manifest: Manifest
    }

    private static func nodeSuggestion(in folder: URL, script: String) -> ProjectSuggestion? {
        guard let root = manifest(in: folder), root.scripts[script] != nil else { return nil }

        let manager = packageManager(in: folder, manifest: root)
        let command = script == "start" ? "\(manager) start" : "\(manager) run \(script)"
        let packages = [Package(folder: folder, manifest: root)] + workspaces(of: root, in: folder)

        // Every framework in the repo, in the order the list declares. The first one is where
        // the health URL comes from; all of them go in the caption, because "next + nest" is
        // the one line that says what this repo is.
        var named: [String] = []
        var port: Int?
        for framework in frameworks {
            guard let package = packages.first(where: { runs(framework.dependency, in: $0, script: script) })
            else { continue }
            named.append(framework.name)
            if port == nil {
                port = self.port(for: framework, in: package, root: folder, script: script)
            }
        }

        let caption = ([manager] + (named.isEmpty ? [] : [named.joined(separator: " + ")]))
            .joined(separator: " · ")

        return ProjectSuggestion(
            subtitle: caption,
            startCommand: command,
            stopCommand: "",
            // A dev server holds its terminal - that is the whole point of it.
            holdsProcess: true,
            // Not only what the start command says. A root script routinely reaches Docker
            // through another script of its own - `bun run dev` is `bun run db:up && turbo run
            // dev` - and a card whose Docker box is off will happily offer a Start that cannot
            // work.
            requiresDocker: reaches(["docker", "compose"], from: script, in: root),
            healthURL: port.map { "http://localhost:\($0)" } ?? ""
        )
    }

    /// Whether this package is the one running a given framework.
    ///
    /// Its dependencies are the reliable half. The script line is checked as well because a
    /// project can run vite through a wrapper without ever listing it as a dependency.
    private static func runs(_ dependency: String, in package: Package, script: String) -> Bool {
        if package.manifest.dependencies.contains(dependency) { return true }
        return line(script, in: package.manifest).contains(dependency)
    }

    /// Where a framework is listening.
    ///
    /// The script line first, because a port written into `next dev --port 3000` is not a guess
    /// at all. Then `.env`, which is where a port that had to move usually ends up. The
    /// framework's own default is the last resort, and a wrong one shows up immediately as a
    /// card stuck on "starting…", which is why the field is right there in settings.
    private static func port(
        for framework: (dependency: String, name: String, port: Int),
        in package: Package,
        root: URL,
        script: String
    ) -> Int {
        if let declared = self.port(in: line(script, in: package.manifest)) { return declared }
        if let value = environment(in: package.folder)["PORT"], let number = Int(value) { return number }
        if package.folder != root, let value = environment(in: root)["PORT"], let number = Int(value) {
            return number
        }
        return framework.port
    }

    /// The script this package would be started by: its own entry for the name being probed,
    /// falling back to `dev`, which is what a workspace app is run by when the root delegates.
    private static func line(_ script: String, in manifest: Manifest) -> String {
        manifest.scripts[script] ?? manifest.scripts["dev"] ?? ""
    }

    /// A port written into a command: `--port 3000`, `-p 3000` or `PORT=3000`.
    public static func port(in line: String) -> Int? {
        let words = line.split(whereSeparator: { " \t=".contains($0) }).map(String.init)
        for (index, word) in words.enumerated() {
            guard ["--port", "-p", "PORT"].contains(word), index + 1 < words.count else { continue }
            if let number = Int(words[index + 1]), (1...65535).contains(number) { return number }
        }
        return nil
    }

    // MARK: What a script reaches

    /// Whether any of these words appears in a script or in the scripts it calls.
    ///
    /// One level deep on purpose. `dev` calling `db:up` calling `docker compose` is the shape
    /// this exists for, and following the chain further starts finding words in scripts that
    /// have nothing to do with starting anything.
    private static func reaches(_ words: [String], from script: String, in manifest: Manifest) -> Bool {
        let line = manifest.scripts[script] ?? ""
        let referenced = referencedScripts(in: line, known: Set(manifest.scripts.keys))
        let text = ([line] + referenced.map { manifest.scripts[$0] ?? "" }).joined(separator: " ")
        return words.contains { text.contains($0) }
    }

    /// The names of other scripts a script line runs: `bun run db:up`, `npm run build`,
    /// `pnpm lint`.
    public static func referencedScripts(in line: String, known: Set<String>) -> [String] {
        let managers: Set<String> = ["npm", "pnpm", "yarn", "bun"]
        let words = line.split(whereSeparator: { " \t&|;\n".contains($0) }).map(String.init)

        var found: [String] = []
        for (index, word) in words.enumerated() where managers.contains(word) {
            var next = index + 1
            if next < words.count, words[next] == "run" { next += 1 }
            guard next < words.count, known.contains(words[next]) else { continue }
            found.append(words[next])
        }
        return found
    }

    // MARK: Reading the folder

    private static func manifest(in folder: URL) -> Manifest? {
        guard
            let data = try? Data(contentsOf: folder.appendingPathComponent("package.json")),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var manifest = Manifest()
        manifest.scripts = root["scripts"] as? [String: String] ?? [:]
        manifest.dependencies = Set(
            Array((root["dependencies"] as? [String: Any])?.keys ?? [:].keys)
                + Array((root["devDependencies"] as? [String: Any])?.keys ?? [:].keys)
        )
        // Both spellings: npm and bun take an array, yarn takes an object with the array under
        // `packages`.
        if let list = root["workspaces"] as? [String] {
            manifest.workspaces = list
        } else if let object = root["workspaces"] as? [String: Any] {
            manifest.workspaces = object["packages"] as? [String] ?? []
        }
        manifest.packageManager = root["packageManager"] as? String
        return manifest
    }

    /// The packages a workspace pattern names. Only the one wildcard npm actually supports at
    /// the end of a path, which is the only one anybody writes.
    private static func workspaces(of manifest: Manifest, in folder: URL) -> [Package] {
        var packages: [Package] = []
        for pattern in manifest.workspaces {
            for candidate in folders(matching: pattern, in: folder) {
                guard packages.count < workspaceLimit else { return packages }
                guard let manifest = self.manifest(in: candidate) else { continue }
                packages.append(Package(folder: candidate, manifest: manifest))
            }
        }
        return packages
    }

    private static func folders(matching pattern: String, in folder: URL) -> [URL] {
        guard pattern.hasSuffix("/*") else {
            let candidate = folder.appendingPathComponent(pattern, isDirectory: true)
            return exists(candidate, "package.json") ? [candidate] : []
        }

        let parent = folder.appendingPathComponent(String(pattern.dropLast(2)), isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A `.env` as a dictionary. Enough of the format to read a port out of it: `KEY=value`,
    /// comments and blank lines skipped, quotes stripped.
    public static func environment(in folder: URL) -> [String: String] {
        guard
            let text = try? String(contentsOf: folder.appendingPathComponent(".env"), encoding: .utf8)
        else { return [:] }

        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<separator]
                .replacingOccurrences(of: "export ", with: "")
                .trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            guard !key.isEmpty else { continue }
            values[key] = value
        }
        return values
    }

    /// What the project is run with.
    ///
    /// `packageManager` first: it is the one place a repo states this rather than implies it,
    /// and a repo that pins bun refuses to run under anything else.
    private static func packageManager(in folder: URL, manifest: Manifest) -> String {
        if let pinned = manifest.packageManager?.split(separator: "@").first.map(String.init),
           ["bun", "pnpm", "yarn", "npm"].contains(pinned) {
            return pinned
        }
        if exists(folder, "bun.lock") || exists(folder, "bun.lockb") { return "bun" }
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
