#if canImport(CoreGraphics)
import CoreGraphics
#endif
import DevDeckCore
import Foundation

/// The deck runtime for a shell in another process: intents in, events out, one JSON object per
/// line.
///
/// It is what the Mac's `DeckController`, `PanelCoordinator` and menu do in process, without
/// AppKit: it hands the runtime the clicks, applies the effects that change the deck itself
/// (panels, tidy, arrangements), measures the cards with the sizes the shell reports, keeps the
/// timing the Mac keeps with its own timers, and sends whatever changed. A card, the status, a
/// menu or a log is sent when it differs from what was sent last, so a shell can draw every
/// event as it comes. See docs/engine-protocol.md and docs/adr/0033-protocol-on-the-runtime.md.
@MainActor
public final class DeckSession {
    public let runtime: DeckRuntime
    private let output: (Data) -> Void
    private let clock: any DateProvider
    private let sleeper: any Sleeper
    private let localizationRoot: URL?
    /// False for the transcripts, which run every pass by hand and send what changed with
    /// `flush()` when they choose, so nothing depends on when a task happens to run.
    private let runsLoops: Bool

    private var revision = 0
    private var isStarted = false
    /// The intent being handled, which the events it causes answer.
    private var answering: String?

    private var displays: [DisplayFrame] = []
    private var primary: DisplayFrame?
    private var placement: DeckPlacement?
    /// What the shell measured each card at, as drawn.
    private var sizes: [CardID: CGSize] = [:]

    // What was sent last, so only a change is sent again.
    private var sentCards: [CardID: SentCard] = [:]
    private var sentStatus: DeckStatusModel?
    private var sentMenu: [DeckMenuEntry]?
    private var sentDeck: DeckWireDeck?
    private var sentLogs: [CardID: DeckWireLog] = [:]

    private var flushPending = false
    private var settleTask: Task<Void, Never>?
    private var screensTask: Task<Void, Never>?
    private var logTasks: [CardID: Task<Void, Never>] = [:]
    /// Settings requests still being answered.
    private var requests: [Int: Task<Void, Never>] = [:]
    private var nextRequest = 0
    private var systemLanguage: String?
    private var sentUpdate: DeckUpdateRow?

    private struct SentCard: Equatable {
        let model: DeckCardModel?
        let menu: [DeckMenuEntry]
    }

    /// How long a card is guessed to be before the shell has measured it: the height of a list
    /// card with its three rows, which most cards are.
    static let unmeasuredHeight: Double = 182

    public init(
        runtime: DeckRuntime,
        clock: any DateProvider = SystemDateProvider(),
        sleeper: any Sleeper = TaskSleeper(),
        localizationRoot: URL? = nil,
        runsLoops: Bool = true,
        output: @escaping (Data) -> Void
    ) {
        self.runtime = runtime
        self.clock = clock
        self.sleeper = sleeper
        self.localizationRoot = localizationRoot
        self.runsLoops = runsLoops
        self.output = output
        runtime.runsLoops = runsLoops
        runtime.onChange = { [weak self] _ in self?.scheduleFlush() }
        runtime.onEffect = { [weak self] effect in self?.carryOut(effect) }
    }

    // MARK: Intents

    /// One line from the shell. A line that is not an intent is answered with a rejection, never
    /// with silence, so the shell can tell a typo from a slow engine.
    public func handle(line: Data) {
        do {
            handle(try DeckIntent.decode(line))
        } catch {
            emit(DeckEvent(revision: 0, event: "intent.rejected", id: nil)) { $0.reason = "invalidIntent" }
        }
    }

