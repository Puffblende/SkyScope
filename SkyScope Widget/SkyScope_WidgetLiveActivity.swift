//
//  SkyScope_WidgetLiveActivity.swift
//  SkyScope Widget
//
//  Created by Dennis Kiefer on 28.05.26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct SkyScope_WidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SkyScopeActivityAttributes.self) { context in
            // MARK: - Lock Screen Expanded View
            VStack(alignment: .leading, spacing: 10) {
                // Row 1 (header): ✈  UAE20  Boeing 777-300ER  A6-ENA
                HStack(spacing: 6) {
                    Image(systemName: "airplane")
                        .font(.headline)
                        .foregroundStyle(.blue)

                    Text(context.state.callsign)
                        .font(.title3.bold())
                        .lineLimit(1)
                        .foregroundStyle(.white)

                    if !context.state.aircraftTypeFullName.isEmpty {
                        Text(context.state.aircraftTypeFullName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let registration = context.state.registration {
                        Text(registration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                // Row 3: Route Progress Bar (if origin + destination available)
                if let origin = context.state.origin,
                   let destination = context.state.destination {
                    RouteProgressView(
                        origin: origin,
                        destination: destination,
                        progress: context.state.progress ?? 0.5
                    )
                    .frame(height: 20)
                }

                // Row 4: Telemetry (one row, four columns: ALT | SPD | HDG | SQK)
                HStack(spacing: 8) {
                    // ALT
                    VStack(alignment: .center, spacing: 2) {
                        Text("ALT")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.altitude)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 20)

                    // SPD
                    VStack(alignment: .center, spacing: 2) {
                        Text("SPD")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.speed)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 20)

                    // HDG
                    VStack(alignment: .center, spacing: 2) {
                        Text("HDG")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.heading)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 20)

                    // SQK
                    VStack(alignment: .center, spacing: 2) {
                        Text("SQK")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.squawk ?? "—")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
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
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(registration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        // Route if available
                        if let origin = context.state.origin,
                           let destination = context.state.destination {
                            RouteProgressView(
                                origin: origin,
                                destination: destination,
                                progress: context.state.progress ?? 0.5
                            )
                            .frame(height: 18)
                        }

                        // Telemetry
                        HStack(spacing: 20) {
                            VStack(alignment: .center, spacing: 2) {
                                Text("ALT")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(context.state.altitude)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .center, spacing: 2) {
                                Text("SPD")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(context.state.speed)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .center, spacing: 2) {
                                Text("HDG")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(context.state.heading)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.blue)
                            }

                            Spacer()
                        }
                        .padding(8)
                    }
                }
            } compactLeading: {
                // MARK: - Dynamic Island Compact Leading
                HStack(spacing: 4) {
                    Image(systemName: "airplane")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    Text(context.state.callsign)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
            } compactTrailing: {
                // MARK: - Dynamic Island Compact Trailing
                Text(context.state.altitude)
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)
            } minimal: {
                // MARK: - Dynamic Island Minimal
                Image(systemName: "airplane")
                    .foregroundStyle(.blue)
            }
            .keylineTint(Color.blue)
        }
    }
}

// MARK: - Route Progress View Component
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
                    // Background line
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 2)

                    // Progress indicator (airplane icon) - offset from leading edge
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

#Preview("Lock Screen - Early Flight", as: .content, using: SkyScopeActivityAttributes(userLocation: "SkyScope")) {
    SkyScope_WidgetLiveActivity()
} contentStates: {
    SkyScopeActivityAttributes.ContentValues(
        callsign: "UAE20",
        altitude: "5,000 ft",
        speed: "250 kts",
        heading: "090°",
        aircraftType: "B77W",
        aircraftTypeFullName: "Boeing 777-300ER",
        airline: "Emirates",
        registration: "A6-ENA",
        origin: "EDDF",
        destination: "EGLL",
        progress: 0.2,
        squawk: "2145",
        updateTime: .now
    )
}

#Preview("Lock Screen - Late Flight", as: .content, using: SkyScopeActivityAttributes(userLocation: "SkyScope")) {
    SkyScope_WidgetLiveActivity()
} contentStates: {
    SkyScopeActivityAttributes.ContentValues(
        callsign: "UAE20",
        altitude: "37,000 ft",
        speed: "436 kts",
        heading: "304°",
        aircraftType: "B77W",
        aircraftTypeFullName: "Boeing 777-300ER",
        airline: "Emirates",
        registration: "A6-ENA",
        origin: "EDDF",
        destination: "EGLL",
        progress: 0.8,
        squawk: "2145",
        updateTime: .now
    )
}
