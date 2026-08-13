import Foundation
import CoreLocation

actor AirportCoordinatesService {
    static let shared = AirportCoordinatesService()

    private var cache: [String: CLLocationCoordinate2D] = [:]

    init() {}


    func coordinates(for icaoCode: String) async -> CLLocationCoordinate2D? {
        let code = icaoCode.uppercased()

        // Check cache first
        if let cached = cache[code] {
            return cached
        }

        // Try to fetch from API
        let coordinates = await fetchFromAPI(code: code)
        if let coordinates = coordinates {
            cache[code] = coordinates
        }

        return coordinates
    }

    private func fetchFromAPI(code: String) async -> CLLocationCoordinate2D? {
        let urlString = "https://api.api-ninjas.com/v1/airports?icao=\(code)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode([AirportResponse].self, from: data)

            guard let airport = response.first else { return nil }
            return CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude)
        } catch {
            // Silent failure as requested
            return nil
        }
    }
}

// MARK: - JSON Response Model

private struct AirportResponse: Codable {
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
}
