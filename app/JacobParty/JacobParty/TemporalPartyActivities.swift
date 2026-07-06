import Foundation
import Temporal

@ActivityContainer
struct TemporalPartyActivities {
    struct RecordPartyStartInput: Codable, Sendable {
        let location: Location
        let startTime: Date
        let deviceId: String?
    }

    struct RecordPartyEndInput: Codable, Sendable {
        let startTime: Date
        let endTime: Date
        let deviceId: String?
    }

    @Activity
    nonisolated
    func recordPartyStart(input: RecordPartyStartInput) async throws {
        print("Temporal iOS worker recorded party start for \(input.deviceId ?? "unknown device") at \(input.location.lat), \(input.location.lng)")
    }

    @Activity
    nonisolated
    func recordPartyEnd(input: RecordPartyEndInput) async throws {
        let duration = Int(input.endTime.timeIntervalSince(input.startTime))
        print("Temporal iOS worker recorded party end for \(input.deviceId ?? "unknown device") after \(duration)s")
    }
}
