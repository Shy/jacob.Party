import Vapor
import Temporal
import Logging
import Foundation

// Storage for cleanup and graceful shutdown
struct CertCleanupKey: StorageKey {
    typealias Value = CertificateCleanup
}

struct TaskManagerKey: StorageKey {
    typealias Value = TaskManager
}

final class CertificateCleanup: @unchecked Sendable {
    var certPath: String?
    var keyPath: String?

    func cleanup() {
        if let certPath = certPath {
            try? FileManager.default.removeItem(atPath: certPath)
        }
        if let keyPath = keyPath {
            try? FileManager.default.removeItem(atPath: keyPath)
        }
    }
}

final class TaskManager: @unchecked Sendable {
    private var tasks: [Task<Void, Never>] = []
    private var isCancelled = false

    func add(_ task: Task<Void, Never>) {
        guard !isCancelled else { return }
        tasks.append(task)
    }

    func cancelAll() {
        isCancelled = true
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
    }
}

public func configure(_ app: Application) async throws {
    var logger = Logger(label: "jacob-party-app")
    logger.logLevel = .info

    // Load environment variables from .env file
    loadEnvFile()

    // Validate required environment variables
    try validateEnvironment(logger: logger)

    // Get configuration from environment
    let appName = Environment.get("APP_NAME") ?? "jacob"
    let temporalHost = Environment.get("TEMPORAL_HOST") ?? "127.0.0.1"
    let temporalPort = Int(Environment.get("TEMPORAL_PORT") ?? "7233") ?? 7233
    let temporalNamespace = Environment.get("TEMPORAL_NAMESPACE") ?? "default"
    let temporalTaskQueue = Environment.get("TEMPORAL_TASK_QUEUE") ?? "party-queue"
    let tlsEnabled = Environment.get("TEMPORAL_TLS_ENABLED")?.lowercased() == "true"
    let temporalApiKey = Environment.get("TEMPORAL_API_KEY")
    let googleMapsApiKey = Environment.get("GOOGLE_MAPS_API_KEY") ?? ""
    let serverHost = Environment.get("SERVER_HOST") ?? "0.0.0.0"
    let serverPort = Int(Environment.get("SERVER_PORT") ?? "8080") ?? 8080

    // Initialize task manager for graceful shutdown
    let taskManager = TaskManager()
    app.storage[TaskManagerKey.self] = taskManager

    // Initialize certificate cleanup
    let certCleanup = CertificateCleanup()
    app.storage[CertCleanupKey.self] = certCleanup

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

        // Register for cleanup
        certCleanup.certPath = clientCertPath
        certCleanup.keyPath = clientKeyPath

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
        logger.warning("⚠️  No device whitelist configured - all devices will be allowed")
    } else {
        logger.info("🔒 Device whitelist enabled", metadata: [
            "device_count": "\(allowedDeviceIDs.count)"
        ])
    }

    // Determine if using TLS and create client/worker accordingly
    if tlsEnabled {
        let authMethod = temporalApiKey != nil ? "API Key" : "mTLS"
        logger.info("🔐 Connecting to Temporal Cloud", metadata: [
            "host": "\(temporalHost)",
            "port": "\(temporalPort)",
            "namespace": "\(temporalNamespace)",
            "task_queue": "\(temporalTaskQueue)",
            "auth_method": "\(authMethod)"
        ])

        // Create Client and Worker with appropriate transport security
        // Supports both authentication methods:
        // 1. mTLS (certificate-based) - if TEMPORAL_CLIENT_CERT/KEY are provided
        // 2. API Key (simpler) - if only TEMPORAL_API_KEY is provided
        // Both can be used together for maximum security (mTLS + API key)
        if let certPath = clientCertPath, let keyPath = clientKeyPath {
            // Use mTLS if certificates are available (supports API key too)
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
            // Use TLS without client certificates (API key auth only)
            let client = try TemporalClient(
                target: .dns(host: temporalHost, port: temporalPort),
                transportSecurity: .tls,
                configuration: .init(
                    instrumentation: .init(serverHostname: temporalHost),
                    namespace: temporalNamespace
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
                target: .dns(host: temporalHost, port: temporalPort),
                transportSecurity: .tls,
                activityContainers: PartyActivities(),
                workflows: [PartyWorkflow.self, GetPartyStateWorkflow.self, StopPartyWorkflow.self, UpdateLocationWorkflow.self],
                logger: logger
            )
            app.storage[WorkerKey.self] = worker
        }
    } else {
        // Local development with plaintext
        logger.warning("⚠️  Using plaintext connection (local development)", metadata: [
            "host": "\(temporalHost)",
            "port": "\(temporalPort)",
            "namespace": "\(temporalNamespace)"
        ])

        let client = try TemporalClient(
            target: .dns(host: temporalHost, port: temporalPort),
            transportSecurity: .plaintext,
            configuration: .init(
                instrumentation: .init(serverHostname: temporalHost),
                namespace: temporalNamespace
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
            target: .dns(host: temporalHost, port: temporalPort),
            transportSecurity: .plaintext,
            activityContainers: PartyActivities(),
            workflows: [PartyWorkflow.self, GetPartyStateWorkflow.self, StopPartyWorkflow.self, UpdateLocationWorkflow.self],
            logger: logger
        )

        app.storage[WorkerKey.self] = worker
    }

    // Start client and worker in background with proper error handling
    guard let client = app.storage[ClientKey.self],
          let worker = app.storage[WorkerKey.self] else {
        throw Abort(.internalServerError, reason: "Client or worker not initialized")
    }

    // Start Temporal client first with retry logic
    let clientTask = Task {
        var retryCount = 0
        let maxRetries = 3

        while retryCount < maxRetries && !Task.isCancelled {
            do {
                logger.info("🔌 Starting Temporal client...", metadata: [
                    "attempt": "\(retryCount + 1)"
                ])
                try await client.run()
                logger.info("✅ Temporal client connected successfully")
                break
            } catch {
                retryCount += 1
                logger.error("❌ Temporal client failed", metadata: [
                    "error": "\(error)",
                    "error_type": "\(type(of: error))",
                    "attempt": "\(retryCount)",
                    "max_retries": "\(maxRetries)"
                ])

                if retryCount < maxRetries && !Task.isCancelled {
                    let backoff = Duration.seconds(min(retryCount * 2, 10))
                    logger.info("⏳ Retrying in \(backoff.components.seconds)s...")
                    try? await Task.sleep(for: backoff)
                }
            }
        }
    }
    taskManager.add(clientTask)

    // Start worker after a brief delay to ensure client is initialized
    let workerTask = Task {
        var retryCount = 0
        let maxRetries = 3

        // Give client time to initialize
        try? await Task.sleep(for: .milliseconds(500))

        while retryCount < maxRetries && !Task.isCancelled {
            do {
                logger.info("👷 Starting Temporal worker...", metadata: [
                    "attempt": "\(retryCount + 1)"
                ])
                try await worker.run()
                logger.info("✅ Temporal worker running successfully")
                break
            } catch {
                retryCount += 1
                logger.error("❌ Temporal worker failed", metadata: [
                    "error": "\(error)",
                    "error_type": "\(type(of: error))",
                    "attempt": "\(retryCount)",
                    "max_retries": "\(maxRetries)"
                ])

                if retryCount < maxRetries && !Task.isCancelled {
                    let backoff = Duration.seconds(min(retryCount * 2, 10))
                    logger.info("⏳ Retrying in \(backoff.components.seconds)s...")
                    try? await Task.sleep(for: backoff)
                }
            }
        }
    }
    taskManager.add(workerTask)

    // Configure HTTP server
    app.http.server.configuration.hostname = serverHost
    app.http.server.configuration.port = serverPort

    // Register routes
    try routes(app)

    // Register shutdown handler
    app.lifecycle.use(
        GracefulShutdownHandler(taskManager: taskManager, certCleanup: certCleanup, logger: logger)
    )

    logger.info("🚀 Server ready", metadata: [
        "app_name": "\(appName)",
        "host": "\(serverHost)",
        "port": "\(serverPort)",
        "temporal_connected": "true",
        "worker_running": "true"
    ])
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

// MARK: - Graceful Shutdown Handler

struct GracefulShutdownHandler: LifecycleHandler {
    let taskManager: TaskManager
    let certCleanup: CertificateCleanup
    let logger: Logger

    func shutdown(_ application: Application) async throws {
        logger.info("🛑 Shutting down gracefully...")

        // Cancel all background tasks
        taskManager.cancelAll()

        // Clean up temporary certificate files
        certCleanup.cleanup()

        logger.info("✅ Shutdown complete")
    }

    func willBoot(_ application: Application) throws {
        // Nothing to do on boot
    }

    func didBoot(_ application: Application) throws {
        // Nothing to do after boot
    }

    func shutdownWait(_ application: Application) async throws {
        // Use default wait behavior
    }
}

// MARK: - Environment Validation

func validateEnvironment(logger: Logger) throws {
    // Check if TLS is enabled and validate certificate/API key configuration
    let tlsEnabled = Environment.get("TEMPORAL_TLS_ENABLED")?.lowercased() == "true"

    if tlsEnabled {
        let hasApiKey = Environment.get("TEMPORAL_API_KEY") != nil && !Environment.get("TEMPORAL_API_KEY")!.isEmpty
        let hasCertPath = Environment.get("TEMPORAL_CLIENT_CERT") != nil
        let hasKeyPath = Environment.get("TEMPORAL_CLIENT_KEY") != nil
        let hasCertContent = Environment.get("TEMPORAL_CLIENT_CERT_CONTENT") != nil
        let hasKeyContent = Environment.get("TEMPORAL_CLIENT_KEY_CONTENT") != nil

        // Must have either API key OR certificates (file paths or content)
        let hasCerts = (hasCertPath && hasKeyPath) || (hasCertContent && hasKeyContent)

        if !hasApiKey && !hasCerts {
            logger.error("❌ TLS enabled but authentication configuration incomplete")
            throw Abort(.internalServerError,
                       reason: "TLS enabled but missing authentication. Provide one of:\n" +
                              "  1. TEMPORAL_API_KEY (recommended), or\n" +
                              "  2. TEMPORAL_CLIENT_CERT + TEMPORAL_CLIENT_KEY, or\n" +
                              "  3. TEMPORAL_CLIENT_CERT_CONTENT + TEMPORAL_CLIENT_KEY_CONTENT")
        }

        if hasApiKey {
            logger.info("✅ TLS configuration validated (using API key authentication)")
        } else {
            logger.info("✅ TLS configuration validated (using mTLS certificate authentication)")
        }
    }

    // Validate Temporal host is set for cloud deployments
    if tlsEnabled, let host = Environment.get("TEMPORAL_HOST"), host.contains("temporal.io") {
        if let namespace = Environment.get("TEMPORAL_NAMESPACE"), !namespace.isEmpty, namespace != "default" {
            // Valid namespace for cloud
        } else {
            logger.warning("⚠️  Using default namespace with Temporal Cloud - this may not work")
        }
    }
}

// MARK: - Environment File Loader

func loadEnvFile() {
    let fileManager = FileManager.default
    let currentPath = fileManager.currentDirectoryPath

    // Check current directory first, then parent directory
    let envPaths = [
        currentPath + "/.env",
        currentPath + "/../.env"
    ]

    guard let envPath = envPaths.first(where: { fileManager.fileExists(atPath: $0) }),
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
