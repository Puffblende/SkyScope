import Foundation
import CoreLocation

// MARK: - Aircraft

/// Domain model representing a single aircraft snapshot returned by an upstream API.
/// This is API-agnostic: both FlightAware and OpenSky responses are mapped into this type.
struct Aircraft: Identifiable, Hashable, Sendable {
    /// Stable identifier. Prefer ICAO24 (hex transponder code) — falls back to registration or callsign.
    var id: String

    /// Aircraft registration, e.g. "D-EVGK".
    var registration: String?

    /// Flight number / callsign, e.g. "DLH441".
    var callsign: String?

    /// Airline name resolved from ICAO/IATA code (best effort).
    var airline: String?

    /// Aircraft type code (ICAO), e.g. "A320".
    var aircraftType: String?

    /// Current geographic position.
    var coordinate: CLLocationCoordinate2D

    /// Altitude above mean sea level in **meters**. Convert at the view layer.
    var altitudeMeters: Double?

    /// Ground speed in **meters per second**. Convert at the view layer.
    var groundSpeedMps: Double?

    /// Heading / track over ground in degrees (0 = north, clockwise).
    var headingDegrees: Double?

    /// Origin airport ICAO/IATA code.
    var originAirport: String?

    /// Destination airport ICAO/IATA code.
    var destinationAirport: String?

    /// Transponder/squawk code, e.g. "1234".
    var squawk: String?

    /// True when the aircraft is reported as on-ground.
    var onGround: Bool

    /// Last update timestamp from the source.
    var lastUpdate: Date

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Aircraft, rhs: Aircraft) -> Bool {
        lhs.id == rhs.id
    }
}

extension Aircraft {
    /// Distance to a reference coordinate in meters.
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let a = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let b = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return a.distance(from: b)
    }

    /// Display name preferring callsign, then registration, then ICAO24.
    var displayName: String {
        if let callsign, !callsign.trimmingCharacters(in: .whitespaces).isEmpty {
            return callsign
        }
        if let registration, !registration.isEmpty { return registration }
        return id
    }

    /// Returns a copy with the coordinate projected forward by `seconds` using
    /// the aircraft's current speed and heading. Ground aircraft are returned unchanged.
    /// Elapsed time is clamped to 120 s to limit drift when data is stale.
    func interpolated(by seconds: Double) -> Aircraft {
        guard !onGround,
              let speed = groundSpeedMps, speed > 0,
              let heading = headingDegrees,
              seconds > 0 else { return self }

        let elapsed = min(seconds, 120)
        let dist = speed * elapsed
        let headingRad = heading * .pi / 180
        let lat = coordinate.latitude
        let cosLat = cos(lat * .pi / 180)

        var copy = self
        copy.coordinate = CLLocationCoordinate2D(
            latitude:  lat + (dist * cos(headingRad)) / 111_320,
            longitude: coordinate.longitude + (dist * sin(headingRad)) / (111_320 * max(cosLat, 0.001))
        )
        return copy
    }
}
