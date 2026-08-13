import Foundation
import CoreLocation

actor AirportCoordinatesService {
    static let shared = AirportCoordinatesService()
    private var cache: [String: CLLocationCoordinate2D] = [:]
    private init() {}
    
    func coordinates(for icaoCode: String) async -> CLLocationCoordinate2D? {
        if let cached = cache[icaoCode] { return cached }
        
        // Free GitHub Pages API - no key needed
        let code = icaoCode.lowercased()
        guard let url = URL(string:
            "https://ryanburnette.github.io/airports-api/icao/\(code).json")
        else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let airport = try JSONDecoder().decode(AirportResponse.self, from: data)
            let coord = CLLocationCoordinate2D(
                latitude: airport.latitude,
                longitude: airport.longitude
            )
            cache[icaoCode] = coord
            print("[AIRPORT] Fetched \(icaoCode): \(airport.latitude), \(airport.longitude)")
            return coord
        } catch {
            print("[AIRPORT] Failed \(icaoCode): \(error.localizedDescription)")
            return nil
        }
    }
}

private struct AirportResponse: Decodable {
    let latitude: Double
    let longitude: Double
}
