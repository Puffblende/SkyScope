import SwiftUI
import MapKit
import SwiftData
import ActivityKit
import AVFoundation

// Reference-type camera state so continuous camera-change callbacks don't trigger SwiftUI re-renders.
private final class MapCameraState {
    var region: MKCoordinateRegion?
    var distance: CLLocationDistance = 8_000
    var heading: CLLocationDegrees = 0
}

/// Primary tab. Shows the user's location, search radius and nearby aircraft.
struct MapView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LocationService.self) private var location
    @Environment(AircraftDataStore.self) private var dataStore
    @Environment(NavigationCoordinator.self) private var navigation
    @Environment(FollowStore.self) private var follow
    @Environment(ARPermissionStore.self) private var arPermission
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var favorites: [Favorite]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedAircraft: Aircraft?
    @State private var hasAutoFramedOnFirstLoad = false

    // Tracks the aircraft whose sheet is open so we can restore the map center on dismiss.
    @State private var lastSheetAircraftID: String?
    // Zoom level captured when the sheet opens — kept constant during aircraft following.
    @State private var sheetSpan: MKCoordinateSpan?

    // Map feature states
    @State private var headingModeEnabled = false
    @State private var lastAppliedHeading: Double = -999
    @State private var compassHeading: Double = 0

    // Live camera state — updated continuously so tap-to-open always has the correct zoom.
    // Stored as a reference type so property mutations don't trigger view re-renders.
    @State private var cam = MapCameraState()

    // Non-nil while we're waiting to snap back to the user after they panned away in heading mode.
    // Heading-mode camera updates are suppressed while this task is pending.
    @State private var snapBackTask: Task<Void, Never>?

    // Weather overlay
    @State private var showWeather = false
    @State private var weather: WeatherData?
    @State private var weatherLoading = false
    @State private var showAR = false
    @State private var currentPlaceName: String?
    @State private var lastReverseGeocodedLocation: CLLocation?
    @State private var reverseGeocodeTask: Task<Void, Never>?

    private var favoriteRegistrations: Set<String> {
        Set(favorites.map { $0.registration })
    }

    private func isFavorite(_ aircraft: Aircraft) -> Bool {
        guard let reg = aircraft.registration?.uppercased() else { return false }
        return favoriteRegistrations.contains(reg)
    }

    var body: some View {
        NavigationStack {
            // TimelineView at 30 fps drives continuous re-renders so MapKit sees smoothly
            // interpolated annotation coordinates — @Observable tracking inside
            // @MapContentBuilder closures is unreliable and won't trigger updates on its own.
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                let interpolatedAircraft = dataStore.aircraft.map {
                    $0.interpolated(by: context.date.timeIntervalSince($0.lastUpdate))
                }
                Map(position: $cameraPosition) {
                    if let userCoord = location.currentLocation?.coordinate {
                        MapCircle(center: userCoord, radius: settings.radiusInMeters)
                            .foregroundStyle(Color.accentColor.opacity(0.10))
                            .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)

                        if !headingModeEnabled, location.heading != nil {
                            Annotation("", coordinate: userCoord, anchor: .center) {
                                DirectionConeView(
                                    angleDegrees: compassHeading - cam.heading,
                                    color: settings.coneColor
                                )
                                .frame(width: 120, height: 120)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                        }
                    }

                    UserAnnotation()

                    ForEach(interpolatedAircraft) { aircraft in
                        Annotation(
                            aircraft.displayName,
                            coordinate: aircraft.coordinate,
                            anchor: .center
                        ) {
                            AircraftAnnotation(
                                aircraft: aircraft,
                                isFavorite: isFavorite(aircraft),
                                isFollowed: follow.isFollowing(aircraft),
                                isSelected: aircraft.id == selectedAircraft?.id,
                                badgeStyle: settings.badgeStyle
                            )
                            .onTapGesture {
                                cancelSnapBack()
                                lastSheetAircraftID = aircraft.id
                                selectedAircraft = aircraft
                                sheetSpan = cam.region?.span ?? MKCoordinateSpan(latitudeDelta: 0.135, longitudeDelta: 0.135)
                                shiftCameraForSheet(to: aircraft.coordinate)
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
                // Continuous tracking so cam is always current when a tap fires, even mid-gesture.
                // Mutating class properties doesn't trigger SwiftUI re-renders.
                .onMapCameraChange(frequency: .continuous) { context in
                    cam.region = context.region
                    cam.distance = context.camera.distance
                    cam.heading = context.camera.heading
                }
                // Detect user-initiated pan/zoom in heading mode → start snap-back countdown.
                .simultaneousGesture(DragGesture(minimumDistance: 5).onChanged { _ in
                    if headingModeEnabled && selectedAircraft == nil { scheduleSnapBack() }
                })
                .simultaneousGesture(MagnifyGesture().onChanged { _ in
                    if headingModeEnabled && selectedAircraft == nil { scheduleSnapBack() }
                })
            } // TimelineView

            .navigationTitle("Map")
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
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                mapTopOverlay
            }
            .overlay(alignment: .bottom) {
                if verticalSizeClass != .compact {
                    RadiusSliderPanel()
                        .padding(.bottom, 16)
                }
            }
            .overlay(alignment: .trailing) {
                if verticalSizeClass != .compact {
                    VStack(spacing: 0) {
                        mapStyleButton
                        Divider().frame(width: 44)
                        headingModeButton
                        Divider().frame(width: 44)
                        fitRadiusButton
                        if canShowARButton {
                            Divider().frame(width: 44)
                            arButton
                        }
                        Divider().frame(width: 44)
                        weatherButton
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 1)
                    .padding(.trailing, 16)
                }
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
            .sheet(isPresented: $showWeather) {
                if weatherLoading {
                    ProgressView("Fetching weather…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .presentationDetents([.medium])
                } else if let w = weather {
                    WeatherOverlayView(weather: w)
                        .presentationDetents([.height(396)])
                        .presentationDragIndicator(.visible)
                } else {
                    ContentUnavailableView("Weather Unavailable", systemImage: "cloud.slash")
                        .presentationDetents([.medium])
                }
            }
            .fullScreenCover(isPresented: $showAR) {
                ARAircraftView()
                    .environment(settings)
                    .environment(location)
                    .environment(dataStore)
                    .environment(navigation)
                    .environment(follow)
                    .environment(arPermission)
            }
            // Frame to radius on every appear — tab switch, cold start.
            // Small delay lets MapKit complete its initial layout before we override the region.
            .onAppear {
                arPermission.refreshCameraStatus()
                location.startUpdatingHeading()
                if let h = location.heading { compassHeading = h.trueHeading }
                updatePlaceName(for: location.currentLocation)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let coord = location.currentLocation?.coordinate {
                        frameRegionAroundUser(coord)
                        hasAutoFramedOnFirstLoad = true
                    }
                }
            }
            .onDisappear {
                location.stopUpdatingHeading()
                reverseGeocodeTask?.cancel()
            }
            // Re-frame when coming back to the foreground.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let coord = location.currentLocation?.coordinate {
                        frameRegionAroundUser(coord)
                    }
                }
            }
            // Cold start: location wasn't available on appear, frame on first fix.
            .onChange(of: location.currentLocation) { _, newValue in
                updatePlaceName(for: newValue)
                guard !hasAutoFramedOnFirstLoad, let coord = newValue?.coordinate else { return }
                frameRegionAroundUser(coord)
                hasAutoFramedOnFirstLoad = true
            }
            // Re-frame whenever the radius changes so the new circle is always visible.
            .onChange(of: settings.radiusInMeters) { _, _ in
                if let coord = location.currentLocation?.coordinate {
                    frameRegionAroundUser(coord)
                }
            }
            // Update map heading when heading mode is on and device rotates.
            // Linear animation avoids the ease-in lag that causes stickiness when updates
            // arrive faster than the animation duration.
            .onChange(of: location.heading) { _, newHeading in
                // Static mode: accumulate heading via shortest-path delta so 0°/360° crossing
                // never causes the compass tape to animate the long way around.
                if !headingModeEnabled, let h = newHeading {
                    let new = h.trueHeading
                    var delta = new - compassHeading.truncatingRemainder(dividingBy: 360)
                    if delta > 180 { delta -= 360 }
                    if delta < -180 { delta += 360 }
                    compassHeading += delta
                }
                // Suppress heading updates while the user has panned away or a detail sheet is open.
                guard headingModeEnabled, snapBackTask == nil, selectedAircraft == nil else { return }
                guard let heading = newHeading else { return }
                // Skip if change is less than 4° — smooths out sensor noise beyond CLLocationManager's 2° filter.
                guard headingDelta(heading.trueHeading, lastAppliedHeading) >= 4 else { return }
                lastAppliedHeading = heading.trueHeading
                if let userCoord = location.currentLocation?.coordinate {
                    withAnimation(.linear(duration: 0.1)) {
                        cameraPosition = .camera(MapCamera(
                            centerCoordinate: userCoord,
                            distance: cam.distance,
                            heading: heading.trueHeading,
                            pitch: 0
                        ))
                    }
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
            // Live Activity tap deep-link: match callsign → pan map → open detail sheet.
            // Fires both when the URL arrives AND after each aircraft refresh so cold-launch
            // timing (URL arrives before first fetch) is handled automatically.
            .onChange(of: navigation.pendingDeepLinkCallsign) { _, _ in
                resolveDeepLink()
            }
            .onChange(of: dataStore.aircraft) { _, _ in
                resolveDeepLink()
            }
            // When the detail sheet is dismissed, re-center the map on the aircraft
            // so it sits at the true screen center (undoes the sheet-open shift).
            .onChange(of: selectedAircraft) { _, newValue in
                guard newValue == nil else { return }
                guard let id = lastSheetAircraftID else { return }
                let coord = dataStore.aircraft.first(where: { $0.id == id })?.coordinate
                let span = sheetSpan ?? cam.region?.span
                if let coord, let span {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        cameraPosition = .region(MKCoordinateRegion(center: coord, span: span))
                    }
                }
                lastSheetAircraftID = nil
                sheetSpan = nil
                // In heading mode, return to user position after 5 s.
                if headingModeEnabled { scheduleSnapBack() }
            }
            // While a detail sheet is open, follow the aircraft at 30 fps using the same
            // interpolation as the annotation so the camera and plane move in perfect sync.
            // The task is keyed on lastSheetAircraftID — SwiftUI cancels it automatically
            // when the sheet closes (id → nil) and restarts it for a new selection.
            .task(id: lastSheetAircraftID) {
                guard let id = lastSheetAircraftID,
                      let span = sheetSpan ?? cam.region?.span else { return }
                // Wait for the opening-shift animation (0.4 s) to settle before taking over.
                try? await Task.sleep(nanoseconds: 400_000_000)
                while !Task.isCancelled {
                    guard let aircraft = dataStore.aircraft.first(where: { $0.id == id }) else { break }
                    let elapsed = Date().timeIntervalSince(aircraft.lastUpdate)
                    let interpolated = aircraft.interpolated(by: elapsed)
                    let shifted = CLLocationCoordinate2D(
                        latitude: interpolated.coordinate.latitude - span.latitudeDelta * 0.28,
                        longitude: interpolated.coordinate.longitude
                    )
                    // Direct assignment without animation — 30 tiny steps/s looks smooth (like video).
                    cameraPosition = .region(MKCoordinateRegion(center: shifted, span: span))
                    try? await Task.sleep(nanoseconds: 33_333_333) // ~30 fps
                }
            }
        } // NavigationStack
    }

    private var mapTopOverlay: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? 2 : 7) {
                    Text("Map")
                        .font(.system(size: verticalSizeClass == .compact ? 22 : 36, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 9) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(mapSubtitle)
                            .font(.system(size: verticalSizeClass == .compact ? 13 : 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer(minLength: 24)
            }

            if !headingModeEnabled, location.heading != nil, verticalSizeClass != .compact {
                CompassStripView(heading: compassHeading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = dataStore.lastError ?? location.lastError {
                Text(error)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.54), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.3), value: headingModeEnabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private var mapSubtitle: String {
        let aircraftText = dataStore.aircraft.count == 1 ? "1 aircraft" : "\(dataStore.aircraft.count) aircraft"
        guard let currentPlaceName, !currentPlaceName.isEmpty else {
            return "\(aircraftText) nearby"
        }
        return "\(aircraftText) · \(currentPlaceName)"
    }

    /// Tries to match `navigation.pendingDeepLinkCallsign` against the current aircraft list.
    /// Pans the map and opens the detail sheet on a match; leaves the callsign pending if
    /// the list is empty (will be retried by the onChange above).
    private func resolveDeepLink() {
        guard let callsign = navigation.pendingDeepLinkCallsign,
              !dataStore.aircraft.isEmpty else { return }

        guard let match = dataStore.aircraft.first(where: {
            $0.displayName.uppercased() == callsign.uppercased()
        }) else {
            // Aircraft left radius or callsign mismatch — clear so we don't retry forever.
            navigation.pendingDeepLinkCallsign = nil
            return
        }

        sheetSpan = cam.region?.span ?? MKCoordinateSpan(latitudeDelta: 0.135, longitudeDelta: 0.135)
        shiftCameraForSheet(to: match.coordinate)
        lastSheetAircraftID = match.id
        selectedAircraft = match
        navigation.pendingDeepLinkCallsign = nil
    }

    private func updatePlaceName(for newLocation: CLLocation?) {
        guard let newLocation else {
            currentPlaceName = nil
            lastReverseGeocodedLocation = nil
            reverseGeocodeTask?.cancel()
            return
        }

        if let lastReverseGeocodedLocation,
           newLocation.distance(from: lastReverseGeocodedLocation) < 5_000 {
            return
        }

        lastReverseGeocodedLocation = newLocation
        reverseGeocodeTask?.cancel()
        reverseGeocodeTask = Task {
            var name: String?
            if #available(iOS 18, *) {
                if let request = MKReverseGeocodingRequest(location: newLocation) {
                    let mapItems = try? await request.mapItems
                    let item = mapItems?.first
                    name = item?.addressRepresentations?.cityName
                        ?? item?.name
                        ?? item?.addressRepresentations?.regionName
                }
            } else {
                let geocoder = CLGeocoder()
                if let placemarks = try? await geocoder.reverseGeocodeLocation(newLocation) {
                    name = placemarks.first?.locality ?? placemarks.first?.administrativeArea
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                currentPlaceName = name
            }
        }
    }

    private var stackButtonStyle: some View { EmptyView() }

    private var canShowARButton: Bool {
        settings.arModeEnabled
        && arPermission.isARSupported
        && arPermission.cameraStatus == .authorized
    }

    /// Map style cycle button (part of right-side stack).
    private var mapStyleButton: some View {
        Button {
            switch settings.mapStyle {
            case .standard: settings.mapStyle = .hybrid
            case .hybrid:   settings.mapStyle = .satellite
            case .satellite: settings.mapStyle = .standard
            }
        } label: {
            Image(systemName: mapIconForStyle(settings.mapStyle))
                .font(.system(size: 17))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    /// Heading mode button (part of right-side stack).
    private var headingModeButton: some View {
        Button {
            headingModeEnabled.toggle()
            if !headingModeEnabled {
                cancelSnapBack()
            }
        } label: {
            Image(systemName: headingModeEnabled ? "location.north.line.fill" : "location.north.line")
                .font(.system(size: 19))
                .foregroundStyle(headingModeEnabled ? .white : Color.accentColor)
                .frame(width: 44, height: 40)
                .background(headingModeEnabled ? Color.accentColor : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Heading mode")
    }

    /// Fit radius button (part of right-side stack).
    private var fitRadiusButton: some View {
        Button {
            if let coord = location.currentLocation?.coordinate {
                frameRegionAroundUser(coord)
            }
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 19))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fit radius to screen")
    }

    /// Opens the full-screen augmented reality aircraft view.
    private var arButton: some View {
        Button {
            showAR = true
        } label: {
            Image(systemName: "arkit")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Sky View AR")
    }

    /// Weather button (part of right-side stack). Fetches only on tap.
    private var weatherButton: some View {
        Button {
            guard let coord = location.currentLocation?.coordinate else { return }
            weatherLoading = true
            weather = nil
            showWeather = true
            Task {
                weather = try? await WeatherService.fetch(at: coord)
                weatherLoading = false
            }
        } label: {
            Image(systemName: weatherLoading ? "ellipsis" : "cloud.sun")
                .font(.system(size: 17))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 40)
                .symbolEffect(.variableColor, isActive: weatherLoading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Weather")
    }

    private func mapIconForStyle(_ style: MapStyleOption) -> String {
        switch style {
        case .standard: return "map"
        case .satellite: return "square.on.circle"
        case .hybrid: return "map.fill"
        }
    }

    /// Starts (or restarts) the 5-second countdown to snap back to the user's position.
    /// While the task is alive, heading-mode camera updates are suppressed so the user
    /// can freely inspect the map without the camera fighting them.
    private func scheduleSnapBack() {
        snapBackTask?.cancel()
        snapBackTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, headingModeEnabled else {
                snapBackTask = nil
                return
            }
            if let coord = location.currentLocation?.coordinate {
                let heading = location.heading?.trueHeading ?? cam.heading
                withAnimation(.easeInOut(duration: 0.6)) {
                    cameraPosition = .camera(MapCamera(
                        centerCoordinate: coord,
                        distance: cam.distance,
                        heading: heading,
                        pitch: 0
                    ))
                }
            }
            snapBackTask = nil
        }
    }

    private func cancelSnapBack() {
        snapBackTask?.cancel()
        snapBackTask = nil
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

    /// Shortest angular distance between two headings (handles 359° → 1° wraparound).
    private func headingDelta(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return abs(d)
    }

    /// Shifts the map camera south so `coordinate` appears centered in the visible map area
    /// above a medium-detent sheet. Uses MKCoordinateRegion(center:span:) so the span object
    /// is reused verbatim — MapKit cannot reinterpret it as a different zoom level.
    /// The 0.28 shift factor: (map_center − top_half_center) / map_height ≈ 0.28 for typical iPhones.
    private func shiftCameraForSheet(to coordinate: CLLocationCoordinate2D) {
        // Use the live span from continuous tracking; fall back to ~15 km for cold launch.
        let span = cam.region?.span ?? MKCoordinateSpan(latitudeDelta: 0.135, longitudeDelta: 0.135)
        let shiftedCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * 0.28,
            longitude: coordinate.longitude
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .region(MKCoordinateRegion(center: shiftedCenter, span: span))
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

// MARK: - Radius Slider Panel

private struct RadiusSliderPanel: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AircraftDataStore.self) private var dataStore

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Search Radius")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.4)
                Spacer()
                Text("\(Int(settings.radiusValue)) \(settings.distanceUnit.shortLabel)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 6)

            Slider(value: $settings.radiusValue, in: 5...250, step: 5)
                .tint(Color.accentColor)

            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("\(dataStore.aircraft.count) aircraft nearby")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                }
                Spacer()
                Text(nextUpdateLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 1)
        .padding(.horizontal, 16)
    }

    private var nextUpdateLabel: String {
        guard let last = dataStore.lastFetchAt else { return "Updating…" }
        let interval = Double(settings.refreshInterval.rawValue)
        let next = last.addingTimeInterval(interval)
        let remaining = next.timeIntervalSinceNow
        if remaining <= 0 { return "Updating…" }
        if remaining < 60 { return "Next update in \(Int(remaining)) s" }
        return "Next update in \(Int(remaining / 60)) min"
    }
}

// MARK: - Direction Cone

private struct DirectionConeView: View {
    var angleDegrees: Double
    var color: Color

    var body: some View {
        ConeShape(angleDegrees: angleDegrees)
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.72), color.opacity(0)],
                    center: .center,
                    startRadius: 6,
                    endRadius: 58
                )
            )
            .animation(.linear(duration: 0.1), value: angleDegrees)
    }
}

private struct ConeShape: Shape {
    var angleDegrees: Double
    private let spreadDegrees: Double = 65

    var animatableData: Double {
        get { angleDegrees }
        set { angleDegrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = Angle(degrees: angleDegrees - spreadDegrees / 2 - 90)
        let endAngle = Angle(degrees: angleDegrees + spreadDegrees / 2 - 90)
        path.move(to: center)
        path.addArc(center: center, radius: radius,
                    startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Compass Strip

private struct CompassStripView: View {
    var heading: Double

    private let pixelsPerDegree: CGFloat = 4.8

    private struct Tick: Identifiable {
        let degree: Double
        let label: String?

        var id: String {
            "\(degree)-\(label ?? "tick")"
        }

        var isMajor: Bool {
            label != nil
        }
    }

    private static let ticks: [Tick] = {
        var ticks: [Tick] = []
        let labels: [Int: String] = [
            0: "N",
            45: "NE",
            90: "E",
            135: "SE",
            180: "S",
            225: "SW",
            270: "W",
            315: "NW",
        ]

        for cycle in -2...2 {
            for degree in stride(from: 0.0, to: 360.0, by: 22.5) {
                let normalized = Int(degree.rounded()) % 360
                ticks.append(Tick(
                    degree: degree + Double(cycle * 360),
                    label: labels[normalized]
                ))
            }
        }

        return ticks
    }()

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                ForEach(Self.ticks) { tick in
                    let xOff = xOffset(for: tick.degree)
                    VStack(spacing: 7) {
                        if let label = tick.label {
                            Text(label)
                                .font(.system(size: label.count == 1 ? 13 : 12, weight: .semibold))
                                .foregroundStyle(label == "N" ? Color.red : Color.primary)
                                .frame(height: 16)
                        } else {
                            Color.clear
                                .frame(height: 16)
                        }

                        RoundedRectangle(cornerRadius: 1)
                            .fill(tickColor(tick))
                            .frame(width: tick.isMajor ? 2 : 1, height: tick.isMajor ? 17 : 10)
                    }
                    .position(x: width / 2 + xOff, y: 22)
                    .opacity(abs(xOff) < width / 2 + 32 ? 1 : 0)
                }

                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .position(x: width / 2, y: 47)
            }
            .animation(.linear(duration: 0.1), value: heading)
            .clipped()
        }
        .frame(height: 58)
        .accessibilityHidden(true)
    }

    private func tickColor(_ tick: Tick) -> Color {
        if tick.label == "N" {
            return Color.red.opacity(0.88)
        }
        return Color.primary.opacity(tick.isMajor ? 0.80 : 0.36)
    }

    private func xOffset(for degree: Double) -> CGFloat {
        var d = (degree - heading).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return CGFloat(d) * pixelsPerDegree
    }
}

#Preview {
    let settings = SettingsStore.shared
    let location = LocationService()
    let follow = FollowStore()

    MapView()
        .environment(settings)
        .environment(location)
        .environment(APIRouter(settings: settings))
        .environment(AircraftDataStore(router: APIRouter(settings: settings),
                                       settings: settings,
                                       location: location,
                                       follow: follow))
        .environment(NavigationCoordinator())
        .environment(follow)
        .environment(ARPermissionStore())
}
