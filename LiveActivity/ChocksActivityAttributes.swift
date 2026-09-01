import ActivityKit
import Foundation

struct ChocksActivityAttributes: ActivityAttributes {
    typealias ContentState = ContentValues

    struct ContentValues: Codable, Hashable {
        var callsign: String
        var altitude: String
        var speed: String
        var heading: String
        var aircraftType: String
        var aircraftTypeFullName: String
        var airline: String?
        var registration: String?
        var origin: String?
        var destination: String?
        var progress: Double?
        var squawk: String?
        var updateTime: Date
        // Layout preferences (passed as strings so the widget extension needs no SettingsStore dep)
        var compactStyle: String
        var lockScreenStyle: String
        // Proximity data (optional — only present when user location is known)
        var distanceNM: Double?
        var minutesToClosest: Int?
        var bearingDeg: Int?
        var totalNearbyCount: Int

        init(
            callsign: String,
            altitude: String,
            speed: String,
            heading: String,
            aircraftType: String,
            aircraftTypeFullName: String,
            airline: String? = nil,
            registration: String? = nil,
            origin: String? = nil,
            destination: String? = nil,
            progress: Double? = nil,
            squawk: String? = nil,
            updateTime: Date,
            compactStyle: String = "flightAndAltitude",
            lockScreenStyle: String = "telemetry",
            distanceNM: Double? = nil,
            minutesToClosest: Int? = nil,
            bearingDeg: Int? = nil,
            totalNearbyCount: Int = 0
        ) {
            self.callsign = callsign
            self.altitude = altitude
            self.speed = speed
            self.heading = heading
            self.aircraftType = aircraftType
            self.aircraftTypeFullName = aircraftTypeFullName
            self.airline = airline
            self.registration = registration
            self.origin = origin
            self.destination = destination
            self.progress = progress
            self.squawk = squawk
            self.updateTime = updateTime
            self.compactStyle = compactStyle
            self.lockScreenStyle = lockScreenStyle
            self.distanceNM = distanceNM
            self.minutesToClosest = minutesToClosest
            self.bearingDeg = bearingDeg
            self.totalNearbyCount = totalNearbyCount
        }
    }

    var userLocation: String
}
