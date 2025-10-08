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
    private let baseURL = "http://127.0.0.1:8080"
    private var locationCancellable: AnyCancellable?
    private let deviceID = DeviceIdentifier.shared.uuid

    init() {
        feedbackGenerator.prepare()

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
        // Track last sent location to avoid sending redundant updates
        var lastSentLocation: CLLocationCoordinate2D?

        // Observe location changes and send updates when location changes significantly
        locationCancellable = locationManager.$currentLocation
            .compactMap { $0 }
            .removeDuplicates { loc1, loc2 in
                // Consider locations duplicate if within ~50 meters
                let distance = self.distance(from: loc1, to: loc2)
                return distance < 50
            }
            .debounce(for: .seconds(5), scheduler: DispatchQueue.main)
            .sink { [weak self] newLocation in
                guard let self = self, self.isPartyMode else { return }

                // Check if this location is significantly different from last sent
                if let last = lastSentLocation {
                    let dist = self.distance(from: last, to: newLocation)
                    guard dist >= 50 else { return }
                }

                lastSentLocation = newLocation

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

    private func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let from = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let to = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return from.distance(from: to)
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
                startParty()
            }
        }
    }

    func setPressed(_ pressed: Bool) {
        isPressed = pressed
    }

    private func startParty() {
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
                try await sendStartParty(latitude: location.latitude, longitude: location.longitude)
                print("✅ Party started via HTTP API")
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
            try await sendStopParty()
            print("✅ Party stopped via HTTP API")
        } catch {
            print("❌ Failed to stop party: \(error)")
            // Rollback UI state on error
            isPartyMode = true
        }
    }

    // MARK: - Network Methods

    func fetchInitialState() async {
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
            ]
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
            ]
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
