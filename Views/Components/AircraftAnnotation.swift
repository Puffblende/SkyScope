import SwiftUI

/// Plane icon rotated toward the aircraft's heading. Supports Solid and Outline badge styles.
/// `badgeStyle` is passed explicitly because MapKit annotation content closures don't reliably
/// propagate SwiftUI environment values.
struct AircraftAnnotation: View {
    let aircraft: Aircraft
    let isFavorite: Bool
    var isFollowed: Bool = false
    var isSelected: Bool = false
    var badgeStyle: BadgeStyle = .solid

    private static let accentColor = Color.accentColor
    private static let favoriteColor = Color(red: 1.0, green: 0.624, blue: 0.039) // #FF9F0A

    // Normal and selected both show accent ring + tint — selected adds a glow.
    private var iconColor: Color {
        if isFollowed { return .white }
        if isFavorite { return Self.favoriteColor }
        return Self.accentColor
    }

    private var ringColor: Color {
        if isFavorite { return Self.favoriteColor }
        if isFollowed { return Self.accentColor }
        return Self.accentColor
    }

    private var ringWidth: CGFloat { 2.5 }

    var body: some View {
        ZStack {
            // Outer halo for followed state
            if isFollowed {
                Circle()
                    .stroke(Self.accentColor.opacity(0.25), lineWidth: 7)
                    .frame(width: 48, height: 48)
            }

            Circle()
                // Dark base + coloured ring + coloured icon — same language as the reference.
                .fill(Color.black.opacity(0.75))
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(ringColor, lineWidth: ringWidth))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                // Selected: coloured glow to distinguish from normal
                .shadow(color: isSelected ? ringColor.opacity(0.85) : .clear, radius: 14)
                .shadow(color: isSelected ? ringColor.opacity(0.55) : .clear, radius: 6)

            planeIcon
                .frame(width: 22, height: 22)
        }
        .scaleEffect(isSelected ? 1.25 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .accessibilityLabel(aircraft.displayName)
    }

    @ViewBuilder
    private var planeIcon: some View {
        let heading = aircraft.headingDegrees ?? 0
        switch badgeStyle {
        case .solid:
            SolidPlaneShape(heading: heading).fill(iconColor)
        case .outline:
            OutlineDartShape(heading: heading).stroke(iconColor, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        }
    }
}

// MARK: - Solid filled plane silhouette
// Heading is baked into the path so MapKit annotation caching can't suppress the rotation.
// SVG: M12 2.6l1.1 1.1v6.6l7.4 4.2v1.9l-7.4-2.3v5.2l2.3 1.7v1.5L12 21.6l-3.4.9v-1.5l2.3-1.7v-5.2L3.5 16.4v-1.9l7.4-4.2V3.7L12 2.6z
private struct SolidPlaneShape: Shape {
    var heading: Double = 0

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
        return p.applying(rotationTransform(in: rect))
    }

    private func rotationTransform(in rect: CGRect) -> CGAffineTransform {
        let angle = CGFloat(heading * .pi / 180)
        return CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: angle)
            .translatedBy(x: -rect.midX, y: -rect.midY)
    }
}

// MARK: - Outline dart / directional arrow
// SVG: M12 3.2l7.6 17.2a.5.5 0 01-.7.6L12 17.4l-6.9 3.6a.5.5 0 01-.7-.6L12 3.2z
private struct OutlineDartShape: Shape {
    var heading: Double = 0

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.midX - 12 * s
        let oy = rect.midY - 12 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        p.move(to: pt(12, 3.2)); p.addLine(to: pt(19.6, 20.4))
        p.addLine(to: pt(12, 17.4)); p.addLine(to: pt(4.4, 21.0))
        p.closeSubpath()
        return p.applying(rotationTransform(in: rect))
    }

    private func rotationTransform(in rect: CGRect) -> CGAffineTransform {
        let angle = CGFloat(heading * .pi / 180)
        return CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: angle)
            .translatedBy(x: -rect.midX, y: -rect.midY)
    }
}
