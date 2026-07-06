import Foundation
import Temporal

@Workflow
struct PartyWorkflow {
    var isPartying: Bool = false
    var currentLocation: Location
    var partyStartTime: Date
    var reason: String
    var autoStopAt: Date
    var locationUpdateCount: Int = 0
    var shouldExit: Bool = false
    var deviceId: String?

    init(input: StartPartyInput) {
        currentLocation = input.location
        reason = input.reason
        deviceId = input.deviceId
        partyStartTime = .distantPast
        autoStopAt = .distantFuture
    }

    nonisolated
    mutating func run(context: WorkflowContext<Self>, input: StartPartyInput) async throws -> PartyResult {
        let hours = input.autoStopHours ?? 6
        partyStartTime = context.now
        autoStopAt = context.now.addingTimeInterval(TimeInterval(hours * 3600))
        isPartying = true

        try await context.executeActivity(
            TemporalPartyActivities.Activities.RecordPartyStart.self,
            options: .init(
                startToCloseTimeout: .seconds(10),
                retryPolicy: RetryPolicy(
                    initialInterval: .seconds(1),
                    backoffCoefficient: 2.0,
                    maximumInterval: .seconds(10),
                    maximumAttempts: 3
                )
            ),
            input: TemporalPartyActivities.RecordPartyStartInput(
                location: currentLocation,
                startTime: partyStartTime,
                deviceId: deviceId
            )
        )

        let plannedAutoStopAt = autoStopAt
        try await withThrowingTaskGroup(of: Void.self) { group in
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
            TemporalPartyActivities.Activities.RecordPartyEnd.self,
            options: .init(
                startToCloseTimeout: .seconds(10),
                retryPolicy: RetryPolicy(
                    initialInterval: .seconds(1),
                    backoffCoefficient: 2.0,
                    maximumInterval: .seconds(10),
                    maximumAttempts: 3
                )
            ),
            input: TemporalPartyActivities.RecordPartyEndInput(
                startTime: partyStartTime,
                endTime: endTime,
                deviceId: deviceId
            )
        )

        return PartyResult(
            startedAt: partyStartTime,
            endedAt: endTime,
            durationSeconds: endTime.timeIntervalSince(partyStartTime),
            locationUpdateCount: locationUpdateCount
        )
    }

    @WorkflowSignal
    nonisolated
    mutating func updateLocation(input: Location) {
        guard isPartying else { return }
        currentLocation = input
        locationUpdateCount += 1
    }

    @WorkflowSignal
    nonisolated
    mutating func stopParty(input: Void) {
        shouldExit = true
    }

    @WorkflowQuery
    nonisolated
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

    @WorkflowUpdate
    nonisolated
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

    @WorkflowUpdate
    nonisolated
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
