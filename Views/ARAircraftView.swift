import ARKit
import CoreLocation
import RealityKit
import SwiftData
import SwiftUI
import UIKit

private struct ARFrameSnapshot {
    let camera: ARCamera
    let viewportSize: CGSize
    let orientation: UIInterfaceOrientation
    let trackingMessage: String?
}

struct ARAircraftView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LocationService.self) private var location
    @Environment(AircraftDataStore.self) private var dataStore
    @Environment(NavigationCoordinator.self) private var navigation
    @Environment(FollowStore.self) private var follow
    @Environment(ARPermissionStore.self) private var arPermission
    @Environment(\.dismiss) private var dismiss

    @State private var frameSnapshot: ARFrameSnapshot?
    @State private var selectedAircraft: Aircraft?
    @State private var sessionMessage: String?
    @State private var arViewID = UUID()
    @State private var expandedAircraftIDs: Set<String> = []

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if arPermission.isARSupported && arPermission.cameraStatus == .authorized {
                    ARAircraftCameraView(
                        onFrame: { frameSnapshot = $0 },
                        onSessionMessage: { sessionMessage = $0 }
                    )
                    .id(arViewID)
                    .ignoresSafeArea()

                    aircraftOverlay(in: geometry.size)
                } else {
                    arUnavailableView
                }
            }
            .overlay(alignment: .top) {
                topBar(topInset: geometry.safeAreaInsets.top)
                    .zIndex(10)
            }
            .background(Color.black)
            .task {
                arPermission.refreshCameraStatus()
                location.startUpdating()
                location.startUpdatingHeading()
            }
            .sheet(item: $selectedAircraft) { aircraft in
                AircraftDetailSheet(
                    aircraft: aircraft,
                    userLocation: location.currentLocation?.coordinate
                )
                .environment(settings)
                .environment(navigation)
                .environment(follow)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func aircraftOverlay(in size: CGSize) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { context in
            let projections = projectedAircraft(at: context.date)

            ZStack {
                if let sessionMessage {
                    ARSessionFailureCard(
                        message: sessionMessage,
                        onRestart: restartARSession
                    )
                } else if projections.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 26, weight: .medium))
                        Text(emptyStateText)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                ForEach(projections) { projection in
                    let isExpanded = expandedAircraftIDs.contains(projection.id)
                    ARAircraftCardView(
                        projection: projection,
                        isExpanded: isExpanded,
                        onOpenDetail: { selectedAircraft = projection.aircraft },
                        onToggleExpanded: { toggleCardExpansion(projection.id) }
                    )
                    .position(projection.clampedPoint)
                    .scaleEffect(projection.scale)
                    .opacity(projection.opacity)
                    .animation(.linear(duration: 0.08), value: projection.clampedPoint)
                    .zIndex(max(0, (isExpanded ? 2_000_000 : 1_000_000) - projection.distanceMeters))
                }
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(true)
        }
    }

    private func projectedAircraft(at date: Date) -> [ARAircraftScreenProjection] {
        guard let frameSnapshot,
              let userLocation = location.currentLocation else {
            return []
        }

        return ARAircraftProjection.screenProjections(
            for: dataStore.aircraft,
            userLocation: userLocation,
            camera: frameSnapshot.camera,
            viewportSize: frameSnapshot.viewportSize,
            orientation: frameSnapshot.orientation,
            radiusMeters: settings.radiusInMeters,
            now: date
        )
    }

    private func topBar(topInset: CGFloat) -> some View {
        ZStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color(red: 0.08, green: 0.19, blue: 0.28).opacity(0.74), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close AR")

                Spacer()
            }

            VStack(spacing: 2) {
                Text("Sky View")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(headerStatusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 22)
            .frame(minWidth: 178)
            .frame(height: 50)
            .background(Color(red: 0.08, green: 0.19, blue: 0.28).opacity(0.86), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Sky View, \(headerStatusText)")
        }
        .padding(.horizontal, 20)
        .padding(.top, max(topInset, 52) + 12)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var arUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arkit")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.white)

            VStack(spacing: 6) {
                Text(unavailableTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text(unavailableMessage)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 24)
            }

            if arPermission.cameraStatus == .denied || arPermission.cameraStatus == .restricted {
                Button {
                    arPermission.openAppSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerStatusText: String {
        if let sessionMessage {
            return sessionMessage == "Camera access needed" ? sessionMessage : "AR tracking failed"
        }
        if let trackingMessage = frameSnapshot?.trackingMessage {
            return trackingMessage
        }
        guard let userLocation = location.currentLocation else {
            return "Waiting for location"
        }
        if let compassMessage {
            return compassMessage
        }
        let count = ARAircraftProjection.eligibleAircraft(
            from: dataStore.aircraft,
            userLocation: userLocation,
            radiusMeters: settings.radiusInMeters
        ).count
        return count == 1 ? "1 aircraft nearby" : "\(count) aircraft nearby"
    }

    private var compassMessage: String? {
        guard let heading = location.heading else { return nil }
        if heading.headingAccuracy < 0 {
            return "Calibrating compass"
        }
        if heading.headingAccuracy > 25 {
            return "Low compass accuracy"
        }
        return nil
    }

    private var emptyStateText: String {
        if frameSnapshot == nil {
            return "Starting AR tracking"
        }
        if location.currentLocation == nil {
            return "Waiting for location"
        }
        if dataStore.aircraft.isEmpty {
            return "No aircraft in range"
        }
        return "Point your phone toward the sky"
    }

    private var unavailableTitle: String {
        if !arPermission.isARSupported {
            return "AR Unavailable"
        }
        return "Camera Access Needed"
    }

    private var unavailableMessage: String {
        if !arPermission.isARSupported {
            return "This device does not support the world tracking required for Sky View."
        }
        return "Enable camera access in Settings to align aircraft cards with the sky."
    }

    private func restartARSession() {
        frameSnapshot = nil
        sessionMessage = nil
        arViewID = UUID()
    }

    private func toggleCardExpansion(_ id: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            if expandedAircraftIDs.contains(id) {
                expandedAircraftIDs.remove(id)
            } else {
                expandedAircraftIDs = [id]
            }
        }
    }
}

private struct ARAircraftCameraView: UIViewRepresentable {
    var onFrame: (ARFrameSnapshot) -> Void
    var onSessionMessage: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFrame: onFrame, onSessionMessage: onSessionMessage)
    }

    static func makeARConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.isAutoFocusEnabled = false
        return configuration
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        arView.session.delegate = context.coordinator
        arView.session.delegateQueue = .main
        context.coordinator.arView = arView

        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .tracking
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coachingOverlay)
        NSLayoutConstraint.activate([
            coachingOverlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coachingOverlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            coachingOverlay.topAnchor.constraint(equalTo: arView.topAnchor),
            coachingOverlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
        ])

        if ARWorldTrackingConfiguration.isSupported {
            arView.session.run(Self.makeARConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        } else {
            onSessionMessage("AR not supported")
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.onFrame = onFrame
        context.coordinator.onSessionMessage = onSessionMessage
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
        uiView.session.delegate = nil
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        var onFrame: (ARFrameSnapshot) -> Void
        var onSessionMessage: (String?) -> Void
        private var lastFrameTimestamp: TimeInterval = 0
        private var lastSessionMessage: String?

        init(
            onFrame: @escaping (ARFrameSnapshot) -> Void,
            onSessionMessage: @escaping (String?) -> Void
        ) {
            self.onFrame = onFrame
            self.onSessionMessage = onSessionMessage
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard frame.timestamp - lastFrameTimestamp >= 1.0 / 15.0 else { return }
            lastFrameTimestamp = frame.timestamp

            guard let arView, arView.bounds.size.width > 0, arView.bounds.size.height > 0 else { return }
            sendSessionMessage(nil)
            onFrame(ARFrameSnapshot(
                camera: frame.camera,
                viewportSize: arView.bounds.size,
                orientation: arView.currentInterfaceOrientation,
                trackingMessage: frame.camera.trackingState.statusMessage
            ))
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            let message = Self.message(for: error)
            sendSessionMessage(message)
            let nsError = error as NSError
            Task { @MainActor in
                DebugStore.shared.log(
                    "AR session failed \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)",
                    isError: true
                )
            }
        }

        func sessionWasInterrupted(_ session: ARSession) {
            sendSessionMessage("AR session interrupted")
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            sendSessionMessage(nil)
            if ARWorldTrackingConfiguration.isSupported {
                session.run(ARAircraftCameraView.makeARConfiguration(), options: [.resetTracking, .removeExistingAnchors])
            }
        }

        private func sendSessionMessage(_ message: String?) {
            guard lastSessionMessage != message else { return }
            lastSessionMessage = message
            onSessionMessage(message)
        }

        private static func message(for error: Error) -> String {
            guard let arError = error as? ARError else {
                return error.localizedDescription
            }

            switch arError.code {
            case .cameraUnauthorized:
                return "Camera access needed"
            case .sensorFailed, .sensorUnavailable:
                return "Required sensor failed. Make sure camera and motion sensors are available, then restart AR."
            case .unsupportedConfiguration:
                return "AR not supported on this device"
            case .worldTrackingFailed:
                return "World tracking failed. Move the phone slowly and restart AR."
            default:
                return arError.localizedDescription
            }
        }
    }
}

