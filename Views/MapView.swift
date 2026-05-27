import SwiftUI
import MapKit
import SwiftData

/// Primary tab. Shows the user's location, search radius and nearby aircraft.
struct MapView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LocationService.self) private var location
    @Environment(AircraftDataStore.self) private var dataStore
    @Environment(NavigationCoordinator.self) private var navigation
    @Query private var favorites: [Favorite]

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedAircraft: Aircraft?
    @State private var hasAutoFramedOnFirstLoad = false

    // Tracks the live visible region so we can capture it before swapping to "radius view".
    @State private var currentVisibleRegion: MKCoordinateRegion?
    // When entering radius mode, snapshot what the user was looking at so we can restore it.
    @State private var preToggleRegion: MKCoordinateRegion?
    // True while the pill has zoomed out to show the full search radius.
    @State private var isRadiusModeActive = false

    private var favoriteRegistrations: Set<String> {
        Set(favorites.map { $0.registration })
    }

    private func isFavorite(_ aircraft: Aircraft) -> Bool {
        guard let reg = aircraft.registration?.uppercased() else { return false }
        return favoriteRegistrations.contains(reg)
    }

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                UserAnnotation()

                if let userCoord = location.currentLocation?.coordinate {
                    MapCircle(center: userCoord, radius: settings.radiusInMeters)
                        .foregroundStyle(Color.accentColor.opacity(0.10))
                        .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                }

                ForEach(dataStore.aircraft) { aircraft in
                    Annotation(
                        aircraft.displayName,
                        coordinate: aircraft.coordinate,
                        anchor: .center
                    ) {
                        AircraftAnnotation(
                            aircraft: aircraft,
                            isFavorite: isFavorite(aircraft)
                        )
                        .onTapGesture {
                            selectedAircraft = aircraft
                        }
                    }
                }
            }
            .mapStyle(mapStyleForSelection)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                currentVisibleRegion = context.region
            }
            .navigationTitle("SkyScope")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await dataStore.refresh() }
                    } label: {
                        if dataStore.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(dataStore.isLoading)
                }
            }
            .overlay(alignment: .top) {
                if let error = dataStore.lastError ?? location.lastError {
                    Text(error)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: .capsule)
                        .padding(.top, 6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                radiusPillButton
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .bottomTrailing) {
                mapStyleButton
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
            .sheet(item: $selectedAircraft) { aircraft in
                AircraftDetailSheet(
                    aircraft: aircraft,
                    userLocation: location.currentLocation?.coordinate,
                    showMapNavigationButton: false
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            // Frame camera to fit user + search radius once on first location fix.
            .onChange(of: location.currentLocation) { _, newValue in
                guard !hasAutoFramedOnFirstLoad, let coord = newValue?.coordinate else { return }
                frameRegionAroundUser(coord)
                hasAutoFramedOnFirstLoad = true
            }
            // Re-frame when radius changes so the user can see the new circle.
            .onChange(of: settings.radiusInMeters) { _, _ in
                if let coord = location.currentLocation?.coordinate {
                    frameRegionAroundUser(coord)
                }
            }
            // Handle deep-links from "Show on Map" in detail sheet. Pan only — do NOT auto-open sheet.
            .onChange(of: navigation.pendingFocus) { _, newValue in
                guard let target = newValue else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: target.coordinate,
                        latitudinalMeters: 15_000,
                        longitudinalMeters: 15_000
                    ))
                }
                navigation.pendingFocus = nil
            }
        }
    }

    /// Tappable pill: toggles between "show full search radius" and the user's previous zoom.
    private var radiusPillButton: some View {
        Button {
            toggleRadiusView()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isRadiusModeActive ? "arrow.up.left.and.arrow.down.right" : "scope")
                    .foregroundStyle(Color.accentColor)
                Text("\(dataStore.aircraft.count) in radius")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRadiusModeActive ? "Restore previous zoom" : "Show full search radius")
    }

    /// Map style selector menu button.
    private var mapStyleButton: some View {
        Menu {
            Button {
                settings.mapStyle = .standard
            } label: {
                Label("Standard", systemImage: "map")
            }
            Button {
                settings.mapStyle = .satellite
            } label: {
                Label("Satellit", systemImage: "globe")
            }
            Button {
                settings.mapStyle = .hybrid
            } label: {
                Label("Hybrid", systemImage: "map.fill")
            }
        } label: {
            Image(systemName: "map")
                .padding(10)
                .background(.thinMaterial, in: .circle)
        }
    }

    private func mapIconForStyle(_ style: MapStyleOption) -> String {
        switch style {
        case .standard: return "map"
        case .satellite: return "square.on.circle"
        case .hybrid: return "map.circle.fill"
        }
    }

    private func toggleRadiusView() {
        if isRadiusModeActive {
            // Restore the user's previous view.
            if let saved = preToggleRegion {
                withAnimation(.easeInOut(duration: 0.4)) {
                    cameraPosition = .region(saved)
                }
            }
            isRadiusModeActive = false
        } else {
            // Snapshot current view, then zoom out to show the entire search radius.
            preToggleRegion = currentVisibleRegion
            if let coord = location.currentLocation?.coordinate {
                frameRegionAroundUser(coord)
            }
            isRadiusModeActive = true
        }
    }

    private func frameRegionAroundUser(_ coord: CLLocationCoordinate2D) {
        // Show user + ~2x radius so the circle is comfortably visible.
        let span = max(settings.radiusInMeters * 2.5, 20_000)
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: coord,
                latitudinalMeters: span,
                longitudinalMeters: span
            ))
        }
    }

    private var mapStyleForSelection: MapStyle {
        switch settings.mapStyle {
        case .standard:
            MapStyle.standard(elevation: .realistic)
        case .satellite:
            MapStyle.imagery(elevation: .realistic)
        case .hybrid:
            MapStyle.hybrid(elevation: .realistic)
        }
    }
}

#Preview {
    MapView()
        .environment(SettingsStore.shared)
        .environment(LocationService())
        .environment(APIRouter(settings: SettingsStore.shared))
        .environment(NavigationCoordinator())
}
