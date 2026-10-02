import DDEVKit
import DevDeckCore
import Foundation

public struct WorkerDDEVPowerOffProject: Codable, Sendable, Equatable {
    public let id: String
    public let distribution: String
    public let kind: String
    public let path: String
    public let title: String?
    public init(id: String, distribution: String, kind: String = "ddev", path: String, title: String? = nil) {
        self.id=id; self.distribution=distribution; self.kind=kind; self.path=path; self.title=title
    }
    var project: WorkerProject { WorkerProject(id: id, distribution: distribution, kind: .ddev, path: path, title: title) }
}

public struct WorkerDDEVPowerOffContext: Codable, Sendable, Equatable {
    public let groupToken: String
    public let projects: [WorkerDDEVPowerOffProject]?
    public init(groupToken: String, projects: [WorkerDDEVPowerOffProject]? = nil) { self.groupToken=groupToken; self.projects=projects }
}

public struct WorkerDDEVPowerOffResult: Codable, Sendable {
    public let groupToken: String
    public let workerInstanceID: String
    public let phase: String
    public let leaseSecondsRemaining: Int
    public let commandState: String
    public let commandExitCode: Int32?
    public let diagnostic: WorkerFailure?
    public let inventoryState: String
    public let statuses: [WorkerStatus]
    public init(groupToken: String, workerInstanceID: String, phase: String, leaseSecondsRemaining: Int,
                commandState: String, commandExitCode: Int32? = nil, diagnostic: WorkerFailure? = nil,
                inventoryState: String = "notChecked", statuses: [WorkerStatus] = []) {
        self.groupToken=groupToken; self.workerInstanceID=workerInstanceID; self.phase=phase
        self.leaseSecondsRemaining=leaseSecondsRemaining; self.commandState=commandState
        self.commandExitCode=commandExitCode; self.diagnostic=diagnostic; self.inventoryState=inventoryState; self.statuses=statuses
    }
}

/// A monotonic lease clock; independent of wall-clock check timestamps.
public protocol WorkerLeaseClock: Sendable {
    func now() async -> Double
    func sleep(until deadline: Double) async throws
}
public struct WorkerContinuousLeaseClock: WorkerLeaseClock {
    private let clock=ContinuousClock()
    private let origin: ContinuousClock.Instant
    public init() { origin=ContinuousClock().now }
    public func now() async -> Double {
        let value=origin.duration(to: clock.now).components
        return Double(value.seconds)+Double(value.attoseconds)/1e18
    }
    public func sleep(until deadline: Double) async throws { try await clock.sleep(until: origin.advanced(by: .seconds(deadline))) }
}

struct PowerOffCommandOutcome: Sendable {
    let state: String
    let exitCode: Int32?
    let diagnostic: WorkerFailure?
}
private actor PowerOffRecordingRunner: CommandRunning {
    let base: any CommandRunning
    let progress: (@Sendable (String)->Void)?
    private var failure: WorkerFailure?
    init(base: any CommandRunning, progress: (@Sendable (String)->Void)?) { self.base=base; self.progress=progress }
    func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
             onOutput: (@Sendable (String)->Void)?) async throws -> CommandResult {
        do { return try await base.run(command, in: directory, timeout: timeout, isInteractive: isInteractive, onOutput: onOutput ?? progress) }
        catch {
            if error is CancellationError { failure=WorkerFailure(code: "cancelled", message: "DDEV poweroff was cancelled; containers may already have stopped.") }
            else if let problem=error as? CommandError,case .timedOut = problem { failure=WorkerFailure(code: "timedOut", message: "DDEV poweroff exceeded its deadline; final state must be checked.") }
            else { failure=WorkerFailure(code: "ddevUnavailable", message: "DDEV poweroff could not be executed in this distribution.") }
            throw error
        }
    }
    func outcome(_ result: CommandResult?) -> PowerOffCommandOutcome {
        if let failure { return PowerOffCommandOutcome(state: failure.code == "ddevUnavailable" ? "unavailable" : failure.code, exitCode: nil, diagnostic: failure) }
        guard let result else { return PowerOffCommandOutcome(state: "unavailable", exitCode: nil, diagnostic: WorkerFailure(code: "ddevUnavailable", message: "DDEV poweroff did not return a result.")) }
        return PowerOffCommandOutcome(state: result.succeeded ? "succeeded" : "failed", exitCode: result.exitCode,
            diagnostic: result.succeeded ? nil : WorkerFailure(code: "commandFailed", message: "DDEV poweroff failed. Final physical state is reported separately."))
    }
}

