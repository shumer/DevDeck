#if os(Windows)
import Foundation
import WinSDK

final class WindowsHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: HANDLE?

    init(_ handle: HANDLE?) throws {
        guard let handle, handle != INVALID_HANDLE_VALUE else {
            throw CommandError.launchFailed("Could not open a Windows process resource.")
        }
        self.handle = handle
    }

    var raw: HANDLE? {
        lock.lock()
        defer { lock.unlock() }
        return handle
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if let handle {
            CloseHandle(handle)
            self.handle = nil
        }
    }

    deinit {
        close()
    }
}

struct WindowsChild: Sendable {
    let process: WindowsHandle
    let thread: WindowsHandle
    let pid: DWORD

    var creationTime: UInt64? {
        var created = FILETIME()
        var exited = FILETIME()
        var kernel = FILETIME()
        var user = FILETIME()
        guard GetProcessTimes(process.raw, &created, &exited, &kernel, &user) else { return nil }
        return UInt64(created.dwHighDateTime) << 32 | UInt64(created.dwLowDateTime)
    }
}

enum WindowsProcessSupport {
    // These input-attribute macros are not imported by the Windows Swift SDK.
    private static let handleListAttribute: DWORD_PTR = 0x0002_0002
    private static let jobListAttribute: DWORD_PTR = 0x0002_000D

    static func quote(_ argument: String) -> String {
        if !argument.isEmpty, !argument.contains(where: { $0.isWhitespace || $0 == "\"" }) {
            return argument
        }
        var result = "\""
        var backslashes = 0
        for character in argument {
            if character == "\\" {
                backslashes += 1
            } else {
                result += String(
                    repeating: "\\", count: character == "\"" ? backslashes * 2 + 1 : backslashes)
                result.append(character)
                backslashes = 0
            }
        }
        return result + String(repeating: "\\", count: backslashes * 2) + "\""
    }

    static func pipe() throws -> (read: WindowsHandle, write: WindowsHandle) {
        var security = SECURITY_ATTRIBUTES()
        security.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
        security.bInheritHandle = true
        var read: HANDLE?
        var write: HANDLE?
        guard CreatePipe(&read, &write, &security, 0) else {
            throw CommandError.launchFailed("Could not create Windows command pipes.")
        }
        return (try WindowsHandle(read), try WindowsHandle(write))
    }

