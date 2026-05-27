import Foundation
import CoreLocation

/// OpenSky Network REST client.
/// Anonymous calls work but are rate-limited; authenticated calls (username/password) get higher limits.
/// Endpoint: https://opensky-network.org/api/states/all
struct OpenSkyService: AircraftDataProvider {
    let username: String?
    let password: String?

    private let baseURL = URL(string: "https://opensky-network.org/api")!
    private let session: URLSession
    private let adsbdbService: AdsbdbService

    private static var metadataCache: [String: OpenSkyAircraftMetadata] = [:]

    init(username: String? = nil, password: String? = nil, session: URLSession = .shared) {
        self.username = username?.isEmpty == true ? nil : username
        self.password = password?.isEmpty == true ? nil : password
        self.session = session
        self.adsbdbService = AdsbdbService(session: session)
    }

    func fetchAircraft(near center: CLLocationCoordinate2D, radiusMeters: Double) async throws -> [Aircraft] {
        // OpenSky expects a lat/lon bounding box. Convert radius to a degree delta — good enough for short distances.
        let latDelta = radiusMeters / 111_000.0
        let lonDelta = radiusMeters / (111_000.0 * max(cos(center.latitude * .pi / 180), 0.0001))

        var components = URLComponents(url: baseURL.appendingPathComponent("states/all"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "lamin", value: String(center.latitude - latDelta)),
            URLQueryItem(name: "lamax", value: String(center.latitude + latDelta)),
            URLQueryItem(name: "lomin", value: String(center.longitude - lonDelta)),
            URLQueryItem(name: "lomax", value: String(center.longitude + lonDelta))
        ]

        guard let url = components.url else { throw AircraftDataError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        if let username, let password {
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AircraftDataError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AircraftDataError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenSkyResponse.self, from: data)
        let timestamp = Date(timeIntervalSince1970: TimeInterval(decoded.time))
        let states = decoded.states ?? []

        var aircraftList: [Aircraft] = []
        for state in states {
            guard let lat = state.latitude, let lon = state.longitude else { continue }
            let icao24 = state.icao24.trimmingCharacters(in: .whitespaces)
            guard !icao24.isEmpty else { continue }

            let metadata = try await fetchMetadata(for: icao24)
            let callsign = state.callsign?.trimmingCharacters(in: .whitespaces)
            let airline = extractAirlineFromCallsign(callsign) ?? metadata?.manufacturerName

            let lastUpdate: Date
            if let lastContact = state.lastContact {
                lastUpdate = Date(timeIntervalSince1970: TimeInterval(lastContact))
            } else {
                lastUpdate = timestamp
            }

            let ac = Aircraft(
                id: icao24,
                registration: metadata?.registration,
                callsign: callsign?.isEmpty == false ? callsign : nil,
                airline: airline,
                aircraftType: metadata?.typecode,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                altitudeMeters: state.baroAltitude ?? state.geoAltitude,
                groundSpeedMps: state.velocity,
                headingDegrees: state.trueTrack,
                originAirport: nil,
                destinationAirport: nil,
                onGround: state.onGround,
                lastUpdate: lastUpdate
            )
            aircraftList.append(ac)
        }

        await enrichWithRoutes(aircraftList: &aircraftList)
        return aircraftList
    }

    private func enrichWithRoutes(aircraftList: inout [Aircraft]) async {
        await withTaskGroup(of: (index: Int, route: (origin: String?, destination: String?)?)?.self) { group in
            for (index, aircraft) in aircraftList.enumerated() {
                group.addTask {
                    let route = await self.adsbdbService.fetchRoute(for: aircraft.callsign)
                    return (index: index, route: route)
                }
            }

            for await result in group {
                if let result = result {
                    aircraftList[result.index].originAirport = result.route?.origin
                    aircraftList[result.index].destinationAirport = result.route?.destination
                }
            }
        }
    }

    private func fetchMetadata(for icao24: String) async throws -> OpenSkyAircraftMetadata? {
        if let cached = Self.metadataCache[icao24] {
            return cached
        }

        let url = baseURL.appendingPathComponent("metadata/aircraft/icao/\(icao24)")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        if let username, let password {
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }

            let metadata = try JSONDecoder().decode(OpenSkyAircraftMetadata.self, from: data)
            Self.metadataCache[icao24] = metadata
            return metadata
        } catch {
            return nil
        }
    }

