import DevDeckCore
import DevDeckWorkerProtocol
import Foundation
import TestHarness

func runWorkerAttentionTests(_ run: TestRun) async {
    run.section("Worker shared attention")
    let start = Date(timeIntervalSince1970: 1000)
    let project = WorkerProject(id: "ddev.project.shop", distribution: "Test", kind: .ddev, path: "/tmp/shop", title: "Shop")
    let up = WorkerStatus(projectID: project.id, state: "running")
    let down = WorkerStatus(projectID: project.id, state: "stopped")
    let docker = DockerStatus(state: .running)
    await run.test("first stopped observation is quiet and a single bad poll cannot stop a running card") {
        let state = WorkerAttentionState()
        let initial = await state.observe(project, status: down, error: nil, action: nil, docker: docker, now: start)
        try expect(initial.1.alerts.isEmpty)
        _ = await state.observe(project, status: up, error: nil, action: nil, docker: docker, now: start.addingTimeInterval(1))
        let hiccup = await state.observe(project, status: down, error: nil, action: nil, docker: docker, now: start.addingTimeInterval(2))
        try expectEqual(hiccup.0?.state, "running"); try expect(hiccup.1.alerts.isEmpty)
        let confirmed = await state.observe(project, status: down, error: nil, action: nil, docker: docker, now: start.addingTimeInterval(3))
        try expectEqual(confirmed.0?.state, "stopped")
        try expectEqual(confirmed.1.alerts.first?.kind, "wentDown")
        try expectEqual(confirmed.1.items.first?.action.cardID, project.id)
    }
    await run.test("a requested stop or restart does not become a spontaneous-stop alert") {
        for action in ["stop", "restart"] {
            let state = WorkerAttentionState()
            _ = await state.observe(project, status: up, error: nil, action: nil, docker: docker, now: start)
            await state.noteAction(project, action: action, now: start.addingTimeInterval(1))
            let result = await state.observe(project, status: down, error: nil, action: action, docker: docker, now: start.addingTimeInterval(2))
            try expect(result.1.alerts.isEmpty)
        }
    }
    await run.test("long failed starts keep a dismissible problem and alert; quick failures stay on the card") {
        for duration in [1.0, 16.0] {
            let state = WorkerAttentionState()
            await state.noteAction(project, action: "start", now: start)
            let result = await state.observe(project, status: nil, error: WorkerFailure(code: "commandFailed", message: "Read project logs."), action: "start", docker: docker, now: start.addingTimeInterval(duration))
            try expectEqual(result.1.alerts.count, duration > 15 ? 1 : 0)
            try expect(result.1.items.first?.dismissible == true)
            let dismissed = await state.dismiss(project, now: start.addingTimeInterval(duration + 1))
            try expect(dismissed.items.isEmpty); try expect(dismissed.alerts.isEmpty)
        }
    }
    await run.test("health silence waits two minutes and recovery clears the live fault") {
        let state = WorkerAttentionState()
        let silent = WorkerStatus(projectID: project.id, state: "starting", notAnswering: "Not serving yet.")
        let first = await state.observe(project, status: silent, error: nil, action: nil, docker: docker, now: start)
        try expect(first.1.items.isEmpty)
        let delayed = await state.observe(project, status: silent, error: nil, action: nil, docker: docker, now: start.addingTimeInterval(121))
        try expectEqual(delayed.1.alerts.first?.kind, "wentDown")
        let recovered = await state.observe(project, status: up, error: nil, action: nil, docker: docker, now: start.addingTimeInterval(122))
        try expect(recovered.1.items.isEmpty)
    }
    await run.test("Docker failure groups project stops and blocks container start without blaming a plain checkout") {
        let state = WorkerAttentionState()
        _ = await state.observe(project, status: up, error: nil, action: nil, docker: docker, now: start)
        let lost = DockerStatus(state: .notRunning)
        _ = await state.observe(project, status: down, error: nil, action: nil, docker: lost, now: start.addingTimeInterval(1))
        let result = await state.observe(project, status: down, error: nil, action: nil, docker: lost, now: start.addingTimeInterval(2))
        try expectEqual(result.1.items.first?.mark, "docker")
        try expectEqual(result.1.alerts.first?.source, "docker")
        try expectEqual(result.1.containerStartAllowed, false)
        let plain = WorkerProject(id: "project.plain", distribution: "Test", kind: .local, path: "/tmp/plain")
        let next = await state.observe(plain, status: WorkerStatus(projectID: plain.id, state: "stopped"), error: nil, action: nil, docker: DockerStatus(state: .unknown), now: start.addingTimeInterval(3))
        try expectEqual(next.1.dockerState, "notRunning")
    }
    await run.test("all-account rejection retains failed-fetch identity and safe account settings attention") {
        let account = WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://api.github.com")
        let worker = WorkerService(distribution: "Test", remoteService: WorkerRemoteService(http: FakeHTTPClient([])))
        let response = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "rejected", operation: "remote.snapshot", remote: WorkerRemoteRequest(cardID: "github.pr", kind: .pullRequests, accounts: [account]))))
        try expectEqual(response.error?.code, "credentialsRejected")
        try expectEqual(response.attention?.items.first?.action.kind, "accountSettings")
        try expectEqual(response.attention?.items.first?.action.accountID, "work")
        try expectEqual(response.attention?.alerts.first?.kind, "cantCheck")
        try expect(response.attention?.items.first?.title.contains("Work") == true)
    }
    await run.test("network grace and account rejection episodes reuse shared thresholds and recover") {
        let state = WorkerAttentionState()
        let account = WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://api.github.com", token: "offline-secret")
        let request = WorkerRemoteRequest(cardID: "github.pr", kind: .pullRequests, accounts: [account])
        func snapshot(_ kind: String?) -> WorkerRemoteSnapshot {
            WorkerRemoteSnapshot(cardID: request.cardID, kind: request.kind, total: 0, blocked: 0, successRate: nil, rows: [],
                                 failures: kind.map { [WorkerRemoteAccountFailure(accountID: "work", kind: $0)] } ?? [], capped: false)
        }
        let short = await state.remote(snapshot("unreachable"), request: request, now: start)
        try expectEqual(short.items.first?.tier, "goodToKnow")
        let long = await state.remote(snapshot("unreachable"), request: request, now: start.addingTimeInterval(901))
        try expectEqual(long.items.first?.tier, "needsFixing")
        let rejected = await state.remote(snapshot("rejected"), request: request, now: start.addingTimeInterval(902))
        _ = await state.remote(snapshot(nil), request: request, now: start.addingTimeInterval(903))
        let again = await state.remote(snapshot("rejected"), request: request, now: start.addingTimeInterval(904))
        try expect(rejected.alerts.first?.id != again.alerts.first?.id)
        try expect(!String(decoding: JSONEncoder().encode(again), as: UTF8.self).contains("offline-secret"))
    }
    await run.test("sync faults stay live after dismissal and disappear when synchronization recovers") {
        let state = WorkerAttentionState()
        let fault = WorkerStatus(projectID: project.id, state: "running", syncBroken: "mutagen")
        let observed = await state.observe(project, status: fault, error: nil, action: nil, docker: docker, now: start)
        try expectEqual(observed.1.items.first?.id, "project:\(project.id):sync")
        try expectEqual(observed.1.alerts.first?.kind, "wentDown")
        let dismissed = await state.dismiss(project, now: start.addingTimeInterval(1))
        try expectEqual(dismissed.items.count, 1)
        let recovered = await state.observe(project, status: up, error: nil, action: nil, docker: docker, now: start.addingTimeInterval(2))
        try expectEqual(recovered.1.items.count, 0)
    }
    await run.test("duplicate account failure paths share one item and another card cannot clear an active failure episode") {
        let state = WorkerAttentionState()
        let accounts = [WorkerRemoteAccount(id: "work", label: "Work", endpoint: "https://api.github.com")]
        let first = WorkerRemoteRequest(cardID: "actions", kind: .actions, accounts: accounts)
        let second = WorkerRemoteRequest(cardID: "pr", kind: .pullRequests, accounts: accounts)
        func failed(_ request: WorkerRemoteRequest) -> WorkerRemoteSnapshot {
            WorkerRemoteSnapshot(cardID: request.cardID, kind: request.kind, total: 0, blocked: 0, successRate: nil, rows: [],
                failures: [WorkerRemoteAccountFailure(accountID: "work", kind: "rejected"), WorkerRemoteAccountFailure(accountID: "work", kind: "rejected")], capped: false)
        }
        let initial = await state.remote(failed(first), request: first, now: start)
        try expectEqual(initial.items.count, 1)
        try expectEqual(initial.alerts.count, 1)
        _ = await state.remote(WorkerRemoteSnapshot(cardID: second.cardID, kind: second.kind, total: 0, blocked: 0, successRate: nil, rows: [], failures: [], capped: false), request: second, now: start.addingTimeInterval(1))
        let again = await state.remote(failed(first), request: first, now: start.addingTimeInterval(2))
        try expectEqual(initial.alerts.first?.id, again.alerts.first?.id)
        try expectEqual(again.items.first?.key, "github:account:work")
    }
}
