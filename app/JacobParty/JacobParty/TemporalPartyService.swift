import Foundation
import GRPCNIOTransportCore
import GRPCNIOTransportHTTP2Posix
import Logging
import Temporal

actor TemporalPartyService {
    enum ServiceError: Error {
        case disabled
        case notConfigured(String)
        case notStarted
    }

    struct Configuration {
        let enabled: Bool
        let host: String
        let port: Int
        let namespace: String
        let taskQueue: String
        let tlsEnabled: Bool
        let apiKey: String?
        let appName: String

        var workflowID: String {
            "\(appName)-party"
        }

        static func load() -> Configuration {
            let bundle = Bundle.main
            let enabled = bundle.boolValue(forInfoKey: "TEMPORAL_DIRECT_ENABLED")
            let host = bundle.stringValue(forInfoKey: "TEMPORAL_HOST", default: "127.0.0.1")
            let port = bundle.intValue(forInfoKey: "TEMPORAL_PORT", default: 7233)
            let namespace = bundle.stringValue(forInfoKey: "TEMPORAL_NAMESPACE", default: "default")
            let taskQueue = bundle.stringValue(forInfoKey: "TEMPORAL_TASK_QUEUE", default: "party-ios-queue")
            let tlsEnabled = bundle.boolValue(forInfoKey: "TEMPORAL_TLS_ENABLED")
            let apiKey = bundle.optionalStringValue(forInfoKey: "TEMPORAL_API_KEY")
            let appName = bundle.stringValue(forInfoKey: "APP_NAME", default: "jacob")

            return Configuration(
                enabled: enabled,
                host: host,
                port: port,
                namespace: namespace,
                taskQueue: taskQueue,
                tlsEnabled: tlsEnabled,
                apiKey: apiKey,
                appName: appName
            )
        }
    }

    private let configuration: Configuration
    private var client: TemporalClient?
    private var worker: TemporalWorker?
    private var clientTask: Task<Void, Never>?
    private var workerTask: Task<Void, Never>?

    init(configuration: Configuration = .load()) {
        self.configuration = configuration
    }

    var isEnabled: Bool {
        configuration.enabled
    }

    func startIfNeeded() async throws {
        guard configuration.enabled else {
            throw ServiceError.disabled
        }
        guard client == nil, worker == nil else {
            return
        }

        let logger = Logger(label: "jacob-party-ios-temporal")
        let client = try TemporalClient(
            target: .dns(host: configuration.host, port: configuration.port),
            transportSecurity: configuration.tlsEnabled ? .tls : .plaintext,
            configuration: .init(
                instrumentation: .init(serverHostname: configuration.host),
                namespace: configuration.namespace,
                apiKey: configuration.apiKey
            ),
            logger: logger
        )

        let worker = try TemporalWorker(
            configuration: .init(
                namespace: configuration.namespace,
                taskQueue: configuration.taskQueue,
                instrumentation: .init(serverHostname: configuration.host),
                apiKey: configuration.apiKey
            ),
            target: .dns(host: configuration.host, port: configuration.port),
            transportSecurity: configuration.tlsEnabled ? .tls : .plaintext,
            activityContainers: TemporalPartyActivities(),
            workflows: [PartyWorkflow.self],
            logger: logger
        )

        self.client = client
        self.worker = worker

        clientTask = Task {
            do {
                try await client.run()
            } catch {
                print("Temporal iOS client stopped: \(error)")
            }
        }

        workerTask = Task {
            do {
                try await worker.run()
            } catch {
                print("Temporal iOS worker stopped: \(error)")
            }
        }

        try await Task.sleep(for: .milliseconds(500))
    }

    func stop() {
        clientTask?.cancel()
        workerTask?.cancel()
        clientTask = nil
        workerTask = nil
        client = nil
        worker = nil
    }

    func fetchState() async throws -> PartyStateOutput {
        let client = try await runningClient()
        let handle = client.workflowHandle(type: PartyWorkflow.self, id: configuration.workflowID)
        return try await handle.query(queryType: PartyWorkflow.GetPartyState.self)
    }

    func startParty(location: Location, deviceId: String) async throws {
        let client = try await runningClient()
        _ = try await client.signalWithStartWorkflow(
            type: PartyWorkflow.self,
            input: StartPartyInput(
                location: location,
                source: "ios-temporal-sdk",
                reason: "user-pressed-button",
                deviceId: deviceId,
                autoStopHours: 6
            ),
            options: .init(
                id: configuration.workflowID,
                taskQueue: configuration.taskQueue
            ),
            signalType: PartyWorkflow.UpdateLocation.self,
            signalInput: location
        )
    }

    func updateLocation(_ location: Location) async throws {
        let client = try await runningClient()
        let handle = client.workflowHandle(type: PartyWorkflow.self, id: configuration.workflowID)
        try await handle.signal(
            signalType: PartyWorkflow.UpdateLocation.self,
            input: location
        )
    }

    func stopParty() async throws {
        let client = try await runningClient()
        let handle = client.workflowHandle(type: PartyWorkflow.self, id: configuration.workflowID)
        try await handle.signal(signalType: PartyWorkflow.StopParty.self)
    }

    private func runningClient() async throws -> TemporalClient {
        try await startIfNeeded()
        guard let client else {
            throw ServiceError.notStarted
        }
        return client
    }
}

private extension Bundle {
    func stringValue(forInfoKey key: String, default fallback: String) -> String {
        optionalStringValue(forInfoKey: key) ?? fallback
    }

    func optionalStringValue(forInfoKey key: String) -> String? {
        guard let value = object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }

    func intValue(forInfoKey key: String, default fallback: Int) -> Int {
        guard let value = optionalStringValue(forInfoKey: key),
              let parsed = Int(value) else {
            return fallback
        }
        return parsed
    }

    func boolValue(forInfoKey key: String) -> Bool {
        guard let value = optionalStringValue(forInfoKey: key) else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }
}
