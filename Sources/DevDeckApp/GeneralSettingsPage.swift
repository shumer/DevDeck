import AppKit
import DevDeckCore

/// The General page: the deck itself, fetching, summoning, notifications, login.
///
/// A page rather than a section: there is nothing to list, so it takes the form column on its
/// own and is pinned at the top of the list as a row of its own.
@MainActor
final class GeneralSettingsPage: NSObject, NSTextFieldDelegate {
    private let preferences: Preferences
    private let updater: Updater
    private let onChanged: () -> Void
    /// Asks the app to put the permission question to macOS.
    var onRequestNotifications: (@escaping (Bool) -> Void) -> Void = { $0(false) }
    /// Posts one banner now, so the chain can be checked without waiting for a review request.
    var onTestNotification: () -> Void = {}

    /// Kept so the Default button can put the field back without rebuilding the page.
    private weak var summonRecorder: HotKeyRecorderView?
    private let actionsField = NSTextField()

    /// The intervals worth offering. Below a minute is polling, and above ten the deck stops
    /// being something you glance at.
    private static let refreshChoices: [(title: String, seconds: Int)] = [
        ("1 minute", 60),
        ("2 minutes", 120),
        ("5 minutes", 300),
        ("10 minutes", 600),
    ]

    init(preferences: Preferences, updater: Updater, onChanged: @escaping () -> Void) {
        self.preferences = preferences
        self.updater = updater
        self.onChanged = onChanged
    }

