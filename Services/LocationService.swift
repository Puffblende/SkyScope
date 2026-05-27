import Foundation
import CoreLocation
import Observation

/// Wraps CLLocationManager and exposes the current location as an observable property.
/// Configured for background updates so refresh keeps working when the screen locks
/// (requires the "location" background mode in Info.plist).
@MainActor
@Observable
final class LocationService: NSObject {
    /// Most recent location reported by the system. Nil until the first fix.
    private(set) var currentLocation: CLLocation?

    /// Current authorization status, surfaced to the UI for permission gating.
    private(set) var authorizationStatus: CLAuthorizationStatus

    /// Last error reported by Core Location, surfaced to the UI for display.
    private(set) var lastError: String?

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 250 // only re-fire when user moves ~250 m
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Requests "When In Use" permission. Background updates require an additional
    /// "Always" request which can be triggered separately from Settings UI later.
    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Starts continuous location updates. Safe to call multiple times.
    func startUpdating() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestAuthorization()
            return
        }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    /// Opt in to background updates. The caller must ensure the entitlement
    /// "location" background mode is configured in Info.plist.
    func enableBackgroundUpdates(_ enabled: Bool) {
        manager.allowsBackgroundLocationUpdates = enabled
        manager.showsBackgroundLocationIndicator = enabled
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = latest
            self.lastError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
        }
    }
}
