import SwiftUI
import SwiftData
import CoreLocation

/// Bottom sheet shown when an aircraft is tapped on the map or in the list.
/// `showMapNavigationButton` controls whether the "Show on Map" action appears — it
/// should be hidden when the sheet is already presented from the map itself.
struct AircraftDetailSheet: View {
    let aircraft: Aircraft
    let userLocation: CLLocationCoordinate2D?
    var showMapNavigationButton: Bool = true

    @Environment(SettingsStore.self) private var settings
    @Environment(NavigationCoordinator.self) private var navigation
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var favorites: [Favorite]

    private var isFavorite: Bool {
        guard let reg = aircraft.registration?.uppercased() else { return false }
        return favorites.contains { $0.registration == reg }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "airplane")
                            .font(.system(size: 36))
                            .rotationEffect(.degrees((aircraft.headingDegrees ?? 0) - 90))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(aircraft.displayName)
                                .font(.title2.bold())
                            if let airline = aircraft.airline {
                                Text(airline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }

                // Show-on-Map action — only valuable when this sheet was opened from somewhere other than the map.
                if showMapNavigationButton {
                    Section {
                        Button {
                            navigation.showOnMap(aircraft)
                            dismiss()
                        } label: {
                            Label("Show on Map", systemImage: "map.fill")
                        }
                    }
                }

                Section("Route") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("From").font(.caption).foregroundStyle(.secondary)
                            Text(aircraft.originAirport ?? "—").font(.headline)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("To").font(.caption).foregroundStyle(.secondary)
                            Text(aircraft.destinationAirport ?? "—").font(.headline)
                        }
                    }
                }

                Section("Telemetry") {
                    detailRow(label: "Altitude", value: UnitFormat.altitude(meters: aircraft.altitudeMeters, unit: settings.altitudeUnit))
                    detailRow(label: "Speed", value: UnitFormat.speed(mps: aircraft.groundSpeedMps, unit: settings.speedUnit))
                    detailRow(label: "Heading", value: UnitFormat.heading(aircraft.headingDegrees))
                    if let userLocation {
                        detailRow(label: "Distance", value: UnitFormat.distance(meters: aircraft.distance(to: userLocation), unit: settings.distanceUnit))
                    }
                }

                Section("Aircraft") {
                    detailRow(label: "Type", value: aircraft.aircraftType ?? "—")
                    detailRow(label: "Registration", value: aircraft.registration ?? "—")
                    detailRow(label: "ICAO24", value: aircraft.id)
                    detailRow(label: "Status", value: aircraft.onGround ? "On Ground" : "Airborne")
                }
            }
            .navigationTitle(aircraft.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if aircraft.registration != nil {
                        Button {
                            toggleFavorite()
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .foregroundStyle(isFavorite ? .yellow : .accentColor)
                        }
                        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                    }
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }

    private func toggleFavorite() {
        guard let reg = aircraft.registration?.uppercased() else { return }
        if let existing = favorites.first(where: { $0.registration == reg }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(Favorite(registration: reg))
        }
        try? modelContext.save()
    }
}
