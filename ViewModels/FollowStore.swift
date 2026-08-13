import Foundation
import Observation

/// Persists the aircraft the user is currently "following".
///
/// Priority when picking the target for the Live Activity is: **Follow > Favorite > Nearest**.
/// Only one aircraft can be followed at a time — setting a new follow clears the previous one.
/// The follow is auto-cleared when the aircraft leaves the search radius (handled by the data store).
@MainActor
@Observable
final class FollowStore {
    private enum Keys {
        static let followedId = "follow.aircraftId"
    }

    private let defaults: UserDefaults

    /// ICAO24 of the currently followed aircraft. Nil when nothing is followed.
    private(set) var followedId: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.followedId = defaults.string(forKey: Keys.followedId)
    }

    func isFollowing(_ aircraft: Aircraft) -> Bool {
        followedId == aircraft.id
    }

    /// Toggles follow for the given aircraft. If already following it, clears the follow instead.
    func toggle(_ aircraft: Aircraft) {
        if followedId == aircraft.id {
            clear()
        } else {
            followedId = aircraft.id
            defaults.set(aircraft.id, forKey: Keys.followedId)
        }
    }

    func clear() {
        followedId = nil
        defaults.removeObject(forKey: Keys.followedId)
    }
}
