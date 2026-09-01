import SwiftUI
import ActivityKit
import AVFoundation
import UIKit

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AircraftDataStore.self) private var dataStore
    @Environment(ARPermissionStore.self) private var arPermission
    @Environment(\.scenePhase) private var scenePhase

    @State private var showRefreshInfo = false
    @State private var pendingAREnableAfterSettings = false
    @State private var versionTapTimes: [Date] = []

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            ScrollView {
                // Tap on empty space to dismiss keyboard
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                    .frame(maxWidth: .infinity, maxHeight: 0)
                VStack(spacing: 0) {

                    // MARK: Map Options
                    SectionHeader(title: "Map Options")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Aircraft badge style")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        BadgeStyleCard(
                            style: .solid,
                            title: "Solid",
                            subtitle: "Filled silhouette, high contrast",
                            isSelected: settings.badgeStyle == .solid
                        ) { settings.badgeStyle = .solid }

                        BadgeStyleCard(
                            style: .outline,
                            title: "Outline",
                            subtitle: "Directional dart, lighter on dense maps",
                            isSelected: settings.badgeStyle == .outline
                        ) { settings.badgeStyle = .outline }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    ConeColorCard(settings: settings)
                        .padding(.bottom, 24)

                    arSettingsSection
                        .padding(.bottom, 24)

                    // MARK: Units
                    SectionHeader(title: "Units")
                    GroupedCard {
                        SegmentedRow(label: "Altitude", selection: $settings.altitudeUnit,
                                     options: [(AltitudeUnit.feet, "ft"), (.meters, "m")])
                        Divider().padding(.leading, 16)
                        SegmentedRow(label: "Speed", selection: $settings.speedUnit,
                                     options: [(SpeedUnit.knots, "kts"), (.kmh, "km/h")])
                        Divider().padding(.leading, 16)
                        SegmentedRow(label: "Distance", selection: $settings.distanceUnit,
                                     options: [(DistanceUnit.nauticalMiles, "NM"), (.kilometers, "km")])
                    }

                    // MARK: Refresh
                    HStack(spacing: 4) {
                        Text("Refresh")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showRefreshInfo.toggle() }
                        } label: {
                            Image(systemName: showRefreshInfo ? "info.circle.fill" : "info.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .padding(.bottom, showRefreshInfo ? 4 : 6)

                    if showRefreshInfo {
                        Text("Controls background / Live Activity refresh. In the foreground the app always polls every 30 s regardless.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(.secondaryLabel))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 6)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    GroupedCard {
                        HStack {
                            Text("Interval")
                                .font(.system(size: 17))
                            Spacer()
                            RefreshSegmentedControl(selection: $settings.refreshInterval)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    Spacer().frame(height: 24)

                    // MARK: Appearance
                    SectionHeader(title: "Appearance")
                    GroupedCard {
                        HStack {
                            Text("Theme")
                                .font(.system(size: 17))
                            Spacer()
                            ThemeSegmentedControl(selection: $settings.colorScheme)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .padding(.bottom, 10)

                    GroupedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("App Icon")
                                .font(.system(size: 17))
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                            AppIconGrid()
                                .padding(.horizontal, 16)
                                .padding(.bottom, 14)
                        }
                    }
                    .padding(.bottom, 24)

                    // MARK: Live Activity
                    SectionHeader(title: "Live Activity")
                    GroupedCard {
                        HStack {
                            Text("Launch at app startup")
                                .font(.system(size: 17))
                            Spacer()
                            Toggle("", isOn: $settings.launchLiveActivityOnStartup)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        Divider().padding(.leading, 16)

                        HStack {
                            Text("Status")
                                .font(.system(size: 17))
                            Spacer()
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(LiveActivityManager.shared.isRunning ? Color.green : Color(.tertiaryLabel))
                                    .frame(width: 8, height: 8)
                                Text(LiveActivityManager.shared.isRunning ? "Running" : "Not running")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        Divider().padding(.leading, 16)

                        Button {
                            Task {
                                if LiveActivityManager.shared.isRunning {
                                    await LiveActivityManager.shared.stop()
                                } else {
                                    await LiveActivityManager.shared.start(target: dataStore.aircraft.first)
                                }
                            }
                        } label: {
                            Text(LiveActivityManager.shared.isRunning ? "Stop Live Activity" : "Start Live Activity")
                                .font(.system(size: 17))
                                .foregroundStyle(LiveActivityManager.shared.isRunning ? Color.red : Color.accentColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: Dynamic Island Style
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dynamic Island pairing")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        ForEach(DynamicIslandCompactStyle.allCases) { style in
                            DICompactStyleCard(
                                style: style,
                                isSelected: settings.dynamicIslandCompactStyle == style
                            ) { settings.dynamicIslandCompactStyle = style }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    // MARK: Lock Screen Layout
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lock screen layout")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        ForEach(LockScreenLayoutStyle.allCases) { style in
                            LockScreenStyleCard(
                                style: style,
                                isSelected: settings.lockScreenLayoutStyle == style
                            ) { settings.lockScreenLayoutStyle = style }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)

                    // MARK: OpenSky Credentials
                    SectionHeader(title: "OpenSky Credentials (optional)")
                    GroupedCard {
                        HStack(spacing: 12) {
                            Text("Username")
                                .font(.system(size: 17))
                                .frame(width: 88, alignment: .leading)
                            TextField("Optional", text: $settings.openSkyUsername)
                                .font(.system(size: 17))
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        Divider().padding(.leading, 16)

                        HStack(spacing: 12) {
                            Text("Password")
                                .font(.system(size: 17))
                                .frame(width: 88, alignment: .leading)
                            SecureField("Optional", text: $settings.openSkyPassword)
                                .font(.system(size: 17))
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                    }
                    Text("Authenticated OpenSky requests have a higher rate limit.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.horizontal, 36)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 24)

                    // MARK: Help & Support
                    SectionHeader(title: "Help & Support")
                    GroupedCard {
                        NavigationLink(destination: HelpView()) {
                            HStack {
                                Text("Help & FAQ")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(.tertiaryLabel))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 16)

                        NavigationLink(destination: FeedbackView()) {
                            HStack {
                                Text("Send Feedback")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(.tertiaryLabel))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 24)

                    // MARK: Version
                    GroupedCard {
                        HStack {
                            Text("Version")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(appVersion)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .contentShape(.rect)
                    .onTapGesture { handleVersionTap() }
                    .padding(.bottom, 32)
                }
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            refreshARPermissionState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshARPermissionState()
            }
        }
        .onChange(of: arPermission.cameraStatus) { _, _ in
            reconcileARPermissionState()
        }
    }

    private func handleVersionTap() {
        #if DEBUG
        let now = Date.now
        versionTapTimes.append(now)
        versionTapTimes = versionTapTimes.filter { now.timeIntervalSince($0) < 10 }
        guard versionTapTimes.count >= 10 else { return }
        versionTapTimes = []
        DebugStore.shared.toggle()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Augmented Reality

    private var arSettingsSection: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Augmented Reality")
            GroupedCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "arkit")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sky View AR")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Camera images stay on your device and are never stored or uploaded.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)
                        arStatusBadge
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    arSettingsControl
                }
            }
        }
    }

    private var arStatusBadge: some View {
        Text(arStatusText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(arStatusColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(arStatusColor.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var arSettingsControl: some View {
        if !arPermission.isARSupported {
            ARSettingsMessageRow(
                title: "Unavailable on this device",
                message: "Sky View needs AR world tracking support."
            )
        } else {
            switch arPermission.cameraStatus {
            case .authorized:
                HStack {
                    Text("Show AR button on map")
                        .font(.system(size: 17))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.arModeEnabled },
                        set: { settings.arModeEnabled = $0 }
                    ))
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            case .notDetermined:
                Button {
                    Task { await enableARFromSettings() }
                } label: {
                    ARSettingsActionRow(
                        title: "Enable Camera Access",
                        message: "iOS will ask for camera permission before the AR button appears.",
                        systemImage: "camera"
                    )
                }
                .buttonStyle(.plain)
            case .denied, .restricted:
                Button {
                    openCameraSettingsForAR()
                } label: {
                    ARSettingsActionRow(
                        title: "Open iOS Settings",
                        message: "Allow camera access there, then return to enable Sky View.",
                        systemImage: "gearshape"
                    )
                }
                .buttonStyle(.plain)
            @unknown default:
                ARSettingsMessageRow(
                    title: "Camera status unknown",
                    message: "Sky View is inactive until camera access can be checked."
                )
            }
        }
    }

    private var arStatusText: String {
        guard arPermission.isARSupported else { return "Unavailable" }

        switch arPermission.cameraStatus {
        case .authorized:
            return settings.arModeEnabled ? "Enabled" : "Inactive"
        case .notDetermined:
            return "Inactive"
        case .denied, .restricted:
            return "Permission Needed"
        @unknown default:
            return "Inactive"
        }
    }

    private var arStatusColor: Color {
        guard arPermission.isARSupported else { return Color(.secondaryLabel) }

        switch arPermission.cameraStatus {
        case .authorized:
            return settings.arModeEnabled ? .green : Color(.secondaryLabel)
        case .notDetermined:
            return .orange
        case .denied, .restricted:
            return .red
        @unknown default:
            return Color(.secondaryLabel)
        }
    }

    private func refreshARPermissionState() {
        arPermission.refreshCameraStatus()

        if pendingAREnableAfterSettings && arPermission.cameraStatus == .authorized {
            settings.arModeEnabled = true
            pendingAREnableAfterSettings = false
        }

        reconcileARPermissionState()
    }

    private func reconcileARPermissionState() {
        guard arPermission.isARSupported else {
            settings.arModeEnabled = false
            return
        }

        switch arPermission.cameraStatus {
        case .authorized, .notDetermined:
            break
        case .denied, .restricted:
            settings.arModeEnabled = false
            pendingAREnableAfterSettings = false
        @unknown default:
            settings.arModeEnabled = false
        }
    }

    private func enableARFromSettings() async {
        let granted = await arPermission.requestCameraAccess()
        settings.arModeEnabled = granted
    }

    private func openCameraSettingsForAR() {
        pendingAREnableAfterSettings = true
        settings.arModeEnabled = false
        arPermission.openAppSettings()
    }
}

private struct ARSettingsActionRow: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.accentColor)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ARSettingsMessageRow: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Reusable layout helpers

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }
}

private struct GroupedCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }
}

private struct SegmentedRow<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 17))
            Spacer()
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                    Button {
                        selection = pair.0
                    } label: {
                        Text(pair.1)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                selection == pair.0
                                    ? Color(.systemBackground).opacity(0.9)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .foregroundStyle(selection == pair.0 ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct RefreshSegmentedControl: View {
    @Binding var selection: RefreshInterval

    private let options: [(RefreshInterval, String)] = [
        (.oneMinute, "1 min"),
        (.twoMinutes, "2 min"),
        (.fiveMinutes, "5 min"),
        (.tenMinutes, "10 min"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0.id) { interval, label in
                Button {
                    selection = interval
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            selection == interval
                                ? Color(.systemBackground).opacity(0.9)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .foregroundStyle(selection == interval ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct ThemeSegmentedControl: View {
    @Binding var selection: AppColorScheme

    private let options: [(AppColorScheme, String)] = [
        (.system, "System"),
        (.light, "Light"),
        (.dark, "Dark"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0.id) { scheme, label in
                Button {
                    selection = scheme
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            selection == scheme
                                ? Color(.systemBackground).opacity(0.9)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .foregroundStyle(selection == scheme ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Badge style picker cards

private struct BadgeStyleCard: View {
    let style: BadgeStyle
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? Color.accentColor : Color(.tertiaryLabel), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 0) {
                    BadgeStatePreview(style: style, state: .normal, label: "Normal")
                    Spacer()
                    BadgeStatePreview(style: style, state: .selected, label: "Selected")
                    Spacer()
                    BadgeStatePreview(style: style, state: .followed, label: "Followed")
                    Spacer()
                    BadgeStatePreview(style: style, state: .favorited, label: "Favorited")
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private enum BadgePreviewState { case normal, selected, followed, favorited }

private struct BadgeStatePreview: View {
    let style: BadgeStyle
    let state: BadgePreviewState
    let label: String

    private static let accent = Color.accentColor
    private static let favorite = Color(red: 1.0, green: 0.624, blue: 0.039)

    // Normal and selected both use accent — selected just adds a glow
    private var iconColor: Color {
        switch state {
        case .normal, .selected: return Self.accent
        case .followed: return .white
        case .favorited: return Self.favorite
        }
    }
    private var ringColor: Color {
        switch state {
        case .favorited: return Self.favorite
        default: return Self.accent
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if state == .followed {
                    Circle()
                        .stroke(Self.accent.opacity(0.25), lineWidth: 7)
                        .frame(width: 48, height: 48)
                }

                // Inner badge — scaled up for selected state, matching the 1.25× on the map.
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(ringColor, lineWidth: 2.5))
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                        .shadow(color: state == .selected ? ringColor : .clear, radius: 10)
                        .shadow(color: state == .selected ? ringColor.opacity(0.5) : .clear, radius: 4)
                    Group {
                        if style == .solid {
                            SolidPreviewShape().fill(iconColor)
                        } else {
                            OutlinePreviewShape().stroke(iconColor, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .scaleEffect(state == .selected ? 1.2 : 1.0)
            }
            .frame(width: 48, height: 48)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// Mini versions of the shapes for the preview grid (same paths, different size context)
private struct SolidPreviewShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12 * s
        let oy = rect.midY - 12 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        p.move(to: pt(12, 2.6)); p.addLine(to: pt(13.1, 3.7)); p.addLine(to: pt(13.1, 10.3))
        p.addLine(to: pt(20.5, 14.5)); p.addLine(to: pt(20.5, 16.4)); p.addLine(to: pt(13.1, 14.1))
        p.addLine(to: pt(13.1, 19.3)); p.addLine(to: pt(15.4, 21.0)); p.addLine(to: pt(15.4, 22.5))
        p.addLine(to: pt(12, 21.6)); p.addLine(to: pt(8.6, 22.5)); p.addLine(to: pt(8.6, 21.0))
        p.addLine(to: pt(10.9, 19.3)); p.addLine(to: pt(10.9, 14.1)); p.addLine(to: pt(3.5, 16.4))
        p.addLine(to: pt(3.5, 14.5)); p.addLine(to: pt(10.9, 10.3)); p.addLine(to: pt(10.9, 3.7))
        p.closeSubpath()
        return p
    }
}

private struct OutlinePreviewShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12 * s
        let oy = rect.midY - 12 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        p.move(to: pt(12, 3.2)); p.addLine(to: pt(19.6, 20.4)); p.addLine(to: pt(12, 17.4))
        p.addLine(to: pt(4.4, 21.0)); p.closeSubpath()
        return p
    }
}

// MARK: - Dynamic Island compact style picker

private struct DICompactStyleCard: View {
    let style: DynamicIslandCompactStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                DICompactPreview(style: style)
                    .frame(width: 148, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(style.label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(style.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.accentColor : Color(.tertiaryLabel), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color.accentColor).frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// Mini Dynamic Island pill preview shown inside the card.
private struct DICompactPreview: View {
    let style: DynamicIslandCompactStyle

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: "airplane")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(style == .flightAndAltitude ? "LH2312" : "D-AIZG")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 10)

            Spacer()

            trailingLabel
                .padding(.trailing, 10)
        }
        .padding(.vertical, 5)
        .background(.black, in: Capsule())
    }

    @ViewBuilder
    private var trailingLabel: some View {
        switch style {
        case .flightAndAltitude:
            Text("34,000 ft")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.blue)
        case .proximity:
            HStack(spacing: 2) {
                Text("26.7")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.blue)
                Text("NM")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(.secondaryLabel))
            }
        case .approachCountdown:
            HStack(spacing: 3) {
                Image(systemName: "scope")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                Text("4 min")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Lock screen layout picker

private struct LockScreenStyleCard: View {
    let style: LockScreenLayoutStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LockScreenMiniPreview(style: style)
                    .frame(width: 72, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(style.label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(style.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.accentColor : Color(.tertiaryLabel), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color.accentColor).frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

private struct LockScreenMiniPreview: View {
    let style: LockScreenLayoutStyle

    var body: some View {
        ZStack {
            Color.black
            if style == .radar {
                HStack(spacing: 4) {
                    // Tiny radar
                    ZStack {
                        ForEach([1.0, 0.6], id: \.self) { s in
                            Circle().stroke(.white.opacity(0.25), lineWidth: 0.5)
                                .frame(width: 20 * s, height: 20 * s)
                        }
                        Circle().fill(.blue).frame(width: 3, height: 3)
                        Image(systemName: "airplane").font(.system(size: 5)).foregroundStyle(.white)
                            .offset(x: 5, y: -4)
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("D-AIZG").font(.system(size: 6, weight: .bold)).foregroundStyle(.white)
                        Text("26.7 NM").font(.system(size: 5, design: .monospaced)).foregroundStyle(.blue)
                        Text("036°").font(.system(size: 5, design: .monospaced)).foregroundStyle(.white)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "airplane").font(.system(size: 5)).foregroundStyle(.blue)
                        Text("LH2312").font(.system(size: 5, weight: .bold)).foregroundStyle(.white)
                    }
                    HStack(spacing: 4) {
                        Text("ALT").font(.system(size: 4)).foregroundStyle(.secondary)
                        Text("SPD").font(.system(size: 4)).foregroundStyle(.secondary)
                        Text("HDG").font(.system(size: 4)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("34k ft").font(.system(size: 4, design: .monospaced)).foregroundStyle(.white)
                        Text("452").font(.system(size: 4, design: .monospaced)).foregroundStyle(.white)
                        Text("036°").font(.system(size: 4, design: .monospaced)).foregroundStyle(.white)
                    }
                }
                .padding(4)
            }
        }
    }
}

// MARK: - App Icon grid

private struct AppIconGrid: View {
    @State private var selectedIcon: String = "Radar"

    private let icons: [(id: String, label: String)] = [
        ("Radar", "Radar"),
        ("Contrail", "Contrail"),
        ("Mono", "Mono"),
    ]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(icons, id: \.id) { icon in
                Button {
                    selectedIcon = icon.id
                    setAlternateIcon(icon.id)
                } label: {
                    VStack(spacing: 7) {
                        AppIconPreview(iconId: icon.id)
                            .frame(width: 62, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(selectedIcon == icon.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                    .padding(-2)
                            )
                        Text(icon.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                if icon.id != "Mono" { Spacer() }
            }
            Spacer()
        }
    }

    private func setAlternateIcon(_ id: String) {
        let name: String? = id == "Radar" ? nil : id
        UIApplication.shared.setAlternateIconName(name) { _ in }
    }
}

private struct AppIconPreview: View {
    let iconId: String

    var body: some View {
        switch iconId {
        case "Contrail":
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.071, green: 0.016, blue: 0.227),  // #12043a
                    Color(red: 0.357, green: 0.118, blue: 0.561),  // #5b1e8f
                    Color(red: 1.000, green: 0.420, blue: 0.290),  // #ff6b4a
                ],
                               startPoint: UnitPoint(x: 0.2, y: 0.1),
                               endPoint: UnitPoint(x: 0.9, y: 0.9))
                Canvas { ctx, size in
                    let w = size.width, h = size.height
                    var trail = Path()
                    trail.move(to: CGPoint(x: w * 0.05, y: h * 0.92))
                    trail.addQuadCurve(to: CGPoint(x: w * 0.64, y: h * 0.45),
                                       control: CGPoint(x: w * 0.3, y: h * 0.92))
                    ctx.stroke(trail, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    ctx.stroke(trail, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    // Plane icon at tip
                    let px = w * 0.72, py = h * 0.28
                    let ps: CGFloat = 10
                    var plane = Path()
                    plane.move(to: CGPoint(x: px, y: py - ps * 0.62))
                    plane.addLine(to: CGPoint(x: px + ps * 0.46, y: py + ps * 0.35))
                    plane.addLine(to: CGPoint(x: px, y: py + ps * 0.17))
                    plane.addLine(to: CGPoint(x: px - ps * 0.46, y: py + ps * 0.35))
                    plane.closeSubpath()
                    ctx.fill(plane, with: .color(.white))
                }
            }
        case "Mono":
            ZStack {
                Color(red: 0.067, green: 0.075, blue: 0.086) // #111316
                OutlinePreviewShape()
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(45))
            }
        default: // Radar
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.043, green: 0.118, blue: 0.239),  // #0b1e3d
                    Color(red: 0.122, green: 0.302, blue: 0.561),  // #1f4d8f
                ],
                               startPoint: UnitPoint(x: 0.1, y: 0.1),
                               endPoint: UnitPoint(x: 0.9, y: 0.9))
                Circle().stroke(.white.opacity(0.28), lineWidth: 1).frame(width: 46, height: 46)
                Circle().stroke(.white.opacity(0.32), lineWidth: 1).frame(width: 26, height: 26)
                SolidPreviewShape()
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(45))
            }
        }
    }
}

// MARK: - Cone color picker card

private struct ConeColorCard: View {
    let settings: SettingsStore

    private static let presets: [(hex: String, color: Color)] = [
        ("#FFFFFF", .white),
        ("#FFD60A", Color(hex: "#FFD60A")),
        ("#5AC8FA", Color(hex: "#5AC8FA")),
        ("#FF9500", Color(hex: "#FF9500")),
        ("#30D158", Color(hex: "#30D158")),
        ("#FF375F", Color(hex: "#FF375F")),
    ]

    private var isPresetSelected: Bool {
        Self.presets.contains { $0.hex == settings.coneColorHex }
    }

    var body: some View {
        GroupedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Direction cone color")
                    .font(.system(size: 17))
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                HStack(spacing: 12) {
                    ForEach(Self.presets, id: \.hex) { preset in
                        let isSelected = settings.coneColorHex == preset.hex
                        Button {
                            settings.coneColorHex = preset.hex
                        } label: {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().strokeBorder(
                                        isSelected ? Color.accentColor : Color(.separator),
                                        lineWidth: isSelected ? 2.5 : 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Custom color picker — shows current color, opens system picker on tap
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { settings.coneColor },
                            set: { settings.coneColor = $0 }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle().strokeBorder(
                            isPresetSelected ? Color.clear : Color.accentColor,
                            lineWidth: 2.5
                        )
                        .frame(width: 36, height: 36)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(SettingsStore.shared)
        .environment(AircraftDataStore(router: APIRouter(settings: SettingsStore.shared),
                                       settings: SettingsStore.shared,
                                       location: LocationService(),
                                       follow: FollowStore()))
}
