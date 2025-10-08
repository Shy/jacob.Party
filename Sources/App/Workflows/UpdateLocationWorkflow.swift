import Foundation
import Temporal

/// Input for UpdateLocationWorkflow
struct UpdateLocationInput: Codable {
    let location: Location
}

/// Workflow that updates the party location in the database.
@Workflow
final class UpdateLocationWorkflow {
    init(input: UpdateLocationInput) {}

    func run(input: UpdateLocationInput) async throws -> String {
        // Update location in database
        try await Workflow.executeActivity(
            PartyActivities.Activities.UpdateLocation.self,
            options: .init(startToCloseTimeout: .seconds(10)),
            input: PartyActivities.UpdateLocationInput(location: input.location)
        )

        return "Location updated"
    }
}
