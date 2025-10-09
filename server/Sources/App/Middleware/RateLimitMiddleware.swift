import Vapor

/// Actor to manage rate limit state in a thread-safe way
actor RateLimitStore {
    struct RequestTracker {
        var count: Int
        var windowStart: Date
    }

    private var requestCounts: [String: RequestTracker] = [:]
    private let maxRequests: Int
    private let windowSeconds: TimeInterval

    init(maxRequests: Int, windowSeconds: TimeInterval) {
        self.maxRequests = maxRequests
        self.windowSeconds = windowSeconds
    }

    func checkAndIncrement(clientIP: String) throws {
        let now = Date()

        // Get or create tracker for this IP
        var tracker = requestCounts[clientIP] ?? RequestTracker(count: 0, windowStart: now)

        // Reset window if expired
        if now.timeIntervalSince(tracker.windowStart) >= windowSeconds {
            tracker = RequestTracker(count: 0, windowStart: now)
        }

        // Check rate limit
        if tracker.count >= maxRequests {
            let resetIn = Int(windowSeconds - now.timeIntervalSince(tracker.windowStart))
            throw Abort(.tooManyRequests, reason: "Rate limit exceeded. Try again in \(resetIn) seconds.")
        }

        // Increment counter
        tracker.count += 1
        requestCounts[clientIP] = tracker

        // Clean up old entries periodically
        if requestCounts.count > 1000 {
            requestCounts = requestCounts.filter { entry in
                now.timeIntervalSince(entry.value.windowStart) < windowSeconds * 2
            }
        }
    }
}

/// Simple in-memory rate limiter for API endpoints
final class RateLimitMiddleware: AsyncMiddleware {
    private let store: RateLimitStore

    init(maxRequests: Int = 30, windowSeconds: TimeInterval = 60) {
        self.store = RateLimitStore(maxRequests: maxRequests, windowSeconds: windowSeconds)
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let clientIP = request.peerAddress?.ipAddress ?? "unknown"

        do {
            try await store.checkAndIncrement(clientIP: clientIP)
        } catch {
            request.logger.warning("⚠️ Rate limit exceeded for \(clientIP)")
            throw error
        }

        return try await next.respond(to: request)
    }
}
