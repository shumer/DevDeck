import AppKit
import DevDeckCore
import DevDeckEngine
import ProjectKit

/// Puts a newer copy in place when the runtime's update watch says to.
///
/// Whether there is a newer build, when to look, what to say about it and whether to wait for a
/// card that is mid-command are `DeckUpdates` in the engine. This is the Mac's half: download,
/// unpack, check that what came out is this app at the promised version and signed by the same
/// identity, put the old bundle in the Trash and the new one in its place, and relaunch. The
/// rules it checks with are `UpdateCheck` in Core.
///
/// What is downloaded by the app itself carries no quarantine, so after the first install the
/// right-click-to-open dance is over for whoever runs this.
@MainActor
final class Updater {
    let updates: DeckUpdates
    private let runner: any CommandRunning

    /// Where this copy lives. Nil under `swift run`, which has no bundle to replace, so the
    /// updates stay quiet there.
    let bundleURL: URL?

    init(runtime: DeckRuntime, runner: any CommandRunning = ShellCommandRunner()) {
        self.runner = runner
        let url = Bundle.main.bundleURL
        let bundle = url.pathExtension == "app" ? url : nil
        bundleURL = bundle
        updates = runtime.watchForUpdates(
            currentVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            canInstall: bundle != nil,
            http: URLSessionHTTPClient.makeDefault()
        )
        updates.onInstall = { [weak self] update in self?.put(update) }
    }

    // MARK: The runtime's watch, as the app asks for it

    var available: AvailableUpdate? { updates.available }
    var onChange: (() -> Void)? {
        get { updates.onChange }
        set { updates.onChange = newValue }
    }
    func start() { updates.start() }
    func applyPreferences() { updates.applyPreferences() }
    func checkAndInstall() { updates.checkAndInstall() }
    func install() { updates.install() }

    // MARK: Installing

