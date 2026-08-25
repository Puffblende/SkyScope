import Foundation
import CoreLocation

/// FlightAware AeroAPI client.
/// Requires an API key from https://www.flightaware.com/aeroapi/portal/ — stored in SettingsStore.
/// We use the `/flights/search/positions` endpoint with a bounding-box query.
struct FlightAwareService: AircraftDataProvider {
    let apiKey: String

    private let baseURL = URL(string: "https://aeroapi.flightaware.com/aeroapi")!
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func fetchAircraft(near center: CLLocationCoordinate2D, radiusMeters: Double) async throws -> [Aircraft] {
        guard !apiKey.isEmpty else { throw AircraftDataError.missingAPIKey }

        // Bounding box for the search query.
        let latDelta = radiusMeters / 111_000.0
        let lonDelta = radiusMeters / (111_000.0 * max(cos(center.latitude * .pi / 180), 0.0001))
        let minLat = center.latitude - latDelta
        let maxLat = center.latitude + latDelta
        let minLon = center.longitude - lonDelta
        let maxLon = center.longitude + lonDelta

        // AeroAPI uses a custom query syntax: -latlong "minLat minLon maxLat maxLon"
        let query = "-latlong \"\(minLat) \(minLon) \(maxLat) \(maxLon)\""

        var components = URLComponents(url: baseURL.appendingPathComponent("flights/search/positions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "query", value: query)]

        guard let url = components.url else { throw AircraftDataError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "x-apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AircraftDataError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // 402 = payment required (free credits used up) → upstream router will fall back.
            throw AircraftDataError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder.aeroAPI.decode(FlightAwareResponse.self, from: data)
        let aircraft = decoded.positions.compactMap(Self.makeAircraft)

        // Post-fetch filter: ensure aircraft is within the radius
        return aircraft.filter { $0.distance(to: center) <= radiusMeters }
    }

    private static func makeAircraft(from position: FlightAwarePosition) -> Aircraft? {
        guard let lat = position.latitude, let lon = position.longitude else { return nil }

        // Altitude is in 100s of feet — convert to meters for our domain model.
        let altitudeMeters: Double?
        if let altitude = position.altitude {
            altitudeMeters = altitude * 100.0 * 0.3048
        } else {
            altitudeMeters = nil
        }

        // Ground speed is reported in knots — convert to m/s.
        let speedMps: Double?
        if let speed = position.groundspeed {
            speedMps = speed * 0.514_444
        } else {
            speedMps = nil
        }

        let id = position.faFlightId ?? position.ident ?? position.registration ?? UUID().uuidString

        return Aircraft(
            id: id,
            registration: position.registration,
            callsign: position.ident,
            airline: position.operatorName,
            aircraftType: position.aircraftType,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitudeMeters: altitudeMeters,
            groundSpeedMps: speedMps,
            headingDegrees: position.heading,
            originAirport: position.origin?.code,
            destinationAirport: position.destination?.code,
            onGround: false,
            lastUpdate: position.lastPosition ?? .now
        )
    }
}

// MARK: - Wire format

private struct FlightAwareResponse: Decodable {
    let positions: [FlightAwarePosition]
}

private struct FlightAwarePosition: Decodable {
    let faFlightId: String?
    let ident: String?
    let registration: String?
    let operatorName: String?
    let aircraftType: String?
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let groundspeed: Double?
    let heading: Double?
    let origin: AirportRef?
    let destination: AirportRef?
    let lastPosition: Date?

    enum CodingKeys: String, CodingKey {
        case faFlightId = "fa_flight_id"
        case ident
        case registration
        case operatorName = "operator"
        case aircraftType = "aircraft_type"
        case latitude = "last_position_latitude"
        case longitude = "last_position_longitude"
        case altitude
        case groundspeed
        case heading
        case origin
        case destination
        case lastPosition = "last_position_time"
    }

    init(from decoder: Decoder) throws {
        // The AeroAPI search/positions response shape uses `last_position` as a nested object on some
        // endpoints and as flat fields on others. We accept both forms.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.faFlightId = try? container.decode(String.self, forKey: .faFlightId)
        self.ident = try? container.decode(String.self, forKey: .ident)
        self.registration = try? container.decode(String.self, forKey: .registration)
        self.operatorName = try? container.decode(String.self, forKey: .operatorName)
        self.aircraftType = try? container.decode(String.self, forKey: .aircraftType)
        self.altitude = try? container.decode(Double.self, forKey: .altitude)
        self.groundspeed = try? container.decode(Double.self, forKey: .groundspeed)
        self.heading = try? container.decode(Double.self, forKey: .heading)
        self.origin = try? container.decode(AirportRef.self, forKey: .origin)
        self.destination = try? container.decode(AirportRef.self, forKey: .destination)

        if let nested = try? decoder.container(keyedBy: NestedKeys.self).decode(LastPositionPayload.self, forKey: .lastPosition) {
            self.latitude = nested.latitude
            self.longitude = nested.longitude
            self.lastPosition = nested.timestamp
        } else {
            self.latitude = try? container.decode(Double.self, forKey: .latitude)
            self.longitude = try? container.decode(Double.self, forKey: .longitude)
            self.lastPosition = try? container.decode(Date.self, forKey: .lastPosition)
        }
    }

    private enum NestedKeys: String, CodingKey {
        case lastPosition = "last_position"
    }

    private struct LastPositionPayload: Decodable {
        let latitude: Double?
        let longitude: Double?
        let timestamp: Date?
        enum CodingKeys: String, CodingKey {
            case latitude, longitude, timestamp
        }
    }
}

private struct AirportRef: Decodable {
    let code: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case code = "code_icao"
        case codeIATA = "code_iata"
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let icao = try? container.decode(String.self, forKey: .code)
        let iata = try? container.decode(String.self, forKey: .codeIATA)
        self.code = icao ?? iata
        self.name = try? container.decode(String.self, forKey: .name)
    }
}

private extension JSONDecoder {
    static let aeroAPI: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
