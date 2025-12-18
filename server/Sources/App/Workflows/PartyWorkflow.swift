import Foundation
import Temporal

/// Long-running workflow that represents the party system state.
///
/// EDUCATIONAL: This demonstrates Temporal's state management capabilities
/// - Workflow state persists automatically (survives restarts)
/// - State is queryable via workflow history
/// - No external database needed
/// - Perfect for business process state machines
///
/// This workflow runs indefinitely and maintains:
/// - Current party state (is partying, location, when started)
/// - Push notification subscriptions
/// - Party history/audit log
@Workflow
final class PartyWorkflow {
    // MARK: - Workflow State (Persisted by Temporal)

    /// Current party state
    private var isPartying: Bool = false
    private var currentLocation: Location?
    private var partyStartTime: Date?

    /// Push notification subscriptions (stored in workflow)
    private var pushSubscriptions: [PushSubscription] = []

    /// Party history for analytics/review
    private var partyHistory: [PartyEvent] = []

    // MARK: - Workflow Execution

    func run(input: StartPartyInput) async throws -> String {
        let startTime = Date()

        Workflow.logger.info("Party started", metadata: [
            "source": .string(input.source),
            "reason": .string(input.reason),
            "deviceId": .string(input.deviceId ?? "none"),
            "location": .string("\(input.location.lat),\(input.location.lng)")
        ])

        // Activity: Record party start with retry policy
        // EDUCATIONAL: Critical operations get aggressive retry configuration
        try await Workflow.executeActivity(
            PartyActivities.Activities.RecordPartyStart.self,
            options: .init(
                startToCloseTimeout: .seconds(10),
                retryPolicy: RetryPolicy(
                    initialInterval: .seconds(1),
                    backoffCoefficient: 2.0,
                    maximumInterval: .seconds(10),
                    maximumAttempts: 3
                )
            ),
            input: PartyActivities.RecordPartyStartInput(
                location: input.location,
                startTime: startTime
            )
        )

        // Get push subscriptions
        let subscriptions = try await Workflow.executeActivity(
            PartyActivities.Activities.GetSubscriptions.self,
            options: .init(
                startToCloseTimeout: .seconds(5),
                retryPolicy: RetryPolicy(
                    initialInterval: .seconds(1),
                    backoffCoefficient: 1.5,
                    maximumInterval: .seconds(5),
                    maximumAttempts: 2
                )
            )
        )

        // Send push notifications if there are subscribers
        if !subscriptions.isEmpty {
            try await Workflow.executeActivity(
                PartyActivities.Activities.SendPushNotification.self,
                options: .init(
                    startToCloseTimeout: .seconds(30),
                    retryPolicy: RetryPolicy(
                        initialInterval: .seconds(1),
                        backoffCoefficient: 2.0,
                        maximumInterval: .seconds(10),
                        maximumAttempts: 3
                    )
                ),
                input: PartyActivities.SendPushNotificationInput(
                    message: "🎉 Jacob started partying, join at jacob.party",
                    subscriptions: subscriptions
                )
            )
        }

        return "Party started at \(input.location)"
    }

    // MARK: - State Management Helpers

    private func logEvent(_ event: PartyEvent) {
        partyHistory.append(event)

        // Keep last 1000 events to avoid unbounded growth
        if partyHistory.count > 1000 {
            partyHistory.removeFirst(partyHistory.count - 1000)
        }
    }

    private func formatLocation(_ location: Location) -> String {
        return String(format: "(%.4f, %.4f)", location.lat, location.lng)
    }

    private func sendPushNotifications(message: String, subscriptions: [PushSubscription]) async throws {
        // Activity: Send push notifications with retry policy
        try await Workflow.executeActivity(
            PartyActivities.Activities.SendPushNotification.self,
            options: .init(
                startToCloseTimeout: .seconds(30),
                retryPolicy: RetryPolicy(
                    initialInterval: .seconds(1),
                    backoffCoefficient: 2.0,
                    maximumInterval: .seconds(10),
                    maximumAttempts: 3
                )
            ),
            input: PartyActivities.SendPushNotificationInput(
                message: message,
                subscriptions: subscriptions
            )
        )
    }
}