    func build(in container: FlippedContainer, width: CGFloat) {
        let form = FormLayout(in: container)
        form.header("About")
        form.beginGroup()

        let version = NSTextField(labelWithString: AppVersion.summary)
        version.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        form.row("Version", [(version, nil)], height: 18)

        let location = NSTextField(labelWithString: AppVersion.location)
        location.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        location.lineBreakMode = .byTruncatingMiddle
        location.textColor = NSColor.secondaryLabelColor
        form.row("Running from", [(location, nil)], height: 18)

        form.endGroup()

        form.header("Fetching")
        form.beginGroup()

        let interval = NSPopUpButton()
        for choice in Self.refreshChoices {
            interval.addItem(withTitle: choice.title)
            interval.lastItem?.representedObject = choice.seconds
        }
        interval.selectItem(at: Self.refreshChoices.firstIndex { $0.seconds == Int(preferences.refreshIntervalSeconds) } ?? 1)
        interval.target = self
        interval.action = #selector(refreshIntervalChanged(_:))
        form.row("Refresh every", [(interval, 160)], height: 24)

        actionsField.stringValue = preferences.actionsRepositories.joined(separator: ", ")
        actionsField.placeholderString = "owner/name, owner/name"
        actionsField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        actionsField.delegate = self
        form.row("Actions", [(actionsField, nil)])
        form.endGroup()
        form.footnote("An empty Actions list follows the repositories your open pull requests are "
            + "in, up to five per account, which is the right default for one person's deck. The "
            + "refresh interval is a floor: GitHub says how often it wants to be polled for "
            + "notifications, and that is honoured when it asks for less.")
        form.footnote("The build number is the commit count, so it moves on every rebuild, the "
            + "quickest way to tell whether the copy in front of you is the change you just made.")

        form.header("Where the panels sit")
        form.beginGroup()

        let placement = NSPopUpButton()
        for mode in DisplayMode.allCases {
            placement.addItem(withTitle: mode.settingsTitle)
            placement.lastItem?.representedObject = mode.rawValue
        }
        placement.selectItem(at: DisplayMode.allCases.firstIndex(of: preferences.displayMode) ?? 0)
        placement.target = self
        placement.action = #selector(placementChanged(_:))
        form.row("Panels", [(placement, 240)], height: 24)

        form.toggleRow(
            deckSwitch(preferences.isLocked, action: #selector(lockChanged(_:))),
            title: "Lock position",
            subtitle: "Stops a stray drag moving a panel. It does not stop the deck packing a column."
        )
        form.toggleRow(
            deckSwitch(preferences.packsColumns, action: #selector(packingChanged(_:))),
            title: "Keep the column packed",
            subtitle: "Closes the gaps when a card changes height, so a gap left on purpose will not survive."
        )
        form.endGroup()
        form.footnote("Tidy, which sorts the deck and wraps it into columns, stays in the menu-bar "
            + "menu: it is something you do rather than something you set.")

        form.header("Summoning")
        form.beginGroup()

        form.toggleRow(
            deckSwitch(preferences.summonEnabled, action: #selector(summonChanged(_:))),
            title: "Raise the deck while the shortcut is held",
            subtitle: "Let go and it drops back. A tap keeps it up until the next press."
        )
        form.toggleRow(
            deckSwitch(preferences.summonDims, action: #selector(summonDimChanged(_:))),
            title: "Dim the screen while it is up",
            subtitle: "Dark glass over a white editor is close to unreadable without it."
        )

        let recorder = HotKeyRecorderView(combo: preferences.summonHotKey)
        recorder.onChange = { [weak self] combo in
            guard let self else { return }
            self.preferences.summonHotKey = combo
            // The app re-registers on this: a shortcut saved but not registered is a setting
            // that lies until the next launch.
            self.onChanged()
        }

        let reset = NSButton(title: "Default", target: nil, action: nil)
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        reset.target = self
        reset.action = #selector(resetSummonHotKey(_:))
        summonRecorder = recorder

        form.row("Shortcut", [(recorder, 120), (reset, 74)], height: 26)
        form.endGroup()
        form.footnote("At least one modifier is required: a bare key would be taken from every "
            + "application on the machine, so pressing it in an editor would raise the deck "
            + "instead of typing.")

        form.header("Notifications")
        form.beginGroup()
        form.toggleRow(
            deckSwitch(preferences.notificationsEnabled, action: #selector(notificationsChanged(_:))),
            title: "Let DevDeck notify me",
            subtitle: "The master switch. What you are told about is set per account."
        )
        let test = NSButton(title: "Send a test", target: self, action: #selector(sendTestNotification))
        test.bezelStyle = .rounded
        test.controlSize = .small
        form.row("Check it", [(test, 96)], height: 24)
        form.endGroup()
        form.footnote("Switching it on is what asks macOS for permission. Which accounts may "
            + "interrupt you, and about what, lives in each account's own form under GitHub "
            + "accounts and GitLab instances. Nothing is announced on the first answer after a "
            + "launch, since that is the state you left things in.")

        form.header("Updates")
        form.beginGroup()
        form.toggleRow(
            deckSwitch(preferences.checksForUpdates, action: #selector(updatesChanged(_:))),
            title: "Check for updates",
            subtitle: "Once after launch and every six hours, from the releases on GitHub. "
                + "Nothing is downloaded or installed until you ask."
        )
        let updateRow = updateStatus
        let action = NSButton(title: updateRow.button, target: self, action: #selector(updateAction))
        action.bezelStyle = .rounded
        action.controlSize = .small
        action.isEnabled = updateRow.isEnabled
        form.liveRow(color: updateRow.color, title: updateRow.title, detail: updateRow.detail, accessory: action)
        form.endGroup()
        form.footnote("What the app downloads itself carries no quarantine, so an update never "
            + "needs the right-click dance a first install does. The old copy goes to the Trash, "
            + "not away, and the new one takes its place and relaunches.")

        form.header("System")
        form.beginGroup()
        form.toggleRow(
            deckSwitch(LoginItem.isEnabled, action: #selector(loginItemChanged(_:))),
            title: "Start at login",
            subtitle: "Read from macOS itself, so removing it in System Settings shows here too."
        )
        form.endGroup()
    }

    /// The one row that answers "and is there one", in the colour the card would use.
    private var updateStatus: (color: NSColor, title: String, detail: String, button: String, isEnabled: Bool) {
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        guard updater.isSupported else {
            return (.tertiaryLabelColor, "Not from a bundle", "run from a terminal, nothing to replace", "Check now", false)
        }
        switch updater.state {
        case .available(let update):
            let size = ByteCountFormatter.string(fromByteCount: Int64(update.asset.size), countStyle: .file)
            return (.systemOrange, "\(update.version) is available", size, "Update now", true)
        case .downloading(let update, let fraction):
            return (.systemOrange, "Downloading \(update.version)", "\(Int((fraction * 100).rounded()))%", "Update now", false)
        case .installing(let update):
            return (.systemOrange, "Installing \(update.version)", "", "Update now", false)
        case .failed(_, let reason):
            return (.systemRed, "Update failed", reason, "Try again", true)
        case .checking:
            return (.tertiaryLabelColor, "Checking…", "", "Check now", false)
        case .idle:
            if let failure = updater.lastCheckFailure {
                return (.systemOrange, "Could not check", "\(failure), will try again later", "Check now", true)
            }
            if let checked = updater.lastCheckedAt {
                return (.systemGreen, "You are on the latest", "\(updater.currentVersion ?? ""), checked at \(clock.string(from: checked))", "Check now", true)
            }
            return (.tertiaryLabelColor, "Not checked yet", updater.currentVersion ?? "", "Check now", true)
        }
    }

    @objc private func updatesChanged(_ sender: NSButton) {
        preferences.checksForUpdates = sender.state == .on
        updater.applyPreferences()
    }

    /// Check, or install, whichever the row is offering.
    @objc private func updateAction() {
        switch updater.state {
        case .available, .failed:
            updater.install()
        default:
            updater.checkNow()
        }
    }

    /// The switches on this page all look the same and all do the same two things: write one
    /// preference, then let the deck act on it.
    private func deckSwitch(_ isOn: Bool, action: Selector) -> NSButton {
        let button = NSButton()
        button.setButtonType(.switch)
        button.title = ""
        button.state = isOn ? .on : .off
        button.target = self
        button.action = action
        return button
    }

    @objc private func refreshIntervalChanged(_ sender: NSPopUpButton) {
        guard let seconds = sender.selectedItem?.representedObject as? Int else { return }
        preferences.refreshIntervalSeconds = TimeInterval(seconds)
        onChanged()
    }

    @objc private func placementChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let mode = DisplayMode(rawValue: raw)
        else { return }
        preferences.displayMode = mode
        onChanged()
    }

    @objc private func lockChanged(_ sender: NSButton) {
        preferences.isLocked = sender.state == .on
        onChanged()
    }

    @objc private func packingChanged(_ sender: NSButton) {
        preferences.packsColumns = sender.state == .on
        onChanged()
    }

    @objc private func summonChanged(_ sender: NSButton) {
        preferences.summonEnabled = sender.state == .on
        onChanged()
    }

    @objc private func summonDimChanged(_ sender: NSButton) {
        preferences.summonDims = sender.state == .on
        onChanged()
    }

    @objc private func sendTestNotification() {
        onTestNotification()
    }

    /// Turning it on asks macOS for permission, and the switch goes back if the answer is no: a
    /// switch that says "on" while nothing can be delivered is a setting that lies.
    @objc private func notificationsChanged(_ sender: NSButton) {
        guard sender.state == .on else {
            preferences.notificationsEnabled = false
            return
        }
        onRequestNotifications { [weak self] granted in
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

    @objc private func loginItemChanged(_ sender: NSButton) {
        // Put back to whatever macOS ended up doing rather than to what was asked for: the
        // registration can fail, and a switch that stays on while the login item is not is a
        // setting that lies.
        sender.state = LoginItem.set(sender.state == .on) ? .on : .off
    }

    @objc private func resetSummonHotKey(_ sender: NSButton) {
        preferences.summonHotKey = .optionSpace
        summonRecorder?.set(.optionSpace)
        onChanged()
    }

    /// Text commits when the field is left, the same as everywhere else in this window.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard (notification.object as? NSTextField) === actionsField else { return }
        preferences.actionsRepositories = actionsField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        onChanged()
    }
}
