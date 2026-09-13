import AppKit
import DevDeckCore
import GitHubKit
import GitLabKit

// The four pages at the top of the settings sidebar. They were one General page of seven groups,
// three screens long, with the switch you came for two scrolls down; now each fits the window.

// MARK: - General

/// Start at login, updates, and which build this is.
@MainActor
final class GeneralSettingsPage: NSObject, SettingsPage {
    let kind = SettingsWindowController.Section.general
    let title = "General"
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
            "Start at login",
            control: SettingsForm.makeSwitch(isOn: LoginItem.isEnabled, title: "Start at login", target: self, action: #selector(loginItemChanged(_:)))
        )
        form.endGroup()

        form.section("Updates")
        form.beginGroup()
        form.settingRow(
            "Check for updates automatically",
            subtitle: "Thirty seconds after launch and every six hours. Nothing installs until you ask.",
            control: SettingsForm.makeSwitch(isOn: preferences.checksForUpdates, title: "Check for updates automatically", target: self, action: #selector(updatesChanged(_:)))
        )
        let status = updateStatus
        let line = StatusLine(tone: status.tone, state: status.title, detail: status.detail)
        let button = SettingsForm.button(status.button, target: self, action: #selector(updateAction))
        button.isEnabled = status.isEnabled
        form.statusRow(line, button: button)
        form.endGroup()
        updateLine = line
        updateButton = button

        form.footnote("Running from \(AppVersion.location)")
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
        clock.dateFormat = "HH:mm"
        guard updater.isSupported else {
            return (.idle, "Not from a bundle", "run from a terminal, nothing to replace", "Check Now", false)
        }
        switch updater.state {
        case .available(let update):
            let size = ByteCountFormatter.string(fromByteCount: Int64(update.asset.size), countStyle: .file)
            return (.busy, "\(update.version) is available", size, "Update Now", true)
        case .downloading(let update, let fraction):
            return (.busy, "Downloading \(update.version)", "\(Int((fraction * 100).rounded()))%", "Update Now", false)
        case .installing(let update):
            return (.busy, "Installing \(update.version)", "", "Update Now", false)
        case .failed(_, let reason):
            return (.bad, "Update failed", reason, "Try Again", true)
        case .checking:
            return (.idle, "Checking…", "", "Check Now", false)
        case .idle:
            if let failure = updater.lastCheckFailure {
                return (.busy, "Could not check", failure, "Check Now", true)
            }
            if let checked = updater.lastCheckedAt {
                return (.good, "Up to date", "\(updater.currentVersion ?? ""), checked at \(clock.string(from: checked))", "Check Now", true)
            }
            return (.idle, "Not checked yet", updater.currentVersion ?? "", "Check Now", true)
        }
    }

    @objc private func loginItemChanged(_ sender: NSSwitch) {
        // Put back to what macOS ended up doing: the registration can fail, and a switch that
        // stays on while the login item is not is a setting that lies.
        sender.state = LoginItem.set(sender.state == .on) ? .on : .off
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
    let title = "Deck"
    var icon: NSImage { SettingsIcons.deck }
    weak var host: SettingsHost?

    private let preferences: Preferences
    private weak var recorder: HotKeyRecorderView?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func build(in container: FlippedContainer) {
        let form = SettingsForm(in: container)
        form.pageHeader(icon: SettingsIcons.tile("rectangle.stack.fill", color: .systemBlue, size: 32), title: title, subtitle: "Where the cards sit and how they come forward")

        form.section("Position")
        form.beginGroup()
        let placement = NSPopUpButton()
        for mode in DisplayMode.allCases {
            placement.addItem(withTitle: mode.settingsTitle)
            placement.lastItem?.representedObject = mode.rawValue
        }
        placement.selectItem(at: DisplayMode.allCases.firstIndex(of: preferences.displayMode) ?? 0)
        placement.target = self
        placement.action = #selector(placementChanged(_:))
        placement.setAccessibilityLabel("Cards sit")
        form.settingRow("Cards sit", control: placement)
        form.settingRow(
            "Lock position",
            subtitle: "Also in the menu-bar menu and on a card's right-click menu.",
            control: SettingsForm.makeSwitch(isOn: preferences.isLocked, title: "Lock position", target: self, action: #selector(lockChanged(_:)))
        )
        form.settingRow(
            "Close gaps automatically",
            subtitle: "When a card changes height, the column closes up.",
            control: SettingsForm.makeSwitch(isOn: preferences.packsColumns, title: "Close gaps automatically", target: self, action: #selector(packingChanged(_:)))
        )
        form.endGroup()

        form.section("Shortcut")
        form.beginGroup()
        form.settingRow(
            "Bring cards forward while holding the shortcut",
            subtitle: "A tap keeps them up until the next press.",
            control: SettingsForm.makeSwitch(isOn: preferences.summonEnabled, title: "Bring cards forward while holding the shortcut", target: self, action: #selector(summonChanged(_:)))
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
        let reset = SettingsForm.button("Default", target: self, action: #selector(resetShortcut))
        reset.controlSize = .small
        reset.sizeToFit()
        let pair = NSStackView(views: [recorder, reset])
        pair.orientation = .horizontal
        pair.spacing = 8
        recorder.widthAnchor.constraint(equalToConstant: 110).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 24).isActive = true
        form.settingRow("Shortcut", control: pair)

        form.settingRow(
            "Dim the screen while they are up",
            control: SettingsForm.makeSwitch(isOn: preferences.summonDims, title: "Dim the screen while they are up", target: self, action: #selector(dimChanged(_:)))
        )
        form.endGroup()
        form.footnote("Use at least one modifier, or the key stops typing in every other app.")
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
    let title = "Cards"
    var icon: NSImage { SettingsIcons.cards }
    weak var host: SettingsHost?

    private let preferences: Preferences
    private let actionsField = SettingsForm.field("", placeholder: "owner/name, owner/name", code: true)
    private var switches: [NSSwitch: CardID] = [:]

    private static let refreshChoices: [(title: String, seconds: Int)] = [
        ("1 minute", 60), ("2 minutes", 120), ("5 minutes", 300), ("10 minutes", 600),
    ]

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func build(in container: FlippedContainer) {
        let form = SettingsForm(in: container)
        form.pageHeader(icon: SettingsIcons.tile("square.grid.2x2.fill", color: .systemIndigo, size: 32), title: title, subtitle: "Cards that are not an account or a project")

        form.section("On the deck")
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

        form.section("Fetching")
        form.beginGroup()
        let interval = NSPopUpButton()
        for choice in Self.refreshChoices {
            interval.addItem(withTitle: choice.title)
            interval.lastItem?.representedObject = choice.seconds
        }
        interval.selectItem(at: Self.refreshChoices.firstIndex { $0.seconds == Int(preferences.refreshIntervalSeconds) } ?? 1)
        interval.target = self
        interval.action = #selector(intervalChanged(_:))
        interval.setAccessibilityLabel("Refresh every")
        form.settingRow("Refresh every", control: interval)

        actionsField.stringValue = preferences.actionsRepositories.joined(separator: ", ")
        actionsField.delegate = self
        form.fieldRow("Actions repos", [(actionsField, nil)])
        form.endGroup()
        form.footnote("Empty: the repositories of your open pull requests, up to five per account.")
    }

    @objc private func cardChanged(_ sender: NSSwitch) {
        guard let card = switches[sender] else { return }
        var layout = preferences.cardLayout
        layout.setEnabled(sender.state == .on, for: card)
        preferences.cardLayout = layout
        host?.changed()
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

/// The master switch and, in one table, what each account may interrupt you about. It used to
/// be a switch under General and two more at the bottom of every account form, each pointing at
/// the other.
@MainActor
final class NotificationsSettingsPage: NSObject, SettingsPage {
    let kind = SettingsWindowController.Section.notifications
    let title = "Notifications"
    var icon: NSImage { SettingsIcons.notifications }
    weak var host: SettingsHost?

    /// Asks the app to put the permission question to macOS.
    var onRequestAuthorization: (@escaping (Bool) -> Void) -> Void = { $0(false) }
    /// Posts one banner now, so the chain can be checked without waiting for a review request.
    var onTest: () -> Void = {}

    private let preferences: Preferences
    private let githubStore: GitHubAccountsStore
    private let gitlabStore: GitLabAccountsStore
    private var reviewSwitches: [NSSwitch: (service: String, id: String)] = [:]
    private var blockedSwitches: [NSSwitch: (service: String, id: String)] = [:]

    init(preferences: Preferences, githubStore: GitHubAccountsStore, gitlabStore: GitLabAccountsStore) {
        self.preferences = preferences
        self.githubStore = githubStore
        self.gitlabStore = gitlabStore
    }

    func build(in container: FlippedContainer) {
        let form = SettingsForm(in: container)
        form.pageHeader(icon: SettingsIcons.tile("bell.badge.fill", color: .systemRed, size: 32), title: title, subtitle: "A banner when somebody is waiting on you")

        form.beginGroup()
        form.settingRow(
            "Allow notifications",
            subtitle: "macOS asks for permission the first time.",
            control: SettingsForm.makeSwitch(isOn: preferences.notificationsEnabled, title: "Allow notifications", target: self, action: #selector(masterChanged(_:)))
        )
        form.settingRow("Check it", control: SettingsForm.button("Send Test Notification", target: self, action: #selector(sendTest)))
        form.endGroup()

        let accounts: [(service: String, id: String, label: String, glyph: NSImage, review: Bool, blocked: Bool)] =
            githubStore.accounts().map { ("github", $0.id, $0.label, SettingsIcons.mark(.github), $0.notifiesReviewRequests, $0.notifiesBlocked) }
            + gitlabStore.accounts().map { ("gitlab", $0.id, $0.label, SettingsIcons.mark(.gitlab), $0.notifiesReviewRequests, $0.notifiesBlocked) }

        guard !accounts.isEmpty else { return }
        form.section("Per account")
        form.beginGroup()
        form.settingRow("", control: Self.columns(Self.columnLabel("Review requests"), Self.columnLabel("My work blocked")))
        reviewSwitches = [:]
        blockedSwitches = [:]
        for account in accounts {
            let review = SettingsForm.makeSwitch(isOn: account.review, title: "\(account.label) review requests", target: self, action: #selector(accountChanged(_:)))
            let blocked = SettingsForm.makeSwitch(isOn: account.blocked, title: "\(account.label) blocked work", target: self, action: #selector(accountChanged(_:)))
            reviewSwitches[review] = (account.service, account.id)
            blockedSwitches[blocked] = (account.service, account.id)
            form.settingRow(account.label, control: Self.columns(review, blocked))
        }
        form.endGroup()
        form.footnote("Nothing is announced on the first check after a launch.")
    }

    /// Two controls centred in two fixed columns, so the switches line up under their headings.
    private static func columns(_ first: NSView, _ second: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 0
        for view in [first, second] {
            let cell = NSStackView(views: [view])
            cell.alignment = .centerX
            cell.widthAnchor.constraint(equalToConstant: 120).isActive = true
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
            return
        }
        // The switch goes back if macOS says no: "on" while nothing can be delivered lies.
        onRequestAuthorization { [weak self] granted in
            self?.preferences.notificationsEnabled = granted
            sender.state = granted ? .on : .off
            if !granted {
                let alert = NSAlert()
                alert.messageText = "macOS is not allowing DevDeck to notify you"
                alert.informativeText = "Turn it on under System Settings, Notifications, DevDeck."
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    @objc private func sendTest() {
        onTest()
    }

    @objc private func accountChanged(_ sender: NSSwitch) {
        let isOn = sender.state == .on
        if let target = reviewSwitches[sender] {
            update(target) { github in github.notifiesReviewRequests = isOn } gitlab: { gitlab in gitlab.notifiesReviewRequests = isOn }
        } else if let target = blockedSwitches[sender] {
            update(target) { github in github.notifiesBlocked = isOn } gitlab: { gitlab in gitlab.notifiesBlocked = isOn }
        }
        host?.changed()
    }

    private func update(
        _ target: (service: String, id: String),
        github: (inout GitHubAccount) -> Void,
        gitlab: (inout GitLabAccount) -> Void
    ) {
        if target.service == "github" {
            var accounts = githubStore.accounts()
            guard let index = accounts.firstIndex(where: { $0.id == target.id }) else { return }
            github(&accounts[index])
            githubStore.save(accounts)
        } else {
            var accounts = gitlabStore.accounts()
            guard let index = accounts.firstIndex(where: { $0.id == target.id }) else { return }
            gitlab(&accounts[index])
            gitlabStore.save(accounts)
        }
    }
}
