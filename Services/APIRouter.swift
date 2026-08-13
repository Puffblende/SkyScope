import Foundation
import CoreLocation
import Observation

/// Protocol implemented by every upstream data source.
protocol AircraftDataProvider: Sendable {
    func fetchAircraft(near center: CLLocationCoordinate2D, radiusMeters: Double) async throws -> [Aircraft]
}

/// Errors thrown by data providers. Reasoned about by the router for fallback decisions.
enum AircraftDataError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case allProvidersFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key missing."
        case .invalidURL:
            return "Failed to construct API URL."
        case .invalidResponse:
            return "Unexpected response from API."
        case .httpStatus(let code):
            return "API returned HTTP \(code)."
        case .allProvidersFailed:
            return "No data sources available — check your connection."
        }
    }
}

/// Routes aircraft position requests to the appropriate provider.
///
/// - Primary:   airplanes.live (free community ADS-B, no key required)
/// - Secondary: adsb.lol      (identical JSON format, independent community feed)
/// - Fallback:  OpenSky Network (free, optional credentials for higher rate limits)
@MainActor
@Observable
final class APIRouter {
    private(set) var lastUsedProvider: String?
    private(set) var lastError: String?

    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func fetch(near center: CLLocationCoordinate2D, radiusMeters: Double) async throws -> [Aircraft] {
        // Primary: airplanes.live
        do {
            let result = try await AirplanesLiveService(baseURL: "https://api.airplanes.live/v2/point")
                .fetchAircraft(near: center, radiusMeters: radiusMeters)
            lastUsedProvider = "airplanes.live"
            lastError = nil
            return result
        } catch {
            print("[ROUTER] airplanes.live failed: \(error)")
        }

        // Secondary: adsb.lol — identical JSON format, independent community feed
        do {
            let result = try await AirplanesLiveService(baseURL: "https://api.adsb.lol/v2/point")
                .fetchAircraft(near: center, radiusMeters: radiusMeters)
            lastUsedProvider = "adsb.lol"
            lastError = nil
            return result
        } catch {
            print("[ROUTER] adsb.lol failed: \(error)")
        }

        // Fallback: OpenSky Network
        let openSky = OpenSkyService(
            username: settings.openSkyUsername.isEmpty ? nil : settings.openSkyUsername,
            password: settings.openSkyPassword.isEmpty ? nil : settings.openSkyPassword
        )
        do {
            let result = try await openSky.fetchAircraft(near: center, radiusMeters: radiusMeters)
            lastUsedProvider = "OpenSky"
            lastError = nil
            return result
        } catch {
            print("[ROUTER] OpenSky failed: \(error)")
            lastError = "OpenSky: \(error.localizedDescription)"
        }

        throw AircraftDataError.allProvidersFailed
    }
}
