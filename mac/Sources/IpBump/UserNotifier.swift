import Foundation
import IpBumpCore
import UserNotifications

/// Notification Center. Outside IpBump.app (a bare debug build) there is no bundle to post under, and
/// UNUserNotificationCenter would crash, so it stays quiet; the menu bar still shows what happened.
final class UserNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate, @unchecked Sendable {
    let available = Bundle.main.bundleIdentifier != nil

    override init() {
        super.init()
        guard available else { return }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    func post(title: String, body: String, isError: Bool) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // Show them even while the Settings window makes IpBump the active app
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
