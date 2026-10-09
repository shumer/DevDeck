import DevDeckCore
import Foundation

/// The settings page's update row, decided: its line, its button and whether it can be pressed.
public struct DeckUpdateRow: Sendable, Equatable, Codable {
    public let summary: CheckSummary
    public let button: String
    public let isEnabled: Bool
}

/// Whether a newer build is out, and what to say about it, by asking rather than by doing.
///
/// Asks GitHub for the latest release now and then, says so when it is newer, and hands the
/// install to the shell when a person chooses it. Nothing is downloaded, let alone installed,
/// without a click. Downloading, unpacking, checking the signature and putting the new copy in
/// place are the platform's, and the shell reports how they go. The rules are `UpdateCheck` in
/// Core. See docs/adr/0032-the-update-check-in-the-engine.md.
@MainActor
public final class DeckUpdates {
    public enum State: Sendable, Equatable {
        case idle
        case checking
        case available(AvailableUpdate)
        case downloading(AvailableUpdate, fraction: Double)
        case installing(AvailableUpdate)
        case failed(AvailableUpdate, reason: String)
    }

    public private(set) var state: State = .idle {
        didSet { onChange?() }
    }
    /// When GitHub last answered, and what it said if it did not.
    public private(set) var lastCheckedAt: Date?
    public private(set) var lastCheckFailure: String?
    /// The card an install someone asked for is waiting on, while it waits.
    public private(set) var waitingFor: String?

    /// Something to redraw: the settings row and the menu.
    public var onChange: (() -> Void)?
    /// Download and install this one. The shell reports back through `downloaded(_:)`,
    /// `installing()` and `failed(_:)`, and relaunches when it is done.
    public var onInstall: ((AvailableUpdate) -> Void)?

    /// The version this copy runs; nil where there is no bundle to replace, which keeps the
    /// updates quiet.
    public let currentVersion: String?
    private let canInstall: Bool
    private unowned let runtime: DeckRuntime
    private let preferences: Preferences
    private let http: any HTTPClient
    private let clock: any DateProvider
    private let sleeper: any Sleeper
    private var loop: Task<Void, Never>?
    private var waitTask: Task<Void, Never>?

    init(
        runtime: DeckRuntime,
        preferences: Preferences,
        http: any HTTPClient,
        clock: any DateProvider,
        sleeper: any Sleeper,
        currentVersion: String?,
        canInstall: Bool
    ) {
        self.runtime = runtime
        self.preferences = preferences
        self.http = http
        self.clock = clock
        self.sleeper = sleeper
        self.currentVersion = currentVersion
        self.canInstall = canInstall
    }

    public var isSupported: Bool { currentVersion != nil && canInstall }

    /// The update on offer, in whichever state it is in.
    public var available: AvailableUpdate? {
        switch state {
        case .available(let update), .downloading(let update, _), .installing(let update), .failed(let update, _):
            return update
        case .idle, .checking:
            return nil
        }
    }

    // MARK: Checking

    /// Once after a pause, then every few hours. Nothing while the switch is off.
    public func start() {
        loop?.cancel()
        loop = nil
        guard isSupported, preferences.checksForUpdates else { return }
        loop = Task { [weak self] in
            guard let sleeper = self?.sleeper else { return }
            try? await sleeper.sleep(seconds: UpdateCheck.firstCheckDelay)
            while !Task.isCancelled {
                guard let self else { return }
                await self.check(quietly: true)
                try? await self.sleeper.sleep(seconds: UpdateCheck.interval)
            }
        }
    }

    /// The switch was flipped in settings.
    public func applyPreferences() {
        if preferences.checksForUpdates {
            if loop == nil { start() }
        } else {
            loop?.cancel()
            loop = nil
        }
    }

    /// Asked for from the settings page. Says what it found, including nothing.
    public func checkNow() {
        Task { await check(quietly: false) }
    }

    /// Checks, and installs whatever is newer: typed by a person, so it counts as the click the
    /// install otherwise waits for.
    public func checkAndInstall() {
        Task {
            await check(quietly: false)
            if case .available = state { install() }
        }
    }

    /// The settings page's one button: install what is on offer, or check.
    public func act() {
        Task { await actNow() }
    }

    /// `act()`, for a caller that waits for the check to finish.
    public func actNow() async {
        switch state {
        case .available, .failed: install()
        default: await check(quietly: false)
        }
    }

