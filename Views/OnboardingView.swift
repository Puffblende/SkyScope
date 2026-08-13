import SwiftUI
import CoreLocation
import UIKit
import UserNotifications

/// Seven-slide first-launch onboarding. Shown once; dismissed permanently when complete.
struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(LocationService.self) private var location

    @State private var step = 0
    @State private var isWaitingForLocation = false
    private let total = 7

    var body: some View {
        ZStack {
            // Slides — TabView fills the full screen (ignores safe areas).
            TabView(selection: $step) {
                slideWelcome.tag(0)
                slideHowItWorks.tag(1)
                slide0.tag(2)
                slide1.tag(3)
                slide2.tag(4)
                slide3.tag(5)
                slide4.tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Back chevron — only from slide 1 onward, hidden while permission dialog is pending.
            if step > 0 && !isWaitingForLocation {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { step -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 64)
                .padding(.leading, 20)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
        // safeAreaInset correctly anchors the chrome above the home indicator on every device.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: step)
                    }
                }
                .padding(.bottom, 22)

                // Continue / Get Started — action varies by slide.
                Button {
                    handleContinue()
                } label: {
                    Group {
                        if isWaitingForLocation {
                            ProgressView()
                                .tint(buttonTextColor)
                        } else {
                            Text(buttonLabel)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(buttonTextColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isWaitingForLocation)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        // Advance from slide 0 once the user responds to the location dialog.
        .onChange(of: location.authorizationStatus) { _, _ in
            if isWaitingForLocation {
                isWaitingForLocation = false
                advance()
            }
        }
    }

    // MARK: - Continue action

    private func handleContinue() {
        switch step {
        case 2:
            // Location slide: show system dialog, advance after user responds.
            if location.authorizationStatus != .notDetermined {
                // Permission already determined (e.g. previously installed), just advance.
                advance()
            } else {
                isWaitingForLocation = true
                location.requestAuthorization()
            }
        case 5:
            // Live Activity slide: request notification permission, then advance.
            Task {
                let granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                await MainActor.run {
                    if granted {
                        // Register APNs token for Firebase Cloud Messaging.
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    advance()
                }
            }
        default:
            advance()
        }
    }

    private func advance() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if step >= total - 1 { onComplete() } else { step += 1 }
        }
    }

    // MARK: - Button label

    private var buttonLabel: String {
        switch step {
        case 2: return "Allow Location Access"
        case total - 1: return "Get Started"
        default: return "Continue"
        }
    }

    // MARK: - Button text colour (dark shade matching each slide's background)

    private var buttonTextColor: Color {
        switch step {
        case 0:  return Color(red: 0.102, green: 0.051, blue: 0.243)  // Welcome: dark violet
        case 1:  return Color(red: 0.024, green: 0.157, blue: 0.188)  // How It Works: dark teal
        case 2:  return Color(red: 0.043, green: 0.118, blue: 0.239)  // Location: dark blue
        case 3:  return Color(red: 0.027, green: 0.231, blue: 0.227)  // Radius: dark teal
        case 4:  return Color(red: 0.078, green: 0.157, blue: 0.314)  // Map: mid blue
        case 5:  return Color(red: 0.020, green: 0.027, blue: 0.051)  // Live Activity: near-black
        default: return Color(red: 0.169, green: 0.063, blue: 0.333)  // Favorites: dark purple
        }
    }

    // MARK: - Slides

    private var slideWelcome: some View {
        shell(
            colors: [Color(hex: "1a0d3e"), Color(hex: "3d1470"), Color(hex: "c07525")],
            title: "Welcome to SkyScope",
            body: "Designed from the flight deck, for everyone who can't stop looking up. Whether you're spotting at the fence or tracking the club aircraft — every flight overhead is one glance away."
        ) { WelcomeIllustration() }
    }

    private var slideHowItWorks: some View {
        shell(
            colors: [Color(hex: "062838"), Color(hex: "0a4a5c"), Color(hex: "0d7870")],
            title: "Here's How It Works",
            body: "Define your search radius — say 50 km (27 NM). Only aircraft within that circle appear on your map, nearest first. Start the Live Activity and the closest flight updates live right on your Lock Screen."
        ) { HowItWorksIllustration() }
    }

    private var slide0: some View {
        shell(
            colors: [Color(hex: "0b1e3d"), Color(hex: "16386b"), Color(hex: "1f4d8f")],
            title: "Location Access",
            body: "SkyScope needs your location to find aircraft within your search radius and center the map on you."
        ) { RadarIllustration() }
    }

    private var slide1: some View {
        shell(
            colors: [Color(hex: "073b3a"), Color(hex: "0f5c56"), Color(hex: "1a8f7b")],
            title: "Search Radius & Units",
            body: "Set how far SkyScope looks for aircraft — default is 50 km (27 NM). Switch altitude, speed and distance between metric and imperial anytime in Settings."
        ) { OrbitIllustration() }
    }

    private var slide2: some View {
        shell(
            colors: [Color(hex: "142850"), Color(hex: "3b4a77"), Color(hex: "c97b3f")],
            title: "Map & Aircraft Detail",
            body: "Aircraft near you show up as icons oriented to their heading. Tap one for flight number, altitude, speed, heading and route."
        ) { PlaneIllustration() }
    }

    private var slide3: some View {
        shell(
            colors: [Color(hex: "05070d"), Color(hex: "12151f"), Color(hex: "1c2333")],
            title: "Live Activity",
            body: "That plane overhead — where is it coming from, where is it heading, what type is it? The Live Activity puts the answer on your Lock Screen without ever opening the app. It updates automatically while you go about your day."
        ) { IslandIllustration() }
    }

    private var slide4: some View {
        shell(
            colors: [Color(hex: "2b1055"), Color(hex: "7b2ff7"), Color(hex: "e08a3e")],
            title: "Favorites",
            body: "Save registrations you want to track — your club's aircraft, for example. You'll get a heads-up the moment one takes off."
        ) { FavoritesIllustration() }
    }

    // MARK: - Slide shell

    private func shell<I: View>(
        colors: [Color],
        title: String,
        body: String,
        @ViewBuilder illustration: () -> I
    ) -> some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: UnitPoint(x: 0.75, y: 0),
                endPoint: UnitPoint(x: 0.25, y: 1)
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                illustration()
                    .padding(.bottom, 32)

                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .tracking(-0.4)

                    Text(body)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 32)

                // Equal bottom spacer → content is vertically centred (chrome lives in safeAreaInset).
                Spacer()
            }
        }
    }
}

