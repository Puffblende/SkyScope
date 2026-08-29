import SwiftUI
import SwiftData
import ActivityKit

@main
struct SkyScopeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = SettingsStore.shared
    @State private var location = LocationService()
    @State private var router: APIRouter
    @State private var dataStore: AircraftDataStore
    @State private var navigation = NavigationCoordinator()
    @State private var follow = FollowStore()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        let settings = SettingsStore.shared
        let location = LocationService()
        let router = APIRouter(settings: settings)
        let follow = FollowStore()
        _settings = State(initialValue: settings)
        _location = State(initialValue: location)
        _router = State(initialValue: router)
        _follow = State(initialValue: follow)
        let dataStore = AircraftDataStore(router: router, settings: settings, location: location, follow: follow)
        AircraftDataStore.shared = dataStore
        _dataStore = State(initialValue: dataStore)

        let authInfo = ActivityAuthorizationInfo()
        print("[STARTUP] areActivitiesEnabled: \(authInfo.areActivitiesEnabled)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(location)
                .environment(router)
                .environment(dataStore)
                .environment(navigation)
                .environment(follow)
                .preferredColorScheme(settings.colorScheme.preferredColorScheme)
                .fullScreenCover(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { if !$0 { hasCompletedOnboarding = true } }
                )) {
                    // Explicitly inject location — @Observable environment values are not
                    // guaranteed to propagate into modal presentations in all iOS versions.
                    OnboardingView { hasCompletedOnboarding = true }
                        .environment(location)
                }
                .task {
                    // Only re-request authorization on subsequent launches (onboarding
                    // handles the first-launch request on slide 0).
                    if hasCompletedOnboarding {
                        location.requestAuthorization()
                    }
                    location.startUpdating()
                    dataStore.startPolling()

                    if settings.launchLiveActivityOnStartup {
                        // Wait for the first fetch to complete (max 15 s).
                        var waited = 0
                        while dataStore.aircraft.isEmpty && waited < 15 {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            waited += 1
                        }
                        // activityTarget needs favorites — use nil (no SwiftData here),
                        // so startup defaults to nearest. The ContentView onChange will
                        // correct this on the next aircraft update.
                        await LiveActivityManager.shared.start(target: dataStore.aircraft.first)
                    }
                }
        }
        .modelContainer(for: Favorite.self)
    }
}
