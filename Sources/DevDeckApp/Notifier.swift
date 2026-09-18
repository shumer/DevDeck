import AppKit
import DevDeckCore
import DevDeckUI
import UserNotifications

/// Posts the banners, and opens what they are about when one is clicked.
///
/// Nothing here decides *whether* to post: that is `NotificationDigest`, which is where the
/// feature actually lives. This is the part that talks to macOS.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Where a clicked banner goes. An address comes with its account, so a pull request opens in
    /// the browser profile signed in as the identity that owns it.
    var onTarget: ((DeckAlert.Target) -> Void)?
    /// A banner about a newer build was clicked: start the update.
    var onUpdate: (() -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var isAuthorized = false

    override init() {
        super.init()
        center.delegate = self
    }

    /// Asks macOS, once, at the moment the user switches notifications on.
    ///
    /// Deliberately not at launch. The permission dialog for an app that has not yet done
    /// anything for you is the thing people say no to and then never revisit.
    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.app.error("Notifications: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in
                self.isAuthorized = granted
                completion(granted)
            }
        }
    }

    /// Picks up an authorization the user granted in an earlier run, so the first banner after a
    /// launch does not have to wait for a round trip through the settings screen.
    func refreshAuthorization() {
        center.getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    /// One banner, now, so the whole chain can be checked without waiting for somebody to ask
    /// for a review. Permission, delivery and the click are the three things that can be wrong,
    /// and the first two are exactly what this exercises.
    func postTest() {
        deliver(DeckAlert(
            id: "test.\(UUID().uuidString)",
            kind: .reviewRequest,
            source: .github,
            title: L("notify.test.title"),
            subtitle: L("notify.test.subtitle"),
            body: L("notify.test.body"),
            subject: "test",
            target: .menu,
            isQuiet: false
        ))
    }

    /// A newer build exists. Carries no mark: this one is the app's own news, and the application
    /// icon macOS puts on every banner is exactly right for it.
    func postUpdate(_ version: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = L("notify.update.title", version)
        content.body = L("notify.update.body")
        content.userInfo = ["action": "update"]
        content.threadIdentifier = "devdeck.update"
        add(content, identifier: "devdeck.update.\(version)")
    }

    func post(_ alerts: [DeckAlert]) {
        guard isAuthorized, !alerts.isEmpty else { return }
        Log.app.info("Posting \(alerts.count, privacy: .public) notification(s)")

        // Many at once become one line. Three banners stacked up the corner of the screen is a
        // wall, and a wall gets swept away without being read.
        if let summary = NotificationDigest.summary(for: alerts) {
            let sources = Set(alerts.map(\.source))
            deliver(DeckAlert(
                id: "summary.\(alerts.map(\.id).joined().hashValue)",
                kind: alerts[0].kind,
                // One mark only when they share it; a mixed summary keeps the app's own icon.
                source: sources.count == 1 ? alerts[0].source : .devdeck,
                title: summary.title,
                subtitle: "",
                body: summary.body,
                subject: "",
                target: .menu,
                isQuiet: alerts.allSatisfy(\.isQuiet)
            ))
            return
        }

        for alert in alerts {
            deliver(alert)
        }
    }

    private func deliver(_ alert: DeckAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.subtitle = alert.subtitle
        content.body = alert.body
        // A person waiting on you is worth a sound. Your own stuck work and a project on this Mac
        // are worth a banner and no more.
        content.sound = alert.isQuiet ? nil : .default
        // Stacked by kind in Notification Center, so reviews, stuck work and this Mac read as
        // three piles rather than one long one.
        content.threadIdentifier = "devdeck.\(alert.kind.rawValue)"
        content.userInfo = Self.userInfo(for: alert.target)
        // macOS puts the application icon on every banner and will not be talked out of it, but
        // an attachment is drawn beside the text: that is where the source's own mark goes, so
        // "who is asking" is answered before the words are read.
        if let artwork = NotificationArtwork.fileURL(for: alert.source),
           let attachment = try? UNNotificationAttachment(identifier: alert.source.rawValue, url: artwork) {
            content.attachments = [attachment]
        }
        add(content, identifier: "devdeck.\(alert.id)")
    }

    private func add(_ content: UNMutableNotificationContent, identifier: String) {
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            if let error {
                Log.app.error("Notification not delivered: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The target as plain values, because that is all a notification can carry.
    nonisolated static func userInfo(for target: DeckAlert.Target) -> [String: String] {
        switch target {
        case .url(let url, let account): return ["url": url.absoluteString, "account": account]
        case .card(let card): return ["card": card.rawValue]
        case .accountSettings(let service, let account): return ["settings": service, "account": account]
        case .menu: return ["action": "menu"]
        }
    }

    nonisolated static func target(from info: [AnyHashable: Any]) -> DeckAlert.Target? {
        if let address = info["url"] as? String, let url = URL(string: address) {
            return .url(url, account: info["account"] as? String ?? "")
        }
        if let card = info["card"] as? String { return .card(CardID(rawValue: card)) }
        if let service = info["settings"] as? String {
            return .accountSettings(service: service, account: info["account"] as? String ?? "")
        }
        if info["action"] as? String == "menu" { return .menu }
        return nil
    }

    // MARK: Delegate

    /// Banners are worth showing even while DevDeck is frontmost: it is an agent app with no
    /// windows of its own to be looking at, so "the app is in front" says nothing about whether
    /// the person has seen this.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let isUpdate = info["action"] as? String == "update"
        let target = Self.target(from: info)
        Task { @MainActor in
            if isUpdate {
                self.onUpdate?()
            } else if let target {
                self.onTarget?(target)
            }
            completionHandler()
        }
    }
}
