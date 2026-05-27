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

    func showOnMap(_ aircraft: Aircraft) {
        pendingFocus = aircraft
        selectedTab = .map
    }
}
