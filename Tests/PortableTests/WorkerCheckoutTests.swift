import DevDeckCore
import DevDeckWorkerProtocol
import Foundation
import TestHarness

private actor CheckoutRedRunner: CommandRunning {
    private var commands: [String] = []
    func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
             onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        commands.append(command)
        return CommandResult(exitCode: 0, standardOutput: "# branch.head main\n# branch.upstream origin/main\n# branch.ab +0 -0\n", standardError: "")
    }
    func recorded() -> [String] { commands }
}

private actor CheckoutScriptRunner: CommandRunning {
    enum Answer: Sendable { case output(String, Int32 = 0), timeout, cancelled, unavailable }
    struct Call: Sendable {
        let command: String; let path: String; let timeout: Double; let interactive: Bool; let progress: Bool
    }
    private var answers: [Answer]
    private var calls: [Call] = []
    init(_ answers: [Answer]) { self.answers = answers }
    func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
             onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        calls.append(.init(command: command, path: directory.path, timeout: timeout, interactive: isInteractive, progress: onOutput != nil))
        guard !answers.isEmpty else { throw CommandError.launchFailed("synthetic-secret-no-answer") }
        switch answers.removeFirst() {
        case .output(let text, let exit): return CommandResult(exitCode: exit, standardOutput: text, standardError: "synthetic-private-stderr")
        case .timeout: throw CommandError.timedOut("synthetic-private-timeout")
        case .cancelled: throw CancellationError()
        case .unavailable: throw CommandError.launchFailed("synthetic-private-launch")
        }
    }
    func recorded() -> [Call] { calls }
}
private actor CheckoutHeldRunner: CommandRunning {
    private var pending: CheckedContinuation<CommandResult, any Error>?
    private var calls = 0
    private var cancelled = false
    func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
             onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        calls += 1
        if calls > 1 { return .init(exitCode: 0, standardOutput: checkoutStatus(), standardError: "") }
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { pending = $0 }
        }, onCancel: { Task { await self.cancel() } })
    }
    private func cancel() { cancelled = true; pending?.resume(throwing: CancellationError()); pending = nil }
    func started() -> Bool { pending != nil }
    func wasCancelled() -> Bool { cancelled }
    func complete() { pending?.resume(returning: .init(exitCode: 0, standardOutput: checkoutStatus(files: "? original.txt\n"), standardError: "")); pending = nil }
}
private actor CheckoutSink {
    private var values: [WorkerResponse] = []
    func append(_ value: WorkerResponse) { values.append(value) }
    func responses() -> [WorkerResponse] { values }
}
private func checkoutFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-wif-" + UUID().uuidString + "-Ж папка")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}
private func checkoutStatus(branch: String = "main", upstream: Bool = true, ahead: Int = 0, behind: Int = 0, files: String = "") -> String {
    "# branch.oid 0123456789abcdef\n# branch.head \(branch)\n"
        + (upstream ? "# branch.upstream origin/main\n# branch.ab +\(ahead) -\(behind)\n" : "") + files
}
private func checkoutRequest(path: String, token: String = "pass", id: String = "project:δ", distribution: String = "Test", title: String = "Folder; $(never-run)") -> WorkerCheckoutRequest {
    .init(passToken: token, reference: .init(projectID: id, distribution: distribution, path: path, title: title))
}
private func checkoutBytes(_ checkout: WorkerCheckoutRequest, id: String = "checkout") throws -> Data {
    try JSONEncoder().encode(WorkerRequest(id: id, operation: "checkouts.snapshot", checkout: checkout))
}
private func checkoutWait(_ predicate: @escaping @Sendable () async -> Bool) async throws {
    for _ in 0..<1000 { if await predicate() { return }; await Task.yield() }
    throw TestFailure(message: "Synthetic checkout operation did not reach its expected state.", file: #filePath, line: #line)
}

func runWorkerCheckoutTests(_ run: TestRun, localization: WorkerStartupLocalization) async {
    run.section("Work in flight worker")
    await run.test("checkout snapshot is advertised by the actual worker dispatcher") {
        let runner = CheckoutRedRunner()
        let worker = WorkerService(distribution: "Test", runner: runner)
        let response = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "wif-hello", operation: "hello")))
        try expect(response.capabilities?.contains("checkouts.snapshot") == true)
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("actual checkout dispatch returns a typed missing-folder read rather than unsupported operation") {
        let runner = CheckoutRedRunner()
        let worker = WorkerService(distribution: "Test", runner: runner)
        let request: [String: Any] = ["protocolVersion": 1, "id": "wif-missing", "operation": "checkouts.snapshot",
            "checkout": ["cardID": "local.workInFlight", "passToken": "wif-red",
                "reference": ["projectID": "hidden", "distribution": "Test", "path": "/tmp/devdeck-wif-does-not-exist", "title": "Hidden"]]]
        let response = await worker.handle(try JSONSerialization.data(withJSONObject: request))
        try expectNil(response.error)
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as! [String: Any]
        let checkout = payload["checkout"] as? [String: Any]
        try expectEqual((checkout?["failure"] as? [String: Any])?["code"] as? String, "missingFolder")
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("clean and dirty upstream reads invoke only the fixed offline status command with exact cwd and deadline") {
        let folder = try checkoutFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let environment = ProcessInfo.processInfo.environment
        let runner = CheckoutScriptRunner([.output(checkoutStatus()), .output(checkoutStatus(files: "? file.txt\n"))])
        let worker = WorkerService(distribution: "Test", runner: runner)
        for dirty in [Int32(0), Int32(1)] {
            let response = await worker.handle(try checkoutBytes(checkoutRequest(path: folder.path)))
            try expectNil(response.error); try expectNil(response.attention); try expectNil(response.status)
            try expectNil(response.remote); try expectNil(response.powerOff); try expectNil(response.logs)
            try expectEqual(response.checkout?.state?.dirtyFiles, dirty)
            try expectEqual(response.checkout?.state?.urgent, false)
            try expectEqual(response.checkout?.state?.inFlight, dirty > 0)
            try expectEqual(response.checkout?.signals.count, 0)
        }
        let calls = await runner.recorded()
        try expectEqual(calls.count, 2)
        for call in calls {
            // A literal boundary catches an accidentally omitted/relaxed transport guard;
            // GIT_ALLOW_PROTOCOL must be present with an explicitly empty allowlist.
            try expectEqual(call.command, "env GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 GIT_ALLOW_PROTOCOL= " + WorkInFlight.command)
            try expectEqual(call.path, folder.path); try expectEqual(call.timeout, 20)
            try expect(!call.interactive && !call.progress)
            try expect(!call.command.contains("never-run"))
        }
        try expectEqual(ProcessInfo.processInfo.environment["GIT_OPTIONAL_LOCKS"], environment["GIT_OPTIONAL_LOCKS"])
        try expectEqual(ProcessInfo.processInfo.environment["GIT_NO_LAZY_FETCH"], environment["GIT_NO_LAZY_FETCH"])
        try expectEqual(ProcessInfo.processInfo.environment["GIT_ALLOW_PROTOCOL"], environment["GIT_ALLOW_PROTOCOL"])
        try expectEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }
    await run.test("urgent status uses shared local-history parsing and the first two original summary facts") {
        let folder = try checkoutFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let oldest = now.timeIntervalSince1970 - CheckoutAttention.unpushedAfter
        let runner = CheckoutScriptRunner([.output(checkoutStatus(ahead: 3, behind: 4, files: "1 changed\n? untracked\n")), .output("\(oldest)\n\(oldest + 1)\n")])
        let worker = WorkerService(distribution: "Test", runner: runner, dates: MutableDateProvider(now: now))
        let request = checkoutRequest(path: folder.path)
        let response = await worker.handle(try checkoutBytes(request))
        try expectNil(response.error); try expectNil(response.attention)
        let state = response.checkout?.state
        try expectEqual(state?.localCommits, 2); try expectEqual(state?.ahead, 3); try expectEqual(state?.behind, 4)
        try expectEqual(state?.oldestLocalCommitAt, oldest)
        try expectEqual(state?.summaryFacts.map(\.kind), ["changed", "unpushed"])
        try expectEqual(state?.summaryFacts.compactMap(\.count), [2, 3])
        try expectEqual(response.checkout?.checkedAt, now.timeIntervalSince1970)
        let signal = response.checkout?.signals.first
        try expectEqual(signal?.tier, "goodToKnow"); try expectEqual(signal?.mark, "unpushed")
        try expectEqual(signal?.action.kind, "openTerminal"); try expectEqual(signal?.action.path, folder.path)
        try expectEqual(signal?.action.checkout, .init(distribution: "Test", projectID: request.reference.projectID, path: folder.path))
        try expectEqual(signal?.dismissible, false); try expectEqual(signal?.since, oldest)
        let calls = await runner.recorded()
        try expectEqual(calls.map(\.command), [OfflineCheckoutRunner.prefix + WorkInFlight.command, OfflineCheckoutRunner.prefix + WorkInFlight.localCommitsCommand])
        try expect(calls.allSatisfy { $0.path == folder.path && $0.timeout == 20 })
    }
    await run.test("shared parser preserves rename merge untracked ignored detached no-upstream and behind-only eligibility") {
        let folder = try checkoutFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let cases = [checkoutStatus(files: "1 modified\n2 renamed\nu unmerged\n? directory/\n! ignored\n"),
            checkoutStatus(branch: "(detached)", upstream: false), checkoutStatus(behind: 2), checkoutStatus(upstream: false)]
        for text in cases {
            let original = WorkInFlight.parse(text, id: "project:δ", title: "Folder; $(never-run)")!
            let runner = CheckoutScriptRunner([.output(text), .output("")])
            let result = await WorkerCheckoutScanner(runner: runner).read(checkoutRequest(path: folder.path))
            try expectNil(result.failure)
            try expectEqual(result.state?.branch, original.branch)
            try expectEqual(result.state?.dirtyFiles, Int32(original.dirtyFiles))
            try expectEqual(result.state?.ahead, Int32(original.ahead)); try expectEqual(result.state?.behind, Int32(original.behind))
            try expectEqual(result.state?.inFlight, original.isInFlight); try expectEqual(result.state?.urgent, original.isUrgent)
            try expectEqual((await runner.recorded()).count, original.isUrgent ? 2 : 1)
            if !original.hasUpstream { try expectEqual(result.state?.summaryFacts.first?.kind, "noRemote"); try expectNil(result.state?.summaryFacts.first?.count) }
        }
    }
    await run.test("three-day informational eligibility is exactly shared including one-second-before future and zero local commits") {
        let folder = try checkoutFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for (upstream, age, count) in [(true, CheckoutAttention.unpushedAfter, 2), (false, CheckoutAttention.unpushedAfter, 1),
                                      (true, CheckoutAttention.unpushedAfter - 1, 1), (false, -1.0, 1), (true, CheckoutAttention.unpushedAfter, 0)] {
            let oldest = now.addingTimeInterval(-age)
            let log = count == 0 ? "" : Array(repeating: String(oldest.timeIntervalSince1970), count: count).joined(separator: "\n")
            let runner = CheckoutScriptRunner([.output(checkoutStatus(upstream: upstream, ahead: upstream ? 1 : 0)), .output(log)])
            let result = await WorkerCheckoutScanner(runner: runner, dates: MutableDateProvider(now: now)).read(checkoutRequest(path: folder.path))
            let state = CheckoutState(id: "project:δ", title: "Folder; $(never-run)", branch: "main", dirtyFiles: 0,
                ahead: upstream ? 1 : 0, behind: 0, hasUpstream: upstream, localCommits: count, oldestLocalCommitAt: count == 0 ? nil : oldest)
            let expected = CheckoutAttention.items(checkouts: [state], folders: [state.id: folder], now: now)
            try expectEqual(result.signals.count, expected.count)
            try expectEqual(result.signals.first?.title, expected.first?.title)
            try expectEqual(result.signals.first?.subtitle, expected.first?.subtitle)
            if !expected.isEmpty {
                try expectEqual(result.signals.first?.mark, upstream ? "unpushed" : "noRemote")
                try expectEqual(result.signals.first?.tier, "goodToKnow")
                try expectNil(AttentionDigest(items: expected).iconTier)
                try expectEqual(result.signals.first?.dismissible, false)
                try expectNil(result.signals.first?.action.cardID); try expectNil(result.signals.first?.action.accountID)
            }
        }
    }
    await run.test("tuple signal identities stay distinct for delimiter Unicode distro and project aliases") {
        let tuples = [("a:b", "c"), ("a", "b:c"), ("Ubuntu", "δ:1"), ("Debian", "δ:1"), ("Ж", "a")]
        let keys = tuples.map { WorkerCheckoutScanner.signalIdentity(distribution: $0.0, projectID: $0.1, hasUpstream: true) }
        try expectEqual(Set(keys).count, tuples.count)
        try expectEqual(keys.last, "checkout:2:Ж:1:a:unpushed")
        try expect(WorkerCheckoutScanner.signalIdentity(distribution: "a", projectID: "b", hasUpstream: true)
            != WorkerCheckoutScanner.signalIdentity(distribution: "a", projectID: "b", hasUpstream: false))
    }
    await run.test("status command failure timeout cancellation unavailable and oversized output export only closed diagnostics") {
        let folder = try checkoutFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let cases: [(CheckoutScriptRunner.Answer, String)] = [(.output("synthetic-private-secret", 1), "statusFailed"),
            (.output("synthetic-private-secret", 127), "gitUnavailable"), (.timeout, "timedOut"), (.cancelled, "cancelled"),
            (.unavailable, "runnerUnavailable"), (.output(String(repeating: "x", count: WorkerProtocol.maximumFrameBytes)), "outputTooLarge")]
        for (answer, code) in cases {
            let runner = CheckoutScriptRunner([answer])
            let worker = WorkerService(distribution: "Test", runner: runner)
            let response = await worker.handle(try checkoutBytes(checkoutRequest(path: folder.path)))
            try expectNil(response.error); try expectNil(response.checkout?.state)
            try expectEqual(response.checkout?.failure, .init(stage: "status", code: code))
            try expectEqual(response.checkout?.signals.count, 0)
            let wire = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
            try expect(!wire.contains("synthetic-private")); try expect(!wire.contains("synthetic-secret"))
            try expectEqual((await runner.recorded()).count, 1)
        }
    }
    await run.test("local history failure retains valid status without fabricating age or informational signals") {
        let folder = try checkoutFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        for (answer, code) in [(CheckoutScriptRunner.Answer.timeout, "timedOut"), (.output("private-error", 1), "localCommitsFailed"),
                               (.output("nan\n"), "invalidState"), (.output("-1\n"), "invalidState"), (.output("9999999999999\n"), "invalidState")] {
            let runner = CheckoutScriptRunner([.output(checkoutStatus(ahead: 4, files: "? dirty\n")), answer])
            let result = await WorkerCheckoutScanner(runner: runner).read(checkoutRequest(path: folder.path))
            try expectEqual(result.failure, .init(stage: "localCommits", code: code))
            try expectEqual(result.state?.ahead, 4); try expectEqual(result.state?.dirtyFiles, 1)
            try expectEqual(result.state?.localCommits, 0); try expectNil(result.state?.oldestLocalCommitAt)
            try expect(result.signals.isEmpty)
        }
    }
    await run.test("malformed porcelain cannot become a fabricated clean state or crash the shared integer parser") {
        let folder = try checkoutFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        for output in ["", "not porcelain", "# branch.head main\n# branch.head other\n", "# branch.head main\nunknown record\n",
            "# branch.head \n", "# branch.head main\tsecret\n", checkoutStatus(branch: String(repeating: "Ж", count: 257)),
            "# branch.head main\n# branch.upstream origin/main\n# branch.ab +9999999999999999999999 -1\n",
            "# branch.head main\n# branch.upstream origin/main\n# branch.ab +-9223372036854775808 -1\n",
            "# branch.head main\n# branch.ab +1 -2\n"] {
            let runner = CheckoutScriptRunner([.output(output)])
            let result = await WorkerCheckoutScanner(runner: runner).read(checkoutRequest(path: folder.path))
            try expectNil(result.state); try expectEqual(result.failure, .init(stage: "status", code: "invalidState"))
            try expect(result.signals.isEmpty); try expectEqual((await runner.recorded()).count, 1)
        }
    }
    await run.test("direct and Session reject invalid checkout envelopes before missing-folder or any runner work") {
        let runner = CheckoutScriptRunner([])
        let worker = WorkerService(distribution: "Test", runner: runner)
        let valid = checkoutRequest(path: "/tmp/devdeck-wif-no-folder")
        let base = try JSONSerialization.jsonObject(with: checkoutBytes(valid)) as! [String: Any]
        var invalid: [[String: Any]] = []
        for (key, value) in [("cardID", "wrong"), ("passToken", ""), ("passToken", String(repeating: "Ж", count: 65))] {
            var envelope = base; var checkout = envelope["checkout"] as! [String: Any]; checkout[key] = value; envelope["checkout"] = checkout; invalid.append(envelope)
        }
        for (key, value) in [("projectID", "\n"), ("projectID", String(repeating: "x", count: 129)), ("distribution", "Foreign"),
                             ("title", ""), ("title", String(repeating: "Ж", count: 257)), ("path", "relative"), ("path", "/tmp/../hidden"),
                             ("path", "//server/share"), ("path", "/tmp/\\windows"), ("path", "/tmp/\u{0}"), ("path", "/" + String(repeating: "x", count: 4096))] {
            var envelope = base; var checkout = envelope["checkout"] as! [String: Any]; var reference = checkout["reference"] as! [String: Any]
            reference[key] = value; checkout["reference"] = reference; envelope["checkout"] = checkout; invalid.append(envelope)
        }
        for (key, value) in [("project", ["id": "x", "distribution": "Test", "kind": "ddev", "path": "/missing"] as Any),
            ("remote", ["cardID": "x", "kind": "pullRequests", "accounts": []] as Any), ("powerOff", ["groupToken": "x"] as Any),
            ("activeProjectIDs", [] as Any), ("refreshCycle", "cycle" as Any), ("targetRequestID", "cancelled" as Any)] {
            var envelope = base; envelope[key] = value; invalid.append(envelope)
        }
        var absent = base; absent.removeValue(forKey: "checkout"); invalid.append(absent)
        var foreignOperation = base; foreignOperation["operation"] = "hello"; invalid.append(foreignOperation)
        let sink = CheckoutSink(); let session = WorkerSession(service: worker) { await sink.append($0) }
        for (index, var envelope) in invalid.enumerated() {
            envelope["id"] = "invalid-\(index)"
            let bytes = try JSONSerialization.data(withJSONObject: envelope)
            let response = await worker.handle(bytes)
            try expectEqual(response.error?.code, "invalidRequest"); try expectNil(response.checkout)
            await session.accept(.data(bytes))
        }
        try expectEqual((await sink.responses()).count, invalid.count)
        try expect((await sink.responses()).allSatisfy { $0.error?.code == "invalidRequest" })
        try expectEqual((await runner.recorded()).count, 0)
        await session.close()
    }
    await run.test("protocol version request identity and frame bounds are enforced before checkout execution") {
        let runner = CheckoutScriptRunner([])
        let worker = WorkerService(distribution: "Test", runner: runner)
        let checkout = checkoutRequest(path: "/tmp/devdeck-wif-no-folder")
        let badVersion = WorkerRequest(protocolVersion: 2, id: "version", operation: "checkouts.snapshot", checkout: checkout)
        try expectEqual((await worker.handle(try JSONEncoder().encode(badVersion))).error?.code, "unsupportedVersion")
        for id in ["", "bad\n", String(repeating: "Ж", count: 65)] {
            try expectEqual((await worker.handle(try checkoutBytes(checkout, id: id))).error?.code, "invalidRequestID")
        }
        try expectEqual((await worker.handle(Data(repeating: 32, count: WorkerProtocol.maximumFrameBytes + 1))).error?.code, "frameTooLarge")
        try expectEqual((await runner.recorded()).count, 0)
    }
    await run.test("independent delayed replies keep exact pass identity and never attach runtime attention or another checkout cache") {
        let folder = try checkoutFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let runner = CheckoutHeldRunner()
        let worker = WorkerService(distribution: "Test", runner: runner)
        let old = Task { await worker.handle(try! checkoutBytes(checkoutRequest(path: folder.path, token: "old"), id: "old")) }
        try await checkoutWait { await runner.started() }
        let current = await worker.handle(try checkoutBytes(checkoutRequest(path: folder.path, token: "new"), id: "new"))
        try expectEqual(current.checkout?.passToken, "new"); try expectEqual(current.checkout?.state?.dirtyFiles, 0)
        await runner.complete()
        let previous = await old.value
        try expectEqual(previous.checkout?.passToken, "old"); try expectEqual(previous.checkout?.state?.dirtyFiles, 1)
        try expectNil(previous.attention); try expectNil(current.attention)
        try expectEqual(previous.checkout?.projectID, current.checkout?.projectID)
        try expect(!(await runner.wasCancelled()))
    }
    await run.test("actual Session cancellation reaps only its checkout child and returns typed cancellation with no log or progress") {
        let folder = try checkoutFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let runner = CheckoutHeldRunner(); let worker = WorkerService(distribution: "Test", runner: runner)
        let sink = CheckoutSink(); let session = WorkerSession(service: worker) { await sink.append($0) }
        await session.accept(.data(try checkoutBytes(checkoutRequest(path: folder.path), id: "held")))
        try await checkoutWait { await runner.started() }
        await session.accept(.data(try JSONEncoder().encode(WorkerRequest(id: "cancel", operation: "cancel", targetRequestID: "held"))))
        try await checkoutWait { await sink.responses().contains { $0.id == "held" } }
        let cancelled = await sink.responses().first { $0.id == "held" }
        try expectEqual(cancelled?.checkout?.failure, .init(stage: "status", code: "cancelled"))
        try expectNil(cancelled?.checkout?.state); try expectNil(cancelled?.attention); try expectNil(cancelled?.event)
        try expect(await runner.wasCancelled())
        await session.close()
    }
    await run.test("optional wire fields preserve legacy hello JSON and required empty checkout signals remain explicit") {
        let runner = CheckoutRedRunner(); let worker = WorkerService(distribution: "Test", runner: runner)
        let legacy = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "legacy", operation: "hello")))
        let legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        try expectNil(legacyJSON["checkout"])
        let request = checkoutRequest(path: "/tmp/devdeck-wif-no-folder")
        let response = await worker.handle(try checkoutBytes(request))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as! [String: Any]
        let result = json["checkout"] as! [String: Any]
        try expectEqual((result["signals"] as? [Any])?.count, 0)
        try expectEqual(result["passToken"] as? String, request.passToken)
        try expectEqual(result["path"] as? String, request.reference.path)
        for key in ["status", "remote", "projects", "logs", "suggestion", "powerOff", "attention", "error"] { try expectNil(json[key]) }
        let action = try JSONDecoder().decode(WorkerAttentionAction.self, from: Data(#"{"kind":"openTerminal","path":"/tmp/legacy"}"#.utf8))
        let actionJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(action)) as! [String: Any]
        try expectNil(actionJSON["checkout"])
    }
    for language in AppLanguage.allCases where language != .system {
        await run.test("production localization bootstrap safely emits aged checkout signals in \(language.rawValue)") {
            try localization.use(language)
            defer { try? localization.use(.english) }
            let folder = try checkoutFolder(); defer { try? FileManager.default.removeItem(at: folder) }
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let oldest = now.timeIntervalSince1970 - CheckoutAttention.unpushedAfter
            let runner = CheckoutScriptRunner([.output(checkoutStatus(ahead: 1)), .output("\(oldest)\n\(oldest + 1)\n")])
            let worker = WorkerService(distribution: "Test", runner: runner, dates: MutableDateProvider(now: now))
            let request = checkoutRequest(path: folder.path)
            let response = await worker.handle(try checkoutBytes(request))
            try expectNil(response.error); try expectNil(response.checkout?.failure)
            let signal = response.checkout?.signals.first
            try expectEqual(response.checkout?.signals.count, 1)
            try expectEqual(signal?.id, "checkout:4:Test:10:project:δ:unpushed")
            try expectEqual(signal?.key, signal?.id); try expectEqual(signal?.tier, "goodToKnow")
            try expectEqual(signal?.action.checkout?.distribution, "Test")
            try expectEqual(signal?.since, oldest); try expectEqual(response.checkout?.state?.localCommits, 2)
            try expect(signal?.title.contains("2") == true)
            try expect(signal?.subtitle.contains("main") == true && signal?.subtitle.contains("3") == true)
            try expect(signal?.title.contains("attention.local") == false)
            try expect(signal?.subtitle.contains("attention.local") == false)
            let chosen = localization.root.appendingPathComponent(language.rawValue + ".lproj")
            try expect(!FileManager.default.fileExists(atPath: chosen.appendingPathComponent("Localizable.stringsdict").path))
            try expect(!FileManager.default.fileExists(atPath: localization.root.appendingPathComponent("en.lproj/Localizable.stringsdict").path))
            let decoded = try JSONDecoder().decode(WorkerResponse.self, from: JSONEncoder().encode(response))
            try expectEqual(decoded.checkout?.signals.first?.action.checkout, signal?.action.checkout)
            try expectEqual(decoded.checkout?.state?.oldestLocalCommitAt, oldest)
        }
    }
    await run.test("localization setup failure is bounded and cleans its own temporary copy without selecting an unsafe fallback") {
        let temporary = FileManager.default.temporaryDirectory
        func ownedRoots() throws -> Set<String> {
            Set(try FileManager.default.contentsOfDirectory(atPath: temporary.path).filter { $0.hasPrefix("devdeck-worker-localization-") })
        }
        let before = try ownedRoots()
        let missing = temporary.appendingPathComponent("devdeck-missing-localization-" + UUID().uuidString)
        do {
            _ = try WorkerStartupLocalization(originalRoot: missing)
            throw TestFailure(message: "Missing worker resources must fail setup.", file: #filePath, line: #line)
        } catch WorkerStartupLocalization.Failure.unavailable { }
        try expectEqual(try ownedRoots(), before)
        try expectEqual(Strings.current, .english)
        let original = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Localizations")
        let copy = try WorkerStartupLocalization(originalRoot: original)
        try expect(FileManager.default.fileExists(atPath: copy.root.path))
        copy.close()
        try expect(!FileManager.default.fileExists(atPath: copy.root.path))
        try expectEqual(try ownedRoots(), before)
    }
}