    static func file(_ path: String, writing: Bool) throws -> WindowsHandle {
        var security = SECURITY_ATTRIBUTES()
        security.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
        security.bInheritHandle = true
        var name = Array((path + "\0").utf16)
        let handle = name.withUnsafeMutableBufferPointer {
            CreateFileW(
                $0.baseAddress, writing ? DWORD(bitPattern: GENERIC_WRITE) : DWORD(GENERIC_READ),
                DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), &security,
                DWORD(writing && path != "NUL" ? CREATE_ALWAYS : OPEN_EXISTING),
                DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        return try WindowsHandle(handle)
    }

    static func job(named name: String?, killOnClose: Bool) throws -> WindowsHandle {
        let handle: HANDLE?
        if let name {
            var wideName = Array((name + "\0").utf16)
            handle = wideName.withUnsafeMutableBufferPointer { CreateJobObjectW(nil, $0.baseAddress) }
            guard GetLastError() != DWORD(ERROR_ALREADY_EXISTS) else {
                if let handle { CloseHandle(handle) }
                throw CommandError.launchFailed("The project job already exists.")
            }
        } else {
            handle = CreateJobObjectW(nil, nil)
        }
        let job = try WindowsHandle(handle)
        if killOnClose {
            var limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
            limits.BasicLimitInformation.LimitFlags = DWORD(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
            guard
                SetInformationJobObject(
                    job.raw, JobObjectExtendedLimitInformation, &limits,
                    DWORD(MemoryLayout.size(ofValue: limits)))
            else {
                throw CommandError.launchFailed("Could not configure command cleanup.")
            }
        }
        return job
    }

    static func openJob(named name: String) throws -> WindowsHandle {
        var wideName = Array((name + "\0").utf16)
        let handle = wideName.withUnsafeMutableBufferPointer {
            OpenJobObjectW(DWORD(JOB_OBJECT_QUERY | JOB_OBJECT_TERMINATE), false, $0.baseAddress)
        }
        return try WindowsHandle(handle)
    }

    static func activeProcesses(_ job: WindowsHandle) -> DWORD? {
        var accounting = JOBOBJECT_BASIC_ACCOUNTING_INFORMATION()
        guard
            QueryInformationJobObject(
                job.raw, JobObjectBasicAccountingInformation, &accounting,
                DWORD(MemoryLayout.size(ofValue: accounting)), nil)
        else { return nil }
        return accounting.ActiveProcesses
    }

    static func create(
        executable: String, commandLine: String, directory: String, flags: DWORD,
        input: WindowsHandle, output: WindowsHandle, error: WindowsHandle,
        job: WindowsHandle?, environment: [String: String], inheritJobHandle: Bool = false
    ) throws -> WindowsChild {
        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        startup.StartupInfo.dwFlags = DWORD(STARTF_USESTDHANDLES)
        startup.StartupInfo.hStdInput = input.raw
        startup.StartupInfo.hStdOutput = output.raw
        startup.StartupInfo.hStdError = error.raw
        let attributeCount: DWORD = job == nil ? 1 : 2
        var attributeBytes: SIZE_T = 0
        InitializeProcThreadAttributeList(nil, attributeCount, 0, &attributeBytes)
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: Int(attributeBytes), alignment: MemoryLayout<UInt>.alignment)
        defer { memory.deallocate() }
        let attributes = OpaquePointer(memory)
        guard InitializeProcThreadAttributeList(attributes, attributeCount, 0, &attributeBytes) else {
            throw CommandError.launchFailed("Could not initialize Windows process attributes.")
        }
        defer { DeleteProcThreadAttributeList(attributes) }
        var handles = [input.raw, output.raw, error.raw]
        if inheritJobHandle, let job {
            guard SetHandleInformation(job.raw, DWORD(HANDLE_FLAG_INHERIT), DWORD(HANDLE_FLAG_INHERIT)) else {
                throw CommandError.launchFailed("Could not retain the project job in its host.")
            }
            handles.append(job.raw)
        }
        // Distinct handles avoid undocumented duplicate entries in the inheritance allowlist.
        handles = Array(Set(handles.compactMap { $0 })).map { Optional($0) }
        var inheritedJob: HANDLE? = job?.raw ?? nil
        let child = try handles.withUnsafeMutableBufferPointer { handleBuffer in
            // Attribute values must remain at the same address until CreateProcessW consumes them.
            try withUnsafeMutablePointer(to: &inheritedJob) { jobPointer in
                guard
                    UpdateProcThreadAttribute(
                        attributes, 0, handleListAttribute, handleBuffer.baseAddress,
                        SIZE_T(handleBuffer.count * MemoryLayout<HANDLE?>.size), nil, nil)
                else {
                    throw CommandError.launchFailed("Could not isolate Windows process handles.")
                }
                if job != nil {
                    guard
                        UpdateProcThreadAttribute(
                            attributes, 0, jobListAttribute, jobPointer,
                            SIZE_T(MemoryLayout<HANDLE?>.size), nil, nil)
                    else {
                        throw CommandError.launchFailed("Could not attach the Windows process job.")
                    }
                }
                startup.lpAttributeList = attributes
                var application = Array((executable + "\0").utf16)
                var arguments = Array((commandLine + "\0").utf16)
                var workingDirectory = Array((directory + "\0").utf16)
                let environmentText =
                    environment.keys.sorted { $0.lowercased() < $1.lowercased() }
                    .map { "\($0)=\(environment[$0]!)" }.joined(separator: "\0") + "\0\0"
                var environmentBlock = Array(environmentText.utf16)
                var information = PROCESS_INFORMATION()
                let created = application.withUnsafeMutableBufferPointer { applicationBuffer in
                    arguments.withUnsafeMutableBufferPointer { argumentBuffer in
                        workingDirectory.withUnsafeMutableBufferPointer { directoryBuffer in
                            environmentBlock.withUnsafeMutableBufferPointer { environmentBuffer in
                                withUnsafeMutablePointer(to: &startup) { startupPointer in
                                    startupPointer.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1) {
                                        CreateProcessW(
                                            applicationBuffer.baseAddress, argumentBuffer.baseAddress,
                                            nil, nil, true,
                                            flags
                                                | DWORD(
                                                    EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT),
                                            environmentBuffer.baseAddress, directoryBuffer.baseAddress,
                                            $0, &information)
                                    }
                                }
                            }
                        }
                    }
                }
                guard created else {
                    throw CommandError.launchFailed("Could not launch the Windows command.")
                }
                return WindowsChild(
                    process: try WindowsHandle(information.hProcess),
                    thread: try WindowsHandle(information.hThread), pid: information.dwProcessId)
            }
        }
        return child
    }

    static func write(_ data: Data, to handle: WindowsHandle) throws {
        var offset = 0
        while offset < data.count {
            var written: DWORD = 0
            let succeeded = data.withUnsafeBytes {
                WriteFile(
                    handle.raw, $0.baseAddress?.advanced(by: offset), DWORD(data.count - offset), &written,
                    nil)
            }
            guard succeeded, written > 0 else {
                throw CommandError.launchFailed("Could not send project startup data.")
            }
            offset += Int(written)
        }
    }

    static func drain(_ handle: WindowsHandle, onOutput: (@Sendable (String) -> Void)?) -> Data {
        var result = Data()
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            var read: DWORD = 0
            let succeeded = buffer.withUnsafeMutableBytes {
                ReadFile(handle.raw, $0.baseAddress, 4096, &read, nil)
            }
            guard succeeded, read > 0 else { break }
            let chunk = Data(buffer.prefix(Int(read)))
            result.append(chunk)
            if let onOutput {
                pending.append(chunk)
                while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                    let line = String(decoding: pending[..<end], as: UTF8.self)
                    pending.removeSubrange(...end)
                    if !line.isEmpty { onOutput(line) }
                }
            }
        }
        if let onOutput, !pending.isEmpty { onOutput(String(decoding: pending, as: UTF8.self)) }
        return result
    }
}
#endif
