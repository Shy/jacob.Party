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

    /// Sends push notifications to subscribers, heartbeating per recipient.
    ///
    /// Heartbeats let the worker tell Temporal "still alive, here's my progress"
    /// — and the heartbeat detail (`"i/total"`) survives retries, so a failed
    /// attempt can resume from where it left off via
    /// `ActivityExecutionContext.current?.info.heartbeatDetails(...)`. Cancellation
    /// is also propagated through heartbeats: if the workflow cancels the
    /// activity, `cancellationReason` will be set and we throw to bail out.
    @Activity
    func sendPushNotification(input: SendPushNotificationInput) async throws {
        let activityContext = ActivityExecutionContext.current
        let total = input.subscriptions.count
        print("📬 Sending push notification to \(total) subscribers")
        print("   Message: \(input.message)")

        // Resume from prior attempt's progress, if any. The heartbeat detail
        // is the index of the next subscription to send to.
        var resumeFrom = 0
        if let info = activityContext?.info,
           let prior = try? await info.heartbeatDetails(as: Int.self) {
            resumeFrom = prior
        }
        if resumeFrom > 0 {
            print("↻ Resuming from subscription \(resumeFrom)/\(total) after retry")
        }

        guard let publicKey = Environment.get("VAPID_PUBLIC_KEY"), !publicKey.isEmpty,
              let privateKey = Environment.get("VAPID_PRIVATE_KEY"), !privateKey.isEmpty else {
            print("⚠️ VAPID keys not configured - skipping push notifications")
            return
        }
        _ = (publicKey, privateKey)

        let sender: WebPushSender
        do {
            sender = try WebPushSender()
        } catch {
            print("❌ Failed to initialize WebPushSender: \(error)")
            return
        }

        for index in resumeFrom..<total {
            if activityContext?.cancellationReason != nil {
                print("🛑 Activity cancelled at \(index)/\(total)")
                throw CancellationError()
            }
            try Task.checkCancellation()

            let subscription = input.subscriptions[index]
            do {
                try await sender.send(message: input.message, to: subscription)
            } catch {
                // Per-subscription failures don't fail the whole batch — push services
                // routinely return errors for expired subscriptions.
                print("⚠️ Send failed for \(subscription.id): \(error)")
            }

            // Heartbeat with current progress so retries can resume here.
            activityContext?.heartbeat(details: index + 1)
        }

        print("✅ Push notifications dispatched to \(total) subscribers")
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
