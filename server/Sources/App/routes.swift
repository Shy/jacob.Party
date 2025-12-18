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

    // Serve service worker for push notifications
    app.get("sw.js") { req async throws -> Response in
        let swPath = "Public/sw.js"
        let content = try String(contentsOfFile: swPath, encoding: .utf8)

        return Response(
            status: .ok,
            headers: [
                "Content-Type": "application/javascript; charset=utf-8",
                "Service-Worker-Allowed": "/"
            ],
            body: .init(string: content)
        )
    }

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
    // EDUCATIONAL: Demonstrates executing workflows for read operations
    rateLimited.get("api", "state") { req async throws -> PartyStateResponse in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        let appName = req.application.storage[AppNameKey.self] ?? "jacob"

        // Determine source based on request headers
        let deviceId = req.headers["X-Device-ID"].first
        let userAgent = req.headers["User-Agent"].first ?? ""
        let source: String
        if deviceId != nil {
            source = "ios-app"
        } else if userAgent.contains("Mozilla") || userAgent.contains("Chrome") {
            source = "web"
        } else {
            source = "api"
        }

        // Execute workflow to query database state
        let input = GetPartyStateInput(source: source, reason: "user-view", deviceId: deviceId)
        let state = try await client.executeWorkflow(
            type: GetPartyStateWorkflow.self,
            options: .init(
                id: "query-\(UUID().uuidString)",
                taskQueue: "party-queue"
            ),
            input: input
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
    // EDUCATIONAL: Demonstrates starting workflows
    protected.post("api", "party", "start") { req async throws -> HTTPStatus in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        // Parse request body
        let body = try req.content.decode(StartPartyRequest.self)

        let appName = req.application.storage[AppNameKey.self] ?? "jacob"
        let workflowID = "\(appName)-party"

        // Determine source based on request headers
        let deviceId = req.headers["X-Device-ID"].first
        let userAgent = req.headers["User-Agent"].first ?? ""
        let source: String
        if deviceId != nil {
            source = "ios-app"
        } else if userAgent.contains("Mozilla") || userAgent.contains("Chrome") {
            source = "web"
        } else {
            source = "api"
        }

        // Start new workflow (non-blocking)
        // Use consistent workflow ID to ensure only one party runs at a time
        Task {
            do {
                _ = try await client.startWorkflow(
                    type: PartyWorkflow.self,
                    options: .init(
                        id: workflowID,
                        taskQueue: "party-queue"
                    ),
                    input: StartPartyInput(
                        location: body.location,
                        source: source,
                        reason: body.reason,
                        deviceId: deviceId,
                        autoStopHours: nil
                    )
                )
                req.logger.info("✅ Started PartyWorkflow", metadata: [
                    "workflow_id": "\(workflowID)"
                ])
            } catch {
                // If workflow already exists, that's okay - it means party is already running
                req.logger.info("ℹ️  Party already running", metadata: [
                    "workflow_id": "\(workflowID)",
                    "error": "\(error)"
                ])
            }
        }

        req.logger.info("🎉 Party start requested at \(body.location)")
        return .ok
    }

    // API endpoint to stop party (HTTP bridge to Temporal) (protected)
    // EDUCATIONAL: Demonstrates workflow execution pattern
    protected.post("api", "party", "stop") { req async throws -> HTTPStatus in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        // Determine source based on request headers
        let deviceId = req.headers["X-Device-ID"].first
        let userAgent = req.headers["User-Agent"].first ?? ""
        let source: String
        if deviceId != nil {
            source = "ios-app"
        } else if userAgent.contains("Mozilla") || userAgent.contains("Chrome") {
            source = "web"
        } else {
            source = "api"
        }

        // Start workflow to record party end
        Task {
            do {
                _ = try await client.startWorkflow(
                    type: StopPartyWorkflow.self,
                    options: .init(
                        id: "stop-party-\(UUID().uuidString)",
                        taskQueue: "party-queue"
                    ),
                    input: StopPartyInput(
                        source: source,
                        reason: "user-stopped",
                        deviceId: deviceId
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
    // EDUCATIONAL: Demonstrates workflow execution pattern
    protected.post("api", "party", "location") { req async throws -> HTTPStatus in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        // Parse request body
        let body = try req.content.decode(UpdateLocationRequest.self)

        // Determine source based on request headers
        let deviceId = req.headers["X-Device-ID"].first
        let userAgent = req.headers["User-Agent"].first ?? ""
        let source: String
        if deviceId != nil {
            source = "ios-app"
        } else if userAgent.contains("Mozilla") || userAgent.contains("Chrome") {
            source = "web"
        } else {
            source = "api"
        }

        // Start workflow to update location
        Task {
            do {
                _ = try await client.startWorkflow(
                    type: UpdateLocationWorkflow.self,
                    options: .init(
                        id: "update-location-\(UUID().uuidString)",
                        taskQueue: "party-queue"
                    ),
                    input: UpdateLocationInput(
                        location: body.location,
                        source: source,
                        reason: body.reason,
                        deviceId: deviceId
                    )
                )
                req.logger.info("✅ Started UpdateLocationWorkflow")
            } catch {
                req.logger.error("❌ Failed to update location: \(error)")
            }
        }

        req.logger.info("📍 Location update requested: \(body.location)")
        return .ok
    }

    // MARK: - Push Notification Endpoints

    // Subscribe to push notifications
    // EDUCATIONAL: Public endpoint for users to opt-in to notifications
    app.post("api", "subscribe") { req async throws -> HTTPStatus in
        guard let manager = req.application.storage[SubscriptionManagerKey.self] else {
            throw Abort(.internalServerError, reason: "Subscription manager not configured")
        }

        let subscription = try req.content.decode(PushSubscription.self)
        try await manager.add(subscription)

        let count = try await manager.count()
        req.logger.info("➕ Added push subscription", metadata: [
            "id": .string(subscription.id),
            "total": .stringConvertible(count)
        ])

        return .created
    }

    // Unsubscribe from push notifications
    app.delete("api", "subscribe", ":id") { req async throws -> HTTPStatus in
        guard let manager = req.application.storage[SubscriptionManagerKey.self] else {
            throw Abort(.internalServerError, reason: "Subscription manager not configured")
        }

        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing subscription ID")
        }

        try await manager.remove(id: id)

        let count = try await manager.count()
        req.logger.info("➖ Removed push subscription", metadata: [
            "id": .string(id),
            "total": .stringConvertible(count)
        ])

        return .ok
    }

    // SSE endpoint for real-time updates
    // EDUCATIONAL: Server-Sent Events for live party state updates
    app.get("api", "events") { req async throws -> Response in
        let response = Response()
        response.headers.contentType = .init(type: "text", subType: "event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: .connection, value: "keep-alive")

        // TODO: Implement full SSE streaming with state polling
        // For now, send initial connection event
        // In full implementation, this would:
        // 1. Poll workflow state every few seconds
        // 2. Send SSE events when state changes
        // 3. Keep connection alive with heartbeats

        let connectEvent = "event: connected\ndata: {\"status\":\"connected\"}\n\n"
        response.body = .init(string: connectEvent)
        return response
    }
}

// MARK: - Request/Response Models

struct StartPartyRequest: Content {
    let location: Location
    let reason: String
}

struct UpdateLocationRequest: Content {
    let location: Location
    let reason: String
}

// MARK: - Request/Response Models

struct HealthResponse: Content {
    let status: String
    let temporalClient: String
    let temporalWorker: String
    let timestamp: String
}
