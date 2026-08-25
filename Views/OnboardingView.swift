import SwiftUI
import CoreLocation
import UIKit
import UserNotifications

/// Five-slide first-launch onboarding. Shown once; dismissed permanently when complete.
struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(LocationService.self) private var location

    @State private var step = 0
    @State private var isWaitingForLocation = false
    private let total = 5

    var body: some View {
        ZStack {
            // Slides — TabView fills the full screen (ignores safe areas).
            TabView(selection: $step) {
                slide0.tag(0)
                slide1.tag(1)
                slide2.tag(2)
                slide3.tag(3)
                slide4.tag(4)
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
        case 0:
            // Location slide: show system dialog, advance after user responds.
            if location.authorizationStatus != .notDetermined {
                advance()
            } else {
                isWaitingForLocation = true
                location.requestAuthorization()
            }
        case 3:
            // Live Activity slide: request notification permission, then advance.
            Task {
                let granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                await MainActor.run {
                    if granted {
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
        step == total - 1 ? "Get Started" : "Continue"
    }

    // MARK: - Button text colour (dark shade matching each slide's background)

    private var buttonTextColor: Color {
        switch step {
        case 0: return Color(red: 0.043, green: 0.118, blue: 0.239)  // Location: dark blue
        case 1: return Color(red: 0.027, green: 0.231, blue: 0.227)  // Radius: dark teal
        case 2: return Color(red: 0.078, green: 0.157, blue: 0.314)  // Map: mid blue
        case 3: return Color(red: 0.020, green: 0.027, blue: 0.051)  // Live Activity: near-black
        default: return Color(red: 0.169, green: 0.063, blue: 0.333) // Favorites: dark purple
        }
    }

    // MARK: - Slides

    private var slide0: some View {
        shell(
            colors: [Color(hex: "0b1e3d"), Color(hex: "16386b"), Color(hex: "1f4d8f")],
            title: "Location Access",
            body: "SkyScope needs your location to find aircraft within your search radius and center the map on you. Foreground access is enough — background access is only used if you turn on Live Activity tracking."
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
            body: "Track nearby aircraft from your Lock Screen and Dynamic Island. It switches to Favorite mode automatically when a tracked registration is airborne, and ends when it lands."
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

// MARK: - Slide 0: Radar

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

// MARK: - Slide 3: Live Activity card (matches the design)

private struct IslandIllustration: View {
    @State private var glowOpacity: Double = 0.25

    var body: some View {
        ZStack {
            // Animated blue glow behind the card
            RoundedRectangle(cornerRadius: 26)
                .fill(Color(red: 0.35, green: 0.55, blue: 1.0).opacity(glowOpacity))
                .blur(radius: 24)
                .frame(width: 230, height: 90)

            // Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("D-EVGK")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Airborne")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text("4,200")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(" ft")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("112")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(" kts")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(width: 210)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                glowOpacity = 0.45
            }
        }
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
