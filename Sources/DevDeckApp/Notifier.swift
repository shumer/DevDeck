import AppKit
import DevDeckCore
import UserNotifications

/// Posts the banners, and opens what they are about when one is clicked.
///
/// Nothing here decides *whether* to post: that is `NotificationDigest`, which is where the
/// feature actually lives. This is the part that talks to macOS.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Where a clicked banner goes. The account comes with it, so a pull request opens in the
    /// browser profile signed in as the identity that owns it.
    var onOpen: ((URL, String) -> Void)?

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
        deliver(
            identifier: "devdeck.test.\(UUID().uuidString)",
            title: "DevDeck",
            body: "Notifications are working. This is what a review request will look like.",
            url: nil,
            accountID: nil
        )
    }

    func post(_ alerts: [DeckAlert]) {
        guard isAuthorized, !alerts.isEmpty else { return }
        Log.app.info("Posting \(alerts.count, privacy: .public) notification(s)")

        // Many at once become one line. Three banners stacked up the corner of the screen is a
        // wall, and a wall gets swept away without being read.
        if let summary = NotificationDigest.summary(for: alerts) {
            deliver(
                identifier: "devdeck.summary.\(alerts.map(\.id).joined().hashValue)",
                title: summary.title,
                body: summary.body,
                url: alerts.first?.url,
                accountID: alerts.first?.accountID
            )
            return
        }

        for alert in alerts {
            deliver(
                identifier: "devdeck.\(alert.id)",
                title: alert.title,
                body: alert.body,
                url: alert.url,
                accountID: alert.accountID
            )
        }
    }

    private func deliver(identifier: String, title: String, body: String, url: URL?, accountID: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url, let accountID {
            content.userInfo = ["url": url.absoluteString, "account": accountID]
        }

        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            if let error {
                Log.app.error("Notification not delivered: \(error.localizedDescription, privacy: .public)")
            }
        }
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
        let address = info["url"] as? String
        let account = info["account"] as? String
        Task { @MainActor in
            if let address, let url = URL(string: address) {
                self.onOpen?(url, account ?? "")
            }
            completionHandler()
        }
    }
}