// MARK: - Slide 0: Welcome

private struct WelcomeIllustration: View {
    @State private var planeFloat: CGFloat = 0
    @State private var glowPulse: Double = 8
    @State private var starA: Double = 0.3
    @State private var starB: Double = 0.5
    @State private var starC: Double = 0.2

    var body: some View {
        ZStack {
            // Amber horizon glow
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "c07525").opacity(0.55), .clear],
                        center: .center, startRadius: 0, endRadius: 80
                    )
                )
                .frame(width: 160, height: 65)
                .offset(y: 72)

            // Horizon line
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 250, height: 1)
                .offset(y: 74)

            // Stars twinkling above the horizon
            starDot(x: -88, y: -62, opacity: starA, size: 3.5)
            starDot(x:  68, y: -76, opacity: starB, size: 3)
            starDot(x: -36, y: -30, opacity: starC, size: 2.5)
            starDot(x:  96, y: -38, opacity: starA, size: 2.5)
            starDot(x:  18, y: -86, opacity: starB, size: 3.5)
            starDot(x: -64, y: -52, opacity: starC, size: 2.5)

            // Main airplane — angled slightly upward, floating gently
            Image(systemName: "airplane")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-20))
                .offset(y: planeFloat)
                .shadow(color: Color(hex: "c07525").opacity(0.65), radius: glowPulse)
        }
        .frame(width: 250, height: 220)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { planeFloat = -14 }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { glowPulse = 22 }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { starA = 1.0 }
            withAnimation(.easeInOut(duration: 2.7).repeatForever(autoreverses: true).delay(0.5)) { starB = 1.0 }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true).delay(1.1)) { starC = 1.0 }
        }
    }

    private func starDot(x: CGFloat, y: CGFloat, opacity: Double, size: CGFloat) -> some View {
        Circle().fill(.white).frame(width: size, height: size).opacity(opacity).offset(x: x, y: y)
    }
}

