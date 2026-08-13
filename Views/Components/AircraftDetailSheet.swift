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
    @Environment(FollowStore.self) private var follow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var favorites: [Favorite]

    @State private var showSilhouette = false
    @State private var showPhoto = false
    @State private var showFollowInfo = false

    private var isFavorite: Bool {
        guard let reg = aircraft.registration?.uppercased() else { return false }
        return favorites.contains { $0.registration == reg }
    }

    private var isFollowing: Bool {
        follow.isFollowing(aircraft)
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
                        if aircraft.registration != nil {
                            Button {
                                toggleFavorite()
                            } label: {
                                Image(systemName: isFavorite ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(isFavorite ? .yellow : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                        }
                    }
                }

                // Follow toggle — pins the Live Activity to this aircraft until it leaves the radius.
                Section {
                    HStack {
                        Button {
                            follow.toggle(aircraft)
                        } label: {
                            Label(
                                isFollowing ? "Following" : "Follow",
                                systemImage: isFollowing ? "location.fill" : "location"
                            )
                            .foregroundStyle(isFollowing ? Color.accentColor : .primary)
                        }
                        Spacer()
                        if isFollowing {
                            Text("Live Activity pinned")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            showFollowInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .popover(isPresented: $showFollowInfo, arrowEdge: .trailing) {
                            Text("Follow locks the Live Activity to this aircraft until it leaves your search radius. Priority order: Follow › Favorite › Nearest.")
                                .font(.callout)
                                .padding()
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                    .buttonStyle(.borderless)
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
                    if let aircraftType = aircraft.aircraftType {
                        Button {
                            showSilhouette = true
                        } label: {
                            HStack {
                                Text("Type").foregroundStyle(.secondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text(aircraftType).font(.body.monospacedDigit())
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.tint)
                            }
                        }
                    } else {
                        detailRow(label: "Type", value: "—")
                    }
                    if let reg = aircraft.registration {
                        Button {
                            showPhoto = true
                        } label: {
                            HStack {
                                Text("Registration").foregroundStyle(.secondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text(reg).font(.body.monospacedDigit())
                                    Image(systemName: "chevron.right").font(.caption2)
                                }
                                .foregroundStyle(.tint)
                            }
                        }
                    } else {
                        detailRow(label: "Registration", value: "—")
                    }
                    detailRow(label: "ICAO24", value: aircraft.id)
                    detailRow(label: "Status", value: aircraft.onGround ? "On Ground" : "Airborne")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSilhouette) {
                AircraftSilhouetteView(aircraftType: aircraft.aircraftType)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPhoto) {
                if let reg = aircraft.registration {
                    AircraftPhotoView(registration: reg)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
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
