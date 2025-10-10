import Foundation
import Temporal

/// Workflow that updates the party location in the database.
@Workflow
final class UpdateLocationWorkflow {
    init(input: PartyActivities.UpdateLocationInput) {}

    func run(input: PartyActivities.UpdateLocationInput) async throws -> String {
        // Update location in database
        try await Workflow.executeActivity(
            PartyActivities.Activities.UpdateLocation.self,
            options: .init(startToCloseTimeout: .seconds(10)),
            input: input
        )

        return "Location updated"
    }
}
