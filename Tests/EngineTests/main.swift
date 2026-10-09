import DevDeckCore
import DevDeckEngine
import DevDeckLocalization
import Foundation
import ProjectKit
import TestHarness

let run = TestRun()
run.section("Engine protocol and model checks")

await run.test("protocol rejects an incompatible version and oversized input") {
    do {
        _ = try DeckIntent.decode(
            Data("{\"protocolVersion\":1,\"id\":\"1\",\"intent\":\"session.start\"}".utf8))
        throw TestFailure(message: "Expected invalid version", file: #filePath, line: #line)
    } catch EngineProtocolError.invalidIntent {}
    do {
        _ = try DeckIntent.decode(Data(repeating: 32, count: 1_048_577))
        throw TestFailure(message: "Expected size limit", file: #filePath, line: #line)
    } catch EngineProtocolError.oversizedMessage {}
}

#if os(Windows)
await run.test("project liveness reads PID and probes it in one command") {
    let runner = StubCommandRunner([
        ("read -r pid", CommandResult(exitCode: 0, standardOutput: "42", standardError: ""))
    ])
    let project = LocalProject(
        id: "demo", title: "Demo", folder: "/demo", startCommand: "demo", holdsProcess: true)
    let status = await LocalProjectService(project: project, runner: runner).status()
    try expect(status.isRunning)
    try expectEqual(status.pid, 42)
    let commands = await runner.commands
    try expectEqual(commands.count, 1)
    try expect(commands[0].contains("kill -0"))
    try expect(commands[0].contains("boot_id"))
}
#endif

await run.test("plural forms retain English and Russian count rules") {
    Strings.use(.english, lookingIn: LocalizationResources.root)
    try expectEqual(LN("card.repos", 1), "1 repo")
    try expectEqual(LN("card.repos", 2), "2 repos")
    Strings.use(.russian, lookingIn: LocalizationResources.root)
    try expectEqual(LN("card.repos", 1), "1 репозиторий")
    try expectEqual(LN("card.repos", 2), "2 репозитория")
    try expectEqual(LN("card.repos", 5), "5 репозиториев")
    try expectEqual(LN("card.repos", 11), "11 репозиториев")
    try expectEqual(LN("card.repos", 21), "21 репозиторий")
}

await run.test("project paths select execution location without a UI choice") {
    func project(_ path: String, distribution: String? = nil) throws -> EngineConfiguration.Project {
        let object: [String: String] = [
            "id": "demo", "title": "Demo", "path": path,
            "startCommand": "demo", "healthURL": "http://example.invalid/",
            "distribution": distribution ?? "",
        ]
        return try JSONDecoder().decode(
            EngineConfiguration.Project.self, from: JSONSerialization.data(withJSONObject: object))
    }
    try expectEqual(try project("C:\\demo folder").executionLocation, .windows(path: "C:\\demo folder"))
    try expectEqual(
        try project("\\\\wsl.localhost\\Ubuntu-24.04\\home\\demo").executionLocation,
        .wsl(distribution: "Ubuntu-24.04", path: "/home/demo"))
    try expectEqual(
        try project("\\\\wsl$\\Demo\\workspace").executionLocation,
        .wsl(distribution: "Demo", path: "/workspace"))
    try expectEqual(
        try project("/demo", distribution: "Demo").executionLocation,
        .wsl(distribution: "Demo", path: "/demo"))
    try expect(try project("/demo").executionLocation == nil)
    try expect(try project("relative").executionLocation == nil)
}

await runRuntimeGoldenTests(run)
await runSessionGoldenTests(run)
run.finish()
