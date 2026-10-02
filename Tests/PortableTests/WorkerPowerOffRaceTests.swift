import DevDeckCore
import DevDeckWorkerProtocol
import Foundation
import TestHarness

/// Every command answer is synthetic. Continuations model readers/CLI children without a shell.
private actor PowerOffRaceRunner: CommandRunning {
    private let paths: [String]
    private let heldLists: Set<Int>
    private let holdsCLI: Bool
    private var stopped = false
    private var commands: [String] = []
    private var lists = 0
    private var listWaiters: [Int: CheckedContinuation<CommandResult, any Error>] = [:]
    private var capturedLists: [Int: String] = [:]
    private var cancelledLists = Set<Int>()
    private var cliStarted = false
    private var cliCancelled = false
    private var cliWaiter: CheckedContinuation<CommandResult, any Error>?
    private var unrelatedStarted = false
    private var unrelatedCancelled = false
    private var unrelatedWaiter: CheckedContinuation<CommandResult, any Error>?

    init(paths: [String], heldLists: Set<Int> = [], holdsCLI: Bool = false) {
        self.paths = paths; self.heldLists = heldLists; self.holdsCLI = holdsCLI
    }
    private func inventory() throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["raw": paths.map {
            ["name": URL(fileURLWithPath: $0).lastPathComponent, "approot": $0,
             "status": stopped ? "stopped" : "running", "type": "php"]
        }]), as: UTF8.self)
    }
    func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
             onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        commands.append(command)
        if command == "ddev list -j" {
            lists += 1; let index = lists; let output = try inventory(); capturedLists[index] = output
            if heldLists.contains(index) {
                return try await withTaskCancellationHandler(operation: {
                    try Task.checkCancellation()
                    return try await withCheckedThrowingContinuation { listWaiters[index] = $0 }
                }, onCancel: { Task { await self.cancelList(index) } })
            }
            return CommandResult(exitCode: 0, standardOutput: output, standardError: "")
        }
        if command == "ddev poweroff" {
            cliStarted = true; stopped = true
            if holdsCLI {
                return try await withTaskCancellationHandler(operation: {
                    try Task.checkCancellation()
                    return try await withCheckedThrowingContinuation { cliWaiter = $0 }
                }, onCancel: { Task { await self.cancelCLI() } })
            }
            return CommandResult(exitCode: 0, standardOutput: "Owned fake completion", standardError: "")
        }
        if command == "owned unrelated read" {
            unrelatedStarted = true
            return try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { unrelatedWaiter = $0 }
            }, onCancel: { Task { await self.cancelUnrelated() } })
        }
        return CommandResult(exitCode: 0, standardOutput: "28.0", standardError: "")
    }
    private func cancelList(_ index: Int) { cancelledLists.insert(index); listWaiters.removeValue(forKey: index)?.resume(throwing: CancellationError()) }
    private func cancelCLI() { cliCancelled = true; cliWaiter?.resume(throwing: CancellationError()); cliWaiter = nil }
    private func cancelUnrelated() { unrelatedCancelled = true; unrelatedWaiter?.resume(throwing: CancellationError()); unrelatedWaiter = nil }
    func finishList(_ index: Int) {
        listWaiters.removeValue(forKey: index)?.resume(returning: CommandResult(exitCode: 0, standardOutput: capturedLists[index] ?? "", standardError: ""))
    }
    func finishUnrelated() { unrelatedWaiter?.resume(returning: CommandResult(exitCode: 0, standardOutput: "Owned read completed", standardError: "")); unrelatedWaiter = nil }
    func finishAll() {
        for index in Array(listWaiters.keys) { finishList(index) }
        cliWaiter?.resume(returning: CommandResult(exitCode: 0, standardOutput: "Owned cleanup", standardError: "")); cliWaiter = nil
        finishUnrelated()
    }
    func listIsHeld(_ index: Int) -> Bool { listWaiters[index] != nil }
    func listWasCancelled(_ index: Int) -> Bool { cancelledLists.contains(index) }
    func hasCLI() -> Bool { cliStarted }
    func cancelledCLI() -> Bool { cliCancelled }
    func hasUnrelatedRead() -> Bool { unrelatedStarted && unrelatedWaiter != nil }
    func cancelledUnrelatedRead() -> Bool { unrelatedCancelled }
    func recorded() -> [String] { commands }
}

