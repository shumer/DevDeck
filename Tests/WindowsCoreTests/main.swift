import DevDeckCore
import Foundation
import ProjectKit
import TestHarness

let run = TestRun()
run.section("Windows core - offline platform checks")

await run.test("conditional HTTP responses retain their cached body") {
    let body = Data("fixture".utf8)
    let client = FakeHTTPClient([
        .success(HTTPResponse(statusCode: 200, headers: ["ETag": "\"fixture\""], body: body)),
        .success(HTTPResponse(statusCode: 304)),
    ])
    let transport = APITransport(client: client)
    let request = HTTPRequest(url: URL(string: "https://example.invalid/demo")!, cacheKey: "demo")
    _ = try await transport.perform(request)
    let response = try await transport.perform(request)
    try expectEqual(response.body, body)
    try expect(response.wasNotModified)
    let requests = await client.requests
    try expectEqual(requests.count, 2)
    try expectEqual(requests[1].headers["If-None-Match"], "\"fixture\"")
}

await run.test("a rejected credential remains an error") {
    let client = FakeHTTPClient([.success(HTTPResponse(statusCode: 401))])
    let transport = APITransport(client: client)
    do {
        _ = try await transport.perform(HTTPRequest(url: URL(string: "https://example.invalid/demo")!))
        throw TestFailure(message: "Expected unauthorized", file: #filePath, line: #line)
    } catch let error as APIError {
        try expectEqual(error, .unauthorized)
    }
    let count = await client.requestCount
    try expectEqual(count, 1)
}

await run.test("Windows standard tokens are scoped to one in-memory store") {
    let first = CompositeTokenStore.standard()
    try first.setToken("fixture", for: .github)
    try expectEqual(try first.token(for: .github), "fixture")
    try expectNil(try CompositeTokenStore.standard().token(for: .github))
    try first.setToken(nil, for: .github)
    try expectNil(try first.token(for: .github))
}

await run.test("Credential Manager keeps a token, reads it back and forgets it") {
    // Its own service name, so a real token is never touched.
    let key = TokenKey(service: "com.shumer.devdeck.tests", account: "credential-\(UUID().uuidString)")
    let store = WindowsCredentialTokenStore()
    try expectNil(try store.token(for: key), "nothing there to begin with")
    try store.setToken("fixture-token", for: key)
    try expectEqual(try store.token(for: key), "fixture-token")
    try store.setToken("fixture-token-2", for: key)
    try expectEqual(try store.token(for: key), "fixture-token-2", "a second write replaces the first")
    try store.setToken(nil, for: key)
    try expectNil(try store.token(for: key))
    try store.setToken(nil, for: key)
}

await run.test("a WSL folder is handed to wsl.exe as the distribution sees it") {
    let unc = URL(fileURLWithPath: #"\\wsl.localhost\Ubuntu-24.04\home\demo\site"#)
    try expectEqual(WSLCommandRunner.linuxPath(unc, "Ubuntu-24.04"), "/home/demo/site")
    let legacy = URL(fileURLWithPath: #"\\wsl$\Ubuntu-24.04\srv\app"#)
    try expectEqual(WSLCommandRunner.linuxPath(legacy, "Ubuntu-24.04"), "/srv/app")
}

await run.test("a local address ignores virtual and unavailable adapters") {
    let adapters = [
        LocalAddress.Adapter(
            name: "vEthernet (WSL)", description: "Hyper-V Virtual Ethernet Adapter",
            address: "172.20.0.1", isUp: true, isLoopback: false, isWireless: false),
        LocalAddress.Adapter(
            name: "VPN", description: "WireGuard Tunnel",
            address: "10.10.0.2", isUp: true, isLoopback: false, isWireless: false),
        LocalAddress.Adapter(
            name: "Ethernet", description: "Physical Ethernet Adapter",
            address: "192.168.1.20", isUp: true, isLoopback: false, isWireless: false),
        LocalAddress.Adapter(
            name: "Wi-Fi", description: "Physical Wireless Adapter",
            address: "192.168.1.21", isUp: true, isLoopback: false, isWireless: true),
        LocalAddress.Adapter(
            name: "Old Ethernet", description: "Physical Ethernet Adapter",
            address: "192.168.1.22", isUp: false, isLoopback: false, isWireless: false),
    ]
    try expectEqual(
        LocalAddress.preferredAddresses(from: adapters),
        ["192.168.1.21", "192.168.1.20"])
}

await run.test("Windows code identity is unsigned") {
    try expectEqual(CodeIdentity.current(), .unsigned)
    try expectEqual(CodeIdentity.kind(ofBundleAt: URL(fileURLWithPath: "C:/demo")), .unsigned)
}

await run.test("detached project commands use bash and quote their input") {
    let command = LocalProjectService.detachedCommand(
        "printf 'demo'", log: URL(fileURLWithPath: "/tmp/demo.log"),
        pidFile: URL(fileURLWithPath: "/tmp/demo.pid")
    )
    try expect(command.contains("nohup /bin/bash -lc"))
    try expect(command.contains(LocalProjectService.shellQuoted("printf 'demo'")))
    try expect(command.contains("2>&1 & echo $!"))
}

await run.test("project health keeps the existing serving rules") {
    try expect(LocalProjectService.isServing(200))
    try expect(LocalProjectService.isServing(302))
    try expect(LocalProjectService.isServing(401))
    try expect(!LocalProjectService.isServing(404))
    try expect(!LocalProjectService.isServing(500))
}

await run.test("file preferences survive reopening and keep their value types") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DevDeck-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("preferences.json")
    let backend = FilePreferencesBackend(file: file)
    backend.set("demo", forKey: "label")
    backend.set(Data([1, 2, 3]), forKey: "data")
    backend.set(true, forKey: "enabled")
    let reopened = FilePreferencesBackend(file: file)
    try expectEqual(reopened.string(forKey: "label"), "demo")
    try expectEqual(reopened.data(forKey: "data"), Data([1, 2, 3]))
    try expect(reopened.bool(forKey: "enabled"))
    try expectNil(reopened.string(forKey: "enabled"))
    reopened.set(nil as String?, forKey: "label")
    try expect(!FilePreferencesBackend(file: file).hasValue(forKey: "label"))
}

await run.test("an unsuccessful preference write keeps the previous state") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DevDeck-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let blocked = directory.appendingPathComponent("blocked")
    try Data("demo".utf8).write(to: blocked)
    let backend = FilePreferencesBackend(file: blocked.appendingPathComponent("preferences.json"))
    backend.set("demo", forKey: "label")
    try expect(!backend.hasValue(forKey: "label"))
}

run.section("Windows core - a WSL project's stop")

/// Answers by the first matching fragment of a command, or throws for it, as a WSL that is slow
/// to answer does.
actor ScriptedRunner: CommandRunning {
    enum Answer: Sendable {
        case result(CommandResult)
        case failure(CommandError)
    }

    private let answers: [(match: String, answer: Answer)]

    init(_ answers: [(String, Answer)]) {
        self.answers = answers.map { (match: $0.0, answer: $0.1) }
    }

    func run(
        _ command: String,
        in directory: URL,
        timeout: TimeInterval,
        isInteractive: Bool,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> CommandResult {
        guard let found = answers.first(where: { command.contains($0.match) }) else {
            return CommandResult(exitCode: 127, standardOutput: "", standardError: "command not found")
        }
        switch found.answer {
        case .result(let result): return result
        case .failure(let error): throw error
        }
    }
}

func wslProject() -> LocalProject {
    LocalProject(
        id: "m1-wsl",
        title: "Demo",
        folder: FileManager.default.temporaryDirectory.path,
        startCommand: "npm run dev",
        holdsProcess: true
    )
}

await run.test("a WSL that does not answer is not a project with nothing to stop") {
    let runner = ScriptedRunner([("boot_id", .failure(.timedOut("WSL command")))])
    let result = await LocalProjectService(project: wslProject(), runner: runner).perform(.stop)
    let failed = try expectNotNil(result, "a stop that could not ask must say so")
    try expect(!failed.succeeded)
    try expectEqual(
        failed.standardError,
        "could not ask WSL for the project's process: WSL command timed out"
    )
}

await run.test("a WSL timeout keeps the cause when cleanup cannot be verified") {
    let runner = ScriptedRunner([
        ("boot_id", .failure(.timedOut("WSL command timed out; its cleanup could not be verified"))),
    ])
    let result = await LocalProjectService(project: wslProject(), runner: runner).perform(.stop)
    let failed = try expectNotNil(result, "a stop that could not clean up must say why")
    try expectEqual(
        failed.standardError,
        "could not ask WSL for the project's process: "
            + "WSL command timed out; its cleanup could not be verified"
    )
}

await run.test("no recorded process is nothing to stop") {
    let runner = ScriptedRunner([("boot_id", .result(CommandResult(exitCode: 1, standardOutput: "", standardError: "")))])
    let result = await LocalProjectService(project: wslProject(), runner: runner).perform(.stop)
    try expectNil(result)
}

await run.test("a stop that does not finish says so instead of looking done") {
    let runner = ScriptedRunner([
        ("boot_id", .result(CommandResult(exitCode: 0, standardOutput: "4242", standardError: ""))),
        ("freeze_tree", .failure(.timedOut("WSL command"))),
    ])
    let result = await LocalProjectService(project: wslProject(), runner: runner).perform(.stop)
    let failed = try expectNotNil(result, "a stop that timed out must say so")
    try expect(failed.standardError.contains("stop did not finish"), "got: \(failed.standardError)")
}

run.finish()
