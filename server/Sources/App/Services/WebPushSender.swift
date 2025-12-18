import Foundation
import Vapor
import WebPush

/// Web Push notification sender using swift-webpush library
/// Handles VAPID authentication and payload encryption automatically
struct WebPushSender {
    private let manager: WebPushManager

    /// Initialize with VAPID configuration from environment
    init() throws {
        guard let privateKey = Environment.get("VAPID_PRIVATE_KEY"),
              !privateKey.isEmpty,
              let subject = Environment.get("VAPID_SUBJECT") else {
            throw Abort(.internalServerError, reason: "VAPID configuration missing")
        }

        // Create VAPID configuration from environment
        let configJSON = """
        {
            "contactInformation": "\(subject)",
            "primaryKey": "\(privateKey)",
            "expirationDuration": 79200,
            "validityDuration": 43200
        }
        """

        let configData = Data(configJSON.utf8)
        let vapidConfig = try JSONDecoder().decode(VAPID.Configuration.self, from: configData)

        self.manager = WebPushManager(vapidConfiguration: vapidConfig)
        print("🔐 WebPush manager initialized with VAPID configuration")
    }

    /// Send a push notification to a single subscription
    func send(message: String, to subscription: PushSubscription) async throws {
        print("📤 Sending web push to: \(subscription.endpoint)")

        // Get VAPID public key for subscriber
        let vapidPublicKey = Environment.get("VAPID_PUBLIC_KEY") ?? ""

        // Convert our PushSubscription to WebPush.Subscriber format
        let subscriberJSON = """
        {
            "endpoint": "\(subscription.endpoint)",
            "keys": {
                "auth": "\(subscription.authKey)",
                "p256dh": "\(subscription.p256dhKey)"
            },
            "applicationServerKey": "\(vapidPublicKey)"
        }
        """

        let subscriberData = Data(subscriberJSON.utf8)
        let subscriber = try JSONDecoder().decode(Subscriber.self, from: subscriberData)

        do {
            // Send notification with the WebPush library
            // Using string message format
            try await manager.send(
                string: message,
                to: subscriber
            )
            print("✅ Push notification sent successfully")
        } catch is BadSubscriberError {
            print("⚠️ Subscription expired or invalid - should be removed")
        } catch is MessageTooLargeError {
            print("⚠️ Message too large for push notification")
        } catch let error as PushServiceError {
            print("❌ Push service error: \(error)")
        } catch {
            print("❌ Push notification failed: \(error)")
        }
    }

    /// Send push notifications to multiple subscriptions in parallel
    func sendBatch(message: String, subscriptions: [PushSubscription]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for subscription in subscriptions {
                group.addTask {
                    do {
                        try await send(message: message, to: subscription)
                    } catch {
                        print("⚠️ Failed to send to subscription \(subscription.id): \(error)")
                    }
                }
            }

            try await group.waitForAll()
        }
    }
}