    private func extractAirlineFromCallsign(_ callsign: String?) -> String? {
        guard let callsign, callsign.count >= 3 else { return nil }
        let icaoCode = String(callsign.prefix(3)).uppercased()
        return Self.airlineNames[icaoCode]
    }

    private static let airlineNames: [String: String] = [
        "AAL": "American Airlines",
        "DAL": "Delta Air Lines",
        "UAL": "United Airlines",
        "AWE": "US Airways",
        "SWA": "Southwest Airlines",
        "BAW": "British Airways",
        "DLH": "Lufthansa",
        "AFR": "Air France",
        "KLM": "KLM Royal Dutch Airlines",
        "SWR": "SWISS",
        "IBE": "Iberia",
        "TAP": "TAP Air Portugal",
        "AZA": "Alitalia",
        "FFT": "Frontier Airlines",
        "ACA": "Air Canada",
        "WJA": "WestJet",
        "ETH": "Ethiopian Airlines",
        "EZY": "easyJet",
        "RYR": "Ryanair",
        "VIR": "Virgin Atlantic",
        "LOT": "LOT Polish Airlines",
        "LUX": "Luxair",
        "NOS": "Nordic Regional Airlines",
        "BJS": "Baltic Air",
        "SVA": "Saudia",
        "EGY": "EgyptAir",
        "MSR": "Egyptair",
        "UAE": "Emirates",
        "TRA": "Transavia",
        "VOI": "Volotea",
        "WZZ": "Wizz Air",
        "ANA": "All Nippon Airways",
        "JAL": "Japan Airlines",
        "CCA": "Air China",
        "CES": "China Eastern",
        "CPA": "Cathay Pacific",
        "SIA": "Singapore Airlines",
        "THA": "Thai Airways",
        "MAS": "Malaysia Airlines",
        "KAL": "Korean Air",
    ]
}

// MARK: - Wire format

/// OpenSky returns `states` as a JSON array of mixed-type arrays. We decode each row manually.
private struct OpenSkyResponse: Decodable {
    let time: Int
    let states: [OpenSkyState]?

    enum CodingKeys: String, CodingKey { case time, states }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.time = try container.decode(Int.self, forKey: .time)
        if container.contains(.states), try !container.decodeNil(forKey: .states) {
            var arrayContainer = try container.nestedUnkeyedContainer(forKey: .states)
            var states: [OpenSkyState] = []
            while !arrayContainer.isAtEnd {
                if let state = try? arrayContainer.decode(OpenSkyState.self) {
                    states.append(state)
                } else {
                    _ = try? arrayContainer.decode(AnyDecodable.self)
                }
            }
            self.states = states
        } else {
            self.states = nil
        }
    }
}

private struct AnyDecodable: Decodable {}

private struct OpenSkyState: Decodable {
    let icao24: String
    let callsign: String?
    let originCountry: String
    let timePosition: Int?
    let lastContact: Int?
    let longitude: Double?
    let latitude: Double?
    let baroAltitude: Double?
    let onGround: Bool
    let velocity: Double?
    let trueTrack: Double?
    let verticalRate: Double?
    let geoAltitude: Double?

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.icao24 = try container.decode(String.self)
        self.callsign = try? container.decode(String?.self)
        self.originCountry = (try? container.decode(String.self)) ?? ""
        self.timePosition = try? container.decode(Int?.self)
        self.lastContact = try? container.decode(Int?.self)
        self.longitude = try? container.decode(Double?.self)
        self.latitude = try? container.decode(Double?.self)
        self.baroAltitude = try? container.decode(Double?.self)
        self.onGround = (try? container.decode(Bool.self)) ?? false
        self.velocity = try? container.decode(Double?.self)
        self.trueTrack = try? container.decode(Double?.self)
        self.verticalRate = try? container.decode(Double?.self)
        // Skip sensors (index 12) and squawk (index 14) etc.
        _ = try? container.decode([Int]?.self) // sensors
        self.geoAltitude = try? container.decode(Double?.self)
    }
}

private struct OpenSkyAircraftMetadata: Decodable {
    let icao24: String
    let registration: String?
    let typecode: String?
    let manufacturerName: String?

    enum CodingKeys: String, CodingKey {
        case icao24
        case registration
        case typecode
        case manufacturerName = "manufacturername"
    }
}
