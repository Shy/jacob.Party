import Foundation
import Vapor

struct Location: Codable, Sendable {
    let lat: Double
    let lng: Double
}

// MARK: - Workflow Input

/// Input passed to `PartyWorkflow.run` when a party starts.
struct StartPartyInput: Codable, Sendable {
    let location: Location
    let source: String  // e.g., "ios-app", "web", "api"
    let reason: String
    let deviceId: String?
    let autoStopHours: Int?
}

// MARK: - Workflow Output / Query

/// Result returned when `PartyWorkflow` finishes.
struct PartyResult: Codable, Sendable {
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Double
    let locationUpdateCount: Int
}

/// Snapshot of party state returned by `getPartyState` query.
struct PartyStateOutput: Codable, Sendable {
    let isPartying: Bool
    let location: Location?
    let startTime: Date?
    let reason: String
    let autoStopAt: Date
    let locationUpdateCount: Int
}

// MARK: - Update Inputs

/// Input for the `setReason` workflow update.
struct SetReasonInput: Codable, Sendable {
    let reason: String
}

/// Input for the `extendAutoStop` workflow update.
struct ExtendAutoStopInput: Codable, Sendable {
    let additionalHours: Int
}

// MARK: - HTTP Response

struct PartyStateResponse: Content {
    let spinning: Bool
    let location: Location?
    let appName: String
    let startTime: String?  // ISO8601 timestamp
}

// MARK: - Push Notifications

struct PushSubscription: Codable, Sendable {
    let id: String
    let endpoint: String
    let authKey: String
    let p256dhKey: String
    let createdAt: String
}
