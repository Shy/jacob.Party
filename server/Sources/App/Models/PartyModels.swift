import Foundation
import Vapor

struct Location: Codable, Sendable {
    let lat: Double
    let lng: Double
}

struct StartPartyInput: Codable, Sendable {
    let location: Location
}

struct PartyStateResponse: Content {
    let spinning: Bool
    let location: Location?
    let appName: String
    let startTime: String?  // ISO8601 timestamp
}
