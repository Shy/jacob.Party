import Foundation
import Temporal

/// Activities for party workflow demonstrating database operations.
@ActivityContainer
struct PartyActivities {
    // MARK: - Activity Input Types

    struct RecordPartyStartInput: Codable {
        let location: Location
        let startTime: Date
    }

    struct RecordPartyEndInput: Codable {
        let startTime: Date
        let endTime: Date
    }

    struct GetPartyStateOutput: Codable {
        let isPartying: Bool
        let location: Location?
        let startTime: Date?
    }

    struct UpdateLocationInput: Codable {
        let location: Location
    }

    // MARK: - Activities

    /// Records when the party starts (updates database).
    @Activity
    func recordPartyStart(input: RecordPartyStartInput) async throws {
        print("🎉 Party started at lat: \(input.location.lat), lng: \(input.location.lng) at \(input.startTime)")

        // TODO: Update SQLite database
        // For now, just write to a file as a simple state store
        let state = PartyState(
            isPartying: true,
            location: input.location,
            startTime: input.startTime
        )
        try saveState(state)
    }

    /// Records when the party ends (updates database).
    @Activity
    func recordPartyEnd(input: RecordPartyEndInput) async throws {
        let duration = input.endTime.timeIntervalSince(input.startTime)
        print("🛑 Party ended. Duration: \(duration) seconds")

        // Delete the state file to clear all data
        let url = stateFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            print("🗑️ Cleared party state data")
        }
    }

    /// Queries the current party state from database.
    @Activity
    func getPartyState(input: ()) async throws -> GetPartyStateOutput {
        // TODO: Query SQLite database
        // For now, read from file
        let state = try loadState()
        return GetPartyStateOutput(
            isPartying: state.isPartying,
            location: state.location,
            startTime: state.startTime
        )
    }

    /// Updates the party location (updates database).
    @Activity
    func updateLocation(input: UpdateLocationInput) async throws {
        print("📍 Location updated to lat: \(input.location.lat), lng: \(input.location.lng)")

        // Load current state
        var state = try loadState()

        // Only update if currently partying
        guard state.isPartying else {
            print("⚠️ Not currently partying, ignoring location update")
            return
        }

        // Update location while preserving other state
        state = PartyState(
            isPartying: state.isPartying,
            location: input.location,
            startTime: state.startTime
        )
        try saveState(state)
    }

    // MARK: - Helper Methods (File-based state for now)

    private func saveState(_ state: PartyState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let url = stateFileURL()
        try data.write(to: url)
    }

    private func loadState() throws -> PartyState {
        let url = stateFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            // No state file, return default (not partying)
            return PartyState(isPartying: false, location: nil, startTime: nil)
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PartyState.self, from: data)
    }

    private func stateFileURL() -> URL {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
        return tmpDir.appendingPathComponent("party-state.json")
    }
}

// MARK: - Internal State Model

private struct PartyState: Codable {
    var isPartying: Bool
    var location: Location?
    var startTime: Date?
}