private struct ARSessionFailureCard: View {
    let message: String
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.yellow)

            VStack(spacing: 5) {
                Text("AR Tracking Failed")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onRestart) {
                Label("Restart AR", systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.20))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: 310)
        .background(Color(red: 0.12, green: 0.22, blue: 0.29).opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
    }
}

private struct ARAircraftCardView: View {
    let projection: ARAircraftScreenProjection
    let isExpanded: Bool
    let onOpenDetail: () -> Void
    let onToggleExpanded: () -> Void

    @Environment(SettingsStore.self) private var settings
    @State private var airlineLogoImage: UIImage?

    private let cardWidth: CGFloat = 266
    private let compactHeight: CGFloat = 64
    private let expandedHeight: CGFloat = 149
    private let cardColor = Color(red: 0.15, green: 0.27, blue: 0.35)
    private let tileColor = Color(red: 0.30, green: 0.43, blue: 0.51)
    private let primaryText = Color.white
    private let secondaryText = Color.white.opacity(0.64)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onOpenDetail) {
                    HStack(spacing: 12) {
                        airlineLogo
                        titleBlock
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(secondaryText)
                        .frame(width: 30, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse aircraft card" : "Expand aircraft card")
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, isExpanded ? 14 : 12)

            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.13))
                    .padding(.horizontal, 14)

                HStack(spacing: 10) {
                    metricBox(title: "ALTITUDE", value: altitudeDisplay.value, unit: altitudeDisplay.unit)
                    metricBox(title: "SPEED", value: speedDisplay.value, unit: speedDisplay.unit)
                }
                .padding(.horizontal, 14)
                .padding(.top, 22)
                .padding(.bottom, 14)
            }
        }
        .frame(width: cardWidth, height: isExpanded ? expandedHeight : compactHeight)
        .background(cardColor.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(projection.isClamped ? 0.30 : 0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
        .accessibilityLabel(accessibilityLabel)
        .task(id: airlineLogoLookupCode ?? "") {
            await loadAirlineLogo()
        }
    }

    private var airlineLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(tileColor.opacity(0.92))

            if let airlineLogoImage {
                Image(uiImage: airlineLogoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(5)
            } else if let airlineLogoText {
                Text(airlineLogoText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.86))
            } else {
                Image(systemName: "airplane")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.86))
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(airlineDisplayName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let flightDisplay {
                    Text(flightDisplay)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private func metricBox(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryText)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(unit)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(height: 50)
        .background(tileColor.opacity(0.70), in: RoundedRectangle(cornerRadius: 14))
    }

    private var accessibilityLabel: String {
        "\(projection.aircraft.displayName), \(UnitFormat.distance(meters: projection.distanceMeters, unit: settings.distanceUnit)) away"
    }

    private var airlineDisplayName: String {
        if let airline = projection.aircraft.airline, !airline.isEmpty {
            return airline
        }
        if let code = icaoAirlineCode, let info = Self.airlineInfo[code] {
            return info.name
        }
        if let iata = iataCode, let name = Self.iataAirlineNames[iata] {
            return name
        }
        return "Aircraft"
    }

    private var flightDisplay: String? {
        guard let callsign = normalizedCallsign else { return nil }
        guard let code = icaoAirlineCode,
              let iata = Self.airlineInfo[code]?.iata,
              callsign.hasPrefix(code) else {
            return callsign
        }

        let suffix = callsign.dropFirst(code.count)
        return suffix.isEmpty ? iata : iata + suffix
    }

    private var subtitle: String {
        let registration = projection.aircraft.registration?.uppercased() ?? projection.aircraft.id.uppercased()
        guard let aircraftType = projection.aircraft.aircraftType, !aircraftType.isEmpty else {
            return registration
        }
        return "\(registration) · \(aircraftType)"
    }

    private var airlineLogoText: String? {
        if let iataCode {
            return iataCode
        }
        if let code = icaoAirlineCode {
            return String(code.prefix(2))
        }
        let fallback = String(projection.aircraft.displayName.prefix(2)).uppercased()
        return fallback.isEmpty ? nil : fallback
    }

    private var airlineLogoLookupCode: String? {
        icaoAirlineCode
    }

    private var normalizedCallsign: String? {
        let trimmed = projection.aircraft.callsign?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private var airlineCode: String? {
        guard let callsign = normalizedCallsign else { return nil }
        let letters = String(callsign.prefix(while: { $0.isLetter }))
        guard !letters.isEmpty else { return nil }
        return letters.count >= 3 ? String(letters.prefix(3)) : letters
    }

    private var icaoAirlineCode: String? {
        if let code = airlineCode {
            if code.count >= 3 {
                return code
            }
            if let mappedCode = Self.iataToICAO[code] {
                return mappedCode
            }
        }

        guard let airline = projection.aircraft.airline?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(), !airline.isEmpty else {
            return nil
        }

        return Self.airlineInfo.first { item in
            let candidate = item.value.name.uppercased()
            return candidate == airline
            || candidate.contains(airline)
            || airline.contains(candidate)
        }?.key
    }

    private var iataCode: String? {
        if let code = icaoAirlineCode,
           let iata = Self.airlineInfo[code]?.iata {
            return iata
        }
        guard let code = airlineCode else { return nil }
        return code.count == 2 ? code : nil
    }

    private func loadAirlineLogo() async {
        guard let airlineLogoLookupCode else {
            airlineLogoImage = nil
            return
        }
        airlineLogoImage = await AirlineLogoCache.shared.image(forICAO: airlineLogoLookupCode)
    }

    private var altitudeDisplay: (value: String, unit: String) {
        guard let meters = projection.aircraft.altitudeMeters else { return ("--", "") }
        switch settings.altitudeUnit {
        case .feet:
            return (Int(meters * 3.28084).formatted(), "ft")
        case .meters:
            return (Int(meters).formatted(), "m")
        }
    }

    private var speedDisplay: (value: String, unit: String) {
        guard let mps = projection.aircraft.groundSpeedMps else { return ("--", "") }
        switch settings.speedUnit {
        case .knots:
            return (Int(mps * 1.94384).formatted(), "kts")
        case .kmh:
            return (Int(mps * 3.6).formatted(), "km/h")
        case .mph:
            return (Int(mps * 2.23694).formatted(), "mph")
        }
    }

    private static let airlineInfo: [String: (name: String, iata: String)] = [
        "AAL": ("American Airlines", "AA"),
        "ACA": ("Air Canada", "AC"),
        "AFR": ("Air France", "AF"),
        "ANA": ("All Nippon Airways", "NH"),
        "AUA": ("Austrian Airlines", "OS"),
        "BAW": ("British Airways", "BA"),
        "BEL": ("Brussels Airlines", "SN"),
        "CCA": ("Air China", "CA"),
        "CES": ("China Eastern", "MU"),
        "CPA": ("Cathay Pacific", "CX"),
        "DAL": ("Delta Air Lines", "DL"),
        "DLH": ("Lufthansa", "LH"),
        "EIN": ("Aer Lingus", "EI"),
        "ETD": ("Etihad Airways", "EY"),
        "ETH": ("Ethiopian Airlines", "ET"),
        "EZY": ("easyJet", "U2"),
        "FIN": ("Finnair", "AY"),
        "IBE": ("Iberia", "IB"),
        "JAL": ("Japan Airlines", "JL"),
        "KAL": ("Korean Air", "KE"),
        "KLM": ("KLM", "KL"),
        "LOT": ("LOT Polish Airlines", "LO"),
        "QTR": ("Qatar Airways", "QR"),
        "RYR": ("Ryanair", "FR"),
        "SAS": ("Scandinavian Airlines", "SK"),
        "SIA": ("Singapore Airlines", "SQ"),
        "SWA": ("Southwest Airlines", "WN"),
        "SWR": ("SWISS", "LX"),
        "TAP": ("TAP Air Portugal", "TP"),
        "THA": ("Thai Airways", "TG"),
        "THY": ("Turkish Airlines", "TK"),
        "UAL": ("United Airlines", "UA"),
        "UAE": ("Emirates", "EK"),
        "VIR": ("Virgin Atlantic", "VS"),
        "VLG": ("Vueling", "VY"),
        "WJA": ("WestJet", "WS"),
        "WZZ": ("Wizz Air", "W6"),
    ]

    private static let iataAirlineNames: [String: String] = Dictionary(
        uniqueKeysWithValues: airlineInfo.values.map { ($0.iata, $0.name) }
    )

    private static let iataToICAO: [String: String] = Dictionary(
        uniqueKeysWithValues: airlineInfo.map { ($0.value.iata, $0.key) }
    )
}

@MainActor
private final class AirlineLogoCache {
    static let shared = AirlineLogoCache()

    private var images: [String: UIImage] = [:]
    private var misses: Set<String> = []

    func image(forICAO icao: String?) async -> UIImage? {
        guard let code = icao?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(), !code.isEmpty else {
            return nil
        }

        if let image = images[code] {
            return image
        }
        if misses.contains(code) {
            return nil
        }

        let fetched = await fetchFlightAwareLogo(icao: code)
        if let fetched {
            images[code] = fetched
        } else {
            misses.insert(code)
        }
        return fetched
    }

    private func fetchFlightAwareLogo(icao: String) async -> UIImage? {
        guard let url = URL(string: "https://www.flightaware.com/images/airline_logos/180px/\(icao).png") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count > 500 else {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

private extension ARView {
    var currentInterfaceOrientation: UIInterfaceOrientation {
        if let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation {
            return orientation
        }

        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.effectiveGeometry.interfaceOrientation }
            .first ?? .portrait
    }
}

private extension ARCamera.TrackingState {
    var statusMessage: String? {
        switch self {
        case .normal:
            return nil
        case .notAvailable:
            return "Tracking unavailable"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "Initializing AR"
            case .excessiveMotion:
                return "Move more slowly"
            case .insufficientFeatures:
                return "Point at textured surroundings"
            case .relocalizing:
                return "Recovering tracking"
            @unknown default:
                return "Tracking limited"
            }
        }
    }
}

#Preview {
    let settings = SettingsStore.shared
    let location = LocationService()
    let follow = FollowStore()

    ARAircraftView()
        .environment(settings)
        .environment(location)
        .environment(AircraftDataStore(router: APIRouter(settings: settings),
                                       settings: settings,
                                       location: location,
                                       follow: follow))
        .environment(NavigationCoordinator())
        .environment(follow)
        .environment(ARPermissionStore())
        .modelContainer(for: Favorite.self, inMemory: true)
}
