import Foundation
import Temporal

/// Simple workflow to query party state from database via activity.
/// Tracks the source of the query (ios-app, web, api) for analytics.
@Workflow
final class GetPartyStateWorkflow {
    private let input: GetPartyStateInput

    init(input: GetPartyStateInput) {
        self.input = input
    }

    func run(input: GetPartyStateInput) async throws -> PartyActivities.GetPartyStateOutput {
        // Log the query source for analytics
        Workflow.logger.info("Party state queried", metadata: [
            "source": .string(input.source),
            "reason": .string(input.reason),
            "deviceId": .string(input.deviceId ?? "none")
        ])

        // Execute activity to query database
        return try await Workflow.executeActivity(
            PartyActivities.Activities.GetPartyState.self,
            options: .init(startToCloseTimeout: .seconds(5))
        )
    }
}
