import Foundation

struct Location: Codable, Sendable {
    let lat: Double
    let lng: Double
}

struct StartPartyInput: Codable, Sendable {
    let location: Location
    let source: String
    let reason: String
    let deviceId: String?
    let autoStopHours: Int?
}

struct PartyResult: Codable, Sendable {
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Double
    let locationUpdateCount: Int
}

struct PartyStateOutput: Codable, Sendable {
    let isPartying: Bool
    let location: Location?
    let startTime: Date?
    let reason: String
    let autoStopAt: Date
    let locationUpdateCount: Int
}

struct SetReasonInput: Codable, Sendable {
    let reason: String
}

struct ExtendAutoStopInput: Codable, Sendable {
    let additionalHours: Int
}
