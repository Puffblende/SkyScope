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

        // Pre-filter to states inside the radius so we only enrich what we'll display.
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var candidates: [(state: OpenSkyState, distance: CLLocationDistance)] = []
        for state in states {
            guard let lat = state.latitude, let lon = state.longitude else { continue }
            guard !state.icao24.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let distance = CLLocation(latitude: lat, longitude: lon).distance(from: centerLocation)
            if distance <= radiusMeters {
                candidates.append((state, distance))
            }
        }

        // Fetch OpenSky metadata + ADSBDB aircraft info in parallel for every candidate.
        let icao24List = candidates.map { $0.state.icao24.trimmingCharacters(in: .whitespaces) }
        async let openSkyMeta = fetchAllMetadata(for: icao24List)
        async let adsbdbMeta = fetchAllAdsbdbInfo(for: icao24List)
        let (osResults, adsbResults) = await (openSkyMeta, adsbdbMeta)

        var aircraftList: [Aircraft] = []
        for (state, _) in candidates {
            let icao24 = state.icao24.trimmingCharacters(in: .whitespaces)
            let openSky = osResults[icao24] ?? nil
            let adsb = adsbResults[icao24] ?? nil

            let callsign = state.callsign?.trimmingCharacters(in: .whitespaces)
            let registration = openSky?.registration ?? adsb?.registration
            let typeCode = openSky?.typecode ?? adsb?.typeCode
            let airline = extractAirlineFromCallsign(callsign) ?? adsb?.operatorName ?? openSky?.manufacturerName

            let lastUpdate: Date
            if let lastContact = state.lastContact {
                lastUpdate = Date(timeIntervalSince1970: TimeInterval(lastContact))
            } else {
                lastUpdate = timestamp
            }

            let altitudeMeters = state.baroAltitude ?? state.geoAltitude

            let ac = Aircraft(
                id: icao24,
                registration: registration,
                callsign: callsign?.isEmpty == false ? callsign : nil,
                airline: airline,
                aircraftType: typeCode,
                coordinate: CLLocationCoordinate2D(latitude: state.latitude ?? 0, longitude: state.longitude ?? 0),
                altitudeMeters: altitudeMeters,
                groundSpeedMps: state.velocity,
                headingDegrees: state.trueTrack,
                originAirport: nil,
                destinationAirport: nil,
                squawk: state.squawk,
                onGround: state.onGround,
                lastUpdate: lastUpdate
            )
            aircraftList.append(ac)
        }

        await enrichWithRoutes(aircraftList: &aircraftList)
        return aircraftList
    }

    private func fetchAllAdsbdbInfo(for icao24List: [String]) async -> [String: AdsbdbService.AircraftInfo?] {
        var results: [String: AdsbdbService.AircraftInfo?] = [:]
        await withTaskGroup(of: (String, AdsbdbService.AircraftInfo?).self) { group in
            for icao24 in icao24List {
                guard !icao24.isEmpty else { continue }
                group.addTask {
                    let info = await self.adsbdbService.fetchAircraftInfo(icao24: icao24)
                    return (icao24, info)
                }
            }
            for await (icao24, info) in group {
                results[icao24] = info
            }
        }
        return results
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

    private func fetchAllMetadata(for icao24List: [String]) async -> [String: OpenSkyAircraftMetadata?] {
        var results: [String: OpenSkyAircraftMetadata?] = [:]

        await withTaskGroup(of: (String, OpenSkyAircraftMetadata?).self) { group in
            for icao24 in icao24List {
                guard !icao24.isEmpty else { continue }
                group.addTask {
                    let metadata = try? await self.fetchMetadata(for: icao24)
                    return (icao24, metadata)
                }
            }

            for await (icao24, metadata) in group {
                results[icao24] = metadata
            }
        }

        return results
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
        "TOM": "TUI Airways",
        "EIN": "Aer Lingus",
        "THY": "Turkish Airlines",
        "QTR": "Qatar Airways",
        "ETD": "Etihad Airways",
        "DLV": "DHL Aviation",
        "UPS": "UPS Airlines",
        "FDX": "FedEx Express",
        "SAS": "Scandinavian Airlines",
        "FIN": "Finnair",
        "AUA": "Austrian Airlines",
        "BEL": "Brussels Airlines",
        "VLG": "Vueling",
        "NAX": "Norwegian Air",
        "WUK": "Wizz Air UK",
        "EXS": "Jet2",
        "TCX": "TUI Airways",
        "MON": "Monarch Airlines",
        "TFL": "Arkefly",
        "SWN": "West Air Sweden",
    ]
}

// MARK: - Wire format

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
    let squawk: String?
    let geoAltitude: Double?

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        // Index 0: icao24
        self.icao24 = try container.decode(String.self)
        // Index 1: callsign
        self.callsign = try? container.decode(String?.self)
        // Index 2: origin country
        self.originCountry = (try? container.decode(String.self)) ?? ""
        // Index 3: time position
        self.timePosition = try? container.decode(Int?.self)
        // Index 4: last contact
        self.lastContact = try? container.decode(Int?.self)
        // Index 5: longitude
        self.longitude = try? container.decode(Double?.self)
        // Index 6: latitude
        self.latitude = try? container.decode(Double?.self)
        // Index 7: baro altitude (meters)
        self.baroAltitude = try? container.decode(Double?.self)
        // Index 8: on ground
        self.onGround = (try? container.decode(Bool.self)) ?? false
        // Index 9: velocity (m/s)
        self.velocity = try? container.decode(Double?.self)
        // Index 10: true track
        self.trueTrack = try? container.decode(Double?.self)
        // Index 11: vertical rate
        self.verticalRate = try? container.decode(Double?.self)
        // Index 12: sensors (skip)
        _ = try? container.decode(AnyDecodable.self)
        // Index 13: geo altitude (meters)
        self.geoAltitude = try? container.decode(Double?.self)
        // Index 14: squawk (String)
        let rawSquawk = try? container.decode(String?.self)
        self.squawk = rawSquawk?.isEmpty == false ? rawSquawk : nil
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
