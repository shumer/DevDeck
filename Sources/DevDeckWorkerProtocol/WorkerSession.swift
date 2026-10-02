import Foundation

/// Read stdin independently of long-running operations so cancellation stays responsive.
public actor WorkerSession {
    private struct Operation {
        let task: Task<Void, Never>
        let projectKey: String?
        let mutates: Bool
        let ddev: Bool
    }
    private let service: WorkerService
    private let send: @Sendable (WorkerResponse) async -> Void
    private var operations: [String: Operation] = [:]
    private var closing = false

    public init(service: WorkerService, send: @escaping @Sendable (WorkerResponse) async -> Void) {
        self.service = service; self.send = send
    }
    public func accept(_ frame: WorkerFramer.Frame) async {
        guard !closing else { return }
        guard case .data(let data) = frame else {
            await send(service.failure(nil, "frameTooLarge", "Request exceeds the frame limit.")); return
        }
        guard let request = try? JSONDecoder().decode(WorkerRequest.self, from: data),
              request.protocolVersion == WorkerProtocol.version, !request.id.isEmpty, request.id.utf8.count <= 128,
              !request.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            await send(await service.handle(data)); return
        }
        guard WorkerService.validActiveProjectIDs(request.activeProjectIDs) else {
            await send(service.failure(request.id, "invalidRequest", "Active project IDs must be distinct bounded IDs without control characters.")); return
        }
        if let problem=WorkerService.validateCheckout(request,distribution:service.distribution) {
            await send(service.failure(request.id,problem.code,problem.message));return
        }
        if let problem=WorkerService.validatePowerOff(request,distribution:service.distribution) {
            await send(service.failure(request.id,problem.code,problem.message));return
        }
        if request.operation == "cancel" {
            guard let target = request.targetRequestID else {
                await send(service.failure(request.id, "missingTarget", "Cancellation requires a target request ID.")); return
            }
            guard let operation = operations[target] else {
                await send(service.failure(request.id, "operationNotFound", "The target operation is no longer running.")); return
            }
            operation.task.cancel()
            await send(WorkerResponse(id: request.id, distribution: service.distribution)); return
        }
        guard operations[request.id] == nil else {
            await send(service.failure(request.id, "duplicateRequestID", "Request ID is already running.")); return
        }
        guard operations.count < 16 else {
            await send(service.failure(request.id, "workerBusy", "Too many operations are running.")); return
        }
        if request.operation=="ddev.poweroff.prepare",operations.values.contains(where:{$0.mutates && $0.ddev}) {
            await send(service.failure(request.id,"ddevBusy","A DDEV mutation is already admitted in this session."));return
        }
        let mutates = ["project.start", "project.stop", "project.restart"].contains(request.operation)
        // Reject foreign/invalid references in the service before doing any local filesystem work.
        let projectKey = request.project.flatMap { project -> String? in
            guard project.distribution == service.distribution, WorkerService.isLinuxPath(project.path) else { return nil }
            return URL(fileURLWithPath: project.path).resolvingSymlinksInPath().standardizedFileURL.path
        }
        if let projectKey, operations.values.contains(where: { $0.projectKey == projectKey && ($0.mutates || mutates) }) {
            await send(service.failure(request.id, "projectBusy", "This project already has an operation in progress.")); return
        }
        let task = Task {
            let gate = ProgressGate()
            let response = await service.handle(data) { line in
                if let line = gate.line(line) { Task { await self.progress(request.id, line: line) } }
            }
            await finished(request.id, response: response)
        }
        operations[request.id] = Operation(task: task, projectKey: projectKey, mutates: mutates, ddev:request.project?.kind == .ddev)
    }
    private func progress(_ id: String, line: String) async {
        guard operations[id] != nil, !closing else { return }
        await send(WorkerResponse(id: id, distribution: service.distribution, event: WorkerEvent(line: line)))
    }
    private func finished(_ id: String, response: WorkerResponse) async {
        operations.removeValue(forKey: id)
        await send(response)
    }
    public func close() async {
        closing = true
        await service.beginClosePowerOffState()
        let pending = operations.values.map(\.task)
        for task in pending { task.cancel() }
        for task in pending { await task.value }
        await service.closePowerOffState()
    }
}
