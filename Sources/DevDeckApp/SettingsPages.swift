import AppKit
import DevDeckCore
import GitHubKit
import GitLabKit
import ArcKit
import DDEVKit
import ProjectKit

// The four pages at the top of the settings sidebar. They were one General page of seven groups,
// three screens long, with the switch you came for two scrolls down; now each fits the window.

// MARK: - General

/// Start at login, updates, and which build this is.
@MainActor
final class GeneralSettingsPage: NSObject, SettingsPage {
    let kind = SettingsWindowController.Section.general
    var title: String { L("settings.general.title") }
    var icon: NSImage { SettingsIcons.general }
    weak var host: SettingsHost?

    private let preferences: Preferences
    private let updater: Updater
    private weak var updateLine: StatusLine?
    private weak var updateButton: NSButton?

    init(preferences: Preferences, updater: Updater) {
        self.preferences = preferences
        self.updater = updater
    }

    func build(in container: FlippedContainer) {
        let form = SettingsForm(in: container)
        form.pageHeader(icon: SettingsIcons.tile("gearshape.fill", color: .systemGray, size: 32), title: title, subtitle: AppVersion.summary)

        form.beginGroup()
        form.settingRow(
            L("settings.general.startAtLogin"),
            control: SettingsForm.makeSwitch(isOn: LoginItem.isEnabled, title: L("settings.general.startAtLogin"), target: self, action: #selector(loginItemChanged(_:)))
        )
        let language = NSPopUpButton()
        for choice in AppLanguage.choices {
            language.addItem(withTitle: choice.title)
            language.lastItem?.representedObject = choice.rawValue
        }
        language.selectItem(at: AppLanguage.choices.firstIndex(of: preferences.language) ?? 0)
        language.target = self
        language.action = #selector(languageChanged(_:))
        language.setAccessibilityLabel(L("settings.language"))
        form.settingRow(L("settings.language"), subtitle: L("settings.language.detail"), control: language)
        form.endGroup()

        form.section(L("settings.general.updates"))
        form.beginGroup()
        form.settingRow(
            L("settings.general.checkAutomatically"),
            subtitle: L("settings.general.checkAutomatically.detail"),
            control: SettingsForm.makeSwitch(isOn: preferences.checksForUpdates, title: L("settings.general.checkAutomatically"), target: self, action: #selector(updatesChanged(_:)))
        )
        let status = updateStatus
        let line = StatusLine(tone: status.tone, state: status.title, detail: status.detail)
        let button = SettingsForm.button(status.button, target: self, action: #selector(updateAction))
        button.isEnabled = status.isEnabled
        form.statusRow(line, button: button)
        form.endGroup()
        updateLine = line
        updateButton = button

        form.footnote(AppVersion.isTranslocated
            ? L("settings.general.runningTranslocated")
            : L("settings.general.runningFrom", AppVersion.location))
    }

    /// Called when the updater moves, so the row changes where it stands without the page
    /// being rebuilt under the pointer.
    func refreshUpdateRow() {
        guard let updateLine, let updateButton else { return }
        let status = updateStatus
        updateLine.update(tone: status.tone, state: status.title, detail: status.detail)
        updateButton.title = status.button
        updateButton.isEnabled = status.isEnabled
    }

    private var updateStatus: (tone: StatusLine.Tone, title: String, detail: String, button: String, isEnabled: Bool) {
        let clock = DateFormatter()
        clock.locale = Strings.locale
        clock.setLocalizedDateFormatFromTemplate("j:mm")
        guard updater.isSupported else {
            return (.idle, L("update.notFromBundle"), L("update.notFromBundle.detail"), L("update.button.check"), false)
        }
        switch updater.state {
        case .available(let update):
            if let working = updater.waitingFor {
                return (.busy, L("update.waits", update.version.description), L("update.waits.detail", working), L("update.button.update"), false)
            }
            let size = ByteCountFormatter.string(fromByteCount: Int64(update.asset.size), countStyle: .file)
            return (.busy, L("update.available", update.version.description), size, L("update.button.update"), true)
        case .downloading(let update, let fraction):
            return (.busy, L("update.downloading", update.version.description), "\(Int((fraction * 100).rounded()))%", L("update.button.update"), false)
        case .installing(let update):
            return (.busy, L("update.installing", update.version.description), "", L("update.button.update"), false)
        case .failed(_, let reason):
            return (.bad, L("update.failed"), reason, L("update.button.retry"), true)
        case .checking:
            return (.idle, L("update.checking"), "", L("update.button.check"), false)
        case .idle:
            if let failure = updater.lastCheckFailure {
                return (.busy, L("update.couldNotCheck"), failure, L("update.button.check"), true)
            }
            if let checked = updater.lastCheckedAt {
                return (.good, L("update.upToDate"), L("update.upToDate.detail", updater.currentVersion ?? "", clock.string(from: checked)), L("update.button.check"), true)
            }
            return (.idle, L("update.notCheckedYet"), updater.currentVersion ?? "", L("update.button.check"), true)
        }
    }

    @objc private func loginItemChanged(_ sender: NSSwitch) {
        // Put back to what macOS ended up doing: the registration can fail, and a switch that
        // stays on while the login item is not is a setting that lies.
        sender.state = LoginItem.set(sender.state == .on) ? .on : .off
    }

    /// The whole interface follows at once: the window is rebuilt, and the menu and the cards
    /// read their words fresh every time they are drawn.
    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: raw)
        else { return }
        preferences.language = language
        Strings.use(language)
        host?.reloadList()
        host?.reloadDetail()
        host?.changed()
    }

    @objc private func updatesChanged(_ sender: NSSwitch) {
        preferences.checksForUpdates = sender.state == .on
        updater.applyPreferences()
    }

    @objc private func updateAction() {
        switch updater.state {
        case .available, .failed: updater.install()
        default: updater.checkNow()
        }
    }
}

// MARK: - Deck

/// Where the cards sit, and the shortcut that brings them forward.
@MainActor
final class DeckSettingsPage: NSObject, SettingsPage {
    let kind = SettingsWindowController.Section.deck
    var title: String { L("settings.deck.title") }
    var icon: NSImage { SettingsIcons.deck }
    weak var host: SettingsHost?

