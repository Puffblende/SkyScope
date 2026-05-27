import Foundation
import CoreLocation
import Observation
import SwiftData

/// Central observable store that owns the current aircraft list, runs polling on the
/// configured refresh interval, and re-fetches when the user moves or changes radius.
/// One instance lives at the app root and is shared across tabs.
@MainActor
@Observable
final class AircraftDataStore {
    private(set) var aircraft: [Aircraft] = []
    private(set) var isLoading: Bool = false
    private(set) var lastFetchAt: Date?
    private(set) var lastError: String?

    private let router: APIRouter
    private let settings: SettingsStore
    private let location: LocationService
    private var pollingTask: Task<Void, Never>?

    init(router: APIRouter, settings: SettingsStore, location: LocationService) {
        self.router = router
        self.settings = settings
        self.location = location
    }

    /// Starts the polling loop. Re-entrant safe.
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let seconds = self?.settings.refreshInterval.rawValue ?? 120
                try? await Task.sleep(for: .seconds(Double(seconds)))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// One-shot refresh. Used by pull-to-refresh and Siri intent.
    func refresh() async {
        guard let coord = location.currentLocation?.coordinate else {
            lastError = "Waiting for location…"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await router.fetch(near: coord, radiusMeters: settings.radiusInMeters)
            self.aircraft = result.sorted { lhs, rhs in
                lhs.distance(to: coord) < rhs.distance(to: coord)
            }
            self.lastFetchAt = .now
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Filters aircraft against the user's saved favorite registrations.
    /// Used by the Live Activity logic and Favorites tab.
    func aircraftMatching(favorites: [Favorite]) -> [Aircraft] {
        let registrations = Set(favorites.map { $0.registration.uppercased() })
        return aircraft.filter { aircraft in
            guard let reg = aircraft.registration?.uppercased() else { return false }
            return registrations.contains(reg)
        }
    }
}
