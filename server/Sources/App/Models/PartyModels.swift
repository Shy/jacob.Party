import Foundation
import Vapor

struct Location: Codable, Sendable {
    let lat: Double
    let lng: Double
}

// MARK: - Workflow Inputs

/// Input for starting a party
struct StartPartyInput: Codable, Sendable {
    let location: Location
    let source: String  // e.g., "ios-app", "web", "api"
    let reason: String  // e.g., "user-pressed-button", "api-call"
    let deviceId: String?
    let autoStopHours: Int?  // Optional: for future long-running workflows
}

/// Input for stopping a party
struct StopPartyInput: Codable, Sendable {
    let source: String
    let reason: String
    let deviceId: String?
}

/// Input for updating location
struct UpdateLocationInput: Codable, Sendable {
    let location: Location
    let source: String
    let reason: String
    let deviceId: String?
}

/// Input for querying party state
struct GetPartyStateInput: Codable, Sendable {
    let source: String
    let reason: String
    let deviceId: String?
}

struct PartyStateResponse: Content {
    let spinning: Bool
    let location: Location?
    let appName: String
    let startTime: String?  // ISO8601 timestamp
}
