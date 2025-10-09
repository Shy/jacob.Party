import Vapor

/// Middleware that validates device IDs against a whitelist.
struct DeviceAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Get allowed device IDs from environment
        let allowedDevices = request.application.storage[AllowedDeviceIDsKey.self] ?? []

        // If no whitelist configured, allow all devices (development mode)
        if allowedDevices.isEmpty {
            if let deviceID = request.headers.first(name: "X-Device-ID") {
                request.logger.info("📱 Device ID: \(deviceID) (whitelist disabled)")
            }
            return try await next.respond(to: request)
        }

        // Check for device ID header
        guard let deviceID = request.headers.first(name: "X-Device-ID") else {
            request.logger.warning("❌ Missing X-Device-ID header")
            throw Abort(.unauthorized, reason: "Device authentication required")
        }

        // Validate device ID against whitelist
        guard allowedDevices.contains(deviceID) else {
            request.logger.warning("❌ Unauthorized device ID: \(deviceID)")
            throw Abort(.forbidden, reason: "Device not authorized")
        }

        request.logger.debug("✅ Authenticated device: \(deviceID)")
        return try await next.respond(to: request)
    }
}

struct AllowedDeviceIDsKey: StorageKey {
    typealias Value = [String]
}
