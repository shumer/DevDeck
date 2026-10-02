import DDEVKit
import DevDeckCore
import Foundation

/// An explicit host cycle avoids both repeated CLI calls and stale manual/action observations.
actor WorkerDDEVInventory {
    private var cycle: String?
    private var pending: Task<[DDEVListEntry]?, Never>?

    func list(cycle requestedCycle: String?, runner: any CommandRunning) async -> [DDEVListEntry]? {
        guard let requestedCycle else {
            invalidate()
            return await DDEVEnvironment(runner: runner).list()
        }
        if cycle != requestedCycle || pending == nil {
            cycle = requestedCycle
            pending = Task { await DDEVEnvironment(runner: runner).list() }
        }
        guard let load = pending else { return nil }
        return await withTaskCancellationHandler(operation: { await load.value }, onCancel: { load.cancel() })
    }

    func invalidate(cancelPending: Bool = true) {
        if cancelPending { pending?.cancel() }
        pending = nil
        cycle = nil
    }
    func freshList(runner: any CommandRunning) async -> ([DDEVListEntry]?,String) {
        invalidate(cancelPending:false)
        guard let result=try? await runner.run("ddev list -j",in:URL(fileURLWithPath:NSHomeDirectory(),isDirectory:true),timeout:30),result.succeeded else{return(nil,"unavailable")}
        let output=result.standardOutput
        let candidates=output.split(separator:"\n").map{String($0).trimmingCharacters(in:.whitespaces)}+[output.trimmingCharacters(in:.whitespacesAndNewlines)]
        guard candidates.contains(where:{ value in
            guard let data=value.data(using:.utf8),let root=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],root["raw"] is [[String:Any]] else{return false}
            return true
        }) else{return(nil,"invalid")}
        return(DDEVEnvironment.parseList(output),"available")
    }
}
