import Foundation
#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#endif

/// Where the running deck listens for an agent on this machine, for this user only, and how a
/// question gets there and back.
///
/// One line of JSON each way per connection. The deck answers; it never calls out. A Unix socket
/// in Application Support on the Mac, readable and writable by its owner alone and checked
/// against the caller's user id on every connection; a named pipe on Windows, refusing remote
/// clients, with an access list that names the current user and nobody else. See
/// docs/adr/0036-agent-access.md.
public enum LocalEndpoint {
    /// The longest line either side accepts, the same bound the shell protocol has.
    public static let maximumLine = 1 << 20

    /// Where this user's deck listens.
    public static var address: String {
        #if os(Windows)
        // A pipe name is global on the machine, so the user is in it. Backslashes would make
        // it a path.
        let user = (ProcessInfo.processInfo.environment["USERNAME"] ?? "user")
            .replacingOccurrences(of: "\\", with: "-")
        return "\\\\.\\pipe\\DevDeck.Agent." + user
        #else
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("DevDeck/agent.sock").path
        #endif
    }
}

public enum LocalEndpointError: Error, Equatable, Sendable {
    /// Nothing listens: the deck is not running, or agent access is off.
    case notListening
    /// Something else went wrong, in the system's words.
    case failed(String)
}

/// Waits for an `async` answer on a thread that may block, which is what a connection is.
private final class AnswerBox: @unchecked Sendable {
    var value = ""
}

private func waitFor(_ operation: @escaping @Sendable () async -> String) -> String {
    let semaphore = DispatchSemaphore(value: 0)
    let box = AnswerBox()
    Task {
        box.value = await operation()
        semaphore.signal()
    }
    semaphore.wait()
    return box.value
}

/// Accepts connections and hands each line to `handler`, one connection at a time per thread.
public final class LocalEndpointServer: @unchecked Sendable {
    public typealias Handler = @Sendable (String) async -> String

    public let address: String
    private let handler: Handler
    private let lock = NSLock()
    private var isStopping = false
    private var isRunning = false
    #if os(Windows)
    private var security: PipeSecurity?
    #else
    private var listener: Int32 = -1
    #endif

    public init(address: String = LocalEndpoint.address, handler: @escaping Handler) {
        self.address = address
        self.handler = handler
    }

    public var running: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning && !isStopping
    }

    #if os(Windows)

    public func start() throws {
        let security = try PipeSecurity()
        // The first instance is made here, so a name somebody else already holds fails the start
        // rather than the loop.
        let first = try makeInstance(first: true, security: security)
        lock.lock()
        self.security = security
        isRunning = true
        isStopping = false
        lock.unlock()
        Thread.detachNewThread { [self] in acceptLoop(first, security: security) }
    }

    public func stop() {
        lock.lock()
        guard isRunning, !isStopping else {
            lock.unlock()
            return
        }
        isStopping = true
        lock.unlock()
        // ConnectNamedPipe waits for a client; one that connects and goes is what wakes it.
        if let wake = try? WindowsPipe.open(address) { wake.close() }
    }

    private func makeInstance(first: Bool, security: PipeSecurity) throws -> WindowsHandle {
        var name = Array((address + "\0").utf16)
        let openMode = DWORD(PIPE_ACCESS_DUPLEX) | (first ? DWORD(FILE_FLAG_FIRST_PIPE_INSTANCE) : 0)
        let pipeMode = DWORD(PIPE_TYPE_BYTE) | DWORD(PIPE_READMODE_BYTE) | DWORD(PIPE_WAIT) | DWORD(PIPE_REJECT_REMOTE_CLIENTS)
        let handle = name.withUnsafeMutableBufferPointer {
            CreateNamedPipeW($0.baseAddress, openMode, pipeMode, DWORD(PIPE_UNLIMITED_INSTANCES), 65536, 65536, 0, security.attributes)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else {
            throw LocalEndpointError.failed("CreateNamedPipe failed with \(GetLastError())")
        }
        return try WindowsHandle(handle)
    }

    private func acceptLoop(_ first: WindowsHandle, security: PipeSecurity) {
        var pipe = first
        while true {
            let connected = ConnectNamedPipe(pipe.raw, nil) || GetLastError() == DWORD(ERROR_PIPE_CONNECTED)
            lock.lock()
            let stopping = isStopping
            lock.unlock()
            if stopping {
                pipe.close()
                break
            }
            if connected {
                let served = pipe
                DispatchQueue.global().async { [self] in serve(served) }
            } else {
                pipe.close()
            }
            guard let next = try? makeInstance(first: false, security: security) else { break }
            pipe = next
        }
        lock.lock()
        isRunning = false
        isStopping = false
        self.security = nil
        lock.unlock()
    }

    private func serve(_ pipe: WindowsHandle) {
        defer {
            FlushFileBuffers(pipe.raw)
            DisconnectNamedPipe(pipe.raw)
            pipe.close()
        }
        guard let line = WindowsPipe.readLine(pipe) else { return }
        let handler = self.handler
        let answer = waitFor { await handler(line) }
        WindowsPipe.write(answer + "\n", to: pipe)
    }

    #else

    public func start() throws {
        let url = URL(fileURLWithPath: address)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        unlink(address)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalEndpointError.failed(String(cString: strerror(errno))) }
        guard var socketAddress = UnixSocket.address(address) else {
            close(fd)
            throw LocalEndpointError.failed("the socket path is too long")
        }
        let bound = withUnsafePointer(to: &socketAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        // Owner only. Until this runs the file has the umask's mode, which gives nobody else
        // write access, and connecting needs write access.
        guard bound == 0, chmod(address, 0o600) == 0, listen(fd, 8) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            unlink(address)
            throw LocalEndpointError.failed(reason)
        }
        lock.lock()
        listener = fd
        isRunning = true
        isStopping = false
        lock.unlock()
        Thread.detachNewThread { [self] in acceptLoop(fd) }
    }

    public func stop() {
        lock.lock()
        guard isRunning, !isStopping else {
            lock.unlock()
            return
        }
        isStopping = true
        lock.unlock()
        // accept() does not return because its socket was closed under it, on every system;
        // a connection that comes and goes does.
        if let wake = try? UnixSocket.connect(address) { close(wake) }
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            lock.lock()
            let stopping = isStopping
            lock.unlock()
            if stopping {
                if client >= 0 { close(client) }
                break
            }
            guard client >= 0 else {
                if errno == EINTR || errno == ECONNABORTED { continue }
                break
            }
            // The caller is this user, by the kernel's word and not only the file's mode.
            var uid = uid_t()
            var gid = gid_t()
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                close(client)
                continue
            }
            DispatchQueue.global().async { [self] in serve(client) }
        }
        close(fd)
        unlink(address)
        lock.lock()
        listener = -1
        isRunning = false
        isStopping = false
        lock.unlock()
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        UnixSocket.noSignalOnBrokenPipe(client)
        guard let line = UnixSocket.readLine(client) else { return }
        let handler = self.handler
        let answer = waitFor { await handler(line) }
        UnixSocket.write(answer + "\n", to: client)
    }

    #endif
}

