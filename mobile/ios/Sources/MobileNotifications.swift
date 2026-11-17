import UIKit
import UserNotifications

/// Local alerts for a finished turn, a pending decision, or a failed turn.
@MainActor
final class MobileNotifications {
    /// Preference shared with the Remote settings toggle.
    static let enabledKey = "mobile.notifications.enabled"
    static let shared = MobileNotifications()

    private let center = UNUserNotificationCenter.current()

    /// Asks for alert and sound permission.
    /// - Returns: whether the person allowed notifications.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Posts one alert when the app is not in front, if the preference and system permission allow it.
    /// - Parameters:
    ///   - title: alert title.
    ///   - body: alert body.
    ///   - sessionId: conversation the alert opens.
    func post(title: String, body: String, sessionId: String) async {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        guard UIApplication.shared.applicationState != .active else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["sessionId": sessionId]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
