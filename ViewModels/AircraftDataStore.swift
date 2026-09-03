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
    /// Set by ChocksApp.init() so AppDelegate's BGTask handler can call refresh().
    static weak var shared: AircraftDataStore?

    private(set) var aircraft: [Aircraft] = []
    private(set) var isLoading: Bool = false
    private(set) var lastFetchAt: Date?
    private(set) var lastError: String?
    /// True while the app is in the foreground; controls the polling interval.
    var isForeground: Bool = true

    private let router: APIRouter
    private let settings: SettingsStore
    private let location: LocationService
    private let follow: FollowStore
    private var pollingTask: Task<Void, Never>?

    /// Kept in sync by ContentView.onChange(of: favorites) so background refresh
    /// can resolve the activity target without touching SwiftData from outside a view.
    var cachedFavorites: [Favorite] = []

    init(router: APIRouter, settings: SettingsStore, location: LocationService, follow: FollowStore) {
        self.router = router
        self.settings = settings
        self.location = location
        self.follow = follow

        // When the device moves while a Live Activity is running, trigger an immediate
        // refresh so the Lock Screen card reflects the latest aircraft positions.
        // LocationService throttles this callback to the configured refresh interval.
        location.onLocationUpdate = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, LiveActivityManager.shared.isRunning else { return }
                await self.refresh()
            }
        }
    }

    /// Starts the polling loop and begins tracking the Live Activity state to manage
    /// background location updates automatically. Re-entrant safe.
    func startPolling() {
        pollingTask?.cancel()
        let configured = Double(settings.refreshInterval.rawValue)
        let effectiveInterval = isForeground ? min(30, configured) : configured
        DebugStore.shared.log("🔄 Polling started · \(isForeground ? "foreground" : "background") · \(Int(effectiveInterval))s")
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let configured = Double(self?.settings.refreshInterval.rawValue ?? 120)
                // In foreground always poll at most every 30 s for fresher positions.
                let seconds = (self?.isForeground ?? true) ? min(30, configured) : configured
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
        // Start observing isRunning so background location follows Live Activity lifecycle.
        observeLiveActivityRunningState()
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        location.enableBackgroundUpdates(false)
    }

    /// One-shot refresh. Used by poll loop, pull-to-refresh, location callback, and Siri intent.
    func refresh() async {
        guard let coord = location.currentLocation?.coordinate else {
            lastError = "Waiting for location…"
            #if DEBUG
            print("[STORE] ⚠️ No location yet — skipping fetch")
            #endif
            DebugStore.shared.log("⚠️ No location — skipping fetch", isError: true)
            return
        }
        isLoading = true
        defer { isLoading = false }
        #if DEBUG
        print("[STORE] 🔄 Fetching near \(String(format: "%.4f", coord.latitude)), \(String(format: "%.4f", coord.longitude)) radius \(Int(settings.radiusInMeters / 1_000)) km")
        #endif
        do {
            let result = try await router.fetch(near: coord, radiusMeters: settings.radiusInMeters)
            let sortedResult = result.sorted { lhs, rhs in
                lhs.distance(to: coord) < rhs.distance(to: coord)
            }
            // Merge: preserve accumulated route/track data for already-known aircraft.
            let existingById = Dictionary(uniqueKeysWithValues: self.aircraft.map { ($0.id, $0) })
            self.aircraft = sortedResult.map { fresh in
                guard var existing = existingById[fresh.id] else { return fresh }
                existing.coordinate = fresh.coordinate
                existing.altitudeMeters = fresh.altitudeMeters
                existing.groundSpeedMps = fresh.groundSpeedMps
                existing.headingDegrees = fresh.headingDegrees
                existing.squawk = fresh.squawk
                existing.onGround = fresh.onGround
                existing.lastUpdate = fresh.lastUpdate
                if let c = fresh.callsign { existing.callsign = c }
                if let r = fresh.registration { existing.registration = r }
                if let a = fresh.airline { existing.airline = a }
                if let t = fresh.aircraftType { existing.aircraftType = t }
                if let o = fresh.originAirport { existing.originAirport = o }
                if let d = fresh.destinationAirport { existing.destinationAirport = d }
                return existing
            }
            self.lastFetchAt = .now
            self.lastError = nil
            let provider = router.lastUsedProvider ?? "?"
            #if DEBUG
            print("[STORE] ✅ \(self.aircraft.count) aircraft via \(provider)")
            #endif
            DebugStore.shared.log("✅ \(self.aircraft.count) aircraft · \(provider)")
            // Clear follow if that aircraft is no longer in range.
            if let followedId = follow.followedId,
               !self.aircraft.contains(where: { $0.id == followedId }) {
                follow.clear()
            }
            // Push Live Activity update from the model layer — runs in background-safe Task.
            if LiveActivityManager.shared.isRunning {
                let target = activityTarget(favorites: cachedFavorites)
                await LiveActivityManager.shared.update(target: target)
            }
        } catch {
            self.lastError = error.localizedDescription
            #if DEBUG
            print("[STORE] ❌ Fetch failed: \(error.localizedDescription)")
            #endif
            DebugStore.shared.log("❌ \(error.localizedDescription)", isError: true)
        }
    }

    /// Filters aircraft against the user's saved favorite registrations.
    func aircraftMatching(favorites: [Favorite]) -> [Aircraft] {
        let registrations = Set(favorites.map { $0.registration.uppercased() })
        return aircraft.filter { aircraft in
            guard let reg = aircraft.registration?.uppercased() else { return false }
            return registrations.contains(reg)
        }
    }

    /// Resolves the aircraft the Live Activity should currently display.
    /// Priority: **Follow > Favorite > Nearest**. Nil when no aircraft are in range.
    func activityTarget(favorites: [Favorite]) -> Aircraft? {
        // 1. Follow — the user pinned a specific aircraft.
        if let followedId = follow.followedId,
           let followed = aircraft.first(where: { $0.id == followedId }) {
            return followed
        }
        // 2. Favorite — the nearest favorited registration currently in radius.
        let matched = aircraftMatching(favorites: favorites)
        if let userCoord = location.currentLocation?.coordinate {
            if let nearestFav = matched.min(by: { $0.distance(to: userCoord) < $1.distance(to: userCoord) }) {
                return nearestFav
            }
            // 3. Nearest — the closest aircraft in the fetched set.
            return aircraft.min(by: { $0.distance(to: userCoord) < $1.distance(to: userCoord) })
        }
        return matched.first ?? aircraft.first
    }

    // MARK: - Background location management

    /// Uses withObservationTracking to watch LiveActivityManager.isRunning.
    /// Enables background location updates while the activity is live so that iOS keeps
    /// the app process running and the polling Task continues executing in the background.
    /// Re-registers itself after each change so tracking stays continuous.
    private func observeLiveActivityRunningState() {
        withObservationTracking {
            let isRunning = LiveActivityManager.shared.isRunning
            location.enableBackgroundUpdates(isRunning)
        } onChange: {
            // onChange fires on an arbitrary thread — re-register on MainActor.
            Task { @MainActor [weak self] in
                self?.observeLiveActivityRunningState()
            }
        }
    }
}
