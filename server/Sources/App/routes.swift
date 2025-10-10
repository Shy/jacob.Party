import Vapor
import Temporal
import Logging

func routes(_ app: Application) throws {
    // Health check endpoint (for monitoring/load balancers)
    app.get("health") { req async throws -> HTTPStatus in
        // Check if Temporal client and worker are initialized
        guard req.application.storage[ClientKey.self] != nil,
              req.application.storage[WorkerKey.self] != nil else {
            throw Abort(.serviceUnavailable, reason: "Temporal not initialized")
        }
        return .ok
    }

    // Readiness check endpoint (more detailed)
    app.get("ready") { req async -> HealthResponse in
        let hasClient = req.application.storage[ClientKey.self] != nil
        let hasWorker = req.application.storage[WorkerKey.self] != nil
        let isReady = hasClient && hasWorker

        return HealthResponse(
            status: isReady ? "ready" : "not ready",
            temporalClient: hasClient ? "connected" : "disconnected",
            temporalWorker: hasWorker ? "running" : "stopped",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    // Create protected routes group with device authentication
    let protected = app.grouped(DeviceAuthMiddleware())

    // Create rate-limited group for state endpoint (30 requests per minute)
    let rateLimited = app.grouped(RateLimitMiddleware(maxRequests: 30, windowSeconds: 60))

    // Serve index.html with dynamic configuration injected (public)
    app.get { req async throws -> Response in
        let htmlPath = "Resources/Views/index.html"
        var html = try String(contentsOfFile: htmlPath, encoding: .utf8)

        // Inject app name and Google Maps API key
        let appName = req.application.storage[AppNameKey.self] ?? "jacob"
        let apiKey = req.application.storage[GoogleMapsApiKeyKey.self] ?? ""

        html = html.replacingOccurrences(of: "{{APP_NAME}}", with: appName)
        html = html.replacingOccurrences(of: "YOUR_GOOGLE_MAPS_API_KEY", with: apiKey)

        return Response(
            status: .ok,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: .init(string: html)
        )
    }

    // API endpoint to query workflow state (public - read-only with rate limiting)
    rateLimited.get("api", "state") { req async throws -> PartyStateResponse in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        let appName = req.application.storage[AppNameKey.self] ?? "jacob"

        // Execute a workflow to query database state
        let state = try await client.executeWorkflow(
            type: GetPartyStateWorkflow.self,
            options: .init(
                id: "query-\(UUID().uuidString)",
                taskQueue: "party-queue"
            )
        )

        // Format startTime as ISO8601 string
        let startTimeString: String?
        if let startTime = state.startTime {
            let formatter = ISO8601DateFormatter()
            startTimeString = formatter.string(from: startTime)
        } else {
            startTimeString = nil
        }

        return PartyStateResponse(
            spinning: state.isPartying,
            location: state.location,
            appName: appName,
            startTime: startTimeString
        )
    }

    // API endpoint to start party (HTTP bridge to Temporal) (protected)
    protected.post("api", "party", "start") { req async throws -> HTTPStatus in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        // Parse request body
        let body = try req.content.decode(StartPartyRequest.self)

        let appName = req.application.storage[AppNameKey.self] ?? "jacob"
        let workflowID = "\(appName)-party"

        // Start new workflow (non-blocking)
        // Use consistent workflow ID to allow workflow to continue/signal existing workflows
        Task {
            do {
                _ = try await client.startWorkflow(
                    type: PartyWorkflow.self,
                    options: .init(
                        id: workflowID,
                        taskQueue: "party-queue"
                    ),
                    input: StartPartyInput(location: body.location)
                )
                req.logger.info("✅ Started PartyWorkflow", metadata: [
                    "workflow_id": "\(workflowID)"
                ])
            } catch {
                // If workflow already exists, that's okay - it means party is already running
                req.logger.info("ℹ️  Workflow start result", metadata: [
                    "workflow_id": "\(workflowID)",
                    "error": "\(error)"
                ])
            }
        }

        req.logger.info("🎉 Party start requested at \(body.location)")
        return .ok
    }

    // API endpoint to stop party (HTTP bridge to Temporal) (protected)
    protected.post("api", "party", "stop") { req async throws -> HTTPStatus in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        // Start a workflow to record party end (non-blocking)
        Task {
            do {
                _ = try await client.startWorkflow(
                    type: StopPartyWorkflow.self,
                    options: .init(
                        id: "stop-party-\(UUID().uuidString)",
                        taskQueue: "party-queue"
                    )
                )
                req.logger.info("✅ Started StopPartyWorkflow")
            } catch {
                req.logger.error("❌ Failed to stop party: \(error)")
            }
        }

        req.logger.info("🛑 Party stop requested")
        return .ok
    }

    // API endpoint to update location (HTTP bridge to Temporal) (protected)
    protected.post("api", "party", "location") { req async throws -> HTTPStatus in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        // Parse request body
        let body = try req.content.decode(UpdateLocationRequest.self)

        // Start a workflow to update location in database (non-blocking)
        Task {
            do {
                _ = try await client.startWorkflow(
                    type: UpdateLocationWorkflow.self,
                    options: .init(
                        id: "update-location-\(UUID().uuidString)",
                        taskQueue: "party-queue"
                    ),
                    input: UpdateLocationInput(location: body.location)
                )
                req.logger.info("✅ Started UpdateLocationWorkflow")
            } catch {
                req.logger.error("❌ Failed to update location: \(error)")
            }
        }

        req.logger.info("📍 Location update requested: \(body.location)")
        return .ok
    }
}

// MARK: - Request/Response Models

struct HealthResponse: Content {
    let status: String
    let temporalClient: String
    let temporalWorker: String
    let timestamp: String
}

struct StartPartyRequest: Content {
    let location: Location
}

struct UpdateLocationRequest: Content {
    let location: Location
}