    /// `quietly` is the background pass: a check that could not reach GitHub keeps whatever the
    /// deck already knew rather than putting a failure in front of anyone. A check a person
    /// asked for reports it.
    public func check(quietly: Bool) async {
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
            lastCheckedAt = clock.now
            lastCheckFailure = nil
            if let update = UpdateCheck.available(current: current, release: release) {
                let wasKnown = available?.version == update.version
                state = .available(update)
                // One banner per version, ever: a restart is not news.
                if !wasKnown, preferences.announcedUpdate != update.version.description {
                    preferences.announcedUpdate = update.version.description
                    if preferences.notificationsEnabled, preferences.notifiesUpdates {
                        runtime.effect(.offerUpdate(
                            title: L("notify.update.title", update.version.description),
                            body: L("notify.update.body"),
                            version: update.version.description
                        ))
                    }
                }
            } else {
                state = .idle
            }
        } catch {
            lastCheckFailure = APIError.wrapping(error).displayMessage
            if !quietly, case .checking = state { state = .idle }
            onChange?()
        }
    }

    // MARK: Installing

    /// Installs what is on offer, once no card is in the middle of a command.
    ///
    /// Replacing the bundle and quitting under a running `fusion start` leaves a stack half up
    /// with nothing on screen to say so. The install was asked for, so it goes ahead by itself
    /// once the command is done.
    public func install() {
        guard let update = available, canInstall else { return }
        switch state {
        case .downloading, .installing: return
        default: break
        }
        if let working = runtime.workingCardTitle {
            waitingFor = working
            onChange?()
            waitForCommands()
            return
        }
        waitTask?.cancel()
        waitTask = nil
        waitingFor = nil
        state = .downloading(update, fraction: 0)
        onInstall?(update)
    }

    /// Looks again every few seconds until no card is working, then installs.
    private func waitForCommands() {
        guard waitTask == nil else { return }
        waitTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let sleeper = self?.sleeper else { return }
                try? await sleeper.sleep(seconds: 3)
                guard let self, !Task.isCancelled else { return }
                if let working = self.runtime.workingCardTitle {
                    if working != self.waitingFor {
                        self.waitingFor = working
                        self.onChange?()
                    }
                    continue
                }
                self.waitTask = nil
                self.install()
                return
            }
        }
    }

    /// How far the download has got.
    public func downloaded(_ fraction: Double) {
        guard case .downloading(let update, _) = state else { return }
        state = .downloading(update, fraction: fraction)
    }

    /// Downloaded; being unpacked, checked and put in place.
    public func installing() {
        guard let update = available else { return }
        state = .installing(update)
    }

    public func failed(_ reason: String) {
        guard let update = available else { return }
        state = .failed(update, reason: reason)
    }

    // MARK: Words

    /// The update, as a row of the menu's own tier, or nothing when there is none.
    public func offer() -> DeckUpdateOffer? {
        guard let update = available else { return nil }
        let version = update.version.description
        let item: AttentionItem
        switch state {
        case .available:
            if let working = waitingFor {
                item = UpdateAttention.item(version: version, phase: .waiting(card: working))
            } else {
                item = UpdateAttention.item(version: version, phase: .available)
            }
        case .downloading(_, let fraction):
            item = UpdateAttention.item(version: version, phase: .downloading(fraction: fraction))
        case .installing:
            item = UpdateAttention.item(version: version, phase: .installing)
        case .failed(_, let reason):
            item = UpdateAttention.item(version: version, phase: .failed(reason: reason))
        case .idle, .checking:
            return nil
        }
        return DeckUpdateOffer(item: item, version: version)
    }

    /// `2.1 MB`, with the deck's decimal separator rather than the machine's, so the row reads
    /// the same in the deck's language whatever the system is set to.
    static func megabytes(_ bytes: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Strings.locale
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let value = formatter.string(from: NSNumber(value: Double(bytes) / 1_000_000)) ?? ""
        return value + " MB"
    }

    /// The settings page's update row.
    public func row() -> DeckUpdateRow {
        guard isSupported else {
            return DeckUpdateRow(
                summary: CheckSummary(tone: .idle, state: L("update.notFromBundle"), detail: L("update.notFromBundle.detail")),
                button: L("update.button.check"),
                isEnabled: false
            )
        }
        switch state {
        case .available(let update):
            if let working = waitingFor {
                return DeckUpdateRow(
                    summary: CheckSummary(tone: .busy, state: L("update.waits", update.version.description), detail: L("update.waits.detail", working)),
                    button: L("update.button.update"),
                    isEnabled: false
                )
            }
            let size = Self.megabytes(update.asset.size)
            return DeckUpdateRow(
                summary: CheckSummary(tone: .busy, state: L("update.available", update.version.description), detail: size),
                button: L("update.button.update"),
                isEnabled: true
            )
        case .downloading(let update, let fraction):
            return DeckUpdateRow(
                summary: CheckSummary(tone: .busy, state: L("update.downloading", update.version.description), detail: "\(Int((fraction * 100).rounded()))%"),
                button: L("update.button.update"),
                isEnabled: false
            )
        case .installing(let update):
            return DeckUpdateRow(
                summary: CheckSummary(tone: .busy, state: L("update.installing", update.version.description), detail: ""),
                button: L("update.button.update"),
                isEnabled: false
            )
        case .failed(_, let reason):
            return DeckUpdateRow(
                summary: CheckSummary(tone: .bad, state: L("update.failed"), detail: reason),
                button: L("update.button.retry"),
                isEnabled: true
            )
        case .checking:
            return DeckUpdateRow(
                summary: CheckSummary(tone: .idle, state: L("update.checking"), detail: ""),
                button: L("update.button.check"),
                isEnabled: false
            )
        case .idle:
            if let failure = lastCheckFailure {
                return DeckUpdateRow(
                    summary: CheckSummary(tone: .busy, state: L("update.couldNotCheck"), detail: failure),
                    button: L("update.button.check"),
                    isEnabled: true
                )
            }
            if let checked = lastCheckedAt {
                let clock = DateFormatter()
                clock.locale = Strings.locale
                clock.setLocalizedDateFormatFromTemplate("j:mm")
                return DeckUpdateRow(
                    summary: CheckSummary(tone: .good, state: L("update.upToDate"), detail: L("update.upToDate.detail", currentVersion ?? "", clock.string(from: checked))),
                    button: L("update.button.check"),
                    isEnabled: true
                )
            }
            return DeckUpdateRow(
                summary: CheckSummary(tone: .idle, state: L("update.notCheckedYet"), detail: currentVersion ?? ""),
                button: L("update.button.check"),
                isEnabled: true
            )
        }
    }
}
