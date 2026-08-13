import Foundation
import ActivityKit
import Observation
import SwiftUI
import CoreLocation

@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    var isRunning = false
    private var liveActivity: Activity<SkyScopeActivityAttributes>?
    private weak var dataStore: AircraftDataStore?
    private weak var location: LocationService?

    private let airportService = AirportCoordinatesService.shared

    private init() {}

    func setDependencies(dataStore: AircraftDataStore, location: LocationService) {
        self.dataStore = dataStore
        self.location = location
    }

    func start() async {
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            print("[LAM] ❌ Live Activities disabled")
            return
        }

        // End all existing Live Activities before creating a new one
        for activity in Activity<SkyScopeActivityAttributes>.activities {
            do {
                await activity.end(
                    using: activity.content.state,
                    dismissalPolicy: .immediate
                )
                print("[LAM] Ended existing activity: \(activity.id)")
            } catch {
                print("[LAM] Error ending existing activity: \(error)")
            }
        }

        guard let dataStore = dataStore else {
            print("[LAM] ❌ DataStore not initialized")
            return
        }

        if dataStore.aircraft.isEmpty {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        guard let firstAircraft = dataStore.aircraft.first else {
            print("[LAM] ❌ No aircraft available")
            return
        }

        let attributes = SkyScopeActivityAttributes(userLocation: "SkyScope")
        let initialState = await formatActivityState(from: firstAircraft)

        do {
            let content = ActivityContent(state: initialState, staleDate: nil)
            let activity = try Activity<SkyScopeActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            self.liveActivity = activity
            self.isRunning = true
            print("[LAM] ✅ Started: \(activity.id)")
        } catch {
            print("[LAM] ❌ Failed: \(error)")
        }
    }

    func stop() async {
        guard let activity = liveActivity else {
            isRunning = false
            return
        }

        do {
            await activity.end(using: activity.content.state, dismissalPolicy: .immediate)
            self.liveActivity = nil
            self.isRunning = false
            print("[LAM] ✅ Stopped")
        } catch {
            print("[LAM] ❌ Error stopping: \(error)")
            self.liveActivity = nil
            self.isRunning = false
        }
    }

    func updateWithNearestAircraft(_ aircraft: [Aircraft]) async {
        guard let activity = liveActivity else { return }
        guard isRunning else { return }

        if aircraft.isEmpty {
            await stop()
            return
        }

        guard let nearest = findNearestAircraft(from: aircraft) else {
            await stop()
            return
        }

        let newState = await formatActivityState(from: nearest)
        do {
            await activity.update(using: newState)
            if let location = location?.currentLocation?.coordinate {
                let distanceKm = nearest.distance(to: location) / 1000
                print("[LAM-UPD] \(nearest.displayName) @ \(String(format: "%.1f", distanceKm))km")
            }
        } catch {
            print("[LAM-UPD] Error: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func calculateProgress(for aircraft: Aircraft) async -> Double {
        guard let originCode = aircraft.originAirport,
              let destCode = aircraft.destinationAirport,
              originCode != destCode else {
            return 0.5
        }

        async let originCoord = AirportCoordinatesService.shared
            .coordinates(for: originCode)
        async let destCoord = AirportCoordinatesService.shared
            .coordinates(for: destCode)

        guard let origin = await originCoord,
              let dest = await destCoord else {
            print("[PROGRESS] Missing coords for \(originCode)→\(destCode)")
            return 0.5
        }

        let aircraftLoc = CLLocation(
            latitude: aircraft.coordinate.latitude,
            longitude: aircraft.coordinate.longitude
        )
        let originLoc = CLLocation(
            latitude: origin.latitude,
            longitude: origin.longitude
        )
        let destLoc = CLLocation(
            latitude: dest.latitude,
            longitude: dest.longitude
        )

        let totalDistance = originLoc.distance(from: destLoc)
        let distanceFromOrigin = originLoc.distance(from: aircraftLoc)
        let progress = min(max(distanceFromOrigin / totalDistance, 0.0), 1.0)
        print("[PROGRESS] \(originCode)→\(destCode): \(Int(progress * 100))%")
        return progress
    }

    private func getFullAircraftTypeName(_ code: String?) -> String {
        guard let code = code?.uppercased() else { return "Unknown" }
        // Map aircraft type codes to full names (from AircraftSilhouetteView mapper)
        let aircraftDatabase: [String: String] = [
            "B738": "Boeing 737-800", "B77W": "Boeing 777",
            "A320": "Airbus A320", "A380": "Airbus A380",
            "B788": "Boeing 787-8 Dreamliner", "A350": "Airbus A350",
            "B744": "Boeing 747", "A333": "Airbus A330",
            "B752": "Boeing 757", "B762": "Boeing 767",
            "E170": "Embraer 170", "E190": "Embraer 190",
            "PA28": "Piper Cherokee", "C172": "Cessna 172 Skyhawk",
            "CRJ2": "Bombardier CRJ200", "AT72": "ATR 72",
            "B739": "Boeing 737-900", "B737": "Boeing 737-700",
            "B736": "Boeing 737-600", "B38M": "Boeing 737 MAX 8",
            "A319": "Airbus A319", "A321": "Airbus A321",
            "B773": "Boeing 777", "B772": "Boeing 777",
            "B78X": "Boeing 787-10 Dreamliner", "B789": "Boeing 787-9",
            "A332": "Airbus A330", "A342": "Airbus A340",
            "MD11": "McDonnell Douglas MD-11", "DC10": "McDonnell Douglas DC-10",
            "DH8D": "Dash 8-300/400", "C208": "Cessna 208 Caravan",
            "E75L": "Embraer 175", "E195": "Embraer 195",
        ]
        return aircraftDatabase[code] ?? code
    }

    private func findNearestAircraft(from aircraft: [Aircraft]) -> Aircraft? {
        guard let userLocation = location?.currentLocation?.coordinate else {
            return aircraft.first
        }
        return aircraft.min {
            $0.distance(to: userLocation) < $1.distance(to: userLocation)
        }
    }

    private func formatActivityState(from aircraft: Aircraft) async -> SkyScopeActivityAttributes.ContentValues {
        let altitude = formatAltitude(aircraft.altitudeMeters)
        let speed = formatSpeed(aircraft.groundSpeedMps)
        let heading = formatHeading(aircraft.headingDegrees)
        let typeCode = aircraft.aircraftType ?? "Unknown"
        let typeFullName = getFullAircraftTypeName(typeCode)

        // Debug squawk
        print("[SQUAWK] aircraft.squawk = \(aircraft.squawk ?? "NIL")")

        // Calculate progress based on airport coordinates
        var progress: Double? = nil
        if aircraft.originAirport != nil && aircraft.destinationAirport != nil {
            progress = await calculateProgress(for: aircraft)
        }

        let newState = SkyScopeActivityAttributes.ContentValues(
            callsign: aircraft.displayName,
            altitude: altitude,
            speed: speed,
            heading: heading,
            aircraftType: typeCode,
            aircraftTypeFullName: typeFullName,
            airline: aircraft.airline,
            registration: aircraft.registration,
            origin: aircraft.originAirport,
            destination: aircraft.destinationAirport,
            progress: progress,
            squawk: aircraft.squawk,
            updateTime: .now
        )

        print("[SQUAWK] ContentValues.squawk = \(newState.squawk ?? "NIL")")
        return newState
    }

    private func formatAltitude(_ meters: Double?) -> String {
        guard let meters = meters else { return "— ft" }
        let feet = meters * 3.28084
        let rounded = Int(feet.rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return (formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)") + " ft"
    }

    private func formatSpeed(_ mps: Double?) -> String {
        guard let mps = mps else { return "— kts" }
        let knots = mps * 1.94384
        return "\(Int(knots.rounded())) kts"
    }

    private func formatHeading(_ degrees: Double?) -> String {
        guard let degrees = degrees else { return "— °" }
        return String(format: "%03d°", Int(degrees.rounded()))
    }
}