/// Asks the deck one thing and returns its answer.
public enum LocalEndpointClient {
    /// `timeout` bounds the wait for the answer, which for a project starting is minutes.
    public static func request(_ line: String, address: String = LocalEndpoint.address, timeout: TimeInterval = 300) throws -> String {
        #if os(Windows)
        let pipe = try WindowsPipe.open(address)
        defer { pipe.close() }
        WindowsPipe.write(line + "\n", to: pipe)
        guard let answer = WindowsPipe.readLine(pipe) else { throw LocalEndpointError.failed("the deck closed the connection") }
        return answer
        #else
        let fd = try UnixSocket.connect(address)
        defer { close(fd) }
        UnixSocket.noSignalOnBrokenPipe(fd)
        var wait = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        UnixSocket.write(line + "\n", to: fd)
        guard let answer = UnixSocket.readLine(fd) else { throw LocalEndpointError.failed("the deck did not answer") }
        return answer
        #endif
    }
}

#if os(Windows)

/// The access list a pipe is made with: this user, everything; nobody else, nothing.
final class PipeSecurity: @unchecked Sendable {
    let attributes: UnsafeMutablePointer<SECURITY_ATTRIBUTES>
    private let descriptor: UnsafeMutableRawPointer
    private let acl: UnsafeMutableRawPointer
    private let tokenUser: UnsafeMutableRawPointer

