import Foundation
import Temporal

/// Workflow that stops a party session (updates database).
@Workflow
final class StopPartyWorkflow {
    init(input: Void) {}

    func run(input: Void) async throws -> String {
        let endTime = Date()

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
