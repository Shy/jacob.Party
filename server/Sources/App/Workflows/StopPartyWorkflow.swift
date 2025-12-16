import Foundation
import Temporal

/// Workflow that stops a party session (updates database).
@Workflow
final class StopPartyWorkflow {
    private let input: StopPartyInput

    init(input: StopPartyInput) {
        self.input = input
    }

    func run(input: StopPartyInput) async throws -> String {
        let endTime = Date()

        // Log party stop with tracking information
        Workflow.logger.info("Party stopped", metadata: [
            "source": .string(input.source),
            "reason": .string(input.reason),
            "deviceId": .string(input.deviceId ?? "none")
        ])

        // Record party end - we don't know the startTime, so pass current time for both
        // The activity will handle clearing the state
        try await Workflow.executeActivity(
            PartyActivities.Activities.RecordPartyEnd.self,
            options: .init(startToCloseTimeout: .seconds(10)),
            input: PartyActivities.RecordPartyEndInput(
                startTime: endTime,  // This doesn't matter since we're just clearing state
                endTime: endTime
            )
        )

        return "Party stopped"
    }
}