    init() throws {
        var token: HANDLE?
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else {
            throw LocalEndpointError.failed("OpenProcessToken failed with \(GetLastError())")
        }
        defer { CloseHandle(token) }
        var size: DWORD = 0
        _ = GetTokenInformation(token, TokenUser, nil, 0, &size)
        guard size > 0 else { throw LocalEndpointError.failed("GetTokenInformation failed with \(GetLastError())") }
        let tokenUser = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        guard GetTokenInformation(token, TokenUser, tokenUser, size, &size) else {
            tokenUser.deallocate()
            throw LocalEndpointError.failed("GetTokenInformation failed with \(GetLastError())")
        }
        let sid = tokenUser.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid
        let aclSize = MemoryLayout<ACL>.size + MemoryLayout<ACCESS_ALLOWED_ACE>.size + Int(GetLengthSid(sid))
        let acl = UnsafeMutableRawPointer.allocate(byteCount: aclSize, alignment: 16)
        let descriptor = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<SECURITY_DESCRIPTOR>.size, alignment: 16)
        let aclPointer = acl.assumingMemoryBound(to: ACL.self)
        guard InitializeAcl(aclPointer, DWORD(aclSize), DWORD(ACL_REVISION)),
              AddAccessAllowedAce(aclPointer, DWORD(ACL_REVISION), DWORD(GENERIC_ALL), sid),
              InitializeSecurityDescriptor(descriptor, DWORD(SECURITY_DESCRIPTOR_REVISION)),
              SetSecurityDescriptorDacl(descriptor, true, aclPointer, false)
        else {
            tokenUser.deallocate()
            acl.deallocate()
            descriptor.deallocate()
            throw LocalEndpointError.failed("the pipe's access list could not be made: \(GetLastError())")
        }
        let attributes = UnsafeMutablePointer<SECURITY_ATTRIBUTES>.allocate(capacity: 1)
        attributes.initialize(to: SECURITY_ATTRIBUTES(
            nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
            lpSecurityDescriptor: descriptor,
            bInheritHandle: false
        ))
        self.tokenUser = tokenUser
        self.acl = acl
        self.descriptor = descriptor
        self.attributes = attributes
    }

    deinit {
        attributes.deallocate()
        descriptor.deallocate()
        acl.deallocate()
        tokenUser.deallocate()
    }
}

enum WindowsPipe {
    static func open(_ address: String) throws -> WindowsHandle {
        var name = Array((address + "\0").utf16)
        for _ in 0..<5 {
            let handle = name.withUnsafeMutableBufferPointer {
                CreateFileW($0.baseAddress, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), 0, nil, DWORD(OPEN_EXISTING), 0, nil)
            }
            if let handle, handle != INVALID_HANDLE_VALUE { return try WindowsHandle(handle) }
            let error = GetLastError()
            if error == DWORD(ERROR_PIPE_BUSY) {
                _ = name.withUnsafeMutableBufferPointer { WaitNamedPipeW($0.baseAddress, 2000) }
                continue
            }
            if error == DWORD(ERROR_FILE_NOT_FOUND) { throw LocalEndpointError.notListening }
            throw LocalEndpointError.failed("CreateFile on the pipe failed with \(error)")
        }
        throw LocalEndpointError.notListening
    }

    static func readLine(_ pipe: WindowsHandle) -> String? {
        var line = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while line.count <= LocalEndpoint.maximumLine {
            var read: DWORD = 0
            let succeeded = buffer.withUnsafeMutableBytes { ReadFile(pipe.raw, $0.baseAddress, DWORD(4096), &read, nil) }
            guard succeeded, read > 0 else { break }
            let chunk = buffer.prefix(Int(read))
            if let end = chunk.firstIndex(of: 10) {
                line.append(contentsOf: chunk[..<end])
                return String(decoding: line, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            }
            line.append(contentsOf: chunk)
        }
        return line.isEmpty ? nil : String(decoding: line, as: UTF8.self)
    }

    static func write(_ text: String, to pipe: WindowsHandle) {
        let data = Array(text.utf8)
        var offset = 0
        while offset < data.count {
            var written: DWORD = 0
            let succeeded = data.withUnsafeBytes {
                WriteFile(pipe.raw, $0.baseAddress?.advanced(by: offset), DWORD(data.count - offset), &written, nil)
            }
            guard succeeded, written > 0 else { return }
            offset += Int(written)
        }
    }
}

#else

enum UnixSocket {
    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
        }
        return address
    }

    static func connect(_ path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalEndpointError.failed(String(cString: strerror(errno))) }
        guard var socketAddress = address(path) else {
            close(fd)
            throw LocalEndpointError.failed("the socket path is too long")
        }
        let connected = withUnsafePointer(to: &socketAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            let error = errno
            close(fd)
            if error == ENOENT || error == ECONNREFUSED { throw LocalEndpointError.notListening }
            throw LocalEndpointError.failed(String(cString: strerror(error)))
        }
        return fd
    }

    static func noSignalOnBrokenPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    static func readLine(_ fd: Int32) -> String? {
        var line = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while line.count <= LocalEndpoint.maximumLine {
            let count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, 4096, 0) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            let chunk = buffer.prefix(count)
            if let end = chunk.firstIndex(of: 10) {
                line.append(contentsOf: chunk[..<end])
                return String(decoding: line, as: UTF8.self)
            }
            line.append(contentsOf: chunk)
        }
        return line.isEmpty ? nil : String(decoding: line, as: UTF8.self)
    }

    static func write(_ text: String, to fd: Int32) {
        let data = Array(text.utf8)
        var offset = 0
        while offset < data.count {
            let sent = data.withUnsafeBytes { send(fd, $0.baseAddress?.advanced(by: offset), data.count - offset, 0) }
            if sent < 0, errno == EINTR { continue }
            guard sent > 0 else { return }
            offset += sent
        }
    }
}

#endif
