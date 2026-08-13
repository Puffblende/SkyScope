import Foundation

/// ADSBDB lookup service.
/// - Route lookup by callsign: `/v0/callsign/{callsign}`
/// - Aircraft metadata lookup by mode-s (ICAO24): `/v0/aircraft/{modes}` — returns
///   manufacturer, ICAO type code, registration, and operator.
struct AdsbdbService {
    private let baseURL = URL(string: "https://api.adsbdb.com/v0")!
    private let session: URLSession
    private static var routeCache: [String: RouteInfo] = [:]
    private static var aircraftCache: [String: AircraftInfo] = [:]
    private static var aircraftNegativeCache: Set<String> = []
    private static var lastRequestTime: Date = Date.distantPast

    struct AircraftInfo: Sendable {
        let typeCode: String?
        let manufacturer: String?
        let registration: String?
        let operatorName: String?
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRoute(for callsign: String?) async -> (origin: String?, destination: String?)? {
        guard let callsign = callsign?.trimmingCharacters(in: .whitespaces), !callsign.isEmpty else {
            return nil
        }

        let key = callsign.uppercased()

        if let cached = Self.routeCache[key] {
            return (origin: cached.origin, destination: cached.destination)
        }

        await rateLimitDelay()

        return await fetchFromAPI(callsign: key)
    }

    /// Aircraft metadata lookup by ICAO24 (mode-s). Cached, rate-limited.
    /// Returns nil for airframes that have no ADSBDB entry.
    func fetchAircraftInfo(icao24: String?) async -> AircraftInfo? {
        guard let raw = icao24?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        let key = raw.uppercased()

        if let cached = Self.aircraftCache[key] {
            return cached
        }
        if Self.aircraftNegativeCache.contains(key) {
            return nil
        }

        await rateLimitDelay()

        let url = baseURL.appendingPathComponent("aircraft/\(key)")
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 404 { Self.aircraftNegativeCache.insert(key) }
                return nil
            }
            let decoded = try JSONDecoder().decode(AdsbdbAircraftResponse.self, from: data)
            guard let ac = decoded.response?.aircraft else {
                Self.aircraftNegativeCache.insert(key)
                return nil
            }
            let info = AircraftInfo(
                typeCode: ac.typeCode,
                manufacturer: ac.manufacturer,
                registration: ac.registration,
                operatorName: ac.registeredOwner
            )
            Self.aircraftCache[key] = info
            return info
        } catch {
            return nil
        }
    }

    private func fetchFromAPI(callsign: String) async -> (origin: String?, destination: String?)? {
        let url = baseURL.appendingPathComponent("callsign/\(callsign)")
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }

            let decoded = try JSONDecoder().decode(AdsbdbResponse.self, from: data)
            guard let flightroute = decoded.response?.flightroute else { return nil }

            let origin = flightroute.origin?.icaoCode ?? flightroute.origin?.iataCode
            let destination = flightroute.destination?.icaoCode ?? flightroute.destination?.iataCode

            let route = RouteInfo(origin: origin, destination: destination)
            Self.routeCache[callsign] = route

            return (origin: origin, destination: destination)
        } catch {
            return nil
        }
    }

    private func rateLimitDelay() async {
        let timeSinceLastRequest = Date().timeIntervalSince(Self.lastRequestTime)
        let minInterval: TimeInterval = 0.25

        if timeSinceLastRequest < minInterval {
            let delayNeeded = minInterval - timeSinceLastRequest
            try? await Task.sleep(nanoseconds: UInt64(delayNeeded * 1_000_000_000))
        }

        Self.lastRequestTime = Date()
    }

    private struct RouteInfo {
        let origin: String?
        let destination: String?
    }
}

// MARK: - Wire format

private struct AdsbdbResponse: Decodable {
    let response: AdsbdbFlightInfo?

    enum CodingKeys: String, CodingKey { case response }
}

private struct AdsbdbFlightInfo: Decodable {
    let flightroute: FlightRoute?

    enum CodingKeys: String, CodingKey { case flightroute }
}

private struct FlightRoute: Decodable {
    let origin: Airport?
    let destination: Airport?

    enum CodingKeys: String, CodingKey { case origin, destination }
}

private struct Airport: Decodable {
    let iataCode: String?
    let icaoCode: String?

    enum CodingKeys: String, CodingKey {
        case iataCode = "iata_code"
        case icaoCode = "icao_code"
    }
}

// MARK: - Aircraft info

private struct AdsbdbAircraftResponse: Decodable {
    let response: AdsbdbAircraftPayload?
    enum CodingKeys: String, CodingKey { case response }
}

private struct AdsbdbAircraftPayload: Decodable {
    let aircraft: AdsbdbAircraftEntity?
    enum CodingKeys: String, CodingKey { case aircraft }
}

private struct AdsbdbAircraftEntity: Decodable {
    /// ICAO type designator, e.g. "B738".
    let typeCode: String?
    let manufacturer: String?
    let registration: String?
    let registeredOwner: String?

    enum CodingKeys: String, CodingKey {
        case icaoType = "icao_type"
        case type
        case manufacturer
        case registration
        case registeredOwner = "registered_owner"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Prefer the compact ICAO type code — falls back to the long human name.
        let icao = try? container.decode(String.self, forKey: .icaoType)
        let long = try? container.decode(String.self, forKey: .type)
        self.typeCode = (icao?.isEmpty == false ? icao : nil) ?? long
        self.manufacturer = try? container.decode(String.self, forKey: .manufacturer)
        self.registration = try? container.decode(String.self, forKey: .registration)
        self.registeredOwner = try? container.decode(String.self, forKey: .registeredOwner)
    }
}
