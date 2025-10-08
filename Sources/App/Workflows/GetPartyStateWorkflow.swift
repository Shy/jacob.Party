import Foundation
import Temporal

/// Simple workflow to query party state from database via activity.
@Workflow
final class GetPartyStateWorkflow {
    init(input: Void) {}

    func run(input: Void) async throws -> PartyActivities.GetPartyStateOutput {
        // Execute activity to query database
        return try await Workflow.executeActivity(
            PartyActivities.Activities.GetPartyState.self,
            options: .init(startToCloseTimeout: .seconds(5))
        )
    }
}