    /// The whole sequence, in order, with the running copy untouched until the new one has been
    /// unpacked and checked.
    private func put(_ update: AvailableUpdate) {
        guard let bundleURL else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await Self.download(update.asset) { [weak self] fraction in
                    Task { @MainActor in self?.updates.downloaded(fraction) }
                }
                self.updates.installing()
                let unpacked = try await self.unpack(data, named: update.asset.name)
                guard let fresh = UpdateCheck.bundle(inUnpacked: unpacked) else {
                    throw UpdateFailure("the archive holds no application")
                }
                guard UpdateCheck.verifyBundle(at: fresh, version: update.version) else {
                    throw UpdateFailure("what unpacked is not DevDeck \(update.version)")
                }
                guard UpdateCheck.trusts(update: CodeIdentity.kind(ofBundleAt: fresh), running: CodeIdentity.current()) else {
                    throw UpdateFailure("the download is not signed by the same identity as this copy")
                }
                let target = UpdateCheck.installTarget(
                    running: bundleURL,
                    isFolderWritable: FileManager.default.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path),
                    applications: Self.applicationsFolder
                )
                try await self.swap(fresh, for: target.bundle)
                if !target.replacesRunningCopy {
                    Log.app.info("Installed to \(target.bundle.path, privacy: .public) instead of the read-only \(bundleURL.path, privacy: .public)")
                    await self.retireOriginal(of: bundleURL, installedAt: target.bundle)
                }
                self.relaunch(at: target.bundle)
            } catch {
                let reason = (error as? UpdateFailure)?.reason ?? error.localizedDescription
                Log.app.error("Update failed: \(reason, privacy: .public)")
                self.updates.failed(reason)
            }
        }
    }

    /// Off the main actor: a couple of megabytes arrive as a stream, and counting them is not
    /// something the panels should wait behind.
    private nonisolated static func download(
        _ asset: ReleaseAsset,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Data {
        let (bytes, response) = try await URLSession.shared.bytes(from: asset.browserDownloadUrl)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateFailure("the download answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        var data = Data()
        data.reserveCapacity(asset.size)
        var reported = 0.0
        for try await byte in bytes {
            data.append(byte)
            // Every five percent, not every byte: each report rebuilds a settings page.
            let fraction = min(1, Double(data.count) / Double(max(asset.size, 1)))
            if fraction - reported >= 0.05 {
                reported = fraction
                progress(fraction)
            }
        }
        return data
    }

    /// `ditto`, the same as the install instructions say, into a folder of its own under the
    /// temporary directory.
    private func unpack(_ data: Data, named name: String) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevDeck-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let archive = folder.appendingPathComponent(name)
        try data.write(to: archive)
        let result = try await runner.run(
            "ditto -x -k \(LocalProjectService.shellQuoted(archive.path)) .",
            in: folder,
            timeout: 60
        )
        guard result.succeeded else {
            throw UpdateFailure(result.failureLine ?? "ditto could not unpack the archive")
        }
        return folder
    }

    /// The old bundle to the Trash, the new one to where the old one was. The Trash rather
    /// than deletion: an update that turns out wrong is one drag away from being undone. When
    /// nothing is there yet, as for a first move into Applications, the new one simply goes in.
    private func swap(_ fresh: URL, for current: URL) async throws {
        guard FileManager.default.fileExists(atPath: current.path) else {
            do {
                try FileManager.default.moveItem(at: fresh, to: current)
                return
            } catch {
                throw UpdateFailure(L("update.error.move", current.deletingLastPathComponent().path, error.localizedDescription))
            }
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.recycle([current]) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        } catch {
            throw UpdateFailure(L("update.error.trash", error.localizedDescription))
        }
        do {
            try FileManager.default.moveItem(at: fresh, to: current)
        } catch {
            throw UpdateFailure("could not put the new copy at \(current.path): \(error.localizedDescription)")
        }
    }

    /// The copy in Downloads that macOS was running a read-only shadow of, to the Trash, so the
    /// next double-click does not open the old version again from there.
    ///
    /// Asked of Security through its C symbol, looked up at run time: the call has been there
    /// since macOS 10.12 but is not in the public headers. If it is not found, or the Trash
    /// refuses, the old copy simply stays where it was and the log says so.
    private func retireOriginal(of translocated: URL, installedAt target: URL) async {
        guard translocated.path.contains("/AppTranslocation/"),
              let original = Self.originalURL(ofTranslocated: translocated),
              original.standardizedFileURL != target.standardizedFileURL,
              FileManager.default.fileExists(atPath: original.path)
        else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NSWorkspace.shared.recycle([original]) { _, error in
                if let error {
                    Log.app.error("Left the old copy at \(original.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                } else {
                    Log.app.info("Moved the old copy at \(original.path, privacy: .public) to the Trash")
                }
                continuation.resume()
            }
        }
    }

    /// `/Applications` when this user may write there, and their own `~/Applications` when not,
    /// which is where macOS itself puts apps for a user who is not an administrator.
    private static var applicationsFolder: URL {
        let shared = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if FileManager.default.isWritableFile(atPath: shared.path) { return shared }
        let own = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        try? FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        return own
    }

    private static func originalURL(ofTranslocated url: URL) -> URL? {
        typealias Original = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL")
        else { return nil }
        let function = unsafeBitCast(symbol, to: Original.self)
        return function(url as CFURL, nil)?.takeRetainedValue() as URL?
    }

    /// Leaves a shell behind that opens the new bundle once this process is gone, then quits.
    private func relaunch(at bundleURL: URL) {
        let script = UpdateCheck.relaunchScript(
            waitingFor: ProcessInfo.processInfo.processIdentifier,
            appPath: bundleURL.path
        )
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", script]
        shell.standardOutput = FileHandle.nullDevice
        shell.standardError = FileHandle.nullDevice
        do {
            try shell.run()
        } catch {
            Log.app.error("Could not arrange the relaunch: \(error.localizedDescription, privacy: .public)")
        }
        Log.app.info("Updated; quitting for the relaunch")
        NSApp.terminate(nil)
    }
}

/// Why an update stopped, in words for the menu and the settings page.
struct UpdateFailure: Error {
    let reason: String

    init(_ reason: String) {
        self.reason = reason
    }
}
