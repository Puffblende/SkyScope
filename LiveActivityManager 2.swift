//
//  LiveActivityManager 2.swift
//  SkyScope
//
//  Created by Dennis Kiefer on 29.05.26.
//


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

        for activity in Activity<SkyScopeActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: activity.content.state, staleDate: nil),
                dismissalPolicy: .immediate
            )
            print("[LAM] Ended existing activity: \(activity.id)")
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
        let initialState = formatActivityState(from: firstAircraft)

        do {
            let activity = try Activity<SkyScopeActivityAttributes>.request(
                attributes: attributes,
                contentState: initialState,
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

        await activity.end(
            ActivityContent(state: activity.content.state, staleDate: nil),
            dismissalPolicy: .immediate
        )
        self.liveActivity = nil
        self.isRunning = false
        print("[LAM] ✅ Stopped")
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

        let newState = formatActivityState(from: nearest)
        await activity.update(ActivityContent(state: newState, staleDate: nil))

        if let location = location?.currentLocation?.coordinate {
            let distanceKm = nearest.distance(to: location) / 1000
            print("[LAM-UPD] \(nearest.displayName) @ \(String(format: "%.1f", distanceKm))km")
        }
    }

    // MARK: - Private Helpers

    private func getFullAircraftTypeName(_ code: String?) -> String {
        guard let code = code?.uppercased() else { return "Unknown" }
        let aircraftNames: [String: String] = [
            "B736": "Boeing 737-600",
            "B737": "Boeing 737-700",
            "B738": "Boeing 737-800",
            "B739": "Boeing 737-900",
            "B38M": "Boeing 737 MAX 8",
            "B39M": "Boeing 737 MAX 9",
            "B3XM": "Boeing 737 MAX 10",
            "B712": "Boeing 717",
            "B741": "Boeing 747-100",
            "B742": "Boeing 747-200",
            "B743": "Boeing 747-300",
            "B744": "Boeing 747-400",
            "B748": "Boeing 747-8",
            "B752": "Boeing 757-200",
            "B753": "Boeing 757-300",
            "B762": "Boeing 767-200",
            "B763": "Boeing 767-300",
            "B764": "Boeing 767-400",
            "B772": "Boeing 777-200",
            "B773": "Boeing 777-300",
            "B77L": "Boeing 777-200LR",
            "B77W": "Boeing 777-300ER",
            "B778": "Boeing 777X-8",
            "B779": "Boeing 777X-9",
            "B788": "Boeing 787-8 Dreamliner",
            "B789": "Boeing 787-9 Dreamliner",
            "B78X": "Boeing 787-10 Dreamliner",
            "A318": "Airbus A318",
            "A319": "Airbus A319",
            "A320": "Airbus A320",
            "A20N": "Airbus A320neo",
            "A321": "Airbus A321",
            "A21N": "Airbus A321neo",
            "A220": "Airbus A220-100",
            "BCS1": "Airbus A220-100",
            "BCS3": "Airbus A220-300",
            "A332": "Airbus A330-200",
            "A333": "Airbus A330-300",
            "A338": "Airbus A330-800neo",
            "A339": "Airbus A330-900neo",
            "A342": "Airbus A340-200",
            "A343": "Airbus A340-300",
            "A345": "Airbus A340-500",
            "A346": "Airbus A340-600",
            "A359": "Airbus A350-900",
            "A35K": "Airbus A350-1000",
            "A388": "Airbus A380",
            "E170": "Embraer 170",
            "E175": "Embraer 175",
            "E75L": "Embraer 175",
            "E190": "Embraer 190",
            "E195": "Embraer 195",
            "E295": "Embraer 195-E2",
            "E50P": "Embraer Phenom 100",
            "E55P": "Embraer Phenom 300",
            "CRJ2": "Bombardier CRJ200",
            "CRJ7": "Bombardier CRJ700",
            "CRJ9": "Bombardier CRJ900",
            "DH8A": "Dash 8-100",
            "DH8B": "Dash 8-200",
            "DH8C": "Dash 8-300",
            "DH8D": "Dash 8-400",
            "AT43": "ATR 42-300",
            "AT45": "ATR 42-500",
            "AT72": "ATR 72-200",
            "AT73": "ATR 72-500",
            "AT75": "ATR 72-500",
            "AT76": "ATR 72-600",
            "C172": "Cessna 172 Skyhawk",
            "C182": "Cessna 182 Skylane",
            "C208": "Cessna 208 Caravan",
            "C25A": "Cessna Citation CJ1",
            "C25B": "Cessna Citation CJ2",
            "C56X": "Cessna Citation Excel",
            "C680": "Cessna Citation Sovereign",
            "C750": "Cessna Citation X",
            "PA28": "Piper Cherokee",
            "PA34": "Piper Seneca",
            "PA44": "Piper Seminole",
            "PA46": "Piper Malibu",
            "SR20": "Cirrus SR20",
            "SR22": "Cirrus SR22",
            "SF50": "Cirrus Vision Jet",
            "DA40": "Diamond DA40",
            "DA42": "Diamond DA42",
            "DA62": "Diamond DA62",
            "PC12": "Pilatus PC-12",
            "PC24": "Pilatus PC-24",
            "LJ35": "Learjet 35",
            "LJ45": "Learjet 45",
            "LJ60": "Learjet 60",
            "CL30": "Bombardier Challenger 300",
            "CL35": "Bombardier Challenger 350",
            "CL60": "Bombardier Challenger 600",
            "GL5T": "Bombardier Global Express",
            "GLEX": "Bombardier Global Express",
            "GLF4": "Gulfstream IV",
            "GLF5": "Gulfstream V",
            "GLF6": "Gulfstream G650",
            "G650": "Gulfstream G650",
            "F2TH": "Dassault Falcon 2000",
            "FA7X": "Dassault Falcon 7X",
            "FA8X": "Dassault Falcon 8X",
            "F900": "Dassault Falcon 900",
            "EC45": "Airbus H145",
            "H145": "Airbus H145",
            "EC35": "Airbus H135",
            "H135": "Airbus H135",
            "R44":  "Robinson R44",
            "R22":  "Robinson R22",
            "B06":  "Bell 206 JetRanger",
            "MD11": "McDonnell Douglas MD-11",
            "MD82": "McDonnell Douglas MD-82",
            "MD83": "McDonnell Douglas MD-83",
            "DC10": "McDonnell Douglas DC-10",
            "IL76": "Ilyushin Il-76",
            "SU95": "Sukhoi Superjet 100",
            "F100": "Fokker 100",
            "F70":  "Fokker 70",
        ]
        return aircraftNames[code] ?? code
    }

    private func calculateProgress(for aircraft: Aircraft) -> Double {
        guard let originCode = aircraft.originAirport,
              let destCode = aircraft.destinationAirport else { return 0.5 }

        let airports: [String: CLLocationCoordinate2D] = [
            "EDDF": CLLocationCoordinate2D(latitude: 50.0333, longitude: 8.5706),
            "EGLL": CLLocationCoordinate2D(latitude: 51.4775, longitude: -0.4614),
            "LFPG": CLLocationCoordinate2D(latitude: 49.0097, longitude: 2.5479),
            "EHAM": CLLocationCoordinate2D(latitude: 52.3086, longitude: 4.7639),
            "LEMD": CLLocationCoordinate2D(latitude: 40.4936, longitude: -3.5668),
            "LIRF": CLLocationCoordinate2D(latitude: 41.7999, longitude: 12.2462),
            "LOWW": CLLocationCoordinate2D(latitude: 48.1103, longitude: 16.5697),
            "LSZH": CLLocationCoordinate2D(latitude: 47.4647, longitude: 8.5492),
            "EKCH": CLLocationCoordinate2D(latitude: 55.6179, longitude: 12.6560),
            "ENGM": CLLocationCoordinate2D(latitude: 60.1939, longitude: 11.1004),
            "EFHK": CLLocationCoordinate2D(latitude: 60.3172, longitude: 24.9633),
            "EPWA": CLLocationCoordinate2D(latitude: 52.1657, longitude: 20.9671),
            "LTFM": CLLocationCoordinate2D(latitude: 41.2753, longitude: 28.7519),
            "OMDB": CLLocationCoordinate2D(latitude: 25.2532, longitude: 55.3657),
            "OMAA": CLLocationCoordinate2D(latitude: 24.4330, longitude: 54.6511),
            "VIDP": CLLocationCoordinate2D(latitude: 28.5562, longitude: 77.1000),
            "ZBAA": CLLocationCoordinate2D(latitude: 40.0799, longitude: 116.5833),
            "ZSPD": CLLocationCoordinate2D(latitude: 31.1434, longitude: 121.8052),
            "RJTT": CLLocationCoordinate2D(latitude: 35.5494, longitude: 139.7798),
            "RKSI": CLLocationCoordinate2D(latitude: 37.4692, longitude: 126.4505),
            "WSSS": CLLocationCoordinate2D(latitude: 1.3644, longitude: 103.9915),
            "YMML": CLLocationCoordinate2D(latitude: -37.6690, longitude: 144.8410),
            "YSSY": CLLocationCoordinate2D(latitude: -33.9461, longitude: 151.1772),
            "CYYZ": CLLocationCoordinate2D(latitude: 43.6777, longitude: -79.6248),
            "CYUL": CLLocationCoordinate2D(latitude: 45.4706, longitude: -73.7408),
            "KJFK": CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781),
            "KLAX": CLLocationCoordinate2D(latitude: 33.9425, longitude: -118.4081),
            "KORD": CLLocationCoordinate2D(latitude: 41.9742, longitude: -87.9073),
            "KATL": CLLocationCoordinate2D(latitude: 33.6407, longitude: -84.4277),
            "KDFW": CLLocationCoordinate2D(latitude: 32.8998, longitude: -97.0403),
            "EDDM": CLLocationCoordinate2D(latitude: 48.3537, longitude: 11.7750),
            "EDDB": CLLocationCoordinate2D(latitude: 52.3667, longitude: 13.5033),
            "EGKK": CLLocationCoordinate2D(latitude: 51.1481, longitude: -0.1903),
            "EGGW": CLLocationCoordinate2D(latitude: 51.8747, longitude: -0.3683),
            "EGCC": CLLocationCoordinate2D(latitude: 53.3537, longitude: -2.2750),
            "LPPT": CLLocationCoordinate2D(latitude: 38.7813, longitude: -9.1359),
            "LSGG": CLLocationCoordinate2D(latitude: 46.2381, longitude: 6.1089),
            "UUEE": CLLocationCoordinate2D(latitude: 55.9736, longitude: 37.4125),
            "VHHH": CLLocationCoordinate2D(latitude: 22.3080, longitude: 113.9185),
            "VTBS": CLLocationCoordinate2D(latitude: 13.6811, longitude: 100.7470),
            "WMKK": CLLocationCoordinate2D(latitude: 2.7456, longitude: 101.7099),
            "FAOR": CLLocationCoordinate2D(latitude: -26.1392, longitude: 28.2460),
            "HECA": CLLocationCoordinate2D(latitude: 30.1219, longitude: 31.4056),
            "DNMM": CLLocationCoordinate2D(latitude: 6.5774, longitude: 3.3216),
        ]

        guard let originCoord = airports[originCode],
              let destCoord = airports[destCode],
              let currentCoord = location?.currentLocation?.coordinate else {
            return 0.5
        }

        let originLoc = CLLocation(latitude: originCoord.latitude, longitude: originCoord.longitude)
        let destLoc = CLLocation(latitude: destCoord.latitude, longitude: destCoord.longitude)
        let currentLoc = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)

        let totalDistance = originLoc.distance(from: destLoc)
        let distanceFromOrigin = originLoc.distance(from: currentLoc)

        guard totalDistance > 0 else { return 0.5 }

        return min(max(distanceFromOrigin / totalDistance, 0.0), 1.0)
    }

    private func findNearestAircraft(from aircraft: [Aircraft]) -> Aircraft? {
        guard let userLocation = location?.currentLocation?.coordinate else {
            return aircraft.first
        }
        return aircraft.min {
            $0.distance(to: userLocation) < $1.distance(to: userLocation)
        }
    }

    private func formatActivityState(from aircraft: Aircraft) -> SkyScopeActivityAttributes.ContentValues {
        let typeCode = aircraft.aircraftType ?? ""
        let typeFullName = getFullAircraftTypeName(typeCode.isEmpty ? nil : typeCode)

        print("[LAM] callsign: \(aircraft.displayName)")
        print("[LAM] registration: \(aircraft.registration ?? "NIL")")
        print("[LAM] squawk: \(aircraft.squawk ?? "NIL")")
        print("[LAM] type: \(typeCode)")

        var progress: Double? = nil
        if aircraft.originAirport != nil && aircraft.destinationAirport != nil {
            progress = calculateProgress(for: aircraft)
        }

        return SkyScopeActivityAttributes.ContentValues(
            callsign: aircraft.displayName,
            altitude: formatAltitude(aircraft.altitudeMeters),
            speed: formatSpeed(aircraft.groundSpeedMps),
            heading: formatHeading(aircraft.headingDegrees),
            aircraftType: typeCode.isEmpty ? "Unknown" : typeCode,
            aircraftTypeFullName: typeFullName,
            registration: aircraft.registration,
            squawk: aircraft.squawk,
            airline: aircraft.airline,
            origin: aircraft.originAirport,
            destination: aircraft.destinationAirport,
            progress: progress,
            updateTime: .now
        )
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
        guard let degrees = degrees else { return "—°" }
        return String(format: "%03d°", Int(degrees.rounded()))
    }
}