// MARK: - Slide 1: How It Works

private struct HowItWorksIllustration: View {
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0.9
    @State private var plane1: Double = 0
    @State private var plane2: Double = 0
    @State private var plane3: Double = 0
    @State private var nearestPulse: Double = 1.0

    var body: some View {
        ZStack {
            // Outer dashed radius ring
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(width: 210, height: 210)

            // Inner reference ring
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: 124, height: 124)

            // Expanding pulse ring (radar sweep feel)
            Circle()
                .stroke(Color.white.opacity(ringOpacity), lineWidth: 1.2)
                .frame(width: 210, height: 210)
                .scaleEffect(ringScale)

            // Aircraft appearing inside the radius
            plane(x:  54, y: -56, angle:  35, opacity: plane1, nearest: false)
            plane(x: -64, y:  20, angle: -18, opacity: plane2, nearest: false)
            plane(x:  22, y:  66, angle:  65, opacity: plane3, nearest: true)

            // Center: user location pin
            ZStack {
                Circle().fill(Color.white.opacity(0.18)).frame(width: 30, height: 30)
                Image(systemName: "location.fill").font(.system(size: 14)).foregroundStyle(.white)
            }
        }
        .frame(width: 220, height: 220)
        .onAppear {
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                ringScale = 1.05
                ringOpacity = 0
            }
            withAnimation(.easeIn(duration: 0.7).delay(0.4)) { plane1 = 1.0 }
            withAnimation(.easeIn(duration: 0.7).delay(0.9)) { plane2 = 1.0 }
            withAnimation(.easeIn(duration: 0.7).delay(1.4)) { plane3 = 1.0 }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { nearestPulse = 1.25 }
        }
    }

    private func plane(x: CGFloat, y: CGFloat, angle: Double, opacity: Double, nearest: Bool) -> some View {
        let accent = Color(hex: "f4a623")
        return Image(systemName: "airplane")
            .font(.system(size: nearest ? 18 : 13, weight: .medium))
            .foregroundStyle(nearest ? accent : Color.white.opacity(0.75))
            .rotationEffect(.degrees(angle))
            .scaleEffect(nearest ? nearestPulse : 1.0)
            .shadow(color: nearest ? accent.opacity(0.7) : .clear, radius: 6)
            .offset(x: x, y: y)
            .opacity(opacity)
    }
}

// MARK: - Slide 2: Radar

private struct RadarIllustration: View {
    @State private var angle: Double = 0
    @State private var blip1: Double = 0.15
    @State private var blip2: Double = 0.15

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 1).frame(width: 220)
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 1).frame(width: 154)
            Circle().stroke(Color.white.opacity(0.20), lineWidth: 1).frame(width: 88)

            LinearGradient(
                colors: [Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.9), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 1, height: 110)
            .offset(y: 55)
            .rotationEffect(.degrees(angle))

            Circle().fill(Color(red: 0.56, green: 0.82, blue: 1.0)).frame(width: 7).opacity(blip1).offset(x: 40, y: -50)
            Circle().fill(Color(red: 0.56, green: 0.82, blue: 1.0)).frame(width: 6).opacity(blip2).offset(x: -40, y: 36)

            Image(systemName: "location.fill").font(.system(size: 34)).foregroundStyle(.white)
        }
        .frame(width: 220, height: 220)
        .onAppear {
            withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) { angle = 360 }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { blip1 = 0.9 }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(0.8)) { blip2 = 0.9 }
        }
    }
}

// MARK: - Slide 1: Orbit

private struct OrbitIllustration: View {
    @State private var orbitAngle: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(width: 220)
            Circle().fill(Color.white.opacity(0.06)).frame(width: 120)

            Image(systemName: "airplane")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white)
                .offset(y: -110)
                .rotationEffect(.degrees(orbitAngle))

            Circle().fill(.white).frame(width: 22)
        }
        .frame(width: 220, height: 220)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { orbitAngle = 360 }
        }
    }
}

