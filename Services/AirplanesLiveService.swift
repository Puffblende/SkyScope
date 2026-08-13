import Foundation
import CoreLocation

/// Aircraft position data from airplanes.live.
///
/// Free community ADS-B network — no API key required.
/// Endpoint: GET https://api.airplanes.live/v2/point/{lat}/{lon}/{radius_nm}
///
/// Position-only source: route data (origin/destination) is enriched via AdsbdbService
/// by callsign lookup, matching the same pattern used by OpenSkyService.
struct AirplanesLiveService: AircraftDataProvider {
    private let baseURL: String
    private let session: URLSession
    private let adsbdbService: AdsbdbService

    init(baseURL: String = "https://api.airplanes.live/v2/point", session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.adsbdbService = AdsbdbService(session: session)
    }

    func fetchAircraft(near center: CLLocationCoordinate2D, radiusMeters: Double) async throws -> [Aircraft] {
        let radiusNM = max(1, Int((radiusMeters / 1_852.0).rounded()))
        guard let url = URL(string: "\(baseURL)/\(center.latitude)/\(center.longitude)/\(radiusNM)") else {
            throw AircraftDataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AircraftDataError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AircraftDataError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(AirplanesLiveResponse.self, from: data)
        var aircraft = decoded.ac.compactMap(Self.makeAircraft)
        await enrichWithRoutes(aircraftList: &aircraft)
        return aircraft
    }

    private func enrichWithRoutes(aircraftList: inout [Aircraft]) async {
        await withTaskGroup(of: (Int, (origin: String?, destination: String?)?)?.self) { group in
            for (index, aircraft) in aircraftList.enumerated() {
                group.addTask {
                    let route = await self.adsbdbService.fetchRoute(for: aircraft.callsign)
                    return (index, route)
                }
            }
            for await result in group {
                if let (index, route) = result {
                    aircraftList[index].originAirport = route?.origin
                    aircraftList[index].destinationAirport = route?.destination
                }
            }
        }
    }

    private static func makeAircraft(from raw: ALAircraft) -> Aircraft? {
        guard let lat = raw.lat, let lon = raw.lon else { return nil }

        // altBaroFeet is nil when the aircraft reported "ground" — skip on-ground aircraft.
        guard let altFeet = raw.altBaroFeet else { return nil }

        let altitudeMeters = altFeet * 0.3048
        let speedMps = raw.gs.map { $0 * 0.514_444 }
        let callsign = raw.flight.map { $0.trimmingCharacters(in: .whitespaces) }

        return Aircraft(
            id: raw.hex,
            registration: raw.r,
            callsign: callsign?.isEmpty == true ? nil : callsign,
            airline: nil,
            aircraftType: raw.t,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitudeMeters: altitudeMeters,
            groundSpeedMps: speedMps,
            headingDegrees: raw.track,
            originAirport: nil,
            destinationAirport: nil,
            squawk: raw.squawk,
            onGround: false,
            lastUpdate: .now
        )
    }
}

// MARK: - Wire format

private struct AirplanesLiveResponse: Decodable {
    let ac: [ALAircraft]
}

/// Readsb/dump1090 aircraft entry. Fields are optional — ADS-B coverage varies by region.
private struct ALAircraft: Decodable {
    let hex: String
    let flight: String?
    let r: String?           // registration
    let t: String?           // ICAO aircraft type code
    let lat: Double?
    let lon: Double?
    let altBaroFeet: Double? // barometric altitude in feet; nil when "ground" string received
    let gs: Double?          // ground speed in knots
    let track: Double?       // track over ground in degrees
    let squawk: String?

    enum CodingKeys: String, CodingKey {
        case hex, flight, r, t, lat, lon, gs, track, squawk
        case altBaroFeet = "alt_baro"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hex    = try c.decode(String.self, forKey: .hex)
        self.flight = try? c.decode(String.self, forKey: .flight)
        self.r      = try? c.decode(String.self, forKey: .r)
        self.t      = try? c.decode(String.self, forKey: .t)
        self.lat    = try? c.decode(Double.self, forKey: .lat)
        self.lon    = try? c.decode(Double.self, forKey: .lon)
        self.gs     = try? c.decode(Double.self, forKey: .gs)
        self.track  = try? c.decode(Double.self, forKey: .track)
        self.squawk = try? c.decode(String.self, forKey: .squawk)

        // alt_baro is either a number (feet) or the literal string "ground"
        if let num = try? c.decode(Double.self, forKey: .altBaroFeet) {
            self.altBaroFeet = num
        } else {
            self.altBaroFeet = nil
        }
    }
}
