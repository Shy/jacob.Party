import SwiftUI
import Combine
import CoreLocation

@MainActor
class PartyViewModel: ObservableObject {
    @Published var isPartyMode: Bool = false
    @Published var isPressed: Bool = false
    @Published var appName: String = "jacob"

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let locationManager = LocationManager()
    private let notificationManager = NotificationManager.shared
    private let temporalService = TemporalPartyService()
    private let baseURL: String = {
        guard let serverURL = Bundle.main.object(forInfoDictionaryKey: "SERVER_URL") as? String,
              !serverURL.isEmpty,
              !serverURL.contains("$(") else {
            // Fallback to localhost for development
            return "http://127.0.0.1:8080"
        }
        return serverURL
    }()
    private var locationCancellable: AnyCancellable?
    private let deviceID = DeviceIdentifier.shared.uuid

    init() {
        feedbackGenerator.prepare()

        // Print device ID for easy identification
        print("🔑 Device ID: \(deviceID)")

        // Setup notification observers
        setupNotificationObservers()

        // Setup location observer
        setupLocationObserver()

        // Request location permission and fetch initial state
        Task {  
            await initialize()
        }
    }

    private func initialize() async {
        // Request location and notification permissions
        locationManager.requestPermission()
        await notificationManager.requestAuthorization()
        notificationManager.setupNotificationActions()

        // Fetch initial state from server
        await fetchInitialState()
    }

    private func setupLocationObserver() {
        // Track last sent time to ensure minimum 1 minute between updates
        var lastSentTime: Date?

        // Location manager already filters by 50m distance via distanceFilter
        // Just add time-based throttling here
        locationCancellable = locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] newLocation in
                guard let self = self, self.isPartyMode else { return }

                let now = Date()

                // Enforce 60-second minimum between updates to reduce battery drain
                if let lastTime = lastSentTime {
                    let timeSinceLastUpdate = now.timeIntervalSince(lastTime)
                    guard timeSinceLastUpdate >= 60 else {
                        print("⏭️ Skipping update - only \(Int(timeSinceLastUpdate))s since last update")
                        return
                    }
                }

                lastSentTime = now

                Task {
                    do {
                        try await self.updateLocation()
                        print("📍 Location updated: \(newLocation.latitude), \(newLocation.longitude)")
                    } catch {
                        print("❌ Failed to update location: \(error)")
                    }
                }
            }
    }

    nonisolated private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("KeepPartyingTapped"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.keepPartying()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StopPartyFromNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.stopParty()
            }
        }
    }

    private func keepPartying() async {
        print("🎉 User chose to keep partying - rescheduling for 6 more hours")
        notificationManager.schedulePartyTimeoutNotification()
    }

    // MARK: - Button Handlers

    func togglePartyMode() {
        Task {
            if isPartyMode {
                await stopParty()
            } else {
                await startParty()
            }
        }
    }

    func setPressed(_ pressed: Bool) {
        isPressed = pressed
    }

    private func startParty() async {
        isPartyMode = true
        feedbackGenerator.impactOccurred()

        // Start location updates
        locationManager.startUpdatingLocation()

        // Schedule 6-hour timeout notification
        notificationManager.schedulePartyTimeoutNotification()

        // Send start party request to server
        Task {
            do {
                let location = locationManager.locationOrDefault
                if await temporalService.isEnabled {
                    try await temporalService.startParty(
                        location: Location(lat: location.latitude, lng: location.longitude),
                        deviceId: deviceID
                    )
                    print("✅ Party started via Temporal Swift SDK on iOS")
                } else {
                    try await sendStartParty(latitude: location.latitude, longitude: location.longitude)
                    print("✅ Party started via HTTP API")
                }
            } catch {
                print("❌ Failed to start party: \(error)")
                // Rollback UI state on error
                isPartyMode = false
                notificationManager.cancelPartyTimeoutNotification()
            }
        }
    }

    private func stopParty() async {
        isPartyMode = false
        feedbackGenerator.impactOccurred()

        // Stop location updates
        locationManager.stopUpdatingLocation()

        // Cancel timeout notification
        notificationManager.cancelPartyTimeoutNotification()

        // Send stop party request to server
        do {
            if await temporalService.isEnabled {
                try await temporalService.stopParty()
                print("✅ Party stopped via Temporal Swift SDK on iOS")
            } else {
                try await sendStopParty()
                print("✅ Party stopped via HTTP API")
            }
        } catch {
            print("❌ Failed to stop party: \(error)")
            // Rollback UI state on error
            isPartyMode = true
        }
    }

    // MARK: - Network Methods

    func fetchInitialState() async {
        if await temporalService.isEnabled {
            do {
                let state = try await temporalService.fetchState()
                isPartyMode = state.isPartying
                appName = Bundle.main.object(forInfoDictionaryKey: "APP_NAME") as? String ?? "jacob"

                if state.isPartying {
                    locationManager.startUpdatingLocation()
                    notificationManager.schedulePartyTimeoutNotification()
                }

                print("✅ Fetched initial state from Temporal: \(appName) is \(state.isPartying ? "partying" : "not partying")")
                return
            } catch {
                print("ℹ️ Temporal state unavailable, falling back to HTTP state: \(error)")
            }
        }

        guard let url = URL(string: "\(baseURL)/api/state") else { return }

        var request = URLRequest(url: url)
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(StateResponse.self, from: data)

            isPartyMode = response.spinning
            appName = response.appName

            if response.spinning {
                locationManager.startUpdatingLocation()
                // If already partying, schedule notification
                notificationManager.schedulePartyTimeoutNotification()
            }

            print("✅ Fetched initial state: \(appName) is \(response.spinning ? "partying" : "not partying")")
        } catch {
            print("❌ Failed to fetch state: \(error)")
            isPartyMode = false
        }
    }

    private func sendStartParty(latitude: Double, longitude: Double) async throws {
        guard let url = URL(string: "\(baseURL)/api/party/start") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")

        let body: [String: Any] = [
            "location": [
                "lat": latitude,
                "lng": longitude
            ],
            "reason": "user-pressed-button"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.requestFailed
        }
    }

    private func sendStopParty() async throws {
        guard let url = URL(string: "\(baseURL)/api/party/stop") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.requestFailed
        }
    }

    // Optional: Update location periodically while partying
    func updateLocation() async throws {
        guard isPartyMode else { return }

        let location = locationManager.locationOrDefault

        if await temporalService.isEnabled {
            try await temporalService.updateLocation(Location(lat: location.latitude, lng: location.longitude))
            return
        }

        guard let url = URL(string: "\(baseURL)/api/party/location") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")

        let body: [String: Any] = [
            "location": [
                "lat": location.latitude,
                "lng": location.longitude
            ],
            "reason": "background-update"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.requestFailed
        }
    }
}

// MARK: - Models

struct StateResponse: Codable {
    let spinning: Bool
    let location: LocationData?
    let appName: String
}

struct LocationData: Codable {
    let lat: Double
    let lng: Double
}

enum NetworkError: Error {
    case invalidURL
    case requestFailed
}
