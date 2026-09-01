import SwiftUI

/// Help & FAQ — pushed from Settings. Matches the design layout with grouped FAQ sections.
struct HelpView: View {
    @State private var showFeedback = false

    var body: some View {
        List {
            Section {
                Text("Common questions about chocks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section("Setup") {
                FAQItem(
                    q: "Why does chocks need my location?",
                    a: "To find aircraft within your search radius and center the map on your position."
                )
                FAQItem(
                    q: "What permissions does the app need?",
                    a: "Location while in use for nearby aircraft, camera only for Sky View AR, and background location only when Live Activity tracking is enabled."
                )
                FAQItem(
                    q: "How do I change my search radius?",
                    a: "Use the radius slider on the map. Default is 50 km / 27 NM, adjustable from 5–250."
                )
            }

            Section("Data & Accuracy") {
                FAQItem(
                    q: "Where does the flight data come from?",
                    a: "Nearby aircraft positions come from community ADS-B sources: airplanes.live first, adsb.lol second, then OpenSky as fallback. Routes and aircraft metadata are enriched best-effort from ADSBDB."
                )
                FAQItem(
                    q: "Do I need an API key?",
                    a: "No. Optional OpenSky credentials can be added in Settings for higher OpenSky limits, but the app works without an account."
                )
                FAQItem(
                    q: "An aircraft is missing or shows outdated info. Why?",
                    a: "Aircraft with transponders off, blocked identifiers, missing route publications or weak ADS-B coverage may be incomplete or absent."
                )
                FAQItem(
                    q: "How often does data refresh?",
                    a: "In the foreground chocks refreshes up to every 30 seconds. Background and Live Activity updates follow the interval selected in Settings."
                )
            }

            Section("Sky View AR") {
                FAQItem(
                    q: "Why does AR need the camera?",
                    a: "The camera lets chocks align aircraft cards with the sky. Camera images stay on your device and are never stored or uploaded."
                )
                FAQItem(
                    q: "Why can an AR card be slightly off?",
                    a: "AR alignment depends on GPS, aircraft data latency, device compass accuracy and AR tracking. Move slowly and recalibrate if chocks shows low compass accuracy."
                )
            }

            Section("Favorites & Live Activity") {
                FAQItem(
                    q: "What are Favorites?",
                    a: "Registrations you track, like your club's aircraft. Add them from an aircraft's detail sheet or the Favorites tab."
                )
                FAQItem(
                    q: "What does Live Activity show?",
                    a: "Nearby aircraft on your Lock Screen and Dynamic Island. If a saved favorite is currently in range, chocks prioritizes it over the nearest aircraft."
                )
                FAQItem(
                    q: "Does Live Activity drain my battery?",
                    a: "It relies on background location updates. Turn off \"Launch on app startup\" in Settings to start it manually instead."
                )
            }

            Section("Pricing & Support") {
                FAQItem(
                    q: "Is there a subscription?",
                    a: "No. chocks is a one-time paid download with all features included, no subscriptions and no in-app purchases."
                )
                FAQItem(
                    q: "I found a bug or have an idea.",
                    a: "Send it through the Feedback form — we read every message."
                )
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Didn't find your answer?")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Tell us what's wrong or what you'd like to see.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        showFeedback = true
                    } label: {
                        Text("Send Feedback")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
        }
    }
}

private struct FAQItem: View {
    let q: String
    let a: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(q)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            Text(a)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(.vertical, 2)
    }
}
