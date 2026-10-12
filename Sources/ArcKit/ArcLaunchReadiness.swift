import DevDeckCore
import Foundation

/// A non-destructive launch check. It never runs the start command or installs a package.
public struct ArcLaunchReadiness: Sendable, Equatable, Codable {
    public let canStart: Bool
    public let detail: String?

    public init(canStart: Bool, detail: String? = nil) {
        self.canStart = canStart
        self.detail = detail
    }

    public static func check(
        _ project: ArcProject,
        runner: any CommandRunning,
        pathExists: @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) async -> ArcLaunchReadiness {
        guard let folder = project.folderURL, pathExists(folder) else { return blocked(L("arc.readiness.folder")) }
        let command = project.startCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return blocked(L("arc.readiness.command")) }
        // Only known command shapes can be checked without evaluating arbitrary shell code.
        let fusionPattern = #"^((?:[A-Za-z_][A-Za-z_0-9]*=(?:'[^']*'|"[^"]*"|\S+)\s+)*)(npx(?:\.cmd)?\s+(?:--no-install\s+)?fusion|fusion(?:\.cmd)?)\s+(?:daemon|start)(?:\s+[^;&|<>]*)?$"#
        let fusion = try? NSRegularExpression(pattern: fusionPattern)
        let range = NSRange(command.startIndex..., in: command)
        let match = fusion?.firstMatch(in: command, range: range)
        let nodeCommand = command.range(of: #"^node(?:\.exe)?\s+"#, options: .regularExpression) != nil
        guard match != nil || nodeCommand else {
            return ArcLaunchReadiness(canStart: true, detail: L("arc.readiness.custom"))
        }
        let prefix = match.flatMap { Range($0.range(at: 1), in: command) }.map { String(command[$0]) } ?? ""
        if prefix.contains("$(") || prefix.contains(where: { ";&|<>\r\n`".contains($0) }) {
            return ArcLaunchReadiness(canStart: true, detail: L("arc.readiness.custom"))
        }
        do {
            let node = try await runner.run(prefix + "node --version", in: folder, timeout: 10)
            guard node.succeeded,
                  node.standardOutput.split(whereSeparator: \.isNewline).contains(where: {
                      $0.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^v\d+\.\d+\.\d+"#, options: .regularExpression) != nil
                  })
            else { return blocked(L("arc.readiness.node")) }
            if nodeCommand {
                let scriptPattern = #"^node(?:\.exe)?\s+(?:"([^"]+)"|'([^']+)'|([^\s]+))"#
                if let expression = try? NSRegularExpression(pattern: scriptPattern),
                   let scriptMatch = expression.firstMatch(in: command, range: range) {
                    for group in 1...3 {
                        guard let scriptRange = Range(scriptMatch.range(at: group), in: command) else { continue }
                        let script = String(command[scriptRange])
                        let absolute = script.hasPrefix("/") || script.hasPrefix("\\\\")
                            || script.range(of: #"^[A-Za-z]:[/\\]"#, options: .regularExpression) != nil
                        let file = absolute ? URL(fileURLWithPath: script) : folder.appendingPathComponent(script)
                        if !script.hasPrefix("-"), !pathExists(file) {
                            return blocked(L("arc.readiness.script"))
                        }
                    }
                }
                return ArcLaunchReadiness(canStart: true)
            }
            if match.flatMap({ Range($0.range(at: 2), in: command) }).map({ command[$0].hasPrefix("npx") }) == true {
                let npx = try await runner.run(prefix + "npx --version", in: folder, timeout: 10)
                guard npx.succeeded else { return blocked(L("arc.readiness.npx")) }
            }
            let local = try await runner.run(prefix + cliProbe(globalRoot: nil), in: folder, timeout: 10)
            if local.succeeded { return ArcLaunchReadiness(canStart: true) }
            let global = try await runner.run(prefix + "npm root -g", in: folder, timeout: 10)
            if global.succeeded {
                let path = global.standardOutput.split(whereSeparator: \.isNewline).last.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                } ?? ""
                if !path.isEmpty {
                    let installed = try await runner.run(prefix + cliProbe(globalRoot: path), in: folder, timeout: 10)
                    if installed.succeeded { return ArcLaunchReadiness(canStart: true) }
                }
            }
            return blocked(L("arc.readiness.fusion"))
        } catch {
            return blocked(L("arc.readiness.failed"))
        }
    }

    private static func blocked(_ detail: String) -> ArcLaunchReadiness {
        ArcLaunchReadiness(canStart: false, detail: detail)
    }

    private static func cliProbe(globalRoot: String?) -> String {
        // Base64 keeps paths out of shell quoting. Resolving files never invokes npx's installer.
        let encoded = Data((globalRoot ?? "").utf8).base64EncodedString()
        let script = "const fs=require('fs'),path=require('path');try{const root=Buffer.from('\(encoded)','base64').toString();const file=require.resolve('@arc-fusion/cli/package.json',{paths:[process.cwd(),root].filter(Boolean)});const cli=require(file);const bin=typeof cli.bin==='string'?cli.bin:cli.bin&&cli.bin.fusion;if(!bin||!fs.existsSync(path.resolve(path.dirname(file),bin)))process.exit(2);console.log('devdeck-fusion-ready')}catch{process.exit(2)}"
        return "node -e \"\(script)\""
    }
}
