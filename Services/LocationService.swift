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

    /// Most recent device heading reported by the system. Nil until the first reading.
    private(set) var heading: CLHeading?

    /// Current authorization status, surfaced to the UI for permission gating.
    private(set) var authorizationStatus: CLAuthorizationStatus

    /// Last error reported by Core Location, surfaced to the UI for display.
    private(set) var lastError: String?

    /// Callback fired on location updates (throttled to avoid excessive calls).
    var onLocationUpdate: ((CLLocation) -> Void)?

    private let manager: CLLocationManager
    private var lastLiveActivityUpdate: Date = .distantPast

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 250 // only re-fire when user moves ~250 m
        manager.pausesLocationUpdatesAutomatically = true
        manager.headingFilter = 2 // only report heading changes >= 2 degrees
    }

    /// Requests "When In Use" permission. Background updates require an additional
    /// "Always" request which can be triggered separately from Settings UI later.
    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Starts continuous location updates. Safe to call multiple times.
    /// Does nothing if permission hasn't been granted yet — the CLLocationManagerDelegate
    /// calls startUpdatingLocation() automatically once authorization changes.
    func startUpdating() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        if let cachedLocation = manager.location {
            self.currentLocation = cachedLocation
            #if DEBUG
            print("[LOC] Using cached location immediately")
            #endif
        }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    func startUpdatingHeading() {
        manager.startUpdatingHeading()
    }

    func stopUpdatingHeading() {
        manager.stopUpdatingHeading()
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
        guard let latest = locations.last,
              latest.horizontalAccuracy >= 0,
              latest.horizontalAccuracy < 1_000 else { return }
        Task { @MainActor in
            self.currentLocation = latest
            self.lastError = nil

            // Throttle Live Activity updates to once per 60 seconds
            if Date().timeIntervalSince(self.lastLiveActivityUpdate) > 60 {
                self.lastLiveActivityUpdate = Date()
                self.onLocationUpdate?(latest)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let clError = error as? CLError else {
                self.lastError = "Location unavailable."
                return
            }
            switch clError.code {
            case .locationUnknown:
                // Transient — location will arrive shortly, no message needed
                break
            case .denied:
                self.lastError = "Location access denied — enable it in Settings → Privacy → Location Services."
            case .network:
                self.lastError = "Location unavailable — check your network connection."
            default:
                self.lastError = "Location error — please try again."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.heading = newHeading
        }
    }
}
