import Vapor
import Temporal
import Logging
import Foundation

public func configure(_ app: Application) async throws {
    let logger = Logger(label: "vapor-app")

    // Load environment variables from .env file
    loadEnvFile()

    // Get configuration from environment
    let appName = Environment.get("APP_NAME") ?? "jacob"
    let temporalHost = Environment.get("TEMPORAL_HOST") ?? "127.0.0.1"
    let temporalPort = Int(Environment.get("TEMPORAL_PORT") ?? "7233") ?? 7233
    let temporalNamespace = Environment.get("TEMPORAL_NAMESPACE") ?? "default"
    let temporalTaskQueue = Environment.get("TEMPORAL_TASK_QUEUE") ?? "party-queue"
    let tlsEnabled = Environment.get("TEMPORAL_TLS_ENABLED")?.lowercased() == "true"
    let googleMapsApiKey = Environment.get("GOOGLE_MAPS_API_KEY") ?? ""
    let serverHost = Environment.get("SERVER_HOST") ?? "0.0.0.0"
    let serverPort = Int(Environment.get("SERVER_PORT") ?? "8080") ?? 8080

    // Get certificate paths (check both file paths and content from env vars)
    var clientCertPath = Environment.get("TEMPORAL_CLIENT_CERT")
    var clientKeyPath = Environment.get("TEMPORAL_CLIENT_KEY")

    // If certificate contents are provided as env vars (Digital Ocean), write them to temp files
    if let certContent = Environment.get("TEMPORAL_CLIENT_CERT_CONTENT"),
       let keyContent = Environment.get("TEMPORAL_CLIENT_KEY_CONTENT") {
        let tmpDir = FileManager.default.temporaryDirectory
        let certFile = tmpDir.appendingPathComponent("client.pem")
        let keyFile = tmpDir.appendingPathComponent("client.key")

        try certContent.write(to: certFile, atomically: true, encoding: .utf8)
        try keyContent.write(to: keyFile, atomically: true, encoding: .utf8)

        clientCertPath = certFile.path
        clientKeyPath = keyFile.path

        logger.info("📝 Wrote certificates from environment variables to temporary files")
    }

    // Store configuration for routes
    app.storage[AppNameKey.self] = appName
    app.storage[GoogleMapsApiKeyKey.self] = googleMapsApiKey

    // Load allowed device IDs from environment
    let allowedDeviceIDsStr = Environment.get("ALLOWED_DEVICE_IDS") ?? ""
    let allowedDeviceIDs = allowedDeviceIDsStr
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    app.storage[AllowedDeviceIDsKey.self] = allowedDeviceIDs

    if allowedDeviceIDs.isEmpty {
        logger.warning("⚠️ No device whitelist configured - all devices will be allowed")
    } else {
        logger.info("🔒 Device whitelist enabled with \(allowedDeviceIDs.count) allowed device(s)")
    }

    // Determine if using TLS and create client/worker accordingly
    if tlsEnabled {
        guard let certPath = clientCertPath, let keyPath = clientKeyPath else {
            logger.error("❌ TLS enabled but TEMPORAL_CLIENT_CERT or TEMPORAL_CLIENT_KEY not set")
            throw Abort(.internalServerError, reason: "TLS enabled but certificate paths missing")
        }

        logger.info("🔐 Connecting to Temporal Cloud with mTLS")
        logger.info("   Host: \(temporalHost)")
        logger.info("   Namespace: \(temporalNamespace)")
        logger.info("   Certificate: \(certPath)")
        logger.info("   Key: \(keyPath)")

        // Create Temporal Client with mTLS using DNS (for cloud hostnames)
        let client = try TemporalClient(
            target: .dns(host: temporalHost, port: temporalPort),
            transportSecurity: .mTLS(
                certificateChain: [.file(path: certPath, format: .pem)],
                privateKey: .file(path: keyPath, format: .pem)
            ),
            configuration: .init(
                instrumentation: .init(serverHostname: temporalHost),
                namespace: temporalNamespace
            ),
            logger: logger
        )

        app.storage[ClientKey.self] = client

        // Configure Temporal Worker with mTLS
        let workerConfig = TemporalWorker.Configuration(
            namespace: temporalNamespace,
            taskQueue: temporalTaskQueue,
            instrumentation: .init(serverHostname: temporalHost)
        )

        let worker = try TemporalWorker(
            configuration: workerConfig,
            target: .dns(host: temporalHost, port: temporalPort),
            transportSecurity: .mTLS(
                certificateChain: [.file(path: certPath, format: .pem)],
                privateKey: .file(path: keyPath, format: .pem)
            ),
            activityContainers: PartyActivities(),
            workflows: [PartyWorkflow.self, GetPartyStateWorkflow.self, StopPartyWorkflow.self, UpdateLocationWorkflow.self],
            logger: logger
        )

        app.storage[WorkerKey.self] = worker
    } else {
        // Local development with plaintext
        logger.info("⚠️ Using plaintext connection (local development)")
        logger.info("   Host: \(temporalHost):\(temporalPort)")

        let client = try TemporalClient(
            target: .ipv4(address: temporalHost, port: temporalPort),
            transportSecurity: .plaintext,
            configuration: .init(
                instrumentation: .init(serverHostname: temporalHost)
            ),
            logger: logger
        )

        app.storage[ClientKey.self] = client

        let workerConfig = TemporalWorker.Configuration(
            namespace: temporalNamespace,
            taskQueue: temporalTaskQueue,
            instrumentation: .init(serverHostname: temporalHost)
        )

        let worker = try TemporalWorker(
            configuration: workerConfig,
            target: .ipv4(address: temporalHost, port: temporalPort),
            transportSecurity: .plaintext,
            activityContainers: PartyActivities(),
            workflows: [PartyWorkflow.self, GetPartyStateWorkflow.self, StopPartyWorkflow.self, UpdateLocationWorkflow.self],
            logger: logger
        )

        app.storage[WorkerKey.self] = worker
    }

    // Start client and worker in background
    guard let client = app.storage[ClientKey.self],
          let worker = app.storage[WorkerKey.self] else {
        throw Abort(.internalServerError, reason: "Client or worker not initialized")
    }

    Task {
        try await client.run()
    }

    Task {
        try await worker.run()
    }

    // Configure HTTP server
    app.http.server.configuration.hostname = serverHost
    app.http.server.configuration.port = serverPort

    // Register routes
    try routes(app)

    logger.info("🚀 Vapor server configured with Temporal worker")
}

struct ClientKey: StorageKey {
    typealias Value = TemporalClient
}

struct WorkerKey: StorageKey {
    typealias Value = TemporalWorker
}

struct AppNameKey: StorageKey {
    typealias Value = String
}

struct GoogleMapsApiKeyKey: StorageKey {
    typealias Value = String
}

// MARK: - Environment File Loader

func loadEnvFile() {
    let fileManager = FileManager.default
    let currentPath = fileManager.currentDirectoryPath
    let envPath = currentPath + "/.env"

    guard fileManager.fileExists(atPath: envPath),
          let contents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
        return
    }

    let lines = contents.components(separatedBy: .newlines)
    for line in lines {
        // Skip comments and empty lines
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") {
            continue
        }

        // Parse KEY=VALUE
        let parts = trimmed.components(separatedBy: "=")
        guard parts.count == 2 else { continue }

        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1].trimmingCharacters(in: .whitespaces)

        // Set environment variable if not already set
        if Environment.get(key) == nil {
            setenv(key, value, 1)
        }
    }
}
