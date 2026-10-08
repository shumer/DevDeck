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

run.finish()
