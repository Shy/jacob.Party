import Foundation
import Vapor

struct Location: Codable, Sendable {
    let lat: Double
    let lng: Double
}

struct StartPartyInput: Codable, Sendable {
    let location: Location
    let source: String  // e.g., "ios-app", "web", "api"
    let reason: String  // e.g., "user-pressed-button", "api-call"
    let deviceId: String?
}

struct StopPartyInput: Codable, Sendable {
    let source: String  // e.g., "ios-app", "web", "api"
    let reason: String  // e.g., "user-stopped", "timeout", "api-call"
    let deviceId: String?
}

struct UpdateLocationInput: Codable, Sendable {
    let location: Location
    let source: String  // e.g., "ios-app", "web", "api"
    let reason: String  // e.g., "background-update", "manual-update"
    let deviceId: String?
}

struct GetPartyStateInput: Codable, Sendable {
    let source: String  // e.g., "ios-app", "web", "api"
    let reason: String  // e.g., "health-check", "user-view", "app-start"
    let deviceId: String?
}

struct PartyStateResponse: Content {
    let spinning: Bool
    let location: Location?
    let appName: String
    let startTime: String?  // ISO8601 timestamp
}
