import DevDeckCore
import DevDeckEngine
import DevDeckLocalization
import Foundation

func diagnostic(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let configFile: URL
    if arguments.count == 2, arguments[0] == "--config" {
        configFile = URL(fileURLWithPath: arguments[1])
    } else if arguments.isEmpty, let local = ProcessInfo.processInfo.environment["LOCALAPPDATA"] {
        configFile = URL(fileURLWithPath: local).appendingPathComponent("DevDeckPOC/config.json")
    } else {
        diagnostic("Provide --config with a non-secret configuration file.")
        exit(1)
    }
    let config = try EngineConfiguration.load(from: configFile)
    #if os(Windows)
    var runners: [String: any CommandRunning] = [:]
    for project in config.projects {
        switch project.executionLocation {
        case .windows:
            runners[project.id] = NativeWindowsCommandRunner()
        case .wsl(let distribution, _):
            runners[project.id] = ShellCommandRunner(distribution: distribution)
        case nil:
            throw EngineProtocolError.invalidConfiguration
        }
    }
    let runner: any CommandRunning = NativeWindowsCommandRunner()
    #else
    let runner = ShellCommandRunner()
    let runners: [String: any CommandRunning] = [:]
    #endif
    let engine = DevDeckEngine(
        configuration: config, runner: runner, projectRunners: runners,
        projectHTTP: URLSessionHTTPClient.makeDefault(timeout: 3),
        localizationRoot: LocalizationResources.root
    ) { data in
        FileHandle.standardOutput.write(data)
    }
    let input = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(32)) { continuation in
        DispatchQueue.global().async {
            var pending = Data()
            var oversized = false
            while true {
                let chunk = FileHandle.standardInput.availableData
                if chunk.isEmpty { break }
                for byte in chunk {
                    if byte == 10 {
                        if pending.last == 13 { pending.removeLast() }
                        if !oversized, !pending.isEmpty {
                            if case .dropped = continuation.yield(pending) {
                                diagnostic("Input queue is full.")
                            }
                        }
                        pending.removeAll(keepingCapacity: true)
                        oversized = false
                    } else if !oversized {
                        if pending.count >= 1_048_576 && !(pending.count == 1_048_576 && byte == 13) {
                            diagnostic("Input message exceeds 1 MiB.")
                            pending.removeAll(keepingCapacity: true)
                            oversized = true
                        } else {
                            pending.append(byte)
                        }
                    }
                }
            }
            if !pending.isEmpty { diagnostic("Incomplete input message.") }
            continuation.finish()
        }
    }
    for await line in input {
        do { await engine.handle(try EngineIntent.decode(line)) } catch {
            diagnostic("Invalid protocol message.")
        }
    }
    await engine.shutdown()
} catch {
    diagnostic("Could not load engine configuration.")
    exit(1)
}
