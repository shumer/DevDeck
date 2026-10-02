import DevDeckCore
import DevDeckWorkerProtocol
import Foundation
import TestHarness

private actor PowerOffRunner: CommandRunning {
    private var commands: [String] = []
    func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
             onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        commands.append(command)
        return CommandResult(exitCode: 0, standardOutput: #"{"raw":[]}"#, standardError: "")
    }
    func recorded() -> [String] { commands }
}

private actor PowerOffEngine {
    private var states: [String:String]
    init(paths: [String], state: String="running") {states=Dictionary(uniqueKeysWithValues:paths.map{($0,state)})}
    func stop() {for path in states.keys{states[path]="stopped"}}
    func inventory() throws -> String {
        String(decoding:try JSONSerialization.data(withJSONObject:["raw":states.sorted{$0.key<$1.key}.map{
            ["name":URL(fileURLWithPath:$0.key).lastPathComponent,"approot":$0.key,"status":$0.value,"type":"php"]}]),as:UTF8.self)
    }
}
private actor PowerOffScriptRunner: CommandRunning {
    struct Invocation: Sendable {let command: String;let directory: String;let timeout: TimeInterval}
    private let engine: PowerOffEngine
    private let stops: Bool
    private let exitCode: Int32
    private let invalidList: Bool
    private var calls: [Invocation]=[]
    init(engine: PowerOffEngine,stops: Bool=true,exitCode: Int32=0,invalidList: Bool=false) {self.engine=engine;self.stops=stops;self.exitCode=exitCode;self.invalidList=invalidList}
    func run(_ command: String,in directory: URL,timeout: TimeInterval,isInteractive: Bool,onOutput: (@Sendable(String)->Void)?) async throws -> CommandResult {
        calls.append(Invocation(command:command,directory:directory.path,timeout:timeout))
        if command=="ddev poweroff" {if stops{await engine.stop()};onOutput?("synthetic DDEV completion");return CommandResult(exitCode:exitCode,standardOutput:"",standardError:"")}
        return CommandResult(exitCode:0,standardOutput:command=="ddev list -j" ? (invalidList ? "malformed inventory" : try await engine.inventory()) : "28.0",standardError:"")
    }
    func recorded() -> [Invocation] {calls}
}
private actor PowerOffManualClock: WorkerLeaseClock {
    private var current=0.0
    private var sleepers: [UUID:(Double,CheckedContinuation<Void,any Error>)]=[:]
    func now() async -> Double {current}
    func sleep(until deadline: Double) async throws {
        let id=UUID()
        try await withTaskCancellationHandler(operation:{
            try Task.checkCancellation()
            if current>=deadline{return}
            try await withCheckedThrowingContinuation{sleepers[id]=(deadline,$0)}
        },onCancel:{Task{await self.cancel(id)}})
    }
    private func cancel(_ id: UUID) {sleepers.removeValue(forKey:id)?.1.resume(throwing:CancellationError())}
    func advance(_ seconds: Double) {
        current+=seconds
        for (id,value) in sleepers where value.0<=current {sleepers.removeValue(forKey:id)?.1.resume()}
    }
}
private actor PowerOffSink {
    private var values: [WorkerResponse]=[]
    func append(_ value: WorkerResponse){values.append(value)}
    func responses()->[WorkerResponse]{values}
}
private actor PowerOffBlockingRunner: CommandRunning {
    private let heldCommand: String
    private var suspension: CheckedContinuation<CommandResult,any Error>?
    private var started=false
    private var cancelled=false
    init(heldCommand: String="ddev poweroff"){self.heldCommand=heldCommand}
    func run(_ command: String,in directory: URL,timeout: TimeInterval,isInteractive: Bool,onOutput: (@Sendable(String)->Void)?) async throws -> CommandResult {
        if command != heldCommand {return CommandResult(exitCode:0,standardOutput:#"{"raw":[]}"#,standardError:"")}
        if started {return CommandResult(exitCode:1,standardOutput:"",standardError:"A duplicate synthetic command entered.")}
        started=true
        return try await withTaskCancellationHandler(operation:{
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation{suspension=$0}
        },onCancel:{Task{await self.cancel()}})
    }
    private func cancel(){cancelled=true;suspension?.resume(throwing:CancellationError());suspension=nil}
    func hasStarted()->Bool{started}
    func wasCancelled()->Bool{cancelled}
}
private func powerOffBytes(_ operation: String,_ token: String,_ projects: [WorkerDDEVPowerOffProject]?=nil,active: [String]?=nil) throws -> Data {
    try JSONEncoder().encode(WorkerRequest(id:UUID().uuidString,operation:"ddev.poweroff."+operation,activeProjectIDs:active,powerOff:WorkerDDEVPowerOffContext(groupToken:token,projects:projects)))
}
private func fixtureProject(_ id: String,distribution: String="Test",path: String) -> WorkerDDEVPowerOffProject {
    WorkerDDEVPowerOffProject(id:id,distribution:distribution,path:path,title:id)
}
private extension WorkerDDEVPowerOffProject {
    var reference: WorkerProject {WorkerProject(id:id,distribution:distribution,kind:.ddev,path:path,title:title)}
}
private func snapshotJSON(_ value: WorkerAttentionSnapshot) throws -> String {
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    return String(decoding:try encoder.encode(value),as:UTF8.self)
}

func runWorkerPowerOffTests(_ run: TestRun) async {
    run.section("DDEV poweroff transaction")
    await run.test("poweroff transaction is advertised by the actual worker dispatcher") {
        let runner = PowerOffRunner()
        let worker = WorkerService(distribution: "Test", runner: runner)
        let result = await worker.handle(try JSONEncoder().encode(WorkerRequest(id: "poweroff-hello", operation: "hello")))
        try expect(result.capabilities?.contains("ddev.poweroff.transaction") == true)
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("preparation accepts a hidden missing-folder DDEV reference without running a command") {
        let runner = PowerOffRunner()
        let worker = WorkerService(distribution: "Test", runner: runner)
        let request: [String: Any] = ["protocolVersion": 1, "id": "poweroff-stage", "operation": "ddev.poweroff.prepare",
            "powerOff": ["groupToken": "group-red", "projects": [["id": "hidden", "distribution": "Test", "kind": "ddev", "path": "/tmp/devdeck-poweroff-does-not-exist"]]]]
        let result = await worker.handle(try JSONSerialization.data(withJSONObject: request))
        try expectNil(result.error)
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
        try expectEqual((payload["powerOff"] as? [String: Any])?["phase"] as? String, "prepared")
        try expectNil(result.attention)
        try expectEqual(await runner.recorded(), [])
        await worker.closePowerOffState()
    }
    await run.test("one global command uses home cwd and final inventory covers hidden aliases with distinct identities") {
        let folder="/tmp/poweroff-missing-"+UUID().uuidString
        let engine=PowerOffEngine(paths:[folder]);let runner=PowerOffScriptRunner(engine:engine)
        let worker=WorkerService(distribution:"Test",runner:runner)
        let projects=[fixtureProject("shown",path:folder),fixtureProject("hidden",path:folder)]
        let prepared=await worker.handle(try powerOffBytes("prepare","global",projects));try expectNil(prepared.error)
        let result=await worker.handle(try powerOffBytes("run","global"));try expectEqual(result.powerOff?.phase,"ran");try expectEqual(result.powerOff?.commandState,"succeeded")
        let repeated=await worker.handle(try powerOffBytes("run","global"));try expectEqual(repeated.powerOff?.commandState,"succeeded")
        let renewed=await worker.handle(try powerOffBytes("prepare","global",projects));try expectEqual(renewed.powerOff?.phase,"prepared");try expectEqual(renewed.powerOff?.commandState,"succeeded")
        let final=await worker.handle(try powerOffBytes("finalize","global",active:[]))
        try expectNil(final.error);try expectEqual(final.powerOff?.phase,"finalized");try expectEqual(final.powerOff?.leaseSecondsRemaining,0)
        try expectEqual(final.powerOff?.statuses.map(\.projectID),["shown","hidden"])
        try expect(final.powerOff?.statuses.allSatisfy{$0.state=="stopped" && $0.checkedAt != nil} == true)
        try expectEqual(final.attention?.items.count,0);try expectEqual(final.attention?.alerts.count,0)
        let commands=await runner.recorded()
        try expectEqual(commands.map(\.command),["ddev poweroff","ddev list -j"])
        try expectEqual(commands[0].directory,NSHomeDirectory());try expectEqual(commands[0].timeout,300)
        let replay=await worker.handle(try powerOffBytes("run","global"));try expectEqual(replay.error?.code,"groupCompleted")
        try expectEqual(await runner.recorded().map(\.command),commands.map(\.command))
        await worker.closePowerOffState()
    }
    await run.test("pure group validation rejects malformed direct and session envelopes before any runner work") {
        let runner=PowerOffRunner();let worker=WorkerService(distribution:"Test",runner:runner)
        let good=fixtureProject("good",path:"/tmp/not-present")
        var requests=[WorkerRequest(id:"foreign",operation:"ddev.poweroff.prepare",powerOff:WorkerDDEVPowerOffContext(groupToken:"t",projects:[fixtureProject("x",distribution:"Other",path:"/tmp/x")])),
            WorkerRequest(id:"duplicate",operation:"ddev.poweroff.prepare",powerOff:WorkerDDEVPowerOffContext(groupToken:"t",projects:[good,good])),
            WorkerRequest(id:"wrong-kind",operation:"ddev.poweroff.prepare",powerOff:WorkerDDEVPowerOffContext(groupToken:"t",projects:[WorkerDDEVPowerOffProject(id:"x",distribution:"Test",kind:"arc",path:"/tmp/x")])),
            WorkerRequest(id:"relative",operation:"ddev.poweroff.prepare",powerOff:WorkerDDEVPowerOffContext(groupToken:"t",projects:[fixtureProject("x",path:"relative")])),
            WorkerRequest(id:"empty",operation:"ddev.poweroff.prepare",powerOff:WorkerDDEVPowerOffContext(groupToken:"t",projects:[])),
            WorkerRequest(id:"control",operation:"ddev.poweroff.prepare",powerOff:WorkerDDEVPowerOffContext(groupToken:"bad\ntoken",projects:[good])),
            WorkerRequest(id:"run-plan",operation:"ddev.poweroff.run",powerOff:WorkerDDEVPowerOffContext(groupToken:"t",projects:[good])),
            WorkerRequest(id:"unrelated",operation:"hello",powerOff:WorkerDDEVPowerOffContext(groupToken:"t"))]
        requests.append(WorkerRequest(id:"active-prepare",operation:"ddev.poweroff.prepare",activeProjectIDs:[],powerOff:WorkerDDEVPowerOffContext(groupToken:"t",projects:[good])))
        let sink=PowerOffSink();let session=WorkerSession(service:worker){await sink.append($0)}
        for request in requests {
            let data=try JSONEncoder().encode(request)
            try expectEqual(await worker.handle(data).error?.code,"invalidRequest")
            await session.accept(.data(data))
        }
        await session.close()
        try expectEqual(await sink.responses().count,requests.count);try expect(await sink.responses().allSatisfy{$0.error?.code=="invalidRequest"})
        try expectEqual(await runner.recorded(),[])
    }
    await run.test("never-run abort preserves exact old DDEV watch faults and its first-negative settling streak") {
        let state=WorkerAttentionState();let date=Date(timeIntervalSince1970:1000);let docker=DockerStatus(state:.running)
        let project=fixtureProject("kept",path:"/tmp/kept").reference
        _=await state.observe(project,status:WorkerStatus(projectID:project.id,state:"running",syncBroken:"sync"),error:nil,action:nil,docker:docker,now:date)
        let before=await state.observe(project,status:WorkerStatus(projectID:project.id,state:"stopped"),error:nil,action:nil,docker:docker,now:date)
        await state.preparePowerOff(token:"aborted",projects:[project])
        _=await state.observe(project,status:WorkerStatus(projectID:project.id,state:"running"),error:nil,action:nil,docker:docker,now:date)
        let restored=await state.abortPowerOff(token:"aborted",distribution:"Test",now:date,activeProjectIDs:nil)
        try expectEqual(snapshotJSON(restored),snapshotJSON(before.1))
        let confirmed=await state.observe(project,status:WorkerStatus(projectID:project.id,state:"stopped"),error:nil,action:nil,docker:docker,now:date.addingTimeInterval(1))
        try expectEqual(confirmed.0?.state,"stopped");try expectEqual(confirmed.1.alerts.first?.kind,"wentDown")
    }
    await run.test("pinned stop survives a late running poll and final one-negative status defeats old observation epochs") {
        let state=WorkerAttentionState();let date=Date(timeIntervalSince1970:1000);let docker=DockerStatus(state:.running)
        let project=fixtureProject("ddev",path:"/tmp/ddev").reference
        _=await state.observe(project,status:WorkerStatus(projectID:project.id,state:"running"),error:nil,action:nil,docker:docker,now:date)
        let old=await state.observationEpoch(project)
        await state.preparePowerOff(token:"pin",projects:[project])
        _=await state.observe(project,status:WorkerStatus(projectID:project.id,state:"running"),error:nil,action:nil,docker:docker,now:date.addingTimeInterval(1))
        let stopped=WorkerStatus(projectID:project.id,state:"stopped",checkedAt:date.addingTimeInterval(2).timeIntervalSince1970)
        let final=await state.finishPowerOff(token:"pin",statuses:[project.id:stopped],distribution:"Test",now:date.addingTimeInterval(2),activeProjectIDs:nil)
        try expect(final.items.isEmpty && final.alerts.isEmpty)
        let stale=await state.observe(project,status:WorkerStatus(projectID:project.id,state:"running"),error:nil,action:nil,docker:docker,now:date.addingTimeInterval(3),observationEpoch:old)
        try expectEqual(stale.0?.state,"stopped");try expectEqual(stale.0?.checkedAt,stopped.checkedAt)
        try expect(stale.1.items.isEmpty && stale.1.alerts.isEmpty)
    }
    await run.test("two staged actors sharing an engine finalize both after only the first caller stopped their projects") {
        let a="/tmp/poweroff-a-"+UUID().uuidString,b="/tmp/poweroff-b-"+UUID().uuidString
        let engine=PowerOffEngine(paths:[a,b]);let runnerA=PowerOffScriptRunner(engine:engine),runnerB=PowerOffScriptRunner(engine:engine)
        let first=WorkerService(distribution:"A",runner:runnerA),second=WorkerService(distribution:"B",runner:runnerB)
        try expectNil(await first.handle(try powerOffBytes("prepare","both",[fixtureProject("a",distribution:"A",path:a)])).error)
        try expectNil(await second.handle(try powerOffBytes("prepare","both",[fixtureProject("b",distribution:"B",path:b)])).error)
        _=await first.handle(try powerOffBytes("run","both"))
        let finalA=await first.handle(try powerOffBytes("finalize","both")),finalB=await second.handle(try powerOffBytes("finalize","both"))
        try expectEqual(finalA.powerOff?.statuses.first?.state,"stopped");try expectEqual(finalB.powerOff?.statuses.first?.state,"stopped")
        try expectEqual(finalB.powerOff?.commandState,"notRun");try expect(finalB.attention?.alerts.isEmpty == true)
        try expectEqual(await runnerB.recorded().map(\.command),["ddev list -j"])
        await first.closePowerOffState();await second.closePowerOffState()
    }
    await run.test("zero CLI exit never fabricates stopped and malformed final inventory is distinct") {
        for invalid in [false,true] {
            let folder="/tmp/poweroff-noop-"+UUID().uuidString
            let runner=PowerOffScriptRunner(engine:PowerOffEngine(paths:[folder]),stops:false,invalidList:invalid)
            let worker=WorkerService(distribution:"Test",runner:runner)
            _=await worker.handle(try powerOffBytes("prepare","noop",[fixtureProject("a",path:folder)]));_=await worker.handle(try powerOffBytes("run","noop"))
            let final=await worker.handle(try powerOffBytes("finalize","noop"))
            try expectEqual(final.powerOff?.commandState,"succeeded");try expectEqual(final.powerOff?.commandExitCode,0)
            try expectEqual(final.powerOff?.inventoryState,invalid ? "invalid" : "available")
            try expectEqual(final.powerOff?.statuses.first?.state,invalid ? "unknown" : "running")
            try expectEqual(final.powerOff?.diagnostic?.code,"outcomeNotConfirmed")
            await worker.closePowerOffState()
        }
    }
    await run.test("lease expiry disarms never-run intent and rejects stale tokens without issuing a command") {
        let clock=PowerOffManualClock(),runner=PowerOffRunner();let worker=WorkerService(distribution:"Test",runner:runner,leaseClock:clock)
        let project=fixtureProject("a",path:"/tmp/a")
        _=await worker.handle(try powerOffBytes("prepare","expires",[project]));await clock.advance(601)
        let stale=await worker.handle(try powerOffBytes("run","expires"));try expect(["groupCompleted","groupNotPrepared","groupBusy"].contains(stale.error?.code ?? ""))
        var next: WorkerResponse?
        for _ in 0..<100 {next=await worker.handle(try powerOffBytes("prepare","next",[project]));if next?.error == nil{break};await Task.yield()}
        try expectNil(next?.error)
        let abort=await worker.handle(try powerOffBytes("abort","next",active:[]));try expectEqual(abort.powerOff?.phase,"aborted");try expectEqual(abort.powerOff?.statuses.count,0);try expectEqual(abort.powerOff?.leaseSecondsRemaining,0)
        try expectEqual(await runner.recorded(),[]);await worker.closePowerOffState()
    }
    await run.test("environment reservation rejects DDEV mutation and close releases only owned prepared state") {
        let runner=PowerOffRunner();let worker=WorkerService(distribution:"Test",runner:runner)
        let project=fixtureProject("a",path:"/tmp/a")
        _=await worker.handle(try powerOffBytes("prepare","reserved",[project]))
        let mutation=await worker.handle(try JSONEncoder().encode(WorkerRequest(id:"blocked",operation:"project.start",project:project.reference)))
        try expectEqual(mutation.error?.code,"ddevBusy");try expectEqual(await runner.recorded(),[])
        await worker.closePowerOffState()
        let closed=await worker.handle(try powerOffBytes("run","reserved"));try expectEqual(closed.error?.code,"disconnected")
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-duplicate-mutation-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder.appendingPathComponent(".ddev"),withIntermediateDirectories:true)
        try Data("name: fixture\ntype: php\n".utf8).write(to:folder.appendingPathComponent(".ddev/config.yaml"))
        defer{try? FileManager.default.removeItem(at:folder)}
        let blocked=PowerOffBlockingRunner(heldCommand:"ddev start"),direct=WorkerService(distribution:"Test",runner:blocked)
        let owned=fixtureProject("own",path:folder.path)
        let bytes=try JSONEncoder().encode(WorkerRequest(id:"same-running-id",operation:"project.start",project:owned.reference))
        let first=Task{await direct.handle(bytes)}
        do {
            for _ in 0..<1000{if await blocked.hasStarted(){break};await Task.yield()}
            try expect(await blocked.hasStarted())
            let duplicate=await direct.handle(bytes);try expectEqual(duplicate.error?.code,"ddevBusy")
            let during=await direct.handle(try powerOffBytes("prepare","during-first",[owned]));try expectEqual(during.error?.code,"ddevBusy")
            first.cancel();_=await first.value
            let after=await direct.handle(try powerOffBytes("prepare","after-first",[owned]));try expectNil(after.error)
            await direct.closePowerOffState()
        }catch{first.cancel();_=await first.value;await direct.closePowerOffState();throw error}
    }
    await run.test("cancelling the group run reaps only its owned fake CLI and releases the environment after honest reconciliation") {
        let runner=PowerOffBlockingRunner();let worker=WorkerService(distribution:"Test",runner:runner)
        let project=fixtureProject("a",path:"/tmp/a")
        _=await worker.handle(try powerOffBytes("prepare","cancelled",[project]))
        let bytes=try powerOffBytes("run","cancelled")
        let task=Task{await worker.handle(bytes)}
        for _ in 0..<1000 {if await runner.hasStarted(){break};await Task.yield()}
        try expect(await runner.hasStarted());task.cancel();let response=await task.value
        try expect(await runner.wasCancelled());try expectEqual(response.powerOff?.phase,"ran")
        try expectEqual(response.powerOff?.commandState,"cancelled");try expectEqual(response.powerOff?.leaseSecondsRemaining,0)
        try expectEqual(response.powerOff?.statuses.count,0);try expectNil(response.attention)
        let aborted=await worker.handle(try powerOffBytes("abort","cancelled",active:[]))
        try expectEqual(aborted.powerOff?.phase,"aborted");try expectEqual(aborted.powerOff?.statuses.first?.state,"unknown")
        let next=await worker.handle(try powerOffBytes("prepare","after-cancel",[project]));try expectNil(next.error)
        await worker.closePowerOffState()
    }
}
