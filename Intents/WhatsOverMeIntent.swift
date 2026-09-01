import AppIntents
import CoreLocation
import Foundation

/// Siri / Shortcuts entrypoint: "Hey Siri, what's flying over me?"
/// Reduces the radius to 10 km for a quick scan and returns a spoken sentence.
struct WhatsOverMeIntent: AppIntent {
    static var title: LocalizedStringResource = "What's flying over me?"
    static var description = IntentDescription(
        "Lists aircraft currently within 10 km of your location.",
        categoryName: "Aircraft"
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = SettingsStore.shared
        let location = LocationService()
        location.startUpdating()

        // Wait briefly for a fix (Siri context has no UI to gate on permissions).
        let userCoordinate = try await waitForLocation(from: location)

        let router = APIRouter(settings: settings)
        let aircraft = (try? await router.fetch(near: userCoordinate, radiusMeters: 10_000)) ?? []

        let dialog = await Self.makeDialog(for: aircraft, near: userCoordinate, settings: settings)
        return .result(dialog: dialog)
    }

    private func waitForLocation(from service: LocationService) async throws -> CLLocationCoordinate2D {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let coord = await MainActor.run(body: { service.currentLocation?.coordinate }) {
                return coord
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw IntentError.noLocation
    }

    private static func makeDialog(for aircraft: [Aircraft], near coord: CLLocationCoordinate2D, settings: SettingsStore) async -> IntentDialog {
        guard !aircraft.isEmpty else {
            return IntentDialog("There are no aircraft within 10 kilometers right now.")
        }
        let sorted = await MainActor.run {
            aircraft.sorted { $0.distance(to: coord) < $1.distance(to: coord) }
        }
        let count = sorted.count
        guard let nearest = sorted.first else {
            return IntentDialog("There are no aircraft within 10 kilometers right now.")
        }

        var sentence = "There \(count == 1 ? "is" : "are") \(count) aircraft within 10 kilometers. "
        let name = nearest.airline ?? nearest.aircraftType ?? "An aircraft"
        let callsign = nearest.callsign.map { ", flight \($0)" } ?? ""
        let route: String
        switch (nearest.originAirport, nearest.destinationAirport) {
        case let (origin?, destination?):
            route = ", from \(origin) to \(destination)"
        default:
            route = ""
        }
        let unit = await MainActor.run { settings.altitudeUnit }
        let altitude = await UnitFormat.altitude(meters: nearest.altitudeMeters, unit: unit)
        sentence += "The closest is \(name)\(callsign)\(route), at \(altitude)."
        return IntentDialog(stringLiteral: sentence)
    }

    enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
        case noLocation

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .noLocation: "I couldn't determine your location."
            }
        }
    }
}

/// Surface the intent in the Shortcuts gallery.
struct ChocksShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsOverMeIntent(),
            phrases: [
                "What's flying over me in \(.applicationName)?",
                "Aircraft nearby in \(.applicationName)",
                "Ask \(.applicationName) what's overhead"
            ],
            shortTitle: "What's overhead",
            systemImageName: "airplane"
        )
    }
}
