import SwiftUI
import SwiftData
import CoreLocation

/// Tab 2 — all aircraft in the configured radius sorted by distance.
struct ListView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LocationService.self) private var location
    @Environment(AircraftDataStore.self) private var dataStore
    @Query private var favorites: [Favorite]

    @State private var selectedAircraft: Aircraft?
    @State private var silhouetteAircraft: Aircraft?

    private var favoriteRegistrations: Set<String> {
        Set(favorites.map { $0.registration })
    }

    var body: some View {
        NavigationStack {
            Group {
                if dataStore.aircraft.isEmpty {
                    ContentUnavailableView {
                        Label("No aircraft", systemImage: "airplane.circle")
                    } description: {
                        Text("Pull to refresh or expand your search radius in Settings.")
                    }
                } else {
                    List(dataStore.aircraft) { aircraft in
                        Button {
                            selectedAircraft = aircraft
                        } label: {
                            aircraftRow(aircraft)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .refreshable {
                await dataStore.refresh()
            }
            .navigationTitle("Aircraft Nearby")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if dataStore.isLoading {
                        ProgressView()
                    }
                }
            }
            .sheet(item: $selectedAircraft) { aircraft in
                AircraftDetailSheet(
                    aircraft: aircraft,
                    userLocation: location.currentLocation?.coordinate
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $silhouetteAircraft) { aircraft in
                AircraftSilhouetteView(aircraftType: aircraft.aircraftType)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private func aircraftRow(_ aircraft: Aircraft) -> some View {
        let isFavorite = aircraft.registration.map { favoriteRegistrations.contains($0.uppercased()) } ?? false

        HStack(alignment: .top, spacing: 12) {
            Button {
                silhouetteAircraft = aircraft
            } label: {
                Image(systemName: "airplane")
                    .font(.title3)
                    .foregroundStyle(isFavorite ? .yellow : .accentColor)
                    .rotationEffect(.degrees((aircraft.headingDegrees ?? 0) - 90))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: .circle)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                // Title row: callsign + favorite indicator
                HStack(spacing: 6) {
                    Text(aircraft.displayName)
                        .font(.headline)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                    if let airline = aircraft.airline {
                        Text("· \(airline)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Route
                if let route = routeLabel(for: aircraft) {
                    Label(route, systemImage: "arrow.right")
                        .labelStyle(.titleOnly)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Metadata pills: type, registration
                HStack(spacing: 6) {
                    if let type = aircraft.aircraftType {
                        Button {
                            silhouetteAircraft = aircraft
                        } label: {
                            metadataPill(text: type, icon: "airplane.circle")
                        }
                        .buttonStyle(.plain)
                    }
                    if let reg = aircraft.registration {
                        metadataPill(text: reg, icon: nil)
                    }
                }

                // Telemetry
                HStack(spacing: 10) {
                    Label(UnitFormat.altitude(meters: aircraft.altitudeMeters, unit: settings.altitudeUnit), systemImage: "arrow.up")
                    Label(UnitFormat.speed(mps: aircraft.groundSpeedMps, unit: settings.speedUnit), systemImage: "speedometer")
                    Label(UnitFormat.heading(aircraft.headingDegrees), systemImage: "location.north")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 4)

            if let userCoord = location.currentLocation?.coordinate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(UnitFormat.distance(meters: aircraft.distance(to: userCoord), unit: settings.distanceUnit))
                        .font(.subheadline.bold().monospacedDigit())
                    Text("away")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func metadataPill(text: String, icon: String?) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).font(.caption2)
            }
            Text(text).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: .capsule)
    }

    private func routeLabel(for aircraft: Aircraft) -> String? {
        switch (aircraft.originAirport, aircraft.destinationAirport) {
        case let (origin?, destination?): return "\(origin) → \(destination)"
        case let (origin?, nil): return "\(origin) → ?"
        case let (nil, destination?): return "? → \(destination)"
        default: return nil
        }
    }
}
