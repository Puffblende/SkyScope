import SwiftUI

/// Tab 4 — user preferences. Backed by SettingsStore (@Observable + UserDefaults).
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

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
                }

                Section {
                    Toggle("Use FlightAware (Primary)", isOn: $settings.useFlightAware)
                    if settings.useFlightAware {
                        SecureField("API Key", text: $settings.flightAwareApiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Toggle("Fall back to OpenSky", isOn: $settings.useOpenSkyFallback)
                } header: {
                    Text("Data Sources")
                } footer: {
                    Text("FlightAware AeroAPI requires an API key. OpenSky works anonymously but provides less detail.")
                }

                if settings.useOpenSkyFallback || !settings.useFlightAware {
                    Section {
                        TextField("Username (optional)", text: $settings.openSkyUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password (optional)", text: $settings.openSkyPassword)
                    } header: {
                        Text("OpenSky Credentials")
                    } footer: {
                        Text("Optional — authenticated requests have higher rate limits.")
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
