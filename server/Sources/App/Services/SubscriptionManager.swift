import Foundation
import Vapor

/// Manages push notification subscriptions with file-based storage
/// NOTE: File storage in temp directory - subscriptions lost on restart
/// For production persistence, use Temporal workflow state or database
actor SubscriptionManager {
    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
        self.fileURL = tmpDir.appendingPathComponent("push-subscriptions.json")
    }

    func add(_ subscription: PushSubscription) throws {
        var subs = try loadSubscriptions()
        subs[subscription.id] = subscription
        try saveSubscriptions(subs)
    }

    func remove(id: String) throws {
        var subs = try loadSubscriptions()
        subs.removeValue(forKey: id)
        try saveSubscriptions(subs)
    }

    func getAll() throws -> [PushSubscription] {
        Array(try loadSubscriptions().values)
    }

    func get(id: String) throws -> PushSubscription? {
        try loadSubscriptions()[id]
    }

    func count() throws -> Int {
        try loadSubscriptions().count
    }

    // MARK: - File Operations

    private func loadSubscriptions() throws -> [String: PushSubscription] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String: PushSubscription].self, from: data)
    }

    private func saveSubscriptions(_ subscriptions: [String: PushSubscription]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subscriptions)
        try data.write(to: fileURL)
    }

    // Static method for activities to access subscriptions
    static func loadAll() throws -> [PushSubscription] {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("push-subscriptions.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let dict = try JSONDecoder().decode([String: PushSubscription].self, from: data)
        return Array(dict.values)
    }
}

/// Storage key for SubscriptionManager
struct SubscriptionManagerKey: StorageKey {
    typealias Value = SubscriptionManager
}
