import AppKit
import DevDeckCore
import ProjectKit

/// Keeps the installed copy current, by asking rather than by doing.
///
/// Asks GitHub for the latest release now and then, says so when it is newer, and installs it
/// when a person chooses to: download, unpack, check that what came out is this app at the
/// promised version, put the old bundle in the Trash, the new one in its place, and relaunch.
/// Nothing is downloaded, let alone installed, without a click. The decisions are
/// `UpdateCheck` in Core, which is where the suite checks them.
///
/// What is downloaded by the app itself carries no quarantine, so after the first install
/// the right-click-to-open dance is over for whoever runs this.
@MainActor
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case available(AvailableUpdate)
        case downloading(AvailableUpdate, fraction: Double)
        case installing(AvailableUpdate)
        case failed(AvailableUpdate, reason: String)
    }

    private(set) var state: State = .idle {
        didSet { onChange?() }
    }
    /// When GitHub last answered, and what it said if it did not.
    private(set) var lastCheckedAt: Date?
    private(set) var lastCheckFailure: String?

    /// Something to redraw: the settings page, mostly.
    var onChange: (() -> Void)?
    /// A newer build has just been found, for the banner. Once per version.
    var onAvailable: ((AvailableUpdate) -> Void)?

    private let preferences: Preferences
    private let http: any HTTPClient
    private let runner: any CommandRunning
    private var loop: Task<Void, Never>?

    /// The version this copy runs, and where it lives. Both nil under `swift run`, which has
    /// no bundle to replace and no version to compare, so the updater stays quiet there.
    let currentVersion: String?
    let bundleURL: URL?

    init(
        preferences: Preferences,
        http: any HTTPClient = URLSessionHTTPClient.makeDefault(),
        runner: any CommandRunning = ShellCommandRunner()
    ) {
        self.preferences = preferences
        self.http = http
        self.runner = runner
        let url = Bundle.main.bundleURL
        bundleURL = url.pathExtension == "app" ? url : nil
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var isSupported: Bool { currentVersion != nil && bundleURL != nil }

    /// The update on offer, in whichever state it is in.
    var available: AvailableUpdate? {
        switch state {
        case .available(let update), .downloading(let update, _), .installing(let update), .failed(let update, _):
            return update
        case .idle, .checking:
            return nil
        }
    }

    // MARK: Checking

    /// Once after a pause, then every few hours. Nothing while the switch is off.
    func start() {
        loop?.cancel()
        loop = nil
        guard isSupported, preferences.checksForUpdates else {
            Log.app.info("Update checks off: supported \(self.isSupported, privacy: .public), enabled \(self.preferences.checksForUpdates, privacy: .public)")
            return
        }
        Log.app.info("Update checks armed, first in \(Int(UpdateCheck.firstCheckDelay), privacy: .public)s")
        loop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(UpdateCheck.firstCheckDelay * 1_000_000_000))
            while !Task.isCancelled {
                guard let self else { return }
                await self.check(quietly: true)
                try? await Task.sleep(nanoseconds: UInt64(UpdateCheck.interval * 1_000_000_000))
            }
        }
    }

    /// The switch was flipped in settings.
    func applyPreferences() {
        if preferences.checksForUpdates {
            if loop == nil { start() }
        } else {
            loop?.cancel()
            loop = nil
        }
    }

    /// Asked for from the settings page. Says what it found, including nothing.
    func checkNow() {
        Task { await check(quietly: false) }
    }

    /// `open -a DevDeck --args --update`: check, and install whatever is newer. Typed by a
    /// person, so it counts as the click the install otherwise waits for.
    func checkAndInstall() {
        Task {
            await check(quietly: false)
            if case .available = state { install() }
        }
    }

    /// `quietly` is the background pass: a check that could not reach GitHub keeps whatever
    /// the deck already knew rather than putting a failure in front of anyone. A check a
    /// person asked for reports it.
    private func check(quietly: Bool) async {
        guard isSupported, let current = currentVersion else { return }
        // A download in flight is not interrupted by a timer.
        switch state {
        case .downloading, .installing: return
        default: break
        }
        if !quietly { state = .checking }

        do {
            let response = try await http.send(UpdateCheck.request())
            guard (200..<300).contains(response.statusCode) else {
                throw APIError.server(status: response.statusCode, message: nil)
            }
            let release = try UpdateCheck.decode(response.body)
            lastCheckedAt = Date()
            lastCheckFailure = nil
            if let update = UpdateCheck.available(current: current, release: release) {
                let wasKnown = available?.version == update.version
                Log.app.info("Update check: \(update.version.description, privacy: .public) is available, running \(current, privacy: .public)")
                state = .available(update)
                if !wasKnown, preferences.announcedUpdate != update.version.description {
                    preferences.announcedUpdate = update.version.description
                    onAvailable?(update)
                }
            } else {
                Log.app.info("Update check: \(current, privacy: .public) is the latest")
                state = .idle
            }
        } catch {
            let reason = APIError.wrapping(error).displayMessage
            Log.app.error("Update check failed: \(reason, privacy: .public)")
            lastCheckFailure = reason
            if !quietly, case .checking = state { state = .idle }
            onChange?()
        }
    }

    // MARK: Installing

    /// The whole sequence, in order, with the running copy untouched until the new one has
    /// been unpacked and checked.
    func install() {
        guard let update = available, let bundleURL else { return }
        switch state {
        case .downloading, .installing: return
        default: break
        }
        state = .downloading(update, fraction: 0)

        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await Self.download(update.asset) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(update, fraction: fraction)
                    }
                }
                self.state = .installing(update)
                let unpacked = try await self.unpack(data, named: update.asset.name)
                guard let fresh = UpdateCheck.bundle(inUnpacked: unpacked) else {
                    throw UpdateFailure("the archive holds no application")
                }
                guard UpdateCheck.verifyBundle(at: fresh, version: update.version) else {
                    throw UpdateFailure("what unpacked is not DevDeck \(update.version)")
                }
                try await self.swap(fresh, for: bundleURL)
                self.relaunch(at: bundleURL)
            } catch {
                let reason = (error as? UpdateFailure)?.reason ?? error.localizedDescription
                Log.app.error("Update failed: \(reason, privacy: .public)")
                self.state = .failed(update, reason: reason)
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
    /// than deletion: an update that turns out wrong is one drag away from being undone.
    private func swap(_ fresh: URL, for current: URL) async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.recycle([current]) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        } catch {
            throw UpdateFailure("could not move the old copy to the Trash: \(error.localizedDescription). "
                + "Download the release and install it by hand.")
        }
        do {
            try FileManager.default.moveItem(at: fresh, to: current)
        } catch {
            throw UpdateFailure("could not put the new copy at \(current.path): \(error.localizedDescription)")
        }
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
