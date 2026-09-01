import SwiftUI

/// Bottom-sheet showing current weather at the user's location.
/// Shown on demand — data is fetched only when the user taps the weather button.
struct WeatherOverlayView: View {
    let weather: WeatherData

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerSection
                cloudSummarySection
                metricGrid
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .scrollIndicators(.hidden)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            Image(systemName: weather.symbolName)
                .font(.system(size: 40))
                .symbolRenderingMode(.multicolor)
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(weather.description)
                        .font(.headline.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    let cond = weather.flightCondition
                    Text(cond.label)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(cond.color.opacity(0.18), in: .capsule)
                        .foregroundStyle(cond.color)
                }

                HStack(spacing: 8) {
                    Text(String(format: "%.1f°C", weather.temperature))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Updated \(weather.fetchedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Cloud Summary

    private var cloudSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Clouds", systemImage: "cloud.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Text("Total \(weather.cloudCoverTotal)% · \(oktaLabel(weather.cloudCoverTotal))")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(cloudColor(weather.cloudCoverTotal))
            }

            CloudLayerStackView(
                highCover: weather.cloudCoverHigh,
                midCover: weather.cloudCoverMid,
                lowCover: weather.cloudCoverLow
            )
            .frame(height: 104)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Metrics

    private var metricGrid: some View {
        HStack(alignment: .top, spacing: 10) {
            WeatherMetricTile(
                title: "Wind",
                systemImage: "wind",
                value: String(format: "%.1f kts", weather.windSpeed),
                detail: "\(weather.windDirection)° · G \(String(format: "%.1f", weather.windGusts))"
            )

            WeatherMetricTile(
                title: "Visibility",
                systemImage: "eye",
                value: visibilityDisplay,
                detail: "\(weather.flightCondition.label) minima",
                detailColor: weather.flightCondition.color
            )

            WeatherMetricTile(
                title: "QNH",
                systemImage: "barometer",
                value: "\(Int(weather.pressure.rounded())) hPa",
                detail: String(format: "%.2f inHg", weather.pressure * 0.02953)
            )
        }
    }

    private var visibilityDisplay: String {
        let visKm = weather.visibility / 1_000
        return visKm >= 10 ? ">10 km" : String(format: "%.1f km", visKm)
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

private struct CloudLayerStackView: View {
    let highCover: Int
    let midCover: Int
    let lowCover: Int

    private let horizontalPadding: CGFloat = 14
    private let verticalPadding: CGFloat = 10
    private let rowHeight: CGFloat = 28
    private let labelWidth: CGFloat = 60

    private struct Layer: Identifiable {
        let id: String
        let title: String
        let altitude: String
        let coverage: Int
    }

    private var layers: [Layer] {
        [
            Layer(id: "high", title: "High", altitude: "FL180+", coverage: highCover),
            Layer(id: "mid", title: "Mid", altitude: "6.5-FL180", coverage: midCover),
            Layer(id: "low", title: "Low", altitude: "<6.5k ft", coverage: lowCover),
        ]
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(layers) { layer in
                    layerRow(layer)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .background(stackBackground)
        .overlay(stackBorder)
    }

    private func layerRow(_ layer: Layer) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(layer.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.88))
                Text(layer.altitude)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.54))
            }
            .frame(width: labelWidth, alignment: .leading)

            CloudCoverageBar(coverage: layer.coverage)

            Text("\(layer.coverage)%")
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(coverageColor(layer.coverage))
                .frame(width: 34, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
    }

    private var stackBackground: some View {
        GeometryReader { proxy in
            let separatorColor = Color.white.opacity(0.16)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.17, blue: 0.36),
                        Color(red: 0.20, green: 0.42, blue: 0.70),
                        Color(red: 0.42, green: 0.65, blue: 0.84),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Path { path in
                    let startX = horizontalPadding + labelWidth + 12
                    let endX = proxy.size.width - horizontalPadding
                    for y in [verticalPadding + rowHeight, verticalPadding + rowHeight * 2] {
                        path.move(to: CGPoint(x: startX, y: y))
                        path.addLine(to: CGPoint(x: endX, y: y))
                    }
                }
                .stroke(separatorColor, lineWidth: 0.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var stackBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.white.opacity(0.14), lineWidth: 1)
    }

    private func coverageColor(_ value: Int) -> Color {
        switch value {
        case 76...100: return .red
        case 51...75:  return .orange
        case 26...50:  return Color(red: 1.0, green: 0.75, blue: 0.0)
        default:       return .green
        }
    }
}

private struct CloudCoverageBar: View {
    let coverage: Int

    var body: some View {
        GeometryReader { proxy in
            let fraction = CGFloat(min(max(coverage, 0), 100)) / 100

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.13))

                if fraction > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.80),
                                    Color.white.opacity(0.34),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * fraction))
                        .opacity(0.45 + Double(fraction) * 0.45)
                }
            }
        }
        .frame(height: 9)
    }
}

private struct WeatherMetricTile: View {
    let title: String
    let systemImage: String
    let value: String
    let detail: String
    var valueColor: Color = .primary
    var detailColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            Text(value)
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(detailColor)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
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
