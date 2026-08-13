import SwiftUI
import ActivityKit

/// Tab 4 — user preferences. Backed by SettingsStore (@Observable + UserDefaults).
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AircraftDataStore.self) private var dataStore

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section("Search Radius") {
                    HStack {
                        Text("Radius")
                        Spacer()
                        Text("\(Int(settings.radiusValue)) \(settings.distanceUnit.shortLabel)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.radiusValue, in: 5...250, step: 5)
                    Picker("Distance Unit", selection: $settings.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                }

                Section("Units") {
                    Picker("Altitude", selection: $settings.altitudeUnit) {
                        ForEach(AltitudeUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    Picker("Speed", selection: $settings.speedUnit) {
                        ForEach(SpeedUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                }

                Section("Refresh") {
                    Picker("Refresh interval", selection: $settings.refreshInterval) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.colorScheme) {
                        ForEach(AppColorScheme.allCases) { scheme in
                            Text(scheme.label).tag(scheme)
                        }
                    }
                    .pickerStyle(.segmented)
                }


                Section("Live Activity") {
                    Toggle("Launch on app startup", isOn: $settings.launchLiveActivityOnStartup)

                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(LiveActivityManager.shared.isRunning ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(LiveActivityManager.shared.isRunning ? "Active" : "Inactive")
                                .font(.body)
                        }
                        Spacer()
                    }

                    Button(action: {
                        Task {
                            if LiveActivityManager.shared.isRunning {
                                await LiveActivityManager.shared.stop()
                            } else {
                                await LiveActivityManager.shared.start(target: dataStore.aircraft.first)
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: LiveActivityManager.shared.isRunning ? "stop.circle.fill" : "play.circle.fill")
                            Text(LiveActivityManager.shared.isRunning ? "Stop Live Activity" : "Start Live Activity")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.blue)
                }

                Section {
                    TextField("OpenSky Username (optional)", text: $settings.openSkyUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("OpenSky Password (optional)", text: $settings.openSkyPassword)
                } header: {
                    Text("OpenSky Credentials")
                } footer: {
                    Text("Optional — authenticated OpenSky requests have higher rate limits.")
                }

                Section("Help & Support") {
                    NavigationLink(destination: HelpView()) {
                        Label("Help & FAQ", systemImage: "questionmark.circle")
                    }
                    NavigationLink(destination: FeedbackView()) {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(SettingsStore.shared)
}
