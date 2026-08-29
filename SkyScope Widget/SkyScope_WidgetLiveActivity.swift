import ActivityKit
import WidgetKit
import SwiftUI

struct SkyScope_WidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SkyScopeActivityAttributes.self) { context in
            // MARK: - Lock Screen / Banner
            Group {
                if context.state.lockScreenStyle == "radar" {
                    RadarLockScreenView(state: context.state)
                } else {
                    TelemetryLockScreenView(state: context.state)
                }
            }
            .widgetURL(URL(string: "skyscope://aircraft/\(context.state.callsign.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? context.state.callsign)"))
            .activityBackgroundTint(Color.black)
            .activitySystemActionForegroundColor(Color.blue)

        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Dynamic Island Expanded
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "airplane")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text(context.state.callsign)
                            .font(.headline.bold())
                            .lineLimit(1)
                        Text(context.state.aircraftType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        if !context.state.aircraftTypeFullName.isEmpty {
                            Text(context.state.aircraftTypeFullName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let registration = context.state.registration {
                            Text("·").foregroundStyle(.secondary)
                            Text(registration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let origin = context.state.origin,
                           let destination = context.state.destination {
                            RouteProgressView(
                                origin: origin,
                                destination: destination,
                                progress: context.state.progress ?? 0.5
                            )
                            .frame(height: 18)
                        }

                        HStack(spacing: 0) {
                            diMetricColumn(label: "ALT", value: context.state.altitude)
                            diMetricColumn(label: "SPD", value: context.state.speed)
                            diMetricColumn(label: "HDG", value: context.state.heading)
                            if let dist = context.state.distanceNM {
                                diMetricColumn(label: "DIST", value: String(format: "%.1f NM", dist))
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
            } compactLeading: {
                // MARK: - Dynamic Island Compact Leading
                HStack(spacing: 4) {
                    Image(systemName: "airplane")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                    // Proximity / approach → show registration; flight+alt → callsign
                    let id = context.state.compactStyle == "flightAndAltitude"
                        ? context.state.callsign
                        : (context.state.registration ?? context.state.callsign)
                    Text(id)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
            } compactTrailing: {
                // MARK: - Dynamic Island Compact Trailing
                switch context.state.compactStyle {
                case "proximity":
                    if let dist = context.state.distanceNM {
                        HStack(spacing: 2) {
                            Text(String(format: "%.1f", dist))
                                .font(.caption.monospaced())
                                .foregroundStyle(.blue)
                            Text("NM")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(context.state.altitude)
                            .font(.caption.monospaced())
                            .foregroundStyle(.blue)
                    }
                case "approachCountdown":
                    if let mins = context.state.minutesToClosest {
                        HStack(spacing: 3) {
                            Image(systemName: "scope")
                                .font(.system(size: 9))
                                .foregroundStyle(.green)
                            Text("\(mins) min")
                                .font(.caption.monospaced())
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text(context.state.altitude)
                            .font(.caption.monospaced())
                            .foregroundStyle(.blue)
                    }
                default: // "flightAndAltitude"
                    Text(context.state.altitude)
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                }
            } minimal: {
                // MARK: - Dynamic Island Minimal
                Image(systemName: "airplane")
                    .foregroundStyle(.blue)
            }
            .keylineTint(Color.blue)
        }
    }

    @ViewBuilder
    private func diMetricColumn(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.blue)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Telemetry Lock Screen Layout (default)

private struct TelemetryLockScreenView: View {
    let state: SkyScopeActivityAttributes.ContentValues

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: icon + callsign + type + registration
            HStack(spacing: 6) {
                Image(systemName: "airplane")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text(state.callsign)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .foregroundStyle(.white)
                if !state.aircraftTypeFullName.isEmpty {
                    Text(state.aircraftTypeFullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let registration = state.registration {
                    Text(registration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let dist = state.distanceNM {
                    Text(String(format: "%.1f NM", dist))
                        .font(.caption.monospaced())
                        .foregroundStyle(.blue)
                }
            }

            // Route progress bar (if origin + destination available)
            if let origin = state.origin, let destination = state.destination {
                RouteProgressView(
                    origin: origin,
                    destination: destination,
                    progress: state.progress ?? 0.5
                )
                .frame(height: 20)
            }

            // Telemetry grid: ALT | SPD | HDG | SQK
            HStack(spacing: 8) {
                telemetryCell("ALT", state.altitude)
                Divider().frame(height: 20)
                telemetryCell("SPD", state.speed)
                Divider().frame(height: 20)
                telemetryCell("HDG", state.heading)
                Divider().frame(height: 20)
                telemetryCell("SQK", state.squawk ?? "—")
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func telemetryCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Radar Lock Screen Layout

private struct RadarLockScreenView: View {
    let state: SkyScopeActivityAttributes.ContentValues

    var body: some View {
        HStack(spacing: 16) {
            // Radar scope
            RadarScopeView(
                distanceNM: state.distanceNM,
                bearingDeg: state.bearingDeg,
                size: 72
            )

            // Aircraft details
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(state.registration ?? state.callsign)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    if let airline = state.airline {
                        Text(airline)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                Text("\(state.totalNearbyCount) aircraft nearby")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    if let dist = state.distanceNM {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: "%.1f NM", dist))
                                .font(.system(.subheadline, design: .monospaced).bold())
                                .foregroundStyle(.white)
                            Text("DISTANCE")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let bearing = state.bearingDeg {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: "%03d°", bearing))
                                .font(.system(.subheadline, design: .monospaced).bold())
                                .foregroundStyle(.white)
                            Text("BEARING")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let mins = state.minutesToClosest {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(mins) min")
                                .font(.system(.subheadline, design: .monospaced).bold())
                                .foregroundStyle(.green)
                            Text("CLOSEST")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - Radar Scope View

private struct RadarScopeView: View {
    let distanceNM: Double?
    let bearingDeg: Int?
    let size: CGFloat

    var body: some View {
        ZStack {
            // Three concentric range rings
            ForEach([1.0, 0.66, 0.33], id: \.self) { scale in
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 0.75)
                    .frame(width: size * scale, height: size * scale)
            }
            // Cross hairs
            Group {
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 0.5, height: size)
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(width: size, height: 0.5)
            }

            // User dot (centre)
            Circle()
                .fill(.blue)
                .frame(width: 7, height: 7)
            Circle()
                .stroke(.blue.opacity(0.35), lineWidth: 2)
                .frame(width: 14, height: 14)

            // Aircraft dot — placed at the correct bearing / normalized distance
            if let bearing = bearingDeg, let dist = distanceNM {
                let angle = Double(bearing) * .pi / 180
                // Max radar range: 100 NM maps to outer ring edge
                let norm = min(dist / 100.0, 1.0)
                let r = CGFloat(norm) * (size / 2 - 6)

                Image(systemName: "airplane")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(Double(bearing)))
                    .offset(
                        x: CGFloat(sin(angle)) * r,
                        y: -CGFloat(cos(angle)) * r
                    )
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Route Progress View

struct RouteProgressView: View {
    let origin: String
    let destination: String
    let progress: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(origin)
                .font(.caption.bold())
                .foregroundStyle(.blue)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 2)
                    Image(systemName: "airplane.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .offset(x: (geometry.size.width * progress) - 7)
                }
            }
            .frame(height: 12)

            Text(destination)
                .font(.caption.bold())
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Previews

#Preview("Lock Screen – Telemetry", as: .content, using: SkyScopeActivityAttributes(userLocation: "SkyScope")) {
    SkyScope_WidgetLiveActivity()
} contentStates: {
    SkyScopeActivityAttributes.ContentValues(
        callsign: "LH2312",
        altitude: "34,000 ft",
        speed: "452 kts",
        heading: "036°",
        aircraftType: "A320",
        aircraftTypeFullName: "Airbus A320",
        airline: "Lufthansa",
        registration: "D-AIZG",
        origin: "EDDS",
        destination: "EDDB",
        progress: 0.72,
        squawk: "2145",
        updateTime: .now,
        lockScreenStyle: "telemetry",
        distanceNM: 26.7,
        minutesToClosest: 4,
        bearingDeg: 36,
        totalNearbyCount: 3
    )
}

#Preview("Lock Screen – Radar", as: .content, using: SkyScopeActivityAttributes(userLocation: "SkyScope")) {
    SkyScope_WidgetLiveActivity()
} contentStates: {
    SkyScopeActivityAttributes.ContentValues(
        callsign: "LH2312",
        altitude: "34,000 ft",
        speed: "452 kts",
        heading: "036°",
        aircraftType: "A320",
        aircraftTypeFullName: "Airbus A320",
        airline: "Lufthansa",
        registration: "D-AIZG",
        updateTime: .now,
        lockScreenStyle: "radar",
        distanceNM: 26.7,
        minutesToClosest: 4,
        bearingDeg: 36,
        totalNearbyCount: 3
    )
}

#Preview("DI – Proximity", as: .content, using: SkyScopeActivityAttributes(userLocation: "SkyScope")) {
    SkyScope_WidgetLiveActivity()
} contentStates: {
    SkyScopeActivityAttributes.ContentValues(
        callsign: "LH2312",
        altitude: "34,000 ft",
        speed: "452 kts",
        heading: "036°",
        aircraftType: "A320",
        aircraftTypeFullName: "Airbus A320",
        registration: "D-AIZG",
        updateTime: .now,
        compactStyle: "proximity",
        distanceNM: 26.7,
        bearingDeg: 36
    )
}
