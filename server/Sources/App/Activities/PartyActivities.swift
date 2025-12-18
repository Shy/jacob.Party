import Foundation
import Temporal
import Vapor

/// Activities for party workflow demonstrating database operations.
@ActivityContainer
struct PartyActivities {
    // MARK: - Activity Input Types

    struct RecordPartyStartInput: Codable {
        let location: Location
        let startTime: Date
    }

    struct RecordPartyEndInput: Codable {
        let startTime: Date
        let endTime: Date
    }

    struct GetPartyStateOutput: Codable {
        let isPartying: Bool
        let location: Location?
        let startTime: Date?
    }

    struct UpdateLocationActivityInput: Codable {
        let location: Location
    }

    struct SendPushNotificationInput: Codable {
        let message: String
        let subscriptions: [PushSubscription]
    }

    // MARK: - Activities

    /// Records when the party starts (updates state file).
    @Activity
    func recordPartyStart(input: RecordPartyStartInput) async throws {
        print("🎉 Party started at lat: \(input.location.lat), lng: \(input.location.lng) at \(input.startTime)")

        let state = PartyState(
            isPartying: true,
            location: input.location,
            startTime: input.startTime
        )
        try saveState(state)
    }

    /// Records when the party ends (clears state file).
    @Activity
    func recordPartyEnd(input: RecordPartyEndInput) async throws {
        let duration = input.endTime.timeIntervalSince(input.startTime)
        print("🛑 Party ended. Duration: \(duration) seconds")

        let url = stateFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            print("🗑️ Cleared party state data")
        }
    }

    /// Queries the current party state from state file.
    @Activity
    func getPartyState(input: ()) async throws -> GetPartyStateOutput {
        let state = try loadState()
        return GetPartyStateOutput(
            isPartying: state.isPartying,
            location: state.location,
            startTime: state.startTime
        )
    }

    /// Updates the party location (updates state file).
    @Activity
    func updateLocation(input: UpdateLocationActivityInput) async throws {
        print("📍 Location updated to lat: \(input.location.lat), lng: \(input.location.lng)")

        // Load current state
        var state = try loadState()

        // Only update if currently partying
        guard state.isPartying else {
            print("⚠️ Not currently partying, ignoring location update")
            return
        }

        // Update location while preserving other state
        state = PartyState(
            isPartying: state.isPartying,
            location: input.location,
            startTime: state.startTime
        )
        try saveState(state)
    }

    /// Gets all push notification subscriptions
    @Activity
    func getSubscriptions(input: ()) async throws -> [PushSubscription] {
        return try SubscriptionManager.loadAll()
    }

    /// Sends push notifications to subscribers.
    /// EDUCATIONAL: Demonstrates external API calls in activities with proper error handling
    @Activity
    func sendPushNotification(input: SendPushNotificationInput) async throws {
        print("📬 Sending push notification to \(input.subscriptions.count) subscribers")
        print("   Message: \(input.message)")

        // EDUCATIONAL: For production, you'd want proper dependency injection
        // For this demo, we check environment and gracefully skip if VAPID not configured

        let vapidPublicKey = Environment.get("VAPID_PUBLIC_KEY")
        let vapidPrivateKey = Environment.get("VAPID_PRIVATE_KEY")

        guard let publicKey = vapidPublicKey, !publicKey.isEmpty,
              let privateKey = vapidPrivateKey, !privateKey.isEmpty else {
            print("⚠️ VAPID keys not configured - skipping push notifications")
            print("   Set VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY environment variables")
            print("   Or leave unconfigured to test workflows without push")
            return
        }

        // Create web push sender (uses swift-webpush library)
        do {
            let sender = try WebPushSender()

            // Send notifications with proper VAPID authentication and encryption
            try await sender.sendBatch(message: input.message, subscriptions: input.subscriptions)
            print("✅ Push notifications sent to all subscribers")
        } catch {
            print("❌ Error sending push notifications: \(error)")
            // Don't throw - we don't want to fail the workflow if push fails
            // In production, you might want to log to error tracking service
        }

        // EDUCATIONAL: Activities should be idempotent
        // Multiple calls with same input should be safe
        // Web push services handle deduplication
    }

    // MARK: - Helper Methods (File-based state for now)

    private func saveState(_ state: PartyState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let url = stateFileURL()
        try data.write(to: url)
    }

    private func loadState() throws -> PartyState {
        let url = stateFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            // No state file, return default (not partying)
            return PartyState(isPartying: false, location: nil, startTime: nil)
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PartyState.self, from: data)
    }

    private func stateFileURL() -> URL {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
        return tmpDir.appendingPathComponent("party-state.json")
    }
}

// MARK: - Internal State Model

private struct PartyState: Codable {
    var isPartying: Bool
    var location: Location?
    var startTime: Date?
}
