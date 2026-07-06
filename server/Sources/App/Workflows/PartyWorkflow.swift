import Foundation
import Temporal

/// Long-running workflow that owns the state of a party session.
///
/// Demonstrates the SDK 1.0 idiomatic pattern: one durable workflow that lives
/// for the duration of the party and is interacted with via signals (write),
/// queries (read), and updates (read-write with validation). The workflow ends
/// when a `stopParty` signal arrives or when the auto-stop timer fires.
@Workflow
struct PartyWorkflow {
    // MARK: - Persistent State

    var isPartying: Bool = false
    var currentLocation: Location
    var partyStartTime: Date
    var reason: String
    var autoStopAt: Date
    var locationUpdateCount: Int = 0
    var shouldExit: Bool = false

    init(input: StartPartyInput) {
        self.currentLocation = input.location
        self.reason = input.reason
        // Placeholder; rewritten from `context.now` in `run` so values are deterministic.
        self.partyStartTime = .distantPast
        self.autoStopAt = .distantFuture
    }

    // MARK: - Run

    mutating func run(context: WorkflowContext<Self>, input: StartPartyInput) async throws -> PartyResult {
        let hours = input.autoStopHours ?? 6
        partyStartTime = context.now
        autoStopAt = context.now.addingTimeInterval(TimeInterval(hours * 3600))
        isPartying = true

        context.logger.info("Party started", metadata: [
            "source": .string(input.source),
            "reason": .string(input.reason),
            "deviceId": .string(input.deviceId ?? "none"),
            "auto_stop_hours": .stringConvertible(hours),
        ])

        try await context.executeActivity(
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
                location: currentLocation,
                startTime: partyStartTime
            )
        )

        // Run two background tasks alongside the main wait:
        //  1. fan out push notifications via a child workflow
        //  2. arm an auto-stop timer that flips `shouldExit` when it fires
        // The main task awaits `shouldExit`, which is also flipped by the
        // `stopParty` signal — whichever happens first wins.
        let parentWorkflowId = context.info.workflowID
        let plannedAutoStopAt = autoStopAt

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try? await context.executeChildWorkflow(
                    SendPartyNotificationsWorkflow.self,
                    options: .init(id: "\(parentWorkflowId)-notify-start"),
                    input: SendPartyNotificationsWorkflow.Input(
                        message: "🎉 Jacob started partying, join at jacob.party"
                    )
                )
            }

            group.addTask {
                let interval = plannedAutoStopAt.timeIntervalSince(context.now)
                guard interval > 0 else { return }
                try await context.sleep(
                    for: .seconds(interval),
                    summary: "auto-stop after \(hours)h"
                )
                context.mutateState { $0.shouldExit = true }
            }

            try await context.condition { $0.shouldExit }
            group.cancelAll()
        }

        let endTime = context.now
        isPartying = false

        try await context.executeActivity(
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
                startTime: partyStartTime,
                endTime: endTime
            )
        )

        let duration = endTime.timeIntervalSince(partyStartTime)
        context.logger.info("Party ended", metadata: [
            "duration_seconds": .stringConvertible(Int(duration)),
            "location_updates": .stringConvertible(locationUpdateCount),
        ])

        return PartyResult(
            startedAt: partyStartTime,
            endedAt: endTime,
            durationSeconds: duration,
            locationUpdateCount: locationUpdateCount
        )
    }

    // MARK: - Signals

    /// Updates the current party location. Sent as the user moves around.
    @WorkflowSignal
    mutating func updateLocation(input: Location) {
        guard isPartying else { return }
        currentLocation = input
        locationUpdateCount += 1
    }

    /// Ends the party. Causes `run` to fall through to recording the end.
    @WorkflowSignal
    mutating func stopParty(input: Void) {
        shouldExit = true
    }

    // MARK: - Queries

    /// Returns the current state of the party without writing to history.
    @WorkflowQuery
    func getPartyState(input: Void) throws -> PartyStateOutput {
        PartyStateOutput(
            isPartying: isPartying,
            location: isPartying ? currentLocation : nil,
            startTime: isPartying ? partyStartTime : nil,
            reason: reason,
            autoStopAt: autoStopAt,
            locationUpdateCount: locationUpdateCount
        )
    }

    // MARK: - Updates

    /// Changes the party reason. Validates length, then mutates and returns
    /// a description of the change. Demonstrates the validate-then-mutate
    /// pattern that updates enable.
    @WorkflowUpdate
    mutating func setReason(input: SetReasonInput) throws -> String {
        let trimmed = input.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 100 else {
            throw ApplicationError(
                message: "Reason must be 1-100 characters after trimming",
                type: "InvalidReason",
                isNonRetryable: true
            )
        }
        let old = reason
        reason = trimmed
        return "Reason changed from '\(old)' to '\(trimmed)'"
    }

    /// Pushes the auto-stop further into the future. Validates the additional
    /// duration and returns the new auto-stop time.
    @WorkflowUpdate
    mutating func extendAutoStop(input: ExtendAutoStopInput) throws -> Date {
        guard input.additionalHours >= 1, input.additionalHours <= 24 else {
            throw ApplicationError(
                message: "Additional hours must be between 1 and 24",
                type: "InvalidExtension",
                isNonRetryable: true
            )
        }
        autoStopAt = autoStopAt.addingTimeInterval(TimeInterval(input.additionalHours * 3600))
        return autoStopAt
    }
}

/// Child workflow spawned from `PartyWorkflow.run` to fan out push
/// notifications. Isolates retry/timeout behaviour from the parent and shows
/// up as a distinct execution in the Temporal UI.
@Workflow
struct SendPartyNotificationsWorkflow {
    struct Input: Codable, Sendable {
        let message: String
    }

    mutating func run(context: WorkflowContext<Self>, input: Input) async throws {
        let subscriptions = try await context.executeActivity(
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

        guard !subscriptions.isEmpty else {
            context.logger.info("No subscribers to notify")
            return
        }

        try await context.executeActivity(
            PartyActivities.Activities.SendPushNotification.self,
            options: .init(
                startToCloseTimeout: .seconds(60),
                heartbeatTimeout: .seconds(15),
                retryPolicy: RetryPolicy(
                    initialInterval: .seconds(1),
                    backoffCoefficient: 2.0,
                    maximumInterval: .seconds(10),
                    maximumAttempts: 3
                )
            ),
            input: PartyActivities.SendPushNotificationInput(
                message: input.message,
                subscriptions: subscriptions
            )
        )
    }
}
