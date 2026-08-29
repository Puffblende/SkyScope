import SwiftUI

/// Bottom-sheet showing current weather at the user's location.
/// Shown on demand — data is fetched only when the user taps the weather button.
struct WeatherOverlayView: View {
    let weather: WeatherData

    var body: some View {
        ScrollView {
            VStack(spacing: 1) {
                headerSection
                skyProfileSection
                windSection
                visibilityPressureSection
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: weather.symbolName)
                .font(.system(size: 46))
                .symbolRenderingMode(.multicolor)
                .frame(width: 56)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(weather.description)
                        .font(.title3.bold())

                    let cond = weather.flightCondition
                    Text(cond.label)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(cond.color.opacity(0.18), in: .capsule)
                        .foregroundStyle(cond.color)
                }

                Text(String(format: "%.1f°C", weather.temperature))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Updated \(weather.fetchedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Sky Profile

    private var skyProfileSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Cloud Layers", systemImage: "cloud.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            SkyProfileView(
                highCover: weather.cloudCoverHigh,
                midCover: weather.cloudCoverMid,
                lowCover: weather.cloudCoverLow
            )
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.28), radius: 8, y: 3)

            HStack(spacing: 0) {
                Text("Total cover: ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(weather.cloudCoverTotal)%  \(oktaLabel(weather.cloudCoverTotal))")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(cloudColor(weather.cloudCoverTotal))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Wind

    private var windSection: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 1.5)
                    .frame(width: 64, height: 64)
                Image(systemName: "arrow.up")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .rotationEffect(.degrees(Double(weather.windDirection)))
                Text("\(weather.windDirection)°")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .offset(y: 26)
            }

            VStack(alignment: .leading, spacing: 5) {
                Label("Wind", systemImage: "wind")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(String(format: "%.1f kts", weather.windSpeed))
                    .font(.title3.bold().monospacedDigit())

                Text(String(format: "Gusts %.1f kts", weather.windGusts))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Visibility + QNH

    private var visibilityPressureSection: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Visibility", systemImage: "eye")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                let visKm = weather.visibility / 1_000
                Text(visKm >= 10 ? ">10 km" : String(format: "%.1f km", visKm))
                    .font(.title3.bold().monospacedDigit())

                let cond = weather.flightCondition
                Text(cond.label + " minima")
                    .font(.caption)
                    .foregroundStyle(cond.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 68)

            VStack(alignment: .leading, spacing: 5) {
                Label("QNH", systemImage: "barometer")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text("\(Int(weather.pressure.rounded())) hPa")
                    .font(.title3.bold().monospacedDigit())

                Text(String(format: "%.2f inHg", weather.pressure * 0.02953))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Helpers

    private func cloudColor(_ pct: Int) -> Color {
        switch pct {
        case 76...100: return .red
        case 51...75:  return .orange
        case 26...50:  return Color(red: 1.0, green: 0.75, blue: 0.0)
        default:       return .green
        }
    }

    private func oktaLabel(_ pct: Int) -> String {
        switch pct {
        case 0:        return "CLR"
        case 1...24:   return "FEW"
        case 25...50:  return "SCT"
        case 51...87:  return "BKN"
        default:       return "OVC"
        }
    }
}

// MARK: - Sky Cross-Section Visualization

/// Renders a vertical atmosphere cross-section showing three cloud altitude bands.
/// Each band's fill opacity and gradient shape mirrors the actual cloud type:
/// - High (FL180+): thin wispy cirrus — fades strongly at edges
/// - Mid (6,500–FL180): altocumulus — moderate, soft edges
/// - Low (< 6,500 ft): stratus — denser base, flat bottom
private struct SkyProfileView: View {
    let highCover: Int
    let midCover: Int
    let lowCover: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let groundH: CGFloat = 22
            let skyH = h - groundH
            let zoneH = skyH / 3

            ZStack(alignment: .topLeading) {
                // Sky gradient: deep space blue → horizon blue
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.05, blue: 0.22),
                        Color(red: 0.10, green: 0.26, blue: 0.62),
                        Color(red: 0.40, green: 0.65, blue: 0.90),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: w, height: skyH)

                // Ground strip
                LinearGradient(
                    colors: [
                        Color(red: 0.30, green: 0.22, blue: 0.11),
                        Color(red: 0.16, green: 0.12, blue: 0.06),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: w, height: groundH)
                .offset(y: skyH)

                // Cloud layers — each type gets a different gradient profile
                cloudLayer(highCover, type: .high)
                    .frame(width: w, height: zoneH)
                    .offset(y: 0)

                cloudLayer(midCover, type: .mid)
                    .frame(width: w, height: zoneH)
                    .offset(y: zoneH)

                cloudLayer(lowCover, type: .low)
                    .frame(width: w, height: zoneH)
                    .offset(y: 2 * zoneH)

                // Altitude zone dividers (dashed)
                dividerLine(at: zoneH, width: w)
                dividerLine(at: 2 * zoneH, width: w)

                // Zone labels: altitude on left, coverage + okta on right
                zoneLabel("FL180+",       "High", highCover, y: 0,         zoneH: zoneH)
                zoneLabel("6,500–FL180",  "Mid",  midCover,  y: zoneH,     zoneH: zoneH)
                zoneLabel("< 6,500 ft",   "Low",  lowCover,  y: 2 * zoneH, zoneH: zoneH)
            }
            .frame(width: w, height: h)
        }
    }

    // MARK: Cloud layer gradient

    private enum CloudType { case high, mid, low }

    @ViewBuilder
    private func cloudLayer(_ coverage: Int, type: CloudType) -> some View {
        if coverage > 0 {
            let f = Double(coverage) / 100.0
            Rectangle()
                .fill(gradient(factor: f, type: type))
        }
    }

    private func gradient(factor: Double, type: CloudType) -> LinearGradient {
        switch type {
        case .high:
            // Cirrus: very transparent, fades strongly at both edges — wispy look
            return LinearGradient(
                colors: [
                    .white.opacity(0),
                    .white.opacity(factor * 0.36),
                    .white.opacity(factor * 0.40),
                    .white.opacity(factor * 0.32),
                    .white.opacity(0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .mid:
            // Altocumulus: moderate density, soft top and bottom fade
            return LinearGradient(
                colors: [
                    .white.opacity(factor * 0.10),
                    .white.opacity(factor * 0.65),
                    .white.opacity(factor * 0.68),
                    .white.opacity(factor * 0.10),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .low:
            // Stratus: dense, flat base — heavy at bottom, soft at top
            return LinearGradient(
                colors: [
                    .white.opacity(factor * 0.15),
                    .white.opacity(factor * 0.70),
                    .white.opacity(factor * 0.88),
                    .white.opacity(factor * 0.90),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: Divider

    private func dividerLine(at y: CGFloat, width: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
        .stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 0.75, dash: [6, 10]))
    }

    // MARK: Zone label

    private func zoneLabel(_ altStr: String, _ typeStr: String, _ coverage: Int,
                            y: CGFloat, zoneH: CGFloat) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(altStr)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.80))
                Text(typeStr)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.leading, 10)
            .padding(.top, 8)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(coverage)%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(coverageColor(coverage))
                Text(oktaLabel(coverage))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.trailing, 10)
            .padding(.top, 8)
        }
        .frame(height: zoneH, alignment: .top)
        .offset(y: y)
    }

    private func coverageColor(_ pct: Int) -> Color {
        switch pct {
        case 76...100: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case 51...75:  return Color(red: 1.0, green: 0.65, blue: 0.20)
        case 26...50:  return Color(red: 1.0, green: 0.90, blue: 0.00)
        default:       return Color(red: 0.40, green: 1.0,  blue: 0.50)
        }
    }

    private func oktaLabel(_ pct: Int) -> String {
        switch pct {
        case 0:        return "CLR"
        case 1...24:   return "FEW"
        case 25...50:  return "SCT"
        case 51...87:  return "BKN"
        default:       return "OVC"
        }
    }
}
