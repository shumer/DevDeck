import DevDeckCore
import DevDeckWorkerProtocol
import Foundation
import Glibc

var passed = 0
var failed = 0
@MainActor func check(_ name: String, _ body: @MainActor () async throws -> Void) async {
    do { try await body(); passed += 1; print("ok  \(name)") }
    catch { failed += 1; print("FAIL \(name): \(error)") }
}
func require(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: message, code: 1) }
}
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck worker live \(UUID().uuidString)")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let runner = WSLCommandRunner(shell: "/bin/bash")

func waitForFile(_ name: String) async throws -> Int32 {
    let file = folder.appendingPathComponent(name)
    for _ in 0..<200 {
        if let contents = try? String(contentsOf: file, encoding: .utf8), let pid = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines)) { return pid }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw NSError(domain: "process did not report its pid", code: 1)
}
func dead(_ pid: Int32) -> Bool {
    if kill(pid, 0) != 0 { return true }
    // A dead child awaiting its init/subreaper is no longer an executable process.
    let status = try? String(contentsOfFile: "/proc/\(pid)/status", encoding: .utf8)
    return status?.split(separator: "\n").contains(where: { $0.hasPrefix("State:") && $0.contains("Z") }) == true
}
let childCommand = "sh -c 'echo $$ > child.pid; trap \"\" TERM; while :; do sleep 1; done' & echo $$ > parent.pid; wait"

await check("Linux session runner preserves spaced cwd and drains both streams") {
    let result = try await runner.run("printf '%s' \"$PWD\"; printf error >&2", in: folder, timeout: 5)
    try require(result.succeeded && result.standardOutput == folder.path && result.standardError == "error", "cwd or streams differed")
}
await check("interactive PATH probe actually launches an interactive shell") {
    let result = try await runner.run("case $- in *i*) printf interactive;; *) printf wrong;; esac", in: folder, timeout: 5, isInteractive: true)
    try require(result.standardOutput == "interactive", "shell ignored interactive flag")
}
await check("large output remains bounded while both pipes drain") {
    let result = try await runner.run("yes output | head -c 2000000; yes error | head -c 2000000 >&2", in: folder, timeout: 5)
    try require(result.standardOutput.utf8.count <= WorkerProtocol.maximumFrameBytes && result.standardError.utf8.count <= WorkerProtocol.maximumFrameBytes, "output exceeded bounds")
}
await check("deadline kills a parent and a child that ignores SIGTERM") {
    let task = Task { try await runner.run(childCommand, in: folder, timeout: 0.3) }
    let parent = try await waitForFile("parent.pid"), child = try await waitForFile("child.pid")
    do { _ = try await task.value; throw NSError(domain: "timeout did not fail", code: 1) }
    catch let error as CommandError { if case .timedOut = error { } else { throw error } }
    try require(dead(parent) && dead(child), "an owned descendant survived timeout")
}
try? FileManager.default.removeItem(at: folder.appendingPathComponent("parent.pid"))
try? FileManager.default.removeItem(at: folder.appendingPathComponent("child.pid"))
await check("task cancellation kills the owned process session and keeps the runner usable") {
    let task = Task { try await runner.run(childCommand, in: folder, timeout: 30) }
    let parent = try await waitForFile("parent.pid"), child = try await waitForFile("child.pid")
    task.cancel()
    do { _ = try await task.value; throw NSError(domain: "cancellation did not fail", code: 1) }
    catch is CancellationError { }
    try require(dead(parent) && dead(child), "an owned descendant survived cancellation")
    let next = try await runner.run("printf recovered", in: folder, timeout: 5)
    try require(next.standardOutput == "recovered", "runner could not recover")
}
await check("missing shell is reported without a hanging pipe") {
    do { _ = try await WSLCommandRunner(shell: "/missing/devdeck-shell").run("true", in: folder, timeout: 1); throw NSError(domain: "missing shell accepted", code: 1) }
    catch let error as NSError { try require(error.domain == NSPOSIXErrorDomain, "wrong launch error") }
}

let genericID = "local.project.live-\(UUID().uuidString)"
let generic = WorkerProject(id: genericID, distribution: "LiveTests", kind: .local, path: folder.path,
                            startCommand: childCommand, holdsProcess: true)
let service = WorkerService(distribution: "LiveTests", runner: runner)
func call(_ operation: String, project: WorkerProject = generic) async throws -> WorkerResponse {
    await service.handle(try JSONEncoder().encode(WorkerRequest(id: UUID().uuidString, operation: "project." + operation, project: project)))
}
let key = Data(genericID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
let runtime = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share/devdeck/projects")
defer {
    for name in [key + ".log", key + ".pid", key + ".pid.identity"] { try? FileManager.default.removeItem(at: runtime.appendingPathComponent(name)) }
}
try? FileManager.default.removeItem(at: folder.appendingPathComponent("parent.pid"))
try? FileManager.default.removeItem(at: folder.appendingPathComponent("child.pid"))
await check("generic start is idempotent and stop kills its session including a SIGTERM-ignoring child") {
    let started = try await call("start")
    try require(started.status?.state == "running", "generic did not start: \(String(describing: started.error))")
    let parent = try await waitForFile("parent.pid"), child = try await waitForFile("child.pid")
    let original = try String(contentsOf: runtime.appendingPathComponent(key + ".pid"), encoding: .utf8)
    let repeated = try await call("start")
    let current = try String(contentsOf: runtime.appendingPathComponent(key + ".pid"), encoding: .utf8)
    try require(repeated.status?.state == "running" && current == original, "start created a duplicate process")
    let stopped = try await call("stop")
    try require(stopped.status?.state == "stopped" && dead(parent) && dead(child), "generic stop left an owned descendant")
}
await check("generic restart from stopped starts a new owned session") {
    let restarted = try await call("restart")
    try require(restarted.status?.state == "running", "stopped generic could not restart")
    let stopped = try await call("stop")
    try require(stopped.status?.state == "stopped", "restarted generic could not stop")
}
await check("a replaced PID file cannot stop a different owned test process") {
    let outside = Task { try await runner.run("echo $$ > outsider.pid; sleep 30", in: folder, timeout: 40) }
    let outsider = try await waitForFile("outsider.pid")
    try Data(String(outsider).utf8).write(to: runtime.appendingPathComponent(key + ".pid"), options: .atomic)
    let stopped = try await call("stop")
    try require(stopped.error?.code == "commandFailed" && !dead(outsider), "a stale PID caused an unrelated process to be stopped")
    outside.cancel()
    _ = try? await outside.value
}
try? FileManager.default.removeItem(at: folder.appendingPathComponent("parent.pid"))
try? FileManager.default.removeItem(at: folder.appendingPathComponent("child.pid"))
await check("cancelling readiness removes only the generic session started by that operation") {
    let starting = WorkerProject(id: genericID, distribution: "LiveTests", kind: .local, path: folder.path,
                                 startCommand: childCommand, holdsProcess: true, healthURL: "http://127.0.0.1:1/")
    let task = Task { try await call("start", project: starting) }
    let parent = try await waitForFile("parent.pid"), child = try await waitForFile("child.pid")
    task.cancel()
    let response = try await task.value
    try require(response.error?.code == "cancelled" && dead(parent) && dead(child), "cancelled readiness left its owned server")
}
print("Linux worker process checks: \(passed) passed, \(failed) failed.")
exit(failed == 0 ? 0 : 1)
