import Foundation

/// ADSBDB route lookup service.
/// Fetches origin/destination airports from https://api.adsbdb.com based on callsign.
struct AdsbdbService {
    private let baseURL = URL(string: "https://api.adsbdb.com/v0")!
    private let session: URLSession
    private static var routeCache: [String: RouteInfo] = [:]
    private static var lastRequestTime: Date = Date.distantPast

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