    private let preferences: Preferences
    private weak var recorder: HotKeyRecorderView?
    /// What the shortcut's own switch turns on and off with it, the way a dependent control is
    /// greyed out in System Settings rather than left live with nothing behind it.
    private var summonControls: [NSView] = []

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func build(in container: FlippedContainer) {
        let form = SettingsForm(in: container)
        form.pageHeader(icon: SettingsIcons.tile("rectangle.stack.fill", color: .systemBlue, size: 32), title: title, subtitle: L("settings.deck.subtitle"))
        summonControls = []

        form.section(L("settings.deck.position"))
        form.beginGroup()
        let placement = NSPopUpButton()
        for mode in DisplayMode.allCases {
            placement.addItem(withTitle: mode.settingsTitle)
            placement.lastItem?.representedObject = mode.rawValue
        }
        placement.selectItem(at: DisplayMode.allCases.firstIndex(of: preferences.displayMode) ?? 0)
        placement.target = self
        placement.action = #selector(placementChanged(_:))
        placement.setAccessibilityLabel(L("settings.deck.placeCards"))
        form.settingRow(L("settings.deck.placeCards"), control: placement)
        form.settingRow(
            L("settings.deck.lock"),
            subtitle: L("settings.deck.lock.detail"),
            control: SettingsForm.makeSwitch(isOn: preferences.isLocked, title: L("settings.deck.lock"), target: self, action: #selector(lockChanged(_:)))
        )
        form.settingRow(
            L("settings.deck.closeGaps"),
            subtitle: L("settings.deck.closeGaps.detail"),
            control: SettingsForm.makeSwitch(isOn: preferences.packsColumns, title: L("settings.deck.closeGaps"), target: self, action: #selector(packingChanged(_:)))
        )
        form.endGroup()

        form.section(L("settings.deck.shortcut"))
        form.beginGroup()
        form.settingRow(
            L("settings.deck.summon"),
            subtitle: L("settings.deck.summon.detail"),
            control: SettingsForm.makeSwitch(isOn: preferences.summonEnabled, title: L("settings.deck.summon"), target: self, action: #selector(summonChanged(_:)))
        )

        let recorder = HotKeyRecorderView(combo: preferences.summonHotKey)
        recorder.onChange = { [weak self] combo in
            guard let self else { return }
            self.preferences.summonHotKey = combo
            // Registered at once: a shortcut saved but not registered lies until the next launch.
            self.host?.changed()
        }
        recorder.frame.size = NSSize(width: 110, height: 24)
        self.recorder = recorder
        let reset = SettingsForm.button(L("settings.deck.default"), target: self, action: #selector(resetShortcut))
        reset.controlSize = .small
        reset.sizeToFit()
        let pair = NSStackView(views: [recorder, reset])
        pair.orientation = .horizontal
        pair.spacing = 8
        recorder.widthAnchor.constraint(equalToConstant: 110).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 24).isActive = true
        form.settingRow(L("settings.deck.shortcut"), control: pair)
        summonControls += [recorder, reset]

        let dim = SettingsForm.makeSwitch(isOn: preferences.summonDims, title: L("settings.deck.dim"), target: self, action: #selector(dimChanged(_:)))
        form.settingRow(L("settings.deck.dim"), control: dim)
        summonControls.append(dim)
        form.endGroup()
        form.footnote(L("settings.deck.footnote"))
        applySummonState()
    }

    private func applySummonState() {
        let isOn = preferences.summonEnabled
        for view in summonControls {
            (view as? NSControl)?.isEnabled = isOn
            view.alphaValue = isOn ? 1 : 0.5
        }
    }

    @objc private func placementChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String, let mode = DisplayMode(rawValue: raw) else { return }
        preferences.displayMode = mode
        host?.changed()
    }

    @objc private func lockChanged(_ sender: NSSwitch) {
        preferences.isLocked = sender.state == .on
        host?.changed()
    }

    @objc private func packingChanged(_ sender: NSSwitch) {
        preferences.packsColumns = sender.state == .on
        host?.changed()
    }

    @objc private func summonChanged(_ sender: NSSwitch) {
        preferences.summonEnabled = sender.state == .on
        applySummonState()
        host?.changed()
    }

    @objc private func dimChanged(_ sender: NSSwitch) {
        preferences.summonDims = sender.state == .on
        host?.changed()
    }

    @objc private func resetShortcut() {
        preferences.summonHotKey = .optionSpace
        recorder?.set(.optionSpace)
        host?.changed()
    }
}

// MARK: - Cards

/// The cards that are not a project or an account: which are on the deck, and how often they
/// ask for news. They could only be switched on and off from the menu-bar menu before, although
/// its item was called "All cards and settings".
@MainActor
final class CardsSettingsPage: NSObject, SettingsPage, NSTextFieldDelegate {
    let kind = SettingsWindowController.Section.cards
    var title: String { L("settings.cards.title") }
    var icon: NSImage { SettingsIcons.cards }
    weak var host: SettingsHost?

    private let preferences: Preferences
    private let actionsField = SettingsForm.field("", placeholder: "owner/name, owner/name", code: true)
    private var switches: [NSSwitch: CardID] = [:]
    private weak var actionsRow: NSView?

    private static var refreshChoices: [(title: String, seconds: Int)] {
        [
            (L("settings.cards.interval.1"), 60),
            (L("settings.cards.interval.2"), 120),
            (L("settings.cards.interval.5"), 300),
            (L("settings.cards.interval.10"), 600),
        ]
    }

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func build(in container: FlippedContainer) {
        let form = SettingsForm(in: container)
        form.pageHeader(icon: SettingsIcons.tile("square.grid.2x2.fill", color: .systemIndigo, size: 32), title: title, subtitle: L("settings.cards.subtitle"))

        form.section(L("settings.cards.onDeck"))
        form.beginGroup()
        switches = [:]
        let layout = preferences.cardLayout
        for descriptor in CardCatalog.all where descriptor.isImplemented {
            let toggle = SettingsForm.makeSwitch(
                isOn: layout.isEnabled(descriptor.id),
                title: descriptor.title,
                target: self,
                action: #selector(cardChanged(_:))
            )
            switches[toggle] = descriptor.id
            form.settingRow(descriptor.title, subtitle: descriptor.subtitle, control: toggle)
        }
        form.endGroup()

        form.section(L("settings.cards.fetching"))
        form.beginGroup()
        let interval = NSPopUpButton()
        for choice in Self.refreshChoices {
            interval.addItem(withTitle: choice.title)
            interval.lastItem?.representedObject = choice.seconds
        }
        interval.selectItem(at: Self.refreshChoices.firstIndex { $0.seconds == Int(preferences.refreshIntervalSeconds) } ?? 1)
        interval.target = self
        interval.action = #selector(intervalChanged(_:))
        interval.setAccessibilityLabel(L("settings.cards.refreshEvery"))
        form.settingRow(L("settings.cards.refreshEvery"), control: interval)

        actionsField.stringValue = preferences.actionsRepositories.joined(separator: ", ")
        actionsField.delegate = self
        form.fieldRow(L("settings.cards.actionsRepositories"), [(actionsField, nil)])
        form.endGroup()
        form.footnote(L("settings.cards.actions.footnote"))
        applyActionsState()
    }

    @objc private func cardChanged(_ sender: NSSwitch) {
        guard let card = switches[sender] else { return }
        var layout = preferences.cardLayout
        layout.setEnabled(sender.state == .on, for: card)
        preferences.cardLayout = layout
        applyActionsState()
        host?.changed()
    }

    /// Nothing to name repositories for while the card that watches them is off.
    private func applyActionsState() {
        let isOn = preferences.cardLayout.isEnabled(.githubActions)
        actionsField.isEnabled = isOn
        actionsField.alphaValue = isOn ? 1 : 0.5
    }

    @objc private func intervalChanged(_ sender: NSPopUpButton) {
        guard let seconds = sender.selectedItem?.representedObject as? Int else { return }
        preferences.refreshIntervalSeconds = TimeInterval(seconds)
        host?.changed()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        preferences.actionsRepositories = actionsField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        host?.changed()
    }
}

// MARK: - Notifications

/// The master switch and, in two tables, what each account and each project may interrupt you
/// about. It used to be a switch under General and two more at the bottom of every account form,
/// each pointing at the other.
@MainActor
final class NotificationsSettingsPage: NSObject, SettingsPage {
    let kind = SettingsWindowController.Section.notifications
    var title: String { L("settings.notifications.title") }
    var icon: NSImage { SettingsIcons.notifications }
    weak var host: SettingsHost?

    /// Asks the app to put the permission question to macOS.
    var onRequestAuthorization: (@escaping (Bool) -> Void) -> Void = { $0(false) }
    /// Posts one banner now, so the chain can be checked without waiting for a review request.
    var onTest: () -> Void = {}

    private let preferences: Preferences
    private let githubStore: GitHubAccountsStore
    private let gitlabStore: GitLabAccountsStore
    private let arcStore: ArcProjectsStore
    private let ddevStore: DDEVProjectsStore
    private let localStore: LocalProjectsStore

    private enum Column { case review, stuck, runs, down, start }
    private var switches: [NSSwitch: (column: Column, service: String, id: String)] = [:]
    /// Everything that only means something while notifications are allowed at all.
    private var dependents: [NSView] = []

    init(
        preferences: Preferences,
        githubStore: GitHubAccountsStore,
        gitlabStore: GitLabAccountsStore,
        arcStore: ArcProjectsStore,
        ddevStore: DDEVProjectsStore,
        localStore: LocalProjectsStore
    ) {
        self.preferences = preferences
        self.githubStore = githubStore
        self.gitlabStore = gitlabStore
        self.arcStore = arcStore
        self.ddevStore = ddevStore
        self.localStore = localStore
    }

    func build(in container: FlippedContainer) {
        let form = SettingsForm(in: container)
        form.pageHeader(
            icon: SettingsIcons.tile("bell.badge.fill", color: .systemRed, size: 32),
            title: title,
            subtitle: L("settings.notifications.subtitle")
        )
        switches = [:]
        dependents = []

        form.beginGroup()
        form.settingRow(
            L("settings.notifications.allow"),
            subtitle: L("settings.notifications.allow.detail"),
            control: SettingsForm.makeSwitch(isOn: preferences.notificationsEnabled, title: L("settings.notifications.allow"), target: self, action: #selector(masterChanged(_:)))
        )
        let updates = SettingsForm.makeSwitch(isOn: preferences.notifiesUpdates, title: L("settings.notifications.updates"), target: self, action: #selector(updatesChanged(_:)))
        form.settingRow(L("settings.notifications.updates"), control: updates)
        let test = SettingsForm.button(L("settings.notifications.test.button"), target: self, action: #selector(sendTest))
        form.settingRow(L("settings.notifications.test"), control: test)
        dependents += [updates, test]
        form.endGroup()

        let github = githubStore.accounts()
        let gitlab = gitlabStore.accounts()
        if !github.isEmpty || !gitlab.isEmpty {
            form.section(L("settings.notifications.accounts"))
            form.beginGroup()
            form.settingRow("", control: Self.columns([
                Self.columnLabel(L("settings.notifications.column.review")),
                Self.columnLabel(L("settings.notifications.column.stuck")),
                Self.columnLabel(L("settings.notifications.column.runs")),
            ]))
            for account in github {
                form.settingRow(account.label, subtitle: "GitHub", control: Self.columns([
                    toggle(.review, "github", account.id, isOn: account.notifiesReviewRequests, title: L("notify.toggle.review", account.label)),
                    toggle(.stuck, "github", account.id, isOn: account.notifiesBlocked, title: L("notify.toggle.stuck", account.label)),
                    toggle(.runs, "github", account.id, isOn: account.notifiesFailedRuns, title: L("notify.toggle.runs", account.label)),
                ]))
            }
            for account in gitlab {
                form.settingRow(account.label, subtitle: "GitLab", control: Self.columns([
                    toggle(.review, "gitlab", account.id, isOn: account.notifiesReviewRequests, title: L("notify.toggle.review", account.label)),
                    toggle(.stuck, "gitlab", account.id, isOn: account.notifiesBlocked, title: L("notify.toggle.stuck", account.label)),
                    // GitLab has no Actions card, so there is nothing to switch here. A dash
                    // rather than a hole, so the column reads as "not for this one".
                    Self.columnLabel("-"),
                ]))
            }
            form.endGroup()
            form.footnote(L("settings.notifications.runs.footnote"))
        }

        let projects: [(id: String, title: String, kind: String)] =
            arcStore.projects().map { ($0.cardID.rawValue, $0.title, "Arc XP") }
            + ddevStore.projects().map { ($0.cardID.rawValue, $0.displayTitle, "DDEV") }
            + localStore.projects().map { ($0.cardID.rawValue, $0.displayTitle, "Project") }
        if !projects.isEmpty {
            form.section(L("settings.notifications.projects"))
            form.beginGroup()
            form.settingRow("", control: Self.columns([
                Self.columnLabel(L("settings.notifications.column.down")),
                Self.columnLabel(L("settings.notifications.column.startFailed")),
                NSView(),
            ]))
            let quietDown = preferences.projectsQuietWhenDown
            let quietStart = preferences.projectsQuietWhenStartFails
            for project in projects.sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) {
                form.settingRow(project.title, subtitle: project.kind, control: Self.columns([
                    toggle(.down, "project", project.id, isOn: !quietDown.contains(project.id), title: L("notify.toggle.down", project.title)),
                    toggle(.start, "project", project.id, isOn: !quietStart.contains(project.id), title: L("notify.toggle.start", project.title)),
                    NSView(),
                ]))
            }
            form.endGroup()
            form.footnote(L("settings.notifications.down.footnote"))
        }
        form.footnote(L("settings.notifications.footnote"))
        applyMasterState()
    }

    private func toggle(_ column: Column, _ service: String, _ id: String, isOn: Bool, title: String) -> NSSwitch {
        let control = SettingsForm.makeSwitch(isOn: isOn, title: title, target: self, action: #selector(switchChanged(_:)))
        switches[control] = (column, service, id)
        dependents.append(control)
        return control
    }

    /// With the master switch off nothing can be delivered, so nothing below it is live.
    private func applyMasterState() {
        let isOn = preferences.notificationsEnabled
        for view in dependents {
            (view as? NSControl)?.isEnabled = isOn
            view.alphaValue = isOn ? 1 : 0.5
        }
    }

    /// Controls centred in fixed columns, so the switches line up under their headings.
    private static func columns(_ views: [NSView]) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 0
        for view in views {
            let cell = NSStackView(views: [view])
            cell.alignment = .centerX
            cell.widthAnchor.constraint(equalToConstant: 96).isActive = true
            row.addArrangedSubview(cell)
        }
        return row
    }

    private static func columnLabel(_ text: String) -> NSTextField {
        SettingsForm.label(text, size: 11, color: .secondaryLabelColor)
    }

    @objc private func masterChanged(_ sender: NSSwitch) {
        guard sender.state == .on else {
            preferences.notificationsEnabled = false
            applyMasterState()
            return
        }
        // The switch goes back if macOS says no: "on" while nothing can be delivered lies.
        onRequestAuthorization { [weak self] granted in
            self?.preferences.notificationsEnabled = granted
            sender.state = granted ? .on : .off
            self?.applyMasterState()
            if !granted {
                let alert = NSAlert()
                alert.messageText = L("settings.notifications.denied.title")
                alert.informativeText = L("settings.notifications.denied.detail")
                alert.addButton(withTitle: L("button.ok"))
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    @objc private func updatesChanged(_ sender: NSSwitch) {
        preferences.notifiesUpdates = sender.state == .on
    }

    @objc private func sendTest() {
        onTest()
    }

    @objc private func switchChanged(_ sender: NSSwitch) {
        guard let target = switches[sender] else { return }
        let isOn = sender.state == .on
        switch (target.column, target.service) {
        case (.review, "github"): updateGitHub(target.id) { $0.notifiesReviewRequests = isOn }
        case (.stuck, "github"): updateGitHub(target.id) { $0.notifiesBlocked = isOn }
        case (.runs, "github"): updateGitHub(target.id) { $0.notifiesFailedRuns = isOn }
        case (.review, "gitlab"): updateGitLab(target.id) { $0.notifiesReviewRequests = isOn }
        case (.stuck, "gitlab"): updateGitLab(target.id) { $0.notifiesBlocked = isOn }
        case (.down, _):
            // Stored as the exceptions, so a project added later is covered without asking.
            if isOn { preferences.projectsQuietWhenDown.remove(target.id) } else { preferences.projectsQuietWhenDown.insert(target.id) }
        case (.start, _):
            if isOn { preferences.projectsQuietWhenStartFails.remove(target.id) } else { preferences.projectsQuietWhenStartFails.insert(target.id) }
        default:
            break
        }
        host?.changed()
    }

    private func updateGitHub(_ id: String, _ change: (inout GitHubAccount) -> Void) {
        var accounts = githubStore.accounts()
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        change(&accounts[index])
        githubStore.save(accounts)
    }

    private func updateGitLab(_ id: String, _ change: (inout GitLabAccount) -> Void) {
        var accounts = gitlabStore.accounts()
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        change(&accounts[index])
        gitlabStore.save(accounts)
    }
}