    public func handle(_ intent: DeckIntent) {
        answering = intent.id
        defer { answering = nil }
        guard isStarted || intent.intent == "session.start" else { return reject("notStarted") }

        switch intent.intent {
        case "session.start":
            guard !isStarted, let displays = intent.displays, accept(displays) else { return reject("invalidDisplays") }
            start(systemLanguage: intent.systemLanguage)
        case "displays.changed":
            guard let displays = intent.displays, accept(displays) else { return reject("invalidDisplays") }
            screensChanged()
        case "card.measured":
            guard let card = intent.card, let size = intent.size, size.count == 2,
                  size.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100_000 })
            else { return reject("invalidSize") }
            sizes[card] = CGSize(width: size[0], height: size[1])
            apply(placement?.syncSizes())
        case "card.moved":
            guard let card = intent.card, let numbers = intent.frame, let frame = DeckWireGeometry.rect(numbers)
            else { return reject("invalidFrame") }
            moved(card, to: frame)
        case "command":
            guard let command = intent.command else { return reject("invalidCommand") }
            runtime.perform(command)
        case "logWindow.changed":
            guard let card = intent.card, let isOpen = intent.isOpen else { return reject("invalidCard") }
            logWindow(card, isOpen: isOpen)
        case "settings":
            guard let request = intent.request else { return reject("invalidRequest") }
            answer(request, to: intent.id)
        case "update.check":
            track { await $0.runtime.updates?.check(quietly: false) }
        case "update.act":
            track { await $0.runtime.updates?.actNow() }
        case "update.progress":
            guard let fraction = intent.fraction, fraction.isFinite, (0...1).contains(fraction) else { return reject("invalidFraction") }
            runtime.updates?.downloaded(fraction)
        case "update.installing":
            runtime.updates?.installing()
        case "update.failed":
            runtime.updates?.failed(intent.reason ?? "")
        case "session.stop":
            stop()
        default:
            reject("unknownIntent")
        }
        flush()
    }

    /// Stops every loop. The projects keep running: they belong to the machine, not to the deck.
    public func stop() {
        runtime.stop()
        settleTask?.cancel()
        screensTask?.cancel()
        for task in logTasks.values { task.cancel() }
        logTasks = [:]
        for task in requests.values { task.cancel() }
        requests = [:]
    }

    /// Waits for every settings request in flight and for the runtime's own work, then sends
    /// what changed. For the transcripts.
    public func settle() async {
        while let task = requests.values.first {
            await task.value
        }
        await runtime.settle()
        flush()
    }

    // MARK: Updates

    /// Watches for a newer build, for a host that has one to replace. The shell installs it when
    /// asked and reports how that goes.
    public func watchForUpdates(currentVersion: String?, canInstall: Bool, http: any HTTPClient) {
        let updates = runtime.watchForUpdates(currentVersion: currentVersion, canInstall: canInstall, http: http)
        updates.onChange = { [weak self] in
            self?.sendUpdate()
            self?.scheduleFlush()
        }
        updates.onInstall = { [weak self] update in
            self?.send(effect: "installUpdate") {
                $0.update = DeckWireUpdate(
                    version: update.version.description, asset: update.asset.browserDownloadUrl.absoluteString,
                    size: update.asset.size, page: update.pageURL.absoluteString
                )
            }
        }
        if isStarted {
            sendUpdate()
            if runsLoops { updates.start() }
        }
    }

    private func sendUpdate() {
        guard isStarted, let row = runtime.updates?.row(), row != sentUpdate else { return }
        sentUpdate = row
        emit("update.changed") { $0.update = row }
    }

    // MARK: Settings

    /// Work an intent started that finishes later, kept so `settle()` and `stop()` can reach it.
    private func track(_ work: @escaping (DeckSession) async -> Void) {
        nextRequest += 1
        let key = nextRequest
        // What it sends carries no id: other intents are handled while it waits, and an id on an
        // event is a promise about which intent caused it.
        requests[key] = Task { [weak self] in
            guard let self else { return }
            await work(self)
            self.requests[key] = nil
            self.flush()
        }
    }

    /// Answered when the engine has the answer, which for a check can be seconds; the answer
    /// carries the request's id.
    private func answer(_ request: DeckSettingsRequest, to id: String) {
        nextRequest += 1
        let key = nextRequest
        requests[key] = Task { [weak self] in
            guard let self else { return }
            let answer = await self.runtime.answer(request)
            self.requests[key] = nil
            guard !Task.isCancelled else { return }
            self.answering = id
            defer { self.answering = nil }
            self.emit("settings.answered") { $0.answer = answer }
            if request.changesDeck { self.settingsChanged() }
            if case .setPreferences = request { self.preferencesChanged() }
            self.flush()
        }
    }

    /// What the Mac does when anything in settings changed: the cards may have come or gone, a
    /// project taken out takes its log window with it, and the data is fetched again.
    private func settingsChanged() {
        apply(placement?.sync())
        let known = Set(runtime.cards.resolved.map(\.id))
        for card in runtime.logWindowCards.sorted(by: { $0.rawValue < $1.rawValue }) where !known.contains(card) {
            send(effect: "closeLogs") { $0.card = card }
        }
        runtime.refreshNow()
    }

    /// Every deck-wide setting put into effect at once: the language, the panels' lock and
    /// layer, the update watch, packed columns.
    private func preferencesChanged() {
        Strings.use(language(system: systemLanguage), lookingIn: localizationRoot)
        sendDeck()
        if runsLoops { runtime.updates?.applyPreferences() }
        if runtime.preferences.packsColumns { apply(placement?.packAllColumns()) }
    }

    // MARK: Starting

    private func start(systemLanguage: String?) {
        isStarted = true
        self.systemLanguage = systemLanguage
        Strings.use(language(system: systemLanguage), lookingIn: localizationRoot)
        placement = runtime.placePanels(
            measure: { [weak self] card in
                self?.measure(card) ?? CGSize(width: CardMetrics.width, height: Self.unmeasuredHeight)
            },
            displays: { [weak self] in
                guard let self else { return DeckDisplays(screens: [], main: nil, fallback: nil) }
                return DeckDisplays(screens: self.displays, main: self.primary, fallback: self.primary ?? self.displays.first)
            }
        )
        sendDeck()
        apply(placement?.sync())
        if runtime.preferences.packsColumns { apply(placement?.packAllColumns()) }
        sendUpdate()
        if runsLoops {
            runtime.start()
            runtime.updates?.start()
        }
    }

    /// The deck's own language, or the system's when the deck says to follow it: English when
    /// the system's is not one the deck speaks.
    private func language(system: String?) -> AppLanguage {
        let chosen = runtime.preferences.language
        guard chosen == .system else { return chosen }
        let code = String((system ?? "").prefix(2)).lowercased()
        return AppLanguage(rawValue: code).flatMap { $0 == .system ? nil : $0 } ?? .english
    }

    private func accept(_ wire: [DeckIntent.Display]) -> Bool {
        var frames: [DisplayFrame] = []
        var primary: DisplayFrame?
        for display in wire {
            guard !display.id.isEmpty, let frame = DeckWireGeometry.rect(display.frame) else { return false }
            let made = DisplayFrame(id: display.id, visibleFrame: frame)
            frames.append(made)
            if display.isPrimary { primary = made }
        }
        guard !frames.isEmpty, Set(frames.map(\.id)).count == frames.count else { return false }
        displays = frames
        self.primary = primary ?? frames.first
        return true
    }

    // MARK: Panels

    private func measure(_ card: CardID) -> CGSize {
        // A folded card is one fixed row; it is never measured.
        if runtime.isCollapsed(card) {
            return CGSize(width: CardMetrics.width, height: CollapsedCardMetrics.height)
        }
        return sizes[card] ?? CGSize(width: CardMetrics.width, height: Self.unmeasuredHeight)
    }

    private func apply(_ changes: [DeckPanelChange]?) {
        guard let changes, !changes.isEmpty else { return }
        emit("panels.changed") { $0.panels = changes.map(DeckWireGeometry.panel) }
    }

    /// A panel moved without the engine moving it. Written down once the screens have stayed
    /// quiet, because the system's own moves come a moment before it says the screens changed.
    private func moved(_ card: CardID, to frame: CGRect) {
        guard let placement else { return }
        schedule(settleAt: placement.moved(card, to: frame, at: now))
    }

    private func schedule(settleAt due: TimeInterval?) {
        settleTask?.cancel()
        settleTask = nil
        guard let due, runsLoops else { return }
        let delay = max(due - now, 0) + 0.01
        settleTask = Task { [weak self] in
            try? await self?.sleeper.sleep(seconds: delay)
            guard let self, !Task.isCancelled else { return }
            self.schedule(settleAt: self.placement?.settleMoves(at: self.now))
        }
    }

    /// The screens changed: whatever moves were waiting were the system's. The deck is put back
    /// once the displays have settled.
    private func screensChanged() {
        placement?.screensChanged()
        settleTask?.cancel()
        settleTask = nil
        screensTask?.cancel()
        guard runsLoops else { return placeAfterScreensChanged() }
        screensTask = Task { [weak self] in
            try? await self?.sleeper.sleep(seconds: DeckPlacement.screensSettle)
            guard let self, !Task.isCancelled else { return }
            self.placeAfterScreensChanged()
            self.flush()
        }
    }

    private func placeAfterScreensChanged() {
        apply(placement?.placeAfterScreensChanged())
    }

    private var now: TimeInterval { clock.now.timeIntervalSinceReferenceDate }

    // MARK: Logs

    private func logWindow(_ card: CardID, isOpen: Bool) {
        logTasks[card]?.cancel()
        logTasks[card] = nil
        guard isOpen else {
            runtime.logWindowClosed(card)
            sentLogs[card] = nil
            return
        }
        runtime.logWindowOpened(card)
        runtime.refreshLogsNow(for: card)
        guard runsLoops else { return }
        logTasks[card] = Task { [weak self] in
            while !Task.isCancelled {
                try? await self?.sleeper.sleep(seconds: DeckRuntime.logWindowInterval)
                guard let self, !Task.isCancelled else { return }
                self.runtime.refreshLogsNow(for: card)
            }
        }
    }

    // MARK: Effects

    private func carryOut(_ effect: DeckEffect) {
        switch effect {
        case .announce(let alerts):
            emit("notify") { event in
                event.notifications = alerts.map { alert in
                    DeckWireNotification(
                        id: alert.id, source: alert.source.rawValue, title: alert.title, subtitle: alert.subtitle,
                        body: alert.body, isQuiet: alert.isQuiet, command: .followAlert(alert.target)
                    )
                }
            }
        case .offerUpdate(let title, let body, let version):
            emit("notify") { event in
                event.notifications = [DeckWireNotification(
                    id: "update.\(version)", source: DeckAlert.Source.devdeck.rawValue, title: title, subtitle: "",
                    body: body, isQuiet: true, command: .installUpdate
                )]
            }
        case .openLogs(let card):
            send(effect: "openLogs") { $0.card = card }
        case .closeLogs(let card):
            send(effect: "closeLogs") { $0.card = card }
        case .launchDocker:
            send(effect: "launchDocker")
        case .attentionChanged:
            scheduleFlush()
        case .openURL(let url, let browser):
            send(effect: "openURL") {
                $0.url = url.absoluteString
                $0.browser = browser
            }
        case .openSetting(let setting):
            send(effect: "openSettings") {
                $0.page = "cards"
                $0.item = setting.rawValue
            }
        case .openTerminal(let folder):
            send(effect: "openTerminal") { $0.folder = Self.platformPath(folder) }
        case .revealFolder(let folder):
            send(effect: "revealFolder") { $0.folder = Self.platformPath(folder) }
        case .cardsChanged:
            apply(placement?.sync())
            scheduleFlush()
        case .lockChanged:
            sendDeck()
        case .tidy:
            apply(placement?.tidy())
        case .openSettings:
            send(effect: "openSettings")
        case .openCardSettings(let card):
            send(effect: "openSettings") { $0.card = card }
        case .openAccountSettings(let service, let account):
            send(effect: "openSettings") {
                $0.page = service.rawValue
                $0.item = account
            }
        case .showCard(let card):
            send(effect: "present") { $0.card = card }
        case .openMenu:
            send(effect: "openMenu")
        case .installUpdate:
            runtime.updates?.install()
        case .quit:
            stop()
            send(effect: "quit")
        case .arrangementApplied:
            apply(placement?.sync())
            apply(placement?.placeAfterScreensChanged())
        }
    }

    /// A folder as the platform spells it: `C:\Users\demo\site` on Windows, `/Users/demo/site`
    /// on the Mac.
    public static func platformPath(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
    }

    private func sendDeck() {
        let deck = DeckWireDeck(isLocked: runtime.preferences.isLocked, displayMode: runtime.preferences.displayMode)
        guard deck != sentDeck else { return }
        sentDeck = deck
        emit("deck.changed") { $0.deck = deck }
    }

    // MARK: Changes

    private func scheduleFlush() {
        guard !flushPending, isStarted, runsLoops else { return }
        flushPending = true
        Task { [weak self] in self?.flush() }
    }

    /// Sends every card, the status, the menu and the open logs that differ from what the shell
    /// has, then lets the panels follow the cards' new sizes.
    public func flush() {
        flushPending = false
        guard isStarted else { return }
        let visible = runtime.cards.visible
        for card in visible {
            let current = SentCard(model: runtime.model(for: card), menu: runtime.cardMenu(for: card))
            guard current != sentCards[card] else { continue }
            sentCards[card] = current
            emit("card.changed") {
                $0.card = card
                $0.model = current.model
                $0.menu = current.menu
            }
        }
        for card in sentCards.keys where !visible.contains(card) {
            sentCards[card] = nil
        }

        let status = runtime.status()
        if status != sentStatus {
            sentStatus = status
            emit("status.changed") { $0.status = status }
        }
        let menu = runtime.menu()
        if menu != sentMenu {
            sentMenu = menu
            emit("menu.changed") { $0.menu = menu }
        }

        for card in runtime.logWindowCards.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let lines = runtime.logs(for: card) else { continue }
            let log = DeckWireLog(lines: lines.lines, source: lines.source, detail: lines.detail)
            guard log != sentLogs[card] else { continue }
            sentLogs[card] = log
            emit("log.changed") {
                $0.card = card
                $0.log = log
            }
        }

        apply(placement?.syncSizes())
    }

    // MARK: Sending

    private func send(effect kind: String, _ fill: (inout DeckWireEffect) -> Void = { _ in }) {
        var effect = DeckWireEffect(kind)
        fill(&effect)
        emit("effect") { $0.effect = effect }
    }

    private func reject(_ reason: String) {
        emit("intent.rejected") { $0.reason = reason }
    }

    private func emit(_ name: String, _ fill: (inout DeckEvent) -> Void) {
        emit(DeckEvent(revision: 0, event: name, id: answering), fill)
    }

    private func emit(_ event: DeckEvent, _ fill: (inout DeckEvent) -> Void) {
        revision += 1
        var event = event
        event.revision = revision
        fill(&event)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(event), data.count <= DeckIntent.maximumSize else {
            Log.app.debug("Could not encode an engine event.")
            return
        }
        output(data + Data([0x0A]))
    }
}
