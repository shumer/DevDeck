#if os(Windows)
import Foundation
import WinSDK

public protocol DetachedProjectLaunching: Sendable {
    func launchProject(_ command: String, in directory: URL) throws -> DetachedProjectClient
}

public final class DetachedProjectClient: @unchecked Sendable {
    private let processHandle: HANDLE?

    fileprivate init(processHandle: HANDLE?) {
        self.processHandle = processHandle
    }

    deinit {
        CloseHandle(processHandle)
    }

    public func terminate() {
        TerminateProcess(processHandle, 125)
    }
}

extension ShellCommandRunner {
    public func launchProject(_ command: String, in directory: URL) throws -> DetachedProjectClient {
        try Task.checkCancellation()
        let systemRoot = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
        let executable = systemRoot + "\\System32\\wsl.exe"
        // A single encoded payload keeps shell quoting out of Windows command-line parsing.
        let encodedCommand = Data(command.utf8).base64EncodedString()
        let foreground = "printf %s \(encodedCommand) | base64 --decode | setsid --wait /bin/bash"
        let arguments = [
            executable, "-d", distribution, "--cd", directory.path,
            "--exec", "bash", "-lc", foreground,
        ]
        var commandLine = Array((arguments.map(Self.windowsArgument).joined(separator: " ") + "\0").utf16)
        var application = Array((executable + "\0").utf16)
        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        var security = SECURITY_ATTRIBUTES()
        security.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
        security.bInheritHandle = true
        var nullName = Array("NUL\0".utf16)
        let nullHandle = nullName.withUnsafeMutableBufferPointer {
            CreateFileW(
                $0.baseAddress, DWORD(GENERIC_READ) | DWORD(bitPattern: GENERIC_WRITE),
                DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), &security,
                DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard nullHandle != INVALID_HANDLE_VALUE else {
            throw CommandError.launchFailed("Could not prepare detached WSL handles.")
        }
        defer { CloseHandle(nullHandle) }
        startup.StartupInfo.dwFlags = DWORD(STARTF_USESTDHANDLES)
        startup.StartupInfo.hStdInput = nullHandle
        startup.StartupInfo.hStdOutput = nullHandle
        startup.StartupInfo.hStdError = nullHandle
        var attributeBytes: SIZE_T = 0
        InitializeProcThreadAttributeList(nil, 1, 0, &attributeBytes)
        let attributeMemory = UnsafeMutableRawPointer.allocate(
            byteCount: Int(attributeBytes), alignment: MemoryLayout<UInt>.alignment)
        defer { attributeMemory.deallocate() }
        let attributes = OpaquePointer(attributeMemory)
        guard InitializeProcThreadAttributeList(attributes, 1, 0, &attributeBytes) else {
            throw CommandError.launchFailed("Could not initialize WSL handle isolation.")
        }
        defer { DeleteProcThreadAttributeList(attributes) }
        var inheritedHandle = nullHandle
        guard
            UpdateProcThreadAttribute(
                attributes, 0, Self.handleListAttribute,
                &inheritedHandle, SIZE_T(MemoryLayout<HANDLE?>.size), nil, nil)
        else {
            throw CommandError.launchFailed("Could not isolate WSL handles.")
        }
        startup.lpAttributeList = attributes
        var information = PROCESS_INFORMATION()
        // Only the independent NUL handle is inherited, so no engine pipe or console remains attached.
        let flags = DWORD(DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | EXTENDED_STARTUPINFO_PRESENT)
        let created = application.withUnsafeMutableBufferPointer { applicationBuffer in
            commandLine.withUnsafeMutableBufferPointer { commandBuffer in
                withUnsafeMutablePointer(to: &startup) { startupPointer in
                    startupPointer.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1) {
                        CreateProcessW(
                            applicationBuffer.baseAddress, commandBuffer.baseAddress,
                            nil, nil, true, flags, nil, nil, $0, &information)
                    }
                }
            }
        }
        guard created else {
            throw CommandError.launchFailed("Could not launch the independent WSL project.")
        }
        CloseHandle(information.hThread)
        // Closing this handle after a successful start leaves the independent process running.
        return DetachedProjectClient(processHandle: information.hProcess)
    }

    // WinSDK does not import the function-like PROC_THREAD_ATTRIBUTE_HANDLE_LIST macro.
    private static let handleListAttribute: DWORD_PTR = 0x0002_0002

    // Windows parses backslashes before quotes differently from a Linux shell.
    private static func windowsArgument(_ argument: String) -> String {
        if !argument.isEmpty, !argument.contains(where: { $0.isWhitespace || $0 == "\"" }) {
            return argument
        }
        var quoted = "\""
        var backslashes = 0
        for character in argument {
            if character == "\\" {
                backslashes += 1
            } else {
                quoted += String(
                    repeating: "\\", count: character == "\"" ? backslashes * 2 + 1 : backslashes)
                quoted.append(character)
                backslashes = 0
            }
        }
        quoted += String(repeating: "\\", count: backslashes * 2)
        return quoted + "\""
    }
}
#endif
