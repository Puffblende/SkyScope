import ActivityKit
import Foundation

struct SkyScopeActivityAttributes: ActivityAttributes {
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
    }

    var userLocation: String
}
