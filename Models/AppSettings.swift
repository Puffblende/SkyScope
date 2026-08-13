import Foundation
import SwiftUI

/// Unit preference for altitude.
enum AltitudeUnit: String, CaseIterable, Identifiable, Codable {
    case feet
    case meters

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feet: "Feet (ft)"
        case .meters: "Meters (m)"
        }
    }

    var shortLabel: String {
        switch self {
        case .feet: "ft"
        case .meters: "m"
        }
    }
}

/// Unit preference for speed.
enum SpeedUnit: String, CaseIterable, Identifiable, Codable {
    case knots
    case kmh
    case mph

    var id: String { rawValue }

    var label: String {
        switch self {
        case .knots: "Knots (kts)"
        case .kmh: "Kilometers/hour (km/h)"
        case .mph: "Miles/hour (mph)"
        }
    }

    var shortLabel: String {
        switch self {
        case .knots: "kts"
        case .kmh: "km/h"
        case .mph: "mph"
        }
    }
}

/// Unit preference for distance (radius).
enum DistanceUnit: String, CaseIterable, Identifiable, Codable {
    case kilometers
    case nauticalMiles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kilometers: "Kilometers (km)"
        case .nauticalMiles: "Nautical Miles (NM)"
        }
    }

    var shortLabel: String {
        switch self {
        case .kilometers: "km"
        case .nauticalMiles: "NM"
        }
    }
}

/// User-configurable refresh interval in seconds.
enum RefreshInterval: Int, CaseIterable, Identifiable, Codable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        }
    }
}

/// User-selectable color scheme.
enum AppColorScheme: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Bridge to SwiftUI's preferredColorScheme. nil = follow system.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// User-selectable map style.
enum MapStyleOption: String, CaseIterable, Identifiable, Codable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
        }
    }
}

/// Single source of truth for user preferences.
///
/// IMPORTANT: properties must be **stored** for `@Observable` to track them. Computed
/// properties over UserDefaults don't fire SwiftUI updates, so we keep stored fields
/// here and write through to UserDefaults via `didSet` for persistence.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private enum Keys {
        static let radiusValue = "settings.radius.value"
        static let distanceUnit = "settings.distance.unit"
        static let altitudeUnit = "settings.altitude.unit"
        static let speedUnit = "settings.speed.unit"
        static let refreshInterval = "settings.refresh.interval"
        static let liveActivityOnLaunch = "settings.liveActivity.launchOnStartup"
        static let openSkyUsername = "settings.api.openSkyUsername"
        static let openSkyPassword = "settings.api.openSkyPassword"
        static let colorScheme = "settings.appearance.colorScheme"
        static let mapStyle = "settings.appearance.mapStyle"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var radiusValue: Double {
        didSet { defaults.set(radiusValue, forKey: Keys.radiusValue) }
    }

    var distanceUnit: DistanceUnit {
        didSet { defaults.set(distanceUnit.rawValue, forKey: Keys.distanceUnit) }
    }

    var altitudeUnit: AltitudeUnit {
        didSet { defaults.set(altitudeUnit.rawValue, forKey: Keys.altitudeUnit) }
    }

    var speedUnit: SpeedUnit {
        didSet { defaults.set(speedUnit.rawValue, forKey: Keys.speedUnit) }
    }

    var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval) }
    }

    var launchLiveActivityOnStartup: Bool {
        didSet { defaults.set(launchLiveActivityOnStartup, forKey: Keys.liveActivityOnLaunch) }
    }

    var openSkyUsername: String {
        didSet { defaults.set(openSkyUsername, forKey: Keys.openSkyUsername) }
    }

    var openSkyPassword: String {
        didSet { defaults.set(openSkyPassword, forKey: Keys.openSkyPassword) }
    }

    var colorScheme: AppColorScheme {
        didSet { defaults.set(colorScheme.rawValue, forKey: Keys.colorScheme) }
    }

    var mapStyle: MapStyleOption {
        didSet { defaults.set(mapStyle.rawValue, forKey: Keys.mapStyle) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.radiusValue = (defaults.object(forKey: Keys.radiusValue) as? Double) ?? 50.0
        self.distanceUnit = DistanceUnit(rawValue: defaults.string(forKey: Keys.distanceUnit) ?? "") ?? .nauticalMiles
        self.altitudeUnit = AltitudeUnit(rawValue: defaults.string(forKey: Keys.altitudeUnit) ?? "") ?? .feet
        self.speedUnit = SpeedUnit(rawValue: defaults.string(forKey: Keys.speedUnit) ?? "") ?? .knots
        self.refreshInterval = RefreshInterval(rawValue: defaults.integer(forKey: Keys.refreshInterval)) ?? .twoMinutes
        self.launchLiveActivityOnStartup = (defaults.object(forKey: Keys.liveActivityOnLaunch) as? Bool) ?? true
        self.openSkyUsername = defaults.string(forKey: Keys.openSkyUsername) ?? ""
        self.openSkyPassword = defaults.string(forKey: Keys.openSkyPassword) ?? ""
        self.colorScheme = AppColorScheme(rawValue: defaults.string(forKey: Keys.colorScheme) ?? "") ?? .system
        self.mapStyle = MapStyleOption(rawValue: defaults.string(forKey: Keys.mapStyle) ?? "") ?? .standard
    }

    /// Radius converted to meters for API queries and map overlay rendering.
    var radiusInMeters: Double {
        switch distanceUnit {
        case .kilometers: return radiusValue * 1_000
        case .nauticalMiles: return radiusValue * 1_852
        }
    }
}

/// Unit conversion helpers used at the view layer.
enum UnitFormat {
    static func altitude(meters: Double?, unit: AltitudeUnit) -> String {
        guard let meters else { return "—" }
        switch unit {
        case .feet:
            return "\(Int(meters * 3.28084).formatted()) ft"
        case .meters:
            return "\(Int(meters).formatted()) m"
        }
    }

    static func speed(mps: Double?, unit: SpeedUnit) -> String {
        guard let mps else { return "—" }
        switch unit {
        case .knots:
            return "\(Int(mps * 1.94384).formatted()) kts"
        case .kmh:
            return "\(Int(mps * 3.6).formatted()) km/h"
        case .mph:
            return "\(Int(mps * 2.23694).formatted()) mph"
        }
    }

    static func distance(meters: Double, unit: DistanceUnit) -> String {
        switch unit {
        case .kilometers:
            return String(format: "%.1f km", meters / 1_000)
        case .nauticalMiles:
            return String(format: "%.1f NM", meters / 1_852)
        }
    }

    static func heading(_ degrees: Double?) -> String {
        guard let degrees else { return "—" }
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let compass = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalized + 22.5) / 45.0) % 8
        return "\(Int(normalized))° \(compass[index])"
    }
}
