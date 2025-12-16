import Foundation
import Temporal

/// Workflow that represents a single party session.
/// Each party start creates a new workflow. Stopping the party cancels it.
@Workflow
final class PartyWorkflow {
    private let input: StartPartyInput
    private let startTime: Date

    init(input: StartPartyInput) {
        self.input = input
        self.startTime = Date()
    }

    // MARK: - Workflow Implementation

    func run(input: StartPartyInput) async throws -> String {
        // Log party start with tracking information
        Workflow.logger.info("Party started", metadata: [
            "source": .string(input.source),
            "reason": .string(input.reason),
            "deviceId": .string(input.deviceId ?? "none"),
            "location": .string("\(input.location.lat),\(input.location.lng)")
        ])

        // Record party start
        try await Workflow.executeActivity(
            PartyActivities.Activities.RecordPartyStart.self,
            options: .init(startToCloseTimeout: .seconds(10)),
            input: PartyActivities.RecordPartyStartInput(
                location: input.location,
                startTime: startTime
            )
        )

        // Workflow completes immediately after recording the party start
        return "Party started at \(input.location)"
    }
}