private actor PowerOffRaceClock: WorkerLeaseClock {
    private var current = 0.0
    private var sleepers: [UUID: (Double, CheckedContinuation<Void, any Error>)] = [:]
    private var cancellations = 0
    func now() async -> Double { current }
    func sleep(until deadline: Double) async throws {
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            if current >= deadline { return }
            try await withCheckedThrowingContinuation { sleepers[id] = (deadline, $0) }
        }, onCancel: { Task { await self.cancel(id) } })
    }
    private func cancel(_ id: UUID) {
        if let sleeper = sleepers.removeValue(forKey: id) { cancellations += 1; sleeper.1.resume(throwing: CancellationError()) }
    }
    func advance(_ seconds: Double) {
        current += seconds
        for (id, sleeper) in sleepers where sleeper.0 <= current { sleepers.removeValue(forKey: id)?.1.resume() }
    }
    func sleeperCount() -> Int { sleepers.count }
    func cancellationCount() -> Int { cancellations }
}

private actor PowerOffRaceSink {
    private var values: [WorkerResponse] = []
    func append(_ response: WorkerResponse) { values.append(response) }
    func hasPrepared() -> Bool { values.contains { $0.powerOff?.phase == "prepared" } }
    func responses() -> [WorkerResponse] { values }
}

private func raceRequest(_ operation: String, token: String, projects: [WorkerDDEVPowerOffProject]? = nil, active: [String]? = nil) throws -> Data {
    try JSONEncoder().encode(WorkerRequest(id: UUID().uuidString, operation: "ddev.poweroff." + operation,
        activeProjectIDs: active, powerOff: WorkerDDEVPowerOffContext(groupToken: token, projects: projects)))
}
private func raceStatusRequest(_ project: WorkerProject, cycle: String) throws -> Data {
    try JSONEncoder().encode(WorkerRequest(id: UUID().uuidString, operation: "project.status", project: project, refreshCycle: cycle))
}
private func raceProject(_ id: String, path: String, kind: WorkerProject.Kind = .ddev) -> WorkerProject {
    WorkerProject(id: id, distribution: "Race", kind: kind, path: path, title: id)
}
private func racePlan(_ project: WorkerProject) -> WorkerDDEVPowerOffProject {
    WorkerDDEVPowerOffProject(id: project.id, distribution: project.distribution, path: project.path, title: project.title)
}
private func raceWait(_ condition: () async -> Bool) async throws {
    for _ in 0..<10_000 { if await condition() { return }; await Task.yield() }
    try expect(await condition(), "Owned fake continuation did not reach the expected state")
}
private struct RacePresentation: Codable { let items: [WorkerAttentionItem]; let alerts: [WorkerAlert] }
private func racePresentation(_ snapshot: WorkerAttentionSnapshot, ids: Set<String>? = nil) throws -> String {
    let value = RacePresentation(items: snapshot.items.filter { ids == nil || ids!.contains($0.action.cardID ?? "") },
        alerts: snapshot.alerts.filter { ids == nil || ids!.contains($0.target.cardID ?? "") })
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

func runWorkerPowerOffRaceTests(_ run: TestRun) async {
    run.section("DDEV poweroff races and owned cleanup")
    await run.test("pending service inventories survive preparation and finalization while epochs retain fresh stopped status and former hidden watches") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-poweroff-races-" + UUID().uuidString)
        let formerFolder = folder.appendingPathComponent("former")
        try FileManager.default.createDirectory(at: formerFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = raceProject("current", path: folder.path), former = raceProject("former-hidden", path: formerFolder.path)
        let runner = PowerOffRaceRunner(paths: [folder.path, formerFolder.path], heldLists: [2, 3])
        let dates = MutableDateProvider(now: Date(timeIntervalSince1970: 1234))
        let worker = WorkerService(distribution: "Race", runner: runner, dates: dates)
        var pending: [Task<WorkerResponse, Never>] = []
        do {
            let first = await worker.handle(try raceStatusRequest(project, cycle: "baseline"))
            let firstFormer = await worker.handle(try raceStatusRequest(former, cycle: "baseline"))
            try expectEqual(first.status?.state, "running"); try expectEqual(firstFormer.status?.state, "running")
            let oldBytes = try raceStatusRequest(project, cycle: "old-cycle")
            let oldRead = Task { await worker.handle(oldBytes) }; pending.append(oldRead)
            try await raceWait { await runner.listIsHeld(2) }
            let prepared = await worker.handle(try raceRequest("prepare", token: "epoch", projects: [racePlan(project)])); try expectNil(prepared.error)
            let busyBytes = try raceStatusRequest(project, cycle: "during-prepare")
            let busyRead = Task { await worker.handle(busyBytes) }; pending.append(busyRead)
            try await raceWait { await runner.listIsHeld(3) }
            _ = await worker.handle(try raceRequest("run", token: "epoch"))
            let final = await worker.handle(try raceRequest("finalize", token: "epoch"))
            try expectNil(final.error); try expectEqual(final.powerOff?.statuses.map(\.projectID), ["current"])
            try expectEqual(final.powerOff?.statuses.first?.state, "stopped"); try expectEqual(final.powerOff?.statuses.first?.checkedAt, 1234)
            try expect(final.attention?.items.isEmpty == true && final.attention?.alerts.isEmpty == true)
            let cancelledOld = await runner.listWasCancelled(2), cancelledBusy = await runner.listWasCancelled(3)
            try expect(!cancelledOld && !cancelledBusy)
            await runner.finishList(3); await runner.finishList(2)
            for task in pending {
                let stale = await task.value
                try expectNil(stale.error); try expectEqual(stale.status?.state, "stopped"); try expectEqual(stale.status?.checkedAt, 1234)
                try expect(stale.attention?.items.isEmpty == true && stale.attention?.alerts.isEmpty == true)
            }
            let formerAfter = await worker.handle(try raceStatusRequest(former, cycle: "after"))
            try expectEqual(formerAfter.status?.state, "stopped")
            try expect(formerAfter.attention?.items.isEmpty == true && formerAfter.attention?.alerts.isEmpty == true)
            let calls = await runner.recorded()
            try expectEqual(calls.filter { $0 == "ddev poweroff" }.count, 1)
            try expectEqual(calls.filter { $0 == "ddev list -j" }.count, 5)
            await worker.closePowerOffState()
        } catch {
            await runner.finishAll(); for task in pending { _ = await task.value }; await worker.closePowerOffState(); throw error
        }
    }
    await run.test("group staging keeps unrelated Arc and plain episodes through abort or final and never registers hidden plan references") {
        for finalized in [false, true] {
            let state = WorkerAttentionState(), now = Date(timeIntervalSince1970: 1000), docker = DockerStatus(state: .running)
            let current = raceProject("current-ddev", path: "/tmp/current"), former = raceProject("former-ddev", path: "/tmp/former")
            let arc = raceProject("arc-sibling", path: "/tmp/arc", kind: .arc), plain = raceProject("plain-sibling", path: "/tmp/plain", kind: .local)
            for project in [current, former, arc, plain] {
                _ = await state.observe(project, status: WorkerStatus(projectID: project.id, state: "running", syncBroken: project.kind == .ddev ? "old sync" : nil),
                    error: nil, action: nil, docker: docker, now: now)
            }
            let reusedDDEV = raceProject("reused-id", path: "/tmp/reused-old"), reusedArc = raceProject("reused-id", path: "/tmp/reused-new", kind: .arc)
            for project in [reusedDDEV, reusedArc] {
                _ = await state.observe(project, status: WorkerStatus(projectID: project.id, state: "running"), error: nil, action: nil, docker: docker, now: now)
            }
            for project in [arc, plain, reusedArc] { for _ in 0..<2 {
                _ = await state.observe(project, status: WorkerStatus(projectID: project.id, state: "stopped"), error: nil, action: nil, docker: docker, now: now)
            } }
            let before = await state.observe(current, status: WorkerStatus(projectID: current.id, state: "running", syncBroken: "old sync"), error: nil, action: nil, docker: docker, now: now)
            let siblingIDs: Set<String> = [arc.id, plain.id, reusedArc.id]
            try expectEqual(before.1.items.filter { siblingIDs.contains($0.action.cardID ?? "") }.count, 3)
            let hidden = (0..<150).map { raceProject("hidden-\($0)", path: "/missing/\($0)") }
            await state.preparePowerOff(token: "scope", projects: [current] + hidden)
            let references = await state.powerOffReferences(token: "scope")
            try expectEqual(Set(references.map(\.id)), Set(([current, former] + hidden).map(\.id)))
            let during = await state.observe(arc, status: WorkerStatus(projectID: arc.id, state: "stopped"), error: nil, action: nil, docker: docker, now: now)
            try expectEqual(racePresentation(during.1), racePresentation(before.1, ids: siblingIDs))
            let final: WorkerAttentionSnapshot
            if finalized {
                let physical = Dictionary(uniqueKeysWithValues: references.map { ($0.id, WorkerStatus(projectID: $0.id, state: "stopped", checkedAt: 1000)) })
                final = await state.finishPowerOff(token: "scope", statuses: physical, distribution: "Race", now: now, activeProjectIDs: nil)
                try expectEqual(racePresentation(final), racePresentation(before.1, ids: siblingIDs))
            } else {
                final = await state.abortPowerOff(token: "scope", distribution: "Race", now: now, activeProjectIDs: nil)
                try expectEqual(racePresentation(final), racePresentation(before.1))
            }
            try expectEqual(final.items.filter { siblingIDs.contains($0.action.cardID ?? "") }.count, 3)
            try expect(final.items.allSatisfy { !($0.action.cardID ?? "").hasPrefix("hidden-") })
        }
    }
    await run.test("lease renewal removes its old sleeper and crossing the old deadline does not expire the new preparation") {
        let clock = PowerOffRaceClock(), runner = PowerOffRaceRunner(paths: ["/missing/renewed"])
        let worker = WorkerService(distribution: "Race", runner: runner, leaseClock: clock)
        let plan = [racePlan(raceProject("renewed", path: "/missing/renewed"))]
        do {
            _ = await worker.handle(try raceRequest("prepare", token: "renewed", projects: plan))
            try await raceWait { await clock.sleeperCount() == 1 }
            await clock.advance(500)
            let renewal = await worker.handle(try raceRequest("prepare", token: "renewed", projects: plan)); try expectEqual(renewal.powerOff?.leaseSecondsRemaining, 600)
            try await raceWait {
                let count = await clock.sleeperCount(), cancellations = await clock.cancellationCount()
                return count == 1 && cancellations >= 1
            }
            await clock.advance(101)
            let result = await worker.handle(try raceRequest("run", token: "renewed")); try expectNil(result.error); try expectEqual(result.powerOff?.commandState, "succeeded")
            _ = await worker.handle(try raceRequest("finalize", token: "renewed"))
            try expectEqual(await runner.recorded().filter { $0 == "ddev poweroff" }.count, 1)
            await worker.closePowerOffState(); try await raceWait { await clock.sleeperCount() == 0 }
        } catch { await worker.closePowerOffState(); throw error }
    }
    await run.test("lease expiry during a held CLI cancels only that child while an unrelated read survives and the next group can prepare") {
        let clock = PowerOffRaceClock(), runner = PowerOffRaceRunner(paths: ["/missing/expiry"], holdsCLI: true)
        let worker = WorkerService(distribution: "Race", runner: runner, leaseClock: clock)
        let plan = [racePlan(raceProject("expires", path: "/missing/expiry"))]
        let unrelated = Task { try await runner.run("owned unrelated read", in: URL(fileURLWithPath: "/tmp"), timeout: 20) }
        var running: Task<WorkerResponse, Never>?
        do {
            try await raceWait { await runner.hasUnrelatedRead() }
            _ = await worker.handle(try raceRequest("prepare", token: "expires", projects: plan))
            try await raceWait { await clock.sleeperCount() == 1 }
            let bytes = try raceRequest("run", token: "expires"); let task = Task { await worker.handle(bytes) }; running = task
            try await raceWait { await runner.hasCLI() }
            await clock.advance(601); try await raceWait { await runner.cancelledCLI() }
            let response = await task.value; try expectEqual(response.powerOff?.commandState, "cancelled")
            try expectEqual(response.powerOff?.phase, "ran"); try expectEqual(response.powerOff?.leaseSecondsRemaining, 0)
            try expectEqual(response.powerOff?.statuses.count, 0); try expectEqual(response.powerOff?.inventoryState, "notChecked")
            try expectNil(response.attention)
            try expect(!(await runner.cancelledUnrelatedRead())); try expect(await runner.hasUnrelatedRead())
            var next: WorkerResponse?
            for _ in 0..<1000 {
                next = await worker.handle(try raceRequest("prepare", token: "after-expiry", projects: plan)); if next?.error == nil { break }; await Task.yield()
            }
            try expectNil(next?.error)
            _ = await worker.handle(try raceRequest("abort", token: "after-expiry"))
            await runner.finishUnrelated(); try expectEqual(try await unrelated.value.standardOutput, "Owned read completed")
            try expectEqual(await runner.recorded().filter { $0 == "ddev poweroff" }.count, 1)
            await worker.closePowerOffState(); try await raceWait { await clock.sleeperCount() == 0 }
        } catch {
            await runner.finishAll(); if let running { _ = await running.value }; _ = try? await unrelated.value; await worker.closePowerOffState(); throw error
        }
    }
    await run.test("closing a held CLI reaps it without EOF reconciliation or cancelling an existing service inventory reader") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-poweroff-close-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = PowerOffRaceClock(), runner = PowerOffRaceRunner(paths: [folder.path], heldLists: [2], holdsCLI: true)
        let worker = WorkerService(distribution: "Race", runner: runner, leaseClock: clock)
        let project = raceProject("close", path: folder.path)
        let baseline = await worker.handle(try raceStatusRequest(project, cycle: "baseline")); try expectEqual(baseline.status?.state, "running")
        let pendingBytes = try raceStatusRequest(project, cycle: "held-reader"); let reader = Task { await worker.handle(pendingBytes) }
        var running: Task<WorkerResponse, Never>?
        do {
            try await raceWait { await runner.listIsHeld(2) }
            _ = await worker.handle(try raceRequest("prepare", token: "close", projects: [racePlan(project)]))
            try await raceWait { await clock.sleeperCount() == 1 }
            let bytes = try raceRequest("run", token: "close"); let task = Task { await worker.handle(bytes) }; running = task
            try await raceWait { await runner.hasCLI() }
            await worker.closePowerOffState(); _ = await task.value
            try expect(await runner.cancelledCLI()); try expect(!(await runner.listWasCancelled(2))); try expect(await runner.listIsHeld(2))
            try await raceWait { await clock.sleeperCount() == 0 }
            try expectEqual(await runner.recorded().filter { $0 == "ddev list -j" }.count, 2)
            await runner.finishList(2); let read = await reader.value; try expectNil(read.error)
            try expect(!(await runner.listWasCancelled(2)))
            try expectEqual(await worker.handle(try raceRequest("run", token: "close")).error?.code, "disconnected")
        } catch {
            await runner.finishAll(); if let running { _ = await running.value }; _ = await reader.value; await worker.closePowerOffState(); throw error
        }
    }
    await run.test("actual session EOF marks the group closing before cancelling its run and never starts reconciliation") {
        let clock = PowerOffRaceClock(), runner = PowerOffRaceRunner(paths: ["/missing/session-close"], holdsCLI: true)
        let worker = WorkerService(distribution: "Race", runner: runner, leaseClock: clock), sink = PowerOffRaceSink()
        let session = WorkerSession(service: worker) { await sink.append($0) }
        do {
            await session.accept(.data(try raceRequest("prepare", token: "session-close", projects: [racePlan(raceProject("session", path: "/missing/session-close"))])))
            try await raceWait { await sink.hasPrepared() }
            try await raceWait { await clock.sleeperCount() == 1 }
            await session.accept(.data(try raceRequest("run", token: "session-close")))
            try await raceWait { await runner.hasCLI() }
            await session.close()
            try expect(await runner.cancelledCLI()); try await raceWait { await clock.sleeperCount() == 0 }
            try expectEqual(await runner.recorded(), ["ddev poweroff"])
            let responses = await sink.responses()
            try expectEqual(responses.count, 2)
            try expectEqual(responses.last?.error?.code, "disconnected")
            try expect(responses.allSatisfy { $0.powerOff?.phase != "finalized" && $0.powerOff?.phase != "aborted" })
        } catch { await runner.finishAll(); await session.close(); throw error }
    }
}
