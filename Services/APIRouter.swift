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
            return "FlightAware API key missing. Add it in Settings."
        case .invalidURL:
            return "Failed to construct API URL."
        case .invalidResponse:
            return "Unexpected response from API."
        case .httpStatus(let code):
            return "API returned HTTP \(code)."
        case .allProvidersFailed:
            return "No data sources are available."
        }
    }
}

/// Routes aircraft requests to the configured primary provider (FlightAware) and falls back
/// to OpenSky if the primary fails (e.g. exhausted free credits, missing key, network error).
/// Lives at the app level so views just talk to one thing.
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
        var attemptedAtLeastOne = false

        if settings.useFlightAware, !settings.flightAwareApiKey.isEmpty {
            attemptedAtLeastOne = true
            let provider = FlightAwareService(apiKey: settings.flightAwareApiKey)
            do {
                let result = try await provider.fetchAircraft(near: center, radiusMeters: radiusMeters)
                lastUsedProvider = "FlightAware"
                lastError = nil
                return result
            } catch {
                lastError = "FlightAware: \(error.localizedDescription)"
            }
        }

        if settings.useOpenSkyFallback || !settings.useFlightAware {
            attemptedAtLeastOne = true
            let provider = OpenSkyService(
                username: settings.openSkyUsername,
                password: settings.openSkyPassword
            )
            do {
                let result = try await provider.fetchAircraft(near: center, radiusMeters: radiusMeters)
                lastUsedProvider = "OpenSky"
                lastError = nil
                return result
            } catch {
                lastError = "OpenSky: \(error.localizedDescription)"
            }
        }

        guard attemptedAtLeastOne else {
            throw AircraftDataError.allProvidersFailed
        }
        throw AircraftDataError.allProvidersFailed
    }
}