// MARK: - Slide 2: Plane drift

private struct PlaneIllustration: View {
    @State private var drift: Double = 0
    @State private var rippleScale: Double = 0.6
    @State private var rippleOpacity: Double = 0.9

    private var planeOffset: CGSize {
        CGSize(width: -85 + 170 * drift, height: 8 - 16 * drift)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.25)).frame(width: 270, height: 1).offset(y: 30)

            Circle()
                .stroke(Color.white.opacity(0.6), lineWidth: 2)
                .frame(width: 20)
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)
                .offset(x: 60, y: 20)

            Image(systemName: "airplane")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-90))
                .offset(planeOffset)
        }
        .frame(width: 270, height: 190)
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { drift = 1 }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                rippleScale = 2.4
                rippleOpacity = 0
            }
        }
    }
}

// MARK: - Slide 3: Live Activity card (mirrors the actual Lock Screen layout)

private struct IslandIllustration: View {
    @State private var glow: Double = 6
    @State private var progress: CGFloat = 0.5

    var body: some View {
        // Content drives the height; background adapts — prevents the shape from
        // expanding to fill all available vertical space in the slide VStack.
        VStack(alignment: .leading, spacing: 10) {
            // Header: ✈ callsign  type  registration
            HStack(spacing: 5) {
                Image(systemName: "airplane")
                    .font(.footnote.bold())
                    .foregroundStyle(.blue)
                Text("EXS7CT")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("Boeing 737-800")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("G-JZBP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Route progress bar
            GeometryReader { geo in
                HStack(spacing: 6) {
                    Text("EGAA")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .fixedSize()

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 2)
                        Image(systemName: "airplane.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .offset(x: progress * (geo.size.width - 48) - 6)
                    }
                    .frame(maxWidth: .infinity)

                    Text("LTAI")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .fixedSize()
                }
            }
            .frame(height: 12)

            // Telemetry grid: ALT | SPD | HDG | SQK
            HStack(spacing: 0) {
                telemetryCell(label: "ALT", value: "38.000 ft")
                Divider().frame(height: 28)
                telemetryCell(label: "SPD", value: "430 kts")
                Divider().frame(height: 28)
                telemetryCell(label: "HDG", value: "306°")
                Divider().frame(height: 28)
                telemetryCell(label: "SQK", value: "3113")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
                .shadow(color: Color.blue.opacity(0.45), radius: glow)
        )
        .padding(.horizontal, 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { glow = 20 }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { progress = 0.7 }
        }
    }

    private func telemetryCell(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Slide 4: Favorites star

private struct FavoritesIllustration: View {
    @State private var starScale: Double = 1.0
    @State private var t0: Double = 0.2
    @State private var t1: Double = 0.2
    @State private var t2: Double = 0.2

    private let starColor = Color(red: 1.0, green: 0.847, blue: 0.541)

    var body: some View {
        ZStack {
            twinkle(x: -66, y: -44, opacity: t0)
            twinkle(x:  44, y:  44, opacity: t1)
            twinkle(x:  62, y: -30, opacity: t2, size: 5)

            Image(systemName: "star.fill")
                .font(.system(size: 70))
                .foregroundStyle(starColor)
                .shadow(color: starColor.opacity(starScale == 1 ? 0.4 : 0.85), radius: starScale == 1 ? 6 : 24)
                .scaleEffect(starScale)
        }
        .frame(width: 220, height: 220)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { starScale = 1.12 }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { t0 = 1.0 }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(0.5)) { t1 = 1.0 }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(1.0)) { t2 = 1.0 }
        }
    }

    private func twinkle(x: CGFloat, y: CGFloat, opacity: Double, size: CGFloat = 5) -> some View {
        Circle()
            .fill(Color(red: 1.0, green: 0.847, blue: 0.541))
            .frame(width: size, height: size)
            .opacity(opacity)
            .scaleEffect(opacity < 0.5 ? 0.8 : 1.15)
            .offset(x: x, y: y)
    }
}

// MARK: - Hex colour helper

private extension Color {
    init(hex: String) {
        let str = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: str).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >>  8) & 0xFF) / 255
        let b = Double((value >>  0) & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
