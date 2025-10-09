import Foundation
import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        locationManager.delegate = self
        // Use NearestTenMeters for good accuracy with reasonable battery life
        // Perfect for NYC - distinguishes between nearby venues without Best's battery drain
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.allowsBackgroundLocationUpdates = true
        // Let system pause updates automatically to save battery
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.showsBackgroundLocationIndicator = true
        // Only get updates when moved at least 50 meters
        locationManager.distanceFilter = 50
        // Optimize for minimal battery usage
        locationManager.activityType = .otherNavigation
    }

    func requestPermission() {
        authorizationStatus = locationManager.authorizationStatus
        if authorizationStatus == .notDetermined {
            // First request "When In Use"
            locationManager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse {
            // Then request "Always" for background updates
            locationManager.requestAlwaysAuthorization()
        }
    }

    func startUpdatingLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }

        // Use regular updates with distance filter (50m)
        locationManager.startUpdatingLocation()

        // Request "Always" permission if only have "When In Use"
        if authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    // Default location for testing (San Francisco)
    var locationOrDefault: CLLocationCoordinate2D {
        currentLocation ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location.coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
}