/// Reservations survive individual RPCs. Only this transaction's CLI child is cancellable here.
actor WorkerPowerOffCoordinator {
    private struct Group {
        let token: String
        let projects: [WorkerDDEVPowerOffProject]
        var deadline: Double
        var phase="preparing"
        var entered=false
        var outcome=PowerOffCommandOutcome(state: "notRun", exitCode: nil, diagnostic: nil)
        var task: Task<PowerOffCommandOutcome,Never>?
    }
    private let distribution: String
    private let instance=UUID().uuidString
    private let runner: any CommandRunning
    private let clock: any WorkerLeaseClock
    private let dates: any DateProvider
    private let attention: WorkerAttentionState
    private let inventory: WorkerDDEVInventory
    private var group: Group?
    private var sleeper: Task<Void,Never>?
    private var terminal: [String:(WorkerDDEVPowerOffResult,WorkerAttentionSnapshot?)] = [:]
    private var individualMutations=Set<String>()
    private var closed=false
    init(distribution: String, runner: any CommandRunning, clock: any WorkerLeaseClock, dates: any DateProvider,
         attention: WorkerAttentionState, inventory: WorkerDDEVInventory) {
        self.distribution=distribution; self.runner=runner; self.clock=clock; self.dates=dates; self.attention=attention; self.inventory=inventory
    }
    func beginMutation(_ id: String) -> Bool { guard !closed, group == nil, !individualMutations.contains(id) else { return false }; individualMutations.insert(id); return true }
    func endMutation(_ id: String) { individualMutations.remove(id) }
    func reserved() -> Bool { group != nil }
    private func receipt(_ value: Group, phase: String, now: Double, inventoryState: String="notChecked", statuses: [WorkerStatus]=[], diagnostic: WorkerFailure?=nil) -> WorkerDDEVPowerOffResult {
        WorkerDDEVPowerOffResult(groupToken: value.token, workerInstanceID: instance, phase: phase,
            leaseSecondsRemaining: ["finalized","aborted"].contains(phase) ? 0 : max(0,min(600,Int(ceil(value.deadline-now)))), commandState: value.outcome.state,
            commandExitCode: value.outcome.exitCode, diagnostic: diagnostic ?? value.outcome.diagnostic, inventoryState: inventoryState, statuses: statuses)
    }
    private func fail(_ id: String, _ code: String, _ message: String) -> WorkerResponse {
        WorkerResponse(id:id, distribution:distribution, error:WorkerFailure(code:code,message:message))
    }
    func handle(_ request: WorkerRequest, progress: (@Sendable (String)->Void)?) async -> WorkerResponse {
        let token=request.powerOff!.groupToken
        if let stored=terminal[token] {
            guard request.operation=="ddev.poweroff."+stored.0.phase.replacingOccurrences(of:"finalized",with:"finalize").replacingOccurrences(of:"aborted",with:"abort") else{return fail(request.id,"groupCompleted","This DDEV transaction has already completed.")}
            let snapshot=await attention.snapshot(distribution:distribution,now:dates.now,activeProjectIDs:request.activeProjectIDs)
            return WorkerResponse(id:request.id,distribution:distribution,attention:snapshot,powerOff:stored.0)
        }
        if closed { return fail(request.id,"disconnected","The worker is closing.") }
        let now=await clock.now()
        if let current=group, current.deadline <= now { await expire(token:current.token, deadline:current.deadline) }
        if terminal[token] != nil {return fail(request.id,"groupCompleted","This DDEV transaction has already expired or completed.")}
        if request.operation == "ddev.poweroff.prepare" {
            let projects=request.powerOff!.projects!
            if var current=group {
                guard current.token==token, current.projects==projects, ["prepared","ran"].contains(current.phase) else { return fail(request.id,"groupBusy","Another DDEV transaction or phase is in progress.") }
                current.deadline=now+600; group=current; scheduleLease(current)
                return WorkerResponse(id:request.id,distribution:distribution,powerOff:receipt(current,phase:"prepared",now:now))
            }
            guard individualMutations.isEmpty else { return fail(request.id,"ddevBusy","A DDEV project mutation is already in progress.") }
            var current=Group(token:token,projects:projects,deadline:now+600); group=current
            await attention.preparePowerOff(token:token, projects:projects.map(\.project))
            await inventory.invalidate(cancelPending:false)
            guard !closed, group?.token==token else { return fail(request.id,"disconnected","Preparation was interrupted.") }
            current.phase="prepared"; group=current; scheduleLease(current)
            return WorkerResponse(id:request.id,distribution:distribution,powerOff:receipt(current,phase:"prepared",now:now))
        }
        guard var current=group, current.token==token else { return fail(request.id,"groupNotPrepared","This DDEV transaction has not been prepared in this worker.") }
        if request.operation == "ddev.poweroff.run" {
            if current.phase=="ran" { return WorkerResponse(id:request.id,distribution:distribution,powerOff:receipt(current,phase:"ran",now:now)) }
            guard current.phase=="prepared" else { return fail(request.id,"groupBusy","This DDEV transaction is already executing or finishing.") }
            current.phase="running"; current.entered=true
            let recorder=PowerOffRecordingRunner(base:runner,progress:progress)
            let task=Task { let result=await DDEVEnvironment(runner:recorder).powerOff(); return await recorder.outcome(result) }
            current.task=task; group=current
            let result=await withTaskCancellationHandler(operation:{ await task.value },onCancel:{ task.cancel() })
            await inventory.invalidate(cancelPending:false)
            if closed {return fail(request.id,"disconnected","The worker is closing; the DDEV command may have partially completed.")}
            guard var latest=group, latest.token==token else {
                if let stored=terminal[token] {
                    let value=stored.0
                    return WorkerResponse(id:request.id,distribution:distribution,powerOff:WorkerDDEVPowerOffResult(groupToken:token,workerInstanceID:instance,
                        phase:"ran",leaseSecondsRemaining:0,commandState:value.commandState,commandExitCode:value.commandExitCode,diagnostic:value.diagnostic))
                }
                return fail(request.id,"disconnected","DDEV transaction ended while the worker was closing.")
            }
            // Expiry may already own reconciliation. Never replace its finalizing phase or
            // start another inventory, and keep every run reply in the run wire shape.
            if latest.phase=="finalizing" {
                return WorkerResponse(id:request.id,distribution:distribution,powerOff:WorkerDDEVPowerOffResult(groupToken:token,workerInstanceID:instance,
                    phase:"ran",leaseSecondsRemaining:0,commandState:result.state,commandExitCode:result.exitCode,diagnostic:result.diagnostic))
            }
            latest.task=nil; latest.phase="ran"; latest.outcome=result; group=latest
            if Task.isCancelled {
                _=await finish(request,aborted:true)
                return WorkerResponse(id:request.id,distribution:distribution,powerOff:WorkerDDEVPowerOffResult(groupToken:token,workerInstanceID:instance,
                    phase:"ran",leaseSecondsRemaining:0,commandState:result.state,commandExitCode:result.exitCode,diagnostic:result.diagnostic))
            }
            return WorkerResponse(id:request.id,distribution:distribution,powerOff:receipt(latest,phase:"ran",now:await clock.now()))
        }
        guard ["prepared","ran"].contains(current.phase) else { return fail(request.id,"groupBusy","DDEV command is still executing or finishing.") }
        return await finish(request,aborted:request.operation=="ddev.poweroff.abort")
    }
    private func finish(_ request: WorkerRequest, aborted: Bool) async -> WorkerResponse {
        let token=request.powerOff!.groupToken
        guard var current=group, current.token==token else { return fail(request.id,"groupNotPrepared","This DDEV transaction is no longer prepared.") }
        current.phase="finalizing"; group=current; sleeper?.cancel(); sleeper=nil
        if aborted && !current.entered {
            let snapshot=await attention.abortPowerOff(token:token, distribution:distribution, now:dates.now, activeProjectIDs:request.activeProjectIDs)
            let result=receipt(current,phase:"aborted",now:await clock.now())
            remember(result,snapshot);group=nil
            return WorkerResponse(id:request.id,distribution:distribution,attention:snapshot,powerOff:result)
        }
        // This child completes physical reconciliation even if the parent request is cancelled.
        let inventory=inventory,runner=runner
        let physical=await Task.detached { await inventory.freshList(runner:runner) }.value
        let references=await attention.powerOffReferences(token:token)
        let environment=DDEVEnvironment(runner:runner,clock:dates)
        let statuses=references.map { WorkerService.ddevStatus($0,environment:environment,entries:physical.0,includeCheckedAt:true) }
        let indexed=Dictionary(uniqueKeysWithValues:statuses.map{($0.projectID,$0)})
        let snapshot=await attention.finishPowerOff(token:token, statuses:indexed, distribution:distribution, now:dates.now, activeProjectIDs:request.activeProjectIDs)
        await inventory.invalidate(cancelPending:false)
        let returned=current.projects.map { indexed[$0.id] ?? WorkerStatus(projectID:$0.id,state:"unknown",checkedAt:dates.now.timeIntervalSince1970) }
        let diagnostic: WorkerFailure?
        if let failure=current.outcome.diagnostic {diagnostic=failure}
        else if physical.1 != "available" { diagnostic=WorkerFailure(code:"outcomeNotConfirmed",message:"Fresh DDEV inventory is unavailable or invalid; stopped state is not confirmed.") }
        else if returned.contains(where:{$0.state != "stopped"}) { diagnostic=WorkerFailure(code:"outcomeNotConfirmed",message:"Some configured DDEV projects are still running or their stopped state is unknown.") }
        else { diagnostic=current.outcome.diagnostic }
        let result=receipt(current,phase:aborted ? "aborted" : "finalized",now:await clock.now(),inventoryState:physical.1,statuses:returned,diagnostic:diagnostic)
        remember(result,snapshot);group=nil
        return WorkerResponse(id:request.id,distribution:distribution,attention:snapshot,powerOff:result)
    }
    private func remember(_ value: WorkerDDEVPowerOffResult, _ snapshot: WorkerAttentionSnapshot?) {
        if terminal.count>=16, let first=terminal.keys.first { terminal.removeValue(forKey:first) }
        terminal[value.groupToken]=(value,snapshot)
    }
    private func scheduleLease(_ value: Group) {
        sleeper?.cancel();let clock=clock
        sleeper=Task { [weak self] in
            do { try await clock.sleep(until:value.deadline);try Task.checkCancellation();await self?.expire(token:value.token,deadline:value.deadline) } catch { }
        }
    }
    private func expire(token: String, deadline: Double) async {
        guard let current=group,current.token==token,current.deadline==deadline,current.phase != "finalizing" else{return}
        current.task?.cancel();if let task=current.task {_=await task.value}
        guard var latest=group,latest.token==token,latest.phase != "finalizing" else{return}
        if let task=latest.task {latest.outcome=await task.value;latest.task=nil}
        latest.phase="ran";group=latest
        _=await finish(WorkerRequest(id:"lease-expired",operation:"ddev.poweroff.abort",powerOff:WorkerDDEVPowerOffContext(groupToken:token)),aborted:true)
    }
    func beginClose() {
        closed=true;sleeper?.cancel();sleeper=nil;group?.task?.cancel()
    }
    func close() async {
        beginClose()
        let pending=group?.task;pending?.cancel();if let pending {_=await pending.value}
        if let current=group {_=await attention.abortPowerOff(token:current.token,distribution:distribution,now:dates.now,activeProjectIDs:[])}
        group=nil;terminal.removeAll()
        await inventory.invalidate(cancelPending:false)
    }
}
