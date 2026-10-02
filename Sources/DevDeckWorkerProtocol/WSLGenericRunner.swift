import DevDeckCore
import Foundation
import Glibc
import ProjectKit
import WSLProcessSupport

/// Reuses ProjectKit's log/status model while giving detached Linux processes a verified session.
struct WSLGenericRunner: CommandRunning {
    let base: any CommandRunning
    let project: LocalProject
    let files: ProjectRuntimeFiles

    var identityFile: URL { files.pid(project.id).appendingPathExtension("identity") }

    func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
             onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        let detached = LocalProjectService.detachedCommand(project.startCommand, log: files.log(project.id), pidFile: files.pid(project.id))
        if command == detached {
            // Spawn directly instead of backgrounding a shell: PID/session ownership exists before return.
            try Task.checkCancellation()
            let path = await ShellPath.shared.value(runner: base)
            try Task.checkCancellation()
            let log = files.log(project.id)
            guard FileManager.default.createFile(atPath: log.path, contents: Data()) else { throw CommandError.launchFailed("Cannot create project log.") }
            let output = try FileHandle(forWritingTo: log)
            defer { try? output.close() }
            var pid: pid_t = 0
            let result = path.withCString { environmentPath in
                devdeck_spawn_session(ShellCommandRunner.defaultShell, project.startCommand, directory.path, environmentPath, 0,
                                      output.fileDescriptor, output.fileDescriptor, &pid)
            }
            guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(result)) }
            let child = pid
            DispatchQueue.global().async { var status: Int32 = 0; _ = devdeck_wait_child(child, &status) }
            do {
                try Data(String(pid).utf8).write(to: files.pid(project.id), options: .atomic)
                if let identity = ProcessIdentity.current(pid) { try JSONEncoder().encode(identity).write(to: identityFile, options: .atomic) }
            } catch { _ = devdeck_signal_group(pid, SIGKILL); throw error }
            if Task.isCancelled { _ = devdeck_signal_group(pid, SIGKILL); throw CancellationError() }
            return CommandResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        if let text = try? String(contentsOf: files.pid(project.id), encoding: .utf8),
           let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), command == LocalProjectService.killTreeCommand(pid: pid) {
            guard let data = try? Data(contentsOf: identityFile), let identity = try? JSONDecoder().decode(ProcessIdentity.self, from: data),
                  identity == ProcessIdentity.current(pid), getsid(pid) == pid, getpgid(pid) == pid else {
                throw CommandError.launchFailed("The recorded process no longer belongs to this project.")
            }
            let members = ProcessIdentity.members(of: pid)
            // Complete the owned cleanup even if the caller cancels Stop halfway through it.
            try await Task.detached { try await Self.stopGroup(pid, members: members) }.value
            try? FileManager.default.removeItem(at: identityFile)
            return CommandResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        return try await base.run(command, in: directory, timeout: timeout, isInteractive: isInteractive, onOutput: onOutput)
    }

    private static func stopGroup(_ pid: pid_t, members: [ProcessIdentity]) async throws {
        func remains() -> Bool { members.contains(where: { $0 == ProcessIdentity.current($0.pid) && getpgid($0.pid) == pid }) }
        _ = devdeck_signal_group(pid, SIGTERM)
        for _ in 0..<20 {
            if !remains() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        if remains() { _ = devdeck_signal_group(pid, SIGKILL) }
        for _ in 0..<100 {
            if !remains() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CommandError.launchFailed("An owned project process did not stop.")
    }
}

private struct ProcessIdentity: Codable, Sendable, Equatable {
    let pid: Int32
    let started: String
    static func current(_ pid: Int32) -> ProcessIdentity? {
        guard pid > 1, let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8), let closing = stat.lastIndex(of: ")") else { return nil }
        let fields = stat[stat.index(after: closing)...].split(separator: " ")
        guard fields.count > 19, fields[0] != "Z" else { return nil }
        return ProcessIdentity(pid: pid, started: String(fields[19]))
    }
    static func members(of group: Int32) -> [ProcessIdentity] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/proc")) ?? []
        return names.compactMap { name in
            guard let pid = Int32(name), getpgid(pid) == group else { return nil }
            return current(pid)
        }
    }
}
