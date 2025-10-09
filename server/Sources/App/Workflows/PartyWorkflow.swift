import Foundation
import Temporal

/// Workflow that represents a single party session.
/// Each party start creates a new workflow. Stopping the party cancels it.
@Workflow
final class PartyWorkflow {
    private let location: Location
    private let startTime: Date

    init(input: StartPartyInput) {
        self.location = input.location
        self.startTime = Date()
    }

    // MARK: - Workflow Implementation

    func run(input: StartPartyInput) async throws -> String {
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
        return "Party started at \(location)"
    }
}
