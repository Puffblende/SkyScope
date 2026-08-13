import Foundation
import ActivityKit
import Observation
import CoreLocation

/// Manages the single SkyScope Live Activity.
///
/// The update flow is intentionally simple:
///   1. The data store's polling loop fetches new aircraft on the configured interval.
///   2. When `dataStore.aircraft` changes, ContentView calls `update(target:)` with the
///      priority-resolved aircraft (`activityTarget(favorites:)` from the data store).
///   3. This manager just pushes that state to ActivityKit — no internal timers needed.
///
/// Priority for the displayed aircraft: **Follow > Favorite > Nearest**.
@Observable
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private(set) var isRunning = false
    private var liveActivity: Activity<SkyScopeActivityAttributes>?

    private init() {}

    // MARK: - Lifecycle

    func start(target: Aircraft?) async {
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            print("[LAM] ❌ Live Activities disabled")
            return
        }

        // End any stale activities first.
        for existing in Activity<SkyScopeActivityAttributes>.activities {
            await existing.end(
                ActivityContent(state: existing.content.state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }

        guard let aircraft = target else {
            print("[LAM] ❌ No aircraft available to display")
            return
        }

        let attributes = SkyScopeActivityAttributes(userLocation: "SkyScope")
        let initialState = await makeState(from: aircraft)

        do {
            let activity = try Activity<SkyScopeActivityAttributes>.request(
                attributes: attributes,
                contentState: initialState,
                pushType: nil
            )
            self.liveActivity = activity
            self.isRunning = true
            print("[LAM] ✅ Started with \(aircraft.displayName)")
        } catch {
            print("[LAM] ❌ Failed to start: \(error)")
        }
    }

    func stop() async {
        guard let activity = liveActivity else {
            isRunning = false
            return
        }
        await activity.end(
            ActivityContent(state: activity.content.state, staleDate: nil),
            dismissalPolicy: .immediate
        )
        self.liveActivity = nil
        self.isRunning = false
        print("[LAM] ✅ Stopped")
    }

    /// Called whenever the aircraft list changes. Pushes the new priority-resolved target to the
    /// Live Activity. Pass `nil` target to stop the activity (no aircraft in range).
    func update(target: Aircraft?) async {
        guard isRunning, let activity = liveActivity else { return }

        guard let aircraft = target else {
            await stop()
            return
        }

        let newState = await makeState(from: aircraft)
        await activity.update(ActivityContent(state: newState, staleDate: nil))
        print("[LAM] Updated → \(aircraft.displayName)")
    }

    // MARK: - State Formatting

    private func makeState(from aircraft: Aircraft) async -> SkyScopeActivityAttributes.ContentValues {
        let origin = aircraft.originAirport
        let destination = aircraft.destinationAirport
        let typeCode = aircraft.aircraftType ?? ""
        let typeFullName = getFullAircraftTypeName(typeCode.isEmpty ? nil : typeCode)

        let progress: Double?
        if let orig = origin, let dest = destination {
            progress = await calculateProgress(for: aircraft, origin: orig, destination: dest)
        } else {
            progress = nil
        }

        return SkyScopeActivityAttributes.ContentValues(
            callsign: aircraft.displayName,
            altitude: formatAltitude(aircraft.altitudeMeters),
            speed: formatSpeed(aircraft.groundSpeedMps),
            heading: formatHeading(aircraft.headingDegrees),
            aircraftType: typeCode.isEmpty ? "?" : typeCode,
            aircraftTypeFullName: typeFullName,
            airline: aircraft.airline,
            registration: aircraft.registration,
            origin: origin,
            destination: destination,
            progress: progress,
            squawk: aircraft.squawk,
            updateTime: .now
        )
    }

    private func calculateProgress(for aircraft: Aircraft, origin: String, destination: String) async -> Double {
        guard origin != destination else { return 0.5 }

        async let originCoord = AirportCoordinatesService.shared.coordinates(for: origin)
        async let destCoord = AirportCoordinatesService.shared.coordinates(for: destination)

        guard let orig = await originCoord, let dest = await destCoord else { return 0.5 }

        let aircraftLoc = CLLocation(latitude: aircraft.coordinate.latitude, longitude: aircraft.coordinate.longitude)
        let originLoc = CLLocation(latitude: orig.latitude, longitude: orig.longitude)
        let destLoc = CLLocation(latitude: dest.latitude, longitude: dest.longitude)

        let total = originLoc.distance(from: destLoc)
        guard total > 0 else { return 0.5 }
        return min(max(originLoc.distance(from: aircraftLoc) / total, 0.0), 1.0)
    }

    private func getFullAircraftTypeName(_ code: String?) -> String {
        guard let code = code?.uppercased() else { return "" }
        let names: [String: String] = [
            "B736": "Boeing 737-600", "B737": "Boeing 737-700",
            "B738": "Boeing 737-800", "B739": "Boeing 737-900",
            "B38M": "Boeing 737 MAX 8", "B39M": "Boeing 737 MAX 9",
            "B3XM": "Boeing 737 MAX 10", "B712": "Boeing 717",
            "B741": "Boeing 747-100", "B742": "Boeing 747-200",
            "B743": "Boeing 747-300", "B744": "Boeing 747-400",
            "B748": "Boeing 747-8", "B752": "Boeing 757-200",
            "B753": "Boeing 757-300", "B762": "Boeing 767-200",
            "B763": "Boeing 767-300", "B764": "Boeing 767-400",
            "B772": "Boeing 777-200", "B773": "Boeing 777-300",
            "B77L": "Boeing 777-200LR", "B77W": "Boeing 777-300ER",
            "B778": "Boeing 777X-8", "B779": "Boeing 777X-9",
            "B788": "Boeing 787-8 Dreamliner", "B789": "Boeing 787-9 Dreamliner",
            "B78X": "Boeing 787-10 Dreamliner",
            "A318": "Airbus A318", "A319": "Airbus A319",
            "A320": "Airbus A320", "A20N": "Airbus A320neo",
            "A321": "Airbus A321", "A21N": "Airbus A321neo",
            "A220": "Airbus A220-100", "BCS1": "Airbus A220-100", "BCS3": "Airbus A220-300",
            "A332": "Airbus A330-200", "A333": "Airbus A330-300",
            "A338": "Airbus A330-800neo", "A339": "Airbus A330-900neo",
            "A342": "Airbus A340-200", "A343": "Airbus A340-300",
            "A345": "Airbus A340-500", "A346": "Airbus A340-600",
            "A359": "Airbus A350-900", "A35K": "Airbus A350-1000",
            "A388": "Airbus A380",
            "E170": "Embraer 170", "E175": "Embraer 175", "E75L": "Embraer 175",
            "E190": "Embraer 190", "E195": "Embraer 195", "E295": "Embraer 195-E2",
            "E50P": "Embraer Phenom 100", "E55P": "Embraer Phenom 300",
            "CRJ2": "Bombardier CRJ200", "CRJ7": "Bombardier CRJ700", "CRJ9": "Bombardier CRJ900",
            "DH8A": "Dash 8-100", "DH8B": "Dash 8-200", "DH8C": "Dash 8-300", "DH8D": "Dash 8-400",
            "AT43": "ATR 42-300", "AT45": "ATR 42-500",
            "AT72": "ATR 72-200", "AT73": "ATR 72-500", "AT75": "ATR 72-500", "AT76": "ATR 72-600",
            "C172": "Cessna 172 Skyhawk", "C182": "Cessna 182 Skylane",
            "C208": "Cessna 208 Caravan", "C25A": "Cessna Citation CJ1",
            "C25B": "Cessna Citation CJ2", "C56X": "Cessna Citation Excel",
            "C680": "Cessna Citation Sovereign", "C750": "Cessna Citation X",
            "PA28": "Piper Cherokee", "PA34": "Piper Seneca",
            "PA44": "Piper Seminole", "PA46": "Piper Malibu",
            "SR20": "Cirrus SR20", "SR22": "Cirrus SR22",
            "SF50": "Cirrus Vision Jet", "DA40": "Diamond DA40",
            "DA42": "Diamond DA42", "DA62": "Diamond DA62",
            "PC12": "Pilatus PC-12", "PC24": "Pilatus PC-24",
            "LJ35": "Learjet 35", "LJ45": "Learjet 45", "LJ60": "Learjet 60",
            "CL30": "Bombardier Challenger 300", "CL35": "Bombardier Challenger 350",
            "CL60": "Bombardier Challenger 600",
            "GL5T": "Bombardier Global Express", "GLEX": "Bombardier Global Express",
            "GLF4": "Gulfstream IV", "GLF5": "Gulfstream V",
            "GLF6": "Gulfstream G650", "G650": "Gulfstream G650",
            "F2TH": "Dassault Falcon 2000", "FA7X": "Dassault Falcon 7X",
            "FA8X": "Dassault Falcon 8X", "F900": "Dassault Falcon 900",
            "EC45": "Airbus H145", "H145": "Airbus H145",
            "EC35": "Airbus H135", "H135": "Airbus H135",
            "R44": "Robinson R44", "R22": "Robinson R22",
            "B06": "Bell 206 JetRanger",
            "MD11": "McDonnell Douglas MD-11", "MD82": "McDonnell Douglas MD-82",
            "MD83": "McDonnell Douglas MD-83", "DC10": "McDonnell Douglas DC-10",
            "IL76": "Ilyushin Il-76", "SU95": "Sukhoi Superjet 100",
            "F100": "Fokker 100", "F70": "Fokker 70",
        ]
        return names[code] ?? code
    }

    private func formatAltitude(_ meters: Double?) -> String {
        guard let meters else { return "— ft" }
        let feet = Int((meters * 3.28084).rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: feet)) ?? "\(feet)") + " ft"
    }

    private func formatSpeed(_ mps: Double?) -> String {
        guard let mps else { return "— kts" }
        return "\(Int((mps * 1.94384).rounded())) kts"
    }

    private func formatHeading(_ degrees: Double?) -> String {
        guard let degrees else { return "—°" }
        return String(format: "%03d°", Int(degrees.rounded()))
    }
}
