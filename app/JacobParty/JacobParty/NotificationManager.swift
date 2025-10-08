import Foundation
import UserNotifications

@MainActor
class NotificationManager: NSObject {
    static let shared = NotificationManager()

    var isAuthorized = false
    private let notificationCenter = UNUserNotificationCenter.current()

    override init() {
        super.init()
        notificationCenter.delegate = self
    }

    func requestAuthorization() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            print("Notification authorization error: \(error)")
        }
    }

    func schedulePartyTimeoutNotification() {
        // Cancel any existing notifications
        notificationCenter.removeAllPendingNotificationRequests()

        let content = UNMutableNotificationContent()
        content.title = "Still Partying? 🎉"
        content.body = "You've been partying for 6 hours! Tap to keep the party going or it will automatically stop."
        content.sound = .default
        content.categoryIdentifier = "PARTY_TIMEOUT"

        // Schedule for 6 hours from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 6 * 60 * 60, repeats: false)

        let request = UNNotificationRequest(
            identifier: "party-timeout",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            } else {
                print("✅ Scheduled 6-hour party timeout notification")
            }
        }
    }

    func cancelPartyTimeoutNotification() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["party-timeout"])
        print("🚫 Cancelled party timeout notification")
    }

    func setupNotificationActions() {
        let keepPartyingAction = UNNotificationAction(
            identifier: "KEEP_PARTYING",
            title: "Keep Partying! 🎉",
            options: [.foreground]
        )

        let stopPartyAction = UNNotificationAction(
            identifier: "STOP_PARTY",
            title: "Stop Party",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: "PARTY_TIMEOUT",
            actions: [keepPartyingAction, stopPartyAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([category])
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            switch response.actionIdentifier {
            case "KEEP_PARTYING":
                // User wants to keep partying - reschedule for another 6 hours
                NotificationCenter.default.post(name: NSNotification.Name("KeepPartyingTapped"), object: nil)

            case "STOP_PARTY", UNNotificationDefaultActionIdentifier:
                // User tapped notification or chose to stop - end party
                NotificationCenter.default.post(name: NSNotification.Name("StopPartyFromNotification"), object: nil)

            default:
                break
            }
            completionHandler()
        }
    }
}
