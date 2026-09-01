import Foundation
import Security
import SwiftUI
import UIKit

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

/// Which data pair to show in the Dynamic Island compact slot.
enum DynamicIslandCompactStyle: String, CaseIterable, Identifiable, Codable {
    case flightAndAltitude
    case proximity
    case approachCountdown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flightAndAltitude:  "Flight & Altitude"
        case .proximity:          "Proximity"
        case .approachCountdown:  "Approach Countdown"
        }
    }

    var subtitle: String {
        switch self {
        case .flightAndAltitude:  "Identifies the aircraft and its level at a glance"
        case .proximity:          "Answers \"is it near me yet?\" — the reason to glance at all"
        case .approachCountdown:  "Closest point of approach, so you know when to look up"
        }
    }
}

/// Which layout to use for the lock-screen Live Activity banner.
enum LockScreenLayoutStyle: String, CaseIterable, Identifiable, Codable {
    case telemetry
    case radar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .telemetry: "Telemetry"
        case .radar:     "Radar"
        }
    }

    var subtitle: String {
        switch self {
        case .telemetry: "ALT · SPD · HDG · SQK readout"
        case .radar:     "Scope view with distance and bearing"
        }
    }
}

/// Aircraft annotation badge style on the map.
enum BadgeStyle: String, CaseIterable, Identifiable, Codable {
    case solid
    case outline

    var id: String { rawValue }
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
        static let badgeStyle = "settings.appearance.badgeStyle"
        static let dynamicIslandStyle = "settings.liveActivity.diStyle"
        static let lockScreenStyle    = "settings.liveActivity.lockScreenStyle"
        static let coneColorHex       = "settings.appearance.coneColorHex"
        static let arModeEnabled      = "settings.ar.enabled"
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
        didSet {
            Self.setOpenSkyPassword(openSkyPassword)
            defaults.removeObject(forKey: Keys.openSkyPassword)
        }
    }

    var colorScheme: AppColorScheme {
        didSet { defaults.set(colorScheme.rawValue, forKey: Keys.colorScheme) }
    }

    var mapStyle: MapStyleOption {
        didSet { defaults.set(mapStyle.rawValue, forKey: Keys.mapStyle) }
    }

    var badgeStyle: BadgeStyle {
        didSet { defaults.set(badgeStyle.rawValue, forKey: Keys.badgeStyle) }
    }

    var dynamicIslandCompactStyle: DynamicIslandCompactStyle {
        didSet { defaults.set(dynamicIslandCompactStyle.rawValue, forKey: Keys.dynamicIslandStyle) }
    }

    var lockScreenLayoutStyle: LockScreenLayoutStyle {
        didSet { defaults.set(lockScreenLayoutStyle.rawValue, forKey: Keys.lockScreenStyle) }
    }

    var coneColorHex: String {
        didSet { defaults.set(coneColorHex, forKey: Keys.coneColorHex) }
    }

    var arModeEnabled: Bool {
        didSet { defaults.set(arModeEnabled, forKey: Keys.arModeEnabled) }
    }

    var coneColor: Color {
        get { Color(hex: coneColorHex) }
        set { coneColorHex = UIColor(newValue).hexString }
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
        let legacyOpenSkyPassword = defaults.string(forKey: Keys.openSkyPassword)
        let keychainOpenSkyPassword = Self.openSkyPasswordFromKeychain()
        if let legacyOpenSkyPassword,
           !legacyOpenSkyPassword.isEmpty,
           keychainOpenSkyPassword == nil {
            Self.setOpenSkyPassword(legacyOpenSkyPassword)
        }
        self.openSkyPassword = keychainOpenSkyPassword ?? legacyOpenSkyPassword ?? ""
        if legacyOpenSkyPassword != nil {
            defaults.removeObject(forKey: Keys.openSkyPassword)
        }
        self.colorScheme = AppColorScheme(rawValue: defaults.string(forKey: Keys.colorScheme) ?? "") ?? .system
        self.mapStyle = MapStyleOption(rawValue: defaults.string(forKey: Keys.mapStyle) ?? "") ?? .standard
        self.badgeStyle = BadgeStyle(rawValue: defaults.string(forKey: Keys.badgeStyle) ?? "") ?? .solid
        self.dynamicIslandCompactStyle = DynamicIslandCompactStyle(
            rawValue: defaults.string(forKey: Keys.dynamicIslandStyle) ?? "") ?? .flightAndAltitude
        self.lockScreenLayoutStyle = LockScreenLayoutStyle(
            rawValue: defaults.string(forKey: Keys.lockScreenStyle) ?? "") ?? .telemetry
        self.coneColorHex = defaults.string(forKey: Keys.coneColorHex) ?? "#FFFFFF"
        self.arModeEnabled = (defaults.object(forKey: Keys.arModeEnabled) as? Bool) ?? false
    }

    /// Radius converted to meters for API queries and map overlay rendering.
    var radiusInMeters: Double {
        switch distanceUnit {
        case .kilometers: return radiusValue * 1_000
        case .nauticalMiles: return radiusValue * 1_852
        }
    }

    private nonisolated static let keychainService = "com.chocks.openSky"
    private nonisolated static let legacyKeychainService = "DK.SkyScope"

    private static func openSkyPasswordKeychainQuery(service: String = keychainService) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Keys.openSkyPassword
        ]
    }

    private static func openSkyPasswordFromKeychain() -> String? {
        if let password = openSkyPasswordFromKeychain(service: keychainService) {
            return password
        }
        guard let legacyPassword = openSkyPasswordFromKeychain(service: legacyKeychainService) else {
            return nil
        }
        setOpenSkyPassword(legacyPassword)
        SecItemDelete(openSkyPasswordKeychainQuery(service: legacyKeychainService) as CFDictionary)
        return legacyPassword
    }

    private static func openSkyPasswordFromKeychain(service: String) -> String? {
        var query = openSkyPasswordKeychainQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data
        else { return nil }

        return String(data: data, encoding: .utf8)
    }

    private static func setOpenSkyPassword(_ password: String) {
        guard !password.isEmpty else {
            SecItemDelete(openSkyPasswordKeychainQuery() as CFDictionary)
            SecItemDelete(openSkyPasswordKeychainQuery(service: legacyKeychainService) as CFDictionary)
            return
        }

        let data = Data(password.utf8)
        let attributesToUpdate = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            openSkyPasswordKeychainQuery() as CFDictionary,
            attributesToUpdate as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var query = openSkyPasswordKeychainQuery()
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }
}

// MARK: - Color hex helpers

extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
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
