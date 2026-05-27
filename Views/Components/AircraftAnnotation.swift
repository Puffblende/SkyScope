import SwiftUI

/// Plane icon rotated toward the aircraft's heading. Used inside Map annotations.
struct AircraftAnnotation: View {
    let aircraft: Aircraft
    let isFavorite: Bool

    var body: some View {
        Image(systemName: "airplane")
            .font(.title2)
            .foregroundStyle(isFavorite ? .yellow : .accentColor)
            .padding(6)
            .background(.thinMaterial, in: .circle)
            .overlay(
                Circle()
                    .stroke(isFavorite ? Color.yellow : Color.accentColor, lineWidth: 2)
            )
            // Default airplane SF Symbol points right (90°). Subtract 90° so 0° = north.
            .rotationEffect(.degrees((aircraft.headingDegrees ?? 0) - 90))
            .accessibilityLabel(aircraft.displayName)
    }
}
