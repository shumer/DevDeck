import DevDeckWorkerProtocol
import DevDeckCore
import Foundation
import Glibc

let arguments = CommandLine.arguments
guard [3, 5].contains(arguments.count), arguments[1] == "--distribution", !arguments[2].isEmpty,
      arguments[2].utf8.count <= 128,
      !arguments[2].unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
    FileHandle.standardError.write(Data("Usage: DevDeckWorker --distribution <WSL distribution> [--language en|ru|de|es|fr|it]\n".utf8))
    exit(64)
}
let distribution = arguments[2]
let languageCode = arguments.count == 5 ? arguments[4] : "en"
guard (arguments.count == 3 || arguments[3] == "--language"), let language = AppLanguage(rawValue: languageCode), language != .system else { exit(64) }
if let actual = ProcessInfo.processInfo.environment["WSL_DISTRO_NAME"], actual != distribution {
    FileHandle.standardError.write(Data("Distribution does not match this WSL process.\n".utf8))
    exit(64)
}
let tables = URL(fileURLWithPath: arguments[0]).deletingLastPathComponent().appendingPathComponent("Localizations")
let localization: WorkerStartupLocalization
do {
    localization = try WorkerStartupLocalization(originalRoot: tables)
    try localization.use(language)
} catch {
    FileHandle.standardError.write(Data("Worker localization tables are unavailable.\n".utf8))
    exit(78)
}
defer { localization.close() }
let runner: WSLCommandRunner
#if DEBUG
// Test harnesses isolate CLI/PATH discovery in an owned fixture. Release builds omit this hook.
if ProcessInfo.processInfo.environment["DEVDECK_ALLOW_TEST_SHELL"] == "1",
   let shell = ProcessInfo.processInfo.environment["DEVDECK_WORKER_TEST_SHELL"],
   WorkerService.isLinuxPath(shell), FileManager.default.isExecutableFile(atPath: shell) {
    runner = WSLCommandRunner(shell: shell)
} else { runner = WSLCommandRunner() }
#else
runner = WSLCommandRunner()
#endif
let service = WorkerService(distribution: distribution, runner: runner)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]

actor OutputChannel {
    func respond(_ response: WorkerResponse) {
        do {
    var data = try encoder.encode(response)
    if data.count > WorkerProtocol.maximumFrameBytes {
        data = try encoder.encode(service.failure(response.id, "responseTooLarge", "Response exceeds the frame limit."))
    }
    data.append(10)
    try FileHandle.standardOutput.write(contentsOf: data)
        } catch { /* The host may close stdout during cancellation; cleanup must still run. */ }
    }
}

signal(SIGPIPE, SIG_IGN)
let output = OutputChannel()
let session = WorkerSession(service: service) { response in await output.respond(response) }
let input = Task.detached {
    var framer = WorkerFramer()
    do {
    // FileHandle.read(upToCount:) may fill the buffer on Linux pipes, waiting for EOF.
    // One POSIX read returns the currently delivered bytes, allowing an interactive client.
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = buffer.withUnsafeMutableBytes { Glibc.read(STDIN_FILENO, $0.baseAddress, $0.count) }
        if count == 0 { break }
        if count < 0 {
            if errno == EINTR { continue }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let chunk = Data(buffer.prefix(count))
        for frame in framer.feed(chunk) { await session.accept(frame) }
    }
    for frame in framer.finish() { await session.accept(frame) }
    } catch {
        FileHandle.standardError.write(Data("Worker transport closed.\n".utf8))
    }
    await session.close()
}
await input.value
