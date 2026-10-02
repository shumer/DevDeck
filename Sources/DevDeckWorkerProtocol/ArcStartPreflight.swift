import DevDeckCore
import Foundation

/// Shared Docker means that choosing another distro does not free a container's published ports.
public struct ArcStartPreflight: Sendable {
    private let runner: any CommandRunning
    public init(runner: any CommandRunning) { self.runner = runner }
    public func check(folder: URL, requiresLocalCLI: Bool = true) async -> WorkerFailure? {
        if requiresLocalCLI {
        let tools = try? await runner.run("command -v node; command -v npx", in: folder, timeout: 15)
        let paths = tools?.standardOutput.split(separator: "\n").map(String.init) ?? []
        guard tools?.succeeded == true, paths.count == 2,
              paths.allSatisfy({ $0.hasPrefix("/") && !$0.hasPrefix("/mnt/") && !$0.hasSuffix(".exe") && !$0.hasSuffix(".cmd") }) else {
            return WorkerFailure(code: "linuxNodeUnavailable", message: "Linux Node.js and npx are required in this distribution's shell profile.")
        }
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("node_modules/@arc-fusion/cli/package.json").path) else {
            return WorkerFailure(code: "fusionUnavailable", message: "Install the project's Fusion CLI dependencies before starting its stack.")
        }
        }
        let compose = folder.appendingPathComponent(".fusion/docker-compose.yml")
        guard FileManager.default.fileExists(atPath: compose.path) else {
            return WorkerFailure(code: "composeUnavailable", message: "A generated Fusion Compose configuration is required for port preflight.")
        }
        let quoted = "'" + compose.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        guard let configuration = try? await runner.run("docker compose -f \(quoted) config --format json", in: folder, timeout: 20),
              configuration.succeeded,
              let config = try? JSONSerialization.jsonObject(with: Data(configuration.standardOutput.utf8)) as? [String: Any],
              let services = config["services"] as? [String: [String: Any]],
              let processes = try? await runner.run("docker ps --format '{{json .}}'", in: folder, timeout: 20), processes.succeeded else {
            return WorkerFailure(code: "preflightUnavailable", message: "Docker port ownership could not be checked. No stack was started.")
        }
        let ports = services.values.flatMap { service -> [Int] in
            (service["ports"] as? [[String: Any]] ?? []).compactMap { port in
                if let number = port["published"] as? Int { return number }
                if let text = port["published"] as? String { return Int(text) }
                return nil
            }
        }
        return Self.conflict(requiredPorts: Set(ports), dockerRows: processes.standardOutput, folder: folder.path)
    }

    public static func conflict(requiredPorts: Set<Int>, dockerRows: String, folder: String) -> WorkerFailure? {
        let pattern = try! NSRegularExpression(pattern: #":([0-9]+)->[0-9]+/tcp"#)
        for line in dockerRows.split(separator: "\n") {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return WorkerFailure(code: "preflightUnavailable", message: "Docker port ownership could not be decoded.")
            }
            let labels = (row["Labels"] as? String ?? "").split(separator: ",").reduce(into: [String: String]()) { result, item in
                let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 { result[pair[0]] = pair[1] }
            }
            let own = [folder, folder + "/.fusion"].contains(labels["com.docker.compose.project.working_dir"] ?? "")
            if own { continue }
            let published = row["Ports"] as? String ?? ""
            for match in pattern.matches(in: published, range: NSRange(published.startIndex..., in: published)) {
                if let range = Range(match.range(at: 1), in: published), let port = Int(published[range]), requiredPorts.contains(port) {
                    return WorkerFailure(code: "portConflict", message: "Host port \(port) belongs to another Docker stack. Resolve its port mapping before starting this project.")
                }
            }
        }
        return nil
    }
}
