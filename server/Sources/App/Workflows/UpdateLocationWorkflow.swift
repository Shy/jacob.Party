import Foundation
import Temporal

/// Workflow that updates the party location in the database.
@Workflow
final class UpdateLocationWorkflow {
    private let input: UpdateLocationInput

    init(input: UpdateLocationInput) {
        self.input = input
    }

    func run(input: UpdateLocationInput) async throws -> String {
        // Log location update with tracking information
        Workflow.logger.info("Location updated", metadata: [
            "source": .string(input.source),
            "reason": .string(input.reason),
            "deviceId": .string(input.deviceId ?? "none"),
            "location": .string("\(input.location.lat),\(input.location.lng)")
        ])

        // Update location in database (activity only needs location)
        try await Workflow.executeActivity(
            PartyActivities.Activities.UpdateLocation.self,
            options: .init(startToCloseTimeout: .seconds(10)),
            input: PartyActivities.UpdateLocationInput(location: input.location)
        )

        return "Location updated"
    }
}
