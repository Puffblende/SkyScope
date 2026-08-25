import SwiftUI

/// Help & FAQ — pushed from Settings. Matches the design layout with grouped FAQ sections.
struct HelpView: View {
    @State private var showFeedback = false

    var body: some View {
        List {
            Section {
                Text("Common questions about SkyScope.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section("Setup") {
                FAQItem(
                    q: "Why does SkyScope need my location?",
                    a: "To find aircraft within your search radius and center the map on your position."
                )
                FAQItem(
                    q: "What permissions does the app need?",
                    a: "Location while in use, and in the background only if Live Activity tracking is turned on."
                )
                FAQItem(
                    q: "How do I change my search radius?",
                    a: "Settings → Search Radius. Default is 50 km / 27 NM, adjustable from 5–250."
                )
            }

            Section("Data & Accuracy") {
                FAQItem(
                    q: "Where does the flight data come from?",
                    a: "FlightAware AeroAPI is the primary source. SkyScope falls back to OpenSky Network if FlightAware's daily free limit is exceeded."
                )
                FAQItem(
                    q: "Do I need an API key?",
                    a: "Only for FlightAware, added in Settings → Data Sources. Without one, SkyScope uses OpenSky anonymously with less detail."
                )
                FAQItem(
                    q: "An aircraft is missing or shows outdated info. Why?",
                    a: "Aircraft with transponders off or outside ADS-B coverage won't appear. Try a wider radius or a shorter refresh interval."
                )
                FAQItem(
                    q: "How often does data refresh?",
                    a: "Every 1, 2, 5 or 10 minutes — configurable in Settings to manage API usage."
                )
            }

            Section("Favorites & Live Activity") {
                FAQItem(
                    q: "What are Favorites?",
                    a: "Registrations you track, like your club's aircraft. Add them from an aircraft's detail sheet or the Favorites tab."
                )
                FAQItem(
                    q: "What does Live Activity show?",
                    a: "Nearby aircraft on your Lock Screen and Dynamic Island. It switches to Favorite mode when a tracked registration is airborne, and ends automatically when it lands."
                )
                FAQItem(
                    q: "Does Live Activity drain my battery?",
                    a: "It relies on background location updates. Turn off \"Launch on app startup\" in Settings to start it manually instead."
                )
            }

            Section("Pricing & Support") {
                FAQItem(
                    q: "Is there a subscription?",
                    a: "No. SkyScope is a one-time purchase (~€1.99) — no subscriptions or in-app purchases."
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
