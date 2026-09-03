import SwiftUI
import SwiftData
import CoreLocation

/// Tab 2 — all aircraft in the configured radius sorted by distance.
struct ListView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LocationService.self) private var location
    @Environment(AircraftDataStore.self) private var dataStore
    @Environment(FollowStore.self) private var follow
    @Query private var favorites: [Favorite]

    @State private var selectedAircraft: Aircraft?
    @State private var refreshToast: String?
    @State private var isRefreshing = false

    private var favoriteRegistrations: Set<String> {
        Set(favorites.map { $0.registration })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    // Zero-height spy row: traverses to the UIScrollView via KVO to
                    // report pull offset and make the system refresh indicator invisible.
                    ScrollOffsetObserver()
                        .frame(width: 0, height: 0)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                    ForEach(dataStore.aircraft) { aircraft in
                        Button {
                            selectedAircraft = aircraft
                        } label: {
                            aircraftRow(aircraft)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await performRefresh()
                }

                // Full-screen empty state sits outside the List so it fills the screen.
                if dataStore.aircraft.isEmpty && !isRefreshing && !dataStore.isLoading {
                    ContentUnavailableView {
                        Label("No aircraft", systemImage: "airplane.circle")
                    } description: {
                        Text("Pull to refresh or expand your search radius in Settings.")
                    }
                }
            }
            .navigationTitle("Aircraft Nearby")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if dataStore.isLoading && !isRefreshing {
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
            .overlay(alignment: .top) {
                if let toast = refreshToast {
                    Text(toast)
                        .font(.caption)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            dataStore.lastError != nil
                                ? Color.red.opacity(0.85)
                                : Color.secondary.opacity(0.85),
                            in: .capsule
                        )
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: refreshToast)
                }
            }
        }
    }

    private func performRefresh() async {
        withAnimation { isRefreshing = true }
        await dataStore.refresh()

        let count = dataStore.aircraft.count
        withAnimation {
            refreshToast = dataStore.lastError.map { "Error: \($0)" }
                ?? (count == 0 ? "No aircraft in range" : "\(count) aircraft found")
        }

        try? await Task.sleep(for: .milliseconds(800))
        withAnimation { isRefreshing = false }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { refreshToast = nil }
    }

    @ViewBuilder
    private func aircraftRow(_ aircraft: Aircraft) -> some View {
        let isFavorite = aircraft.registration.map { favoriteRegistrations.contains($0.uppercased()) } ?? false
        let isFollowed = follow.isFollowing(aircraft)

        HStack(alignment: .top, spacing: 12) {
            // Plane icon — colour reflects priority state
            Image(systemName: "airplane")
                .font(.title3)
                .foregroundStyle(isFollowed ? .green : isFavorite ? .yellow : .accentColor)
                .rotationEffect(.degrees((aircraft.headingDegrees ?? 0) - 90))
                .frame(width: 36, height: 36)
                .background(.thinMaterial, in: .circle)
                .overlay(Circle().stroke(isFollowed ? Color.green : Color.clear, lineWidth: 2))

            VStack(alignment: .leading, spacing: 4) {
                // Title row: callsign + badges
                HStack(spacing: 6) {
                    Text(aircraft.displayName)
                        .font(.headline)
                    if isFollowed {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else if isFavorite {
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
                        metadataPill(text: type, icon: "airplane.circle")
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

            VStack(alignment: .trailing, spacing: 6) {
                if let userCoord = location.currentLocation?.coordinate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(UnitFormat.distance(meters: aircraft.distance(to: userCoord), unit: settings.distanceUnit))
                            .font(.subheadline.bold().monospacedDigit())
                        Text("away")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Follow button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        follow.toggle(aircraft)
                    }
                } label: {
                    Image(systemName: isFollowed ? "location.fill" : "location")
                        .font(.caption)
                        .foregroundStyle(isFollowed ? .green : .secondary)
                        .padding(6)
                        .background(.thinMaterial, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFollowed ? "Unfollow" : "Follow")
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
        case let (origin?, nil): return "From \(origin) · destination not published"
        case let (nil, destination?): return "To \(destination) · origin not published"
        default: return nil
        }
    }
}

// MARK: - UIScrollView spy + custom refresh indicator

/// Zero-height row that traverses up to the List's UIScrollView, hides the
/// system refresh spinner, and injects a custom CAAnimation orbit indicator
/// directly inside the UIRefreshControl. UIKit then owns all positioning:
/// it holds the refresh control in place while fetching and springs it back
/// when done — no SwiftUI overlay needed.
private struct ScrollOffsetObserver: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isHidden = true
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: uiView) }
    }

    final class Coordinator: NSObject {
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private weak var orbitContainer: UIView?
        private var hasAttached = false
        private let orbitDiameter: CGFloat = 36
        private let threshold: CGFloat = 70

        func attach(to view: UIView) {
            guard !hasAttached else { return }
            var cur: UIView? = view.superview
            while let v = cur {
                if let sv = v as? UIScrollView {
                    hasAttached = true
                    scrollView = sv
                    // Drive orbit container alpha from pull distance so it fades in as you pull.
                    observation = sv.observe(\.contentOffset, options: .new) { [weak self] sv, _ in
                        guard let self else { return }
                        // While the refresh control is held open by UIKit (isRefreshing == true),
                        // adjustedContentInset already includes the control height so the pull
                        // calculation returns 0 — keep alpha at 1 for the duration of the fetch.
                        let isActive = sv.refreshControl?.isRefreshing ?? false
                        let pull = max(0, -(sv.contentOffset.y + sv.adjustedContentInset.top))
                        let alpha = isActive ? 1.0 : min(pull / self.threshold, 1.0)
                        DispatchQueue.main.async { self.orbitContainer?.alpha = alpha }
                    }
                    trySetupRefreshControl(sv)
                    return
                }
                cur = v.superview
            }
        }

        // SwiftUI creates the UIRefreshControl asynchronously; retry until it appears.
        private func trySetupRefreshControl(_ sv: UIScrollView, attempt: Int = 0) {
            guard let rc = sv.refreshControl else {
                guard attempt < 20 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak sv] in
                    guard let self, let sv else { return }
                    self.trySetupRefreshControl(sv, attempt: attempt + 1)
                }
                return
            }
            rc.tintColor = .clear
            buildOrbit(in: rc)
        }

        private func buildOrbit(in rc: UIRefreshControl) {
            let d = orbitDiameter

            // Ring drawn as a CAShapeLayer inside the spinning container.
            let ring = CAShapeLayer()
            ring.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: d, height: d)).cgPath
            ring.strokeColor = UIColor.systemBlue.withAlphaComponent(0.2).cgColor
            ring.fillColor = UIColor.clear.cgColor
            ring.lineWidth = 1.5

            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.layer.addSublayer(ring)

            // Plane placed at the top of the orbit circle.
            // The container rotates as a whole, so the plane naturally orbits the center.
            let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            if let img = UIImage(systemName: "airplane", withConfiguration: cfg) {
                let plane = UIImageView(image: img)
                plane.tintColor = .systemBlue
                // Frame-based: centered horizontally, 2pt from top edge.
                let pw: CGFloat = 16, ph: CGFloat = 16
                plane.frame = CGRect(x: d / 2 - pw / 2, y: 2, width: pw, height: ph)
                plane.contentMode = .scaleAspectFit
                // SF Symbols "airplane" points northeast; +45° makes it face east (right),
                // which is the direction of travel for a clockwise orbit starting at the top.
                plane.transform = CGAffineTransform(rotationAngle: .pi / 4)
                container.addSubview(plane)
            }

            rc.addSubview(container)
            NSLayoutConstraint.activate([
                container.centerXAnchor.constraint(equalTo: rc.centerXAnchor),
                container.centerYAnchor.constraint(equalTo: rc.centerYAnchor),
                container.widthAnchor.constraint(equalToConstant: d),
                container.heightAnchor.constraint(equalToConstant: d),
            ])

            // Continuous spin — CAAnimation is immune to SwiftUI re-renders.
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = CGFloat.pi * 2
            spin.duration = 1.2
            spin.repeatCount = .infinity
            container.layer.add(spin, forKey: "spin")

            container.alpha = 0
            orbitContainer = container
        }
    }
}
