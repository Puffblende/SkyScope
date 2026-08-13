import Foundation
import Observation
import CoreLocation

/// Lightweight cross-tab navigation state. Allows the detail sheet to ask the Map tab
/// to focus on a specific aircraft (and switch tabs along the way).
@MainActor
@Observable
final class NavigationCoordinator {
    enum Tab: Hashable {
        case map, list, favorites, settings
    }

    var selectedTab: Tab = .map

    /// When non-nil, the MapView should pan/zoom to this aircraft on next render
    /// and present its detail sheet. The MapView clears it after consuming.
    var pendingFocus: Aircraft?

    /// Set when the user taps the Live Activity. MapView resolves this callsign against
    /// the aircraft list and opens the detail sheet. Cleared after the match is consumed.
    /// Survives across aircraft list refreshes so cold-launch timing works correctly.
    var pendingDeepLinkCallsign: String?

    func showOnMap(_ aircraft: Aircraft) {
        pendingFocus = aircraft
        selectedTab = .map
    }

    /// Called from onOpenURL. Parses `skyscope://aircraft/<callsign>` URLs produced
    /// by the Live Activity widget tap and stores the callsign for MapView to consume.
    func handleOpenURL(_ url: URL) {
        guard url.scheme == "skyscope", url.host == "aircraft" else { return }
        let raw = url.lastPathComponent
        guard !raw.isEmpty else { return }
        pendingDeepLinkCallsign = raw.removingPercentEncoding ?? raw
        selectedTab = .map
    }
}
