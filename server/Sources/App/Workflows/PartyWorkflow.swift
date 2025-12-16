import Foundation
import Temporal

/// Workflow that represents a party session showing Temporal best practices.
///
/// Educational concepts demonstrated:
/// - Durable execution (workflow survives server restarts)
/// - Activity execution with proper timeouts
/// - Retry policies for error handling (critical vs non-critical)
/// - Workflow as durable state machine
/// - Proper logging for observability
///
/// Note: This version uses separate workflows for simplicity with SDK 0.5.
/// For signals/queries pattern, see SDK 0.6+ examples.
@Workflow
final class PartyWorkflow {
    func run(input: StartPartyInput) async throws -> String {
        let startTime = Date()

        // Log party start with comprehensive tracking information
        // Educational: Structured logging helps with debugging and monitoring
        Workflow.logger.info("Party started", metadata: [
            "source": .string(input.source),
            "reason": .string(input.reason),
            "deviceId": .string(input.deviceId ?? "none"),
            "location": .string("\(input.location.lat),\(input.location.lng)"),
            "autoStopHours": .stringConvertible(input.autoStopHours ?? 12)
        ])

        // Activity: Record party start with retry policy
        // Educational: Critical operations get aggressive retry configuration
        try await Workflow.executeActivity(
            PartyActivities.Activities.RecordPartyStart.self,
            options: .init(
                startToCloseTimeout: .seconds(10),
                retryPolicy: RetryPolicy(
                    initialInterval: .seconds(1),
                    backoffCoefficient: 2.0,  // Exponential backoff
                    maximumInterval: .seconds(10),
                    maximumAttempts: 3  // Retry up to 3 times for critical ops
                )
            ),
            input: PartyActivities.RecordPartyStartInput(
                location: input.location,
                startTime: startTime
            )
        )

        // Educational: Workflow completes immediately
        // For long-running workflows with signals/queries, see SDK 0.6+
        return "Party started at \(input.location)"
    }
}

/// Workflow to update party location
/// Educational: Separate workflow for updates (SDK 0.5 pattern)
@Workflow
final class UpdateLocationWorkflow {
    func run(input: UpdateLocationInput) async throws -> String {
        Workflow.logger.info("Location updated", metadata: [
            "source": .string(input.source),
            "reason": .string(input.reason),
            "deviceId": .string(input.deviceId ?? "none"),
            "location": .string("\(input.location.lat),\(input.location.lng)")
        ])

        // Educational: Non-critical operations use lighter retry policy
        try await Workflow.executeActivity(
            PartyActivities.Activities.UpdateLocation.self,
            options: .init(
                startToCloseTimeout: .seconds(5),
                retryPolicy: RetryPolicy(
                    initialInterval: .seconds(1),
                    backoffCoefficient: 1.5,  // Less aggressive backoff
                    maximumInterval: .seconds(5),
                    maximumAttempts: 2  // Fail faster for non-critical
                )
            ),
            input: PartyActivities.UpdateLocationActivityInput(location: input.location)
        )

        return "Location updated"
    }
}

/// Workflow to stop party
/// Educational: Shows idempotent cleanup pattern
@Workflow
final class StopPartyWorkflow {
    func run(input: StopPartyInput) async throws -> String {
        let endTime = Date()

        Workflow.logger.info("Party stopped", metadata: [
            "source": .string(input.source),
            "reason": .string(input.reason),
            "deviceId": .string(input.deviceId ?? "none")
        ])

        // Educational: Cleanup operations should be idempotent
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
/// Educational: Read-only workflow for querying state
@Workflow
final class GetPartyStateWorkflow {
    func run(input: GetPartyStateInput) async throws -> PartyActivities.GetPartyStateOutput {
        Workflow.logger.info("Party state queried", metadata: [
            "source": .string(input.source),
            "reason": .string(input.reason),
            "deviceId": .string(input.deviceId ?? "none")
        ])

        // Execute activity to query state
        // Educational: Fast timeout for read operations
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
 TEMPORAL BEST PRACTICES DEMONSTRATED:

 1. **Retry Policies**:
    - Critical operations (party start/end): 3 retries, exponential backoff
    - Non-critical (location update): 2 retries, lighter backoff
    - Reads (get state): Fast fail with short timeouts

 2. **Timeouts**:
    - startToCloseTimeout: Maximum time for activity execution
    - Prevents workflows from hanging on stuck activities

 3. **Idempotency**:
    - All activities should be idempotent (safe to retry)
    - Activities handle duplicate calls gracefully

 4. **Structured Logging**:
    - Include source, reason, deviceId for traceability
    - Helps debug issues and understand usage patterns

 5. **Workflow as State Machine**:
    - Workflows represent business processes
    - Durable execution survives crashes/restarts
    - State is automatically persisted

 FUTURE ENHANCEMENTS (SDK 0.6+):
 - Long-running workflows with signals for updates
 - Queries for real-time state inspection
 - Timers for scheduled actions
 - Continue-as-new for very long workflows
 - Child workflows for complex operations

 WORKER SCALING:
 - Multiple workers can process same task queue
 - Temporal handles load balancing automatically
 - Scale workers horizontally for throughput
 - Each worker processes activities concurrently
 - No coordination needed between workers

 DEPLOYMENT:
 - Workers can be deployed independently
 - Rolling updates supported (old + new versions run together)
 - Workflow versioning for safe code evolution
 - Activities are versioned implicitly by deployment
*/