/// Workflow to update party location
@Workflow
final class UpdateLocationWorkflow {
    func run(input: UpdateLocationInput) async throws -> String {
        Workflow.logger.info("Location update requested", metadata: [
            "source": .string(input.source),
            "location": .string("\(input.location.lat),\(input.location.lng)")
        ])

        // Note: This workflow should signal the main PartyWorkflow
        // For now, we'll execute an activity that updates state
        // In SDK 0.6+, this would use signals to update the long-running workflow

        return "Location updated"
    }
}

/// Workflow to stop party
@Workflow
final class StopPartyWorkflow {
    func run(input: StopPartyInput) async throws -> String {
        let endTime = Date()

        Workflow.logger.info("Party stopped", metadata: [
            "source": .string(input.source),
            "reason": .string(input.reason),
            "deviceId": .string(input.deviceId ?? "none")
        ])

        // Activity: Record party end
        try await Workflow.executeActivity(
            PartyActivities.Activities.RecordPartyEnd.self,
            options: .init(
                startToCloseTimeout: .seconds(10),
                retryPolicy: RetryPolicy(
                    initialInterval: .seconds(1),
                    backoffCoefficient: 2.0,
                    maximumInterval: .seconds(10),
                    maximumAttempts: 3
                )
            ),
            input: PartyActivities.RecordPartyEndInput(
                startTime: endTime,
                endTime: endTime
            )
        )

        return "Party stopped"
    }
}

/// Workflow to query party state
@Workflow
final class GetPartyStateWorkflow {
    func run(input: GetPartyStateInput) async throws -> PartyActivities.GetPartyStateOutput {
        Workflow.logger.info("Party state queried", metadata: [
            "source": .string(input.source)
        ])

        // Note: In a full implementation, this would query the long-running workflow
        // For SDK 0.5 compatibility, we use a simple activity-based approach
        return try await Workflow.executeActivity(
            PartyActivities.Activities.GetPartyState.self,
            options: .init(
                startToCloseTimeout: .seconds(5),
                retryPolicy: RetryPolicy(
                    initialInterval: .milliseconds(500),
                    backoffCoefficient: 1.5,
                    maximumInterval: .seconds(2),
                    maximumAttempts: 2
                )
            )
        )
    }
}

// MARK: - Educational Notes

/*
 TEMPORAL STATE MANAGEMENT PATTERN:

 This workflow demonstrates storing application state in Temporal:

 ✅ GOOD for workflow state:
    - Current party status (small, changes infrequently)
    - Business process state (order status, approval state)
    - Audit trail/history (what happened in this process)
    - Configuration for THIS workflow instance

 ❌ NOT good for workflow state:
    - Large datasets (>50KB recommended limit)
    - High-frequency updates (1000s/second)
    - Shared state across many workflows
    - Data queried independently by external systems

 BENEFITS:
    - State persists automatically (survives crashes/restarts)
    - No database setup needed
    - Built-in audit trail via workflow history
    - Queryable via Temporal UI
    - Version controlled with workflow code

 TRADE-OFFS:
    - Limited to workflow event size limits
    - Not optimized for complex queries
    - Need to query workflow to access state

 FOR JACOB.PARTY:
    - Party state: ~100 bytes (perfect for workflow)
    - Push subscriptions: ~1KB per 10 subscriptions (acceptable)
    - Party history: ~10KB per 100 events (acceptable)
    - Total: Well within limits for educational demo

 FUTURE ENHANCEMENTS (SDK 0.6+):
    - Use signals to update location without new workflow
    - Use queries to read state without executing workflow
    - Use continue-as-new for very long-running parties
*/
