import Foundation
import SwiftData

/// A favorited aircraft registration tracked by the user.
/// Persisted via SwiftData so we can extend with metadata later (notes, photos, etc.).
@Model
final class Favorite {
    /// The aircraft registration, stored uppercased and trimmed, e.g. "D-EVGK".
    @Attribute(.unique) var registration: String

    /// Optional human-readable label, e.g. "Vereinsmaschine".
    var label: String?

    /// When the user added this favorite.
    var createdAt: Date

    /// Last time we observed this favorite in the sky. Nil means never seen.
    var lastSeenInTheAir: Date?

    init(registration: String, label: String? = nil) {
        self.registration = registration.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = label
        self.createdAt = .now
        self.lastSeenInTheAir = nil
    }
}
