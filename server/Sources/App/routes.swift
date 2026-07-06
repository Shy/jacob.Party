import Vapor
import Temporal
import Logging

func routes(_ app: Application) throws {
    // MARK: - Health / Readiness

    app.get("health") { req async throws -> HTTPStatus in
        guard req.application.storage[ClientKey.self] != nil,
              req.application.storage[WorkerKey.self] != nil else {
            throw Abort(.serviceUnavailable, reason: "Temporal not initialized")
        }
        return .ok
    }

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

    let protected = app.grouped(DeviceAuthMiddleware())
    let rateLimited = app.grouped(RateLimitMiddleware(maxRequests: 30, windowSeconds: 60))

    // MARK: - Static assets

    app.get("sw.js") { req async throws -> Response in
        let content = try String(contentsOfFile: "Public/sw.js", encoding: .utf8)
        return Response(
            status: .ok,
            headers: [
                "Content-Type": "application/javascript; charset=utf-8",
                "Service-Worker-Allowed": "/",
            ],
            body: .init(string: content)
        )
    }

    app.get { req async throws -> Response in
        var html = try String(contentsOfFile: "Resources/Views/index.html", encoding: .utf8)
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

    // MARK: - Party API

    /// Read state via a workflow query — no events written, no activity executed.
    /// Falls back to `isPartying:false` when no party workflow is currently running.
    rateLimited.get("api", "state") { req async throws -> PartyStateResponse in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        let appName = req.application.storage[AppNameKey.self] ?? "jacob"
        let workflowID = "\(appName)-party"
        let handle = client.workflowHandle(type: PartyWorkflow.self, id: workflowID)

        let state: PartyStateOutput
        do {
            state = try await handle.query(queryType: PartyWorkflow.GetPartyState.self)
        } catch {
            // Workflow not running (or query rejected) — return a sensible default.
            req.logger.debug("Party query returned no state: \(error)")
            return PartyStateResponse(
                spinning: false,
                location: nil,
                appName: appName,
                startTime: nil
            )
        }

        let startTimeString = state.startTime.map { ISO8601DateFormatter().string(from: $0) }

        return PartyStateResponse(
            spinning: state.isPartying,
            location: state.location,
            appName: appName,
            startTime: startTimeString
        )
    }

    /// Start (or resume into) a party. Uses `signalWithStartWorkflow` so a
    /// repeated POST while a party is running just refreshes the location
    /// instead of erroring.
    protected.post("api", "party", "start") { req async throws -> HTTPStatus in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        let body = try req.content.decode(StartPartyRequest.self)
        let appName = req.application.storage[AppNameKey.self] ?? "jacob"
        let workflowID = "\(appName)-party"
        let source = sourceFor(req: req)
        let deviceId = req.headers["X-Device-ID"].first

        Task {
            do {
                _ = try await client.signalWithStartWorkflow(
                    type: PartyWorkflow.self,
                    input: StartPartyInput(
                        location: body.location,
                        source: source,
                        reason: body.reason,
                        deviceId: deviceId,
                        autoStopHours: body.autoStopHours
                    ),
                    options: .init(
                        id: workflowID,
                        taskQueue: "party-queue",
                        // A tap on "start party" means the user wants a new session.
                        // If a stale execution is stuck under this ID (e.g. after a
                        // workflow rewrite that broke replay), terminate it and start fresh
                        // instead of silently signalling into a dead history.
                        idConflictPolicy: .terminateExisting
                    ),
                    signalType: PartyWorkflow.UpdateLocation.self,
                    signalInput: body.location
                )
                req.logger.info("✅ signalWithStart PartyWorkflow", metadata: [
                    "workflow_id": .string(workflowID)
                ])
            } catch {
                req.logger.error("❌ Failed to start party: \(error)")
            }
        }

        req.logger.info("🎉 Party start requested at \(body.location)")
        return .ok
    }

    /// Stop the current party by signalling the running workflow.
    protected.post("api", "party", "stop") { req async throws -> HTTPStatus in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        let appName = req.application.storage[AppNameKey.self] ?? "jacob"
        let workflowID = "\(appName)-party"
        let handle = client.workflowHandle(type: PartyWorkflow.self, id: workflowID)

        do {
            try await handle.signal(signalType: PartyWorkflow.StopParty.self)
            req.logger.info("🛑 stopParty signal sent", metadata: [
                "workflow_id": .string(workflowID)
            ])
        } catch {
            // Either no party running or already stopped — both are fine.
            req.logger.info("ℹ️  Stop signal not delivered: \(error)")
        }

        return .ok
    }

    /// Update location by signalling the running workflow. No new workflow
    /// execution is created.
    protected.post("api", "party", "location") { req async throws -> HTTPStatus in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        let body = try req.content.decode(UpdateLocationRequest.self)
        let appName = req.application.storage[AppNameKey.self] ?? "jacob"
        let workflowID = "\(appName)-party"
        let handle = client.workflowHandle(type: PartyWorkflow.self, id: workflowID)

        do {
            try await handle.signal(
                signalType: PartyWorkflow.UpdateLocation.self,
                input: body.location
            )
            req.logger.info("📍 updateLocation signal sent", metadata: [
                "location": .string("\(body.location.lat),\(body.location.lng)")
            ])
        } catch {
            req.logger.info("ℹ️  Location signal not delivered (no active party): \(error)")
        }

        return .ok
    }

    /// Update the party's reason via a workflow update — synchronous, validated.
    protected.post("api", "party", "reason") { req async throws -> ReasonUpdateResponse in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        let body = try req.content.decode(SetReasonRequest.self)
        let appName = req.application.storage[AppNameKey.self] ?? "jacob"
        let workflowID = "\(appName)-party"
        let handle = client.workflowHandle(type: PartyWorkflow.self, id: workflowID)

        do {
            let message = try await handle.executeUpdate(
                updateType: PartyWorkflow.SetReason.self,
                input: SetReasonInput(reason: body.reason)
            )
            return ReasonUpdateResponse(message: message)
        } catch {
            throw Abort(.badRequest, reason: "\(error)")
        }
    }

    /// Extend the auto-stop time via a workflow update.
    protected.post("api", "party", "extend") { req async throws -> ExtendResponse in
        guard let client = req.application.storage[ClientKey.self] else {
            throw Abort(.internalServerError, reason: "Temporal client not configured")
        }

        let body = try req.content.decode(ExtendRequest.self)
        let appName = req.application.storage[AppNameKey.self] ?? "jacob"
        let workflowID = "\(appName)-party"
        let handle = client.workflowHandle(type: PartyWorkflow.self, id: workflowID)

        do {
            let newAutoStop = try await handle.executeUpdate(
                updateType: PartyWorkflow.ExtendAutoStop.self,
                input: ExtendAutoStopInput(additionalHours: body.additionalHours)
            )
            return ExtendResponse(autoStopAt: ISO8601DateFormatter().string(from: newAutoStop))
        } catch {
            throw Abort(.badRequest, reason: "\(error)")
        }
    }

    // MARK: - Push notification subscriptions

    app.post("api", "subscribe") { req async throws -> HTTPStatus in
        guard let manager = req.application.storage[SubscriptionManagerKey.self] else {
            throw Abort(.internalServerError, reason: "Subscription manager not configured")
        }

        let subscription = try req.content.decode(PushSubscription.self)
        try await manager.add(subscription)

        let count = try await manager.count()
        req.logger.info("➕ Added push subscription", metadata: [
            "id": .string(subscription.id),
            "total": .stringConvertible(count),
        ])

        return .created
    }

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
            "total": .stringConvertible(count),
        ])

        return .ok
    }

    // SSE endpoint — kept as a stub from the previous version.
    app.get("api", "events") { req async throws -> Response in
        let response = Response()
        response.headers.contentType = .init(type: "text", subType: "event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: .connection, value: "keep-alive")
        response.body = .init(string: "event: connected\ndata: {\"status\":\"connected\"}\n\n")
        return response
    }
}

// MARK: - Helpers

private func sourceFor(req: Request) -> String {
    if req.headers["X-Device-ID"].first != nil { return "ios-app" }
    let userAgent = req.headers["User-Agent"].first ?? ""
    if userAgent.contains("Mozilla") || userAgent.contains("Chrome") { return "web" }
    return "api"
}

// MARK: - Request / Response Models

struct StartPartyRequest: Content {
    let location: Location
    let reason: String
    let autoStopHours: Int?
}

struct UpdateLocationRequest: Content {
    let location: Location
    let reason: String?
}

struct SetReasonRequest: Content {
    let reason: String
}

struct ReasonUpdateResponse: Content {
    let message: String
}

struct ExtendRequest: Content {
    let additionalHours: Int
}

struct ExtendResponse: Content {
    let autoStopAt: String
}

struct HealthResponse: Content {
    let status: String
    let temporalClient: String
    let temporalWorker: String
    let timestamp: String
}
