import SwiftUI
import SwiftData

@main
struct SkyScopeApp: App {
    @State private var settings = SettingsStore.shared
    @State private var location = LocationService()
    @State private var router: APIRouter
    @State private var dataStore: AircraftDataStore
    @State private var navigation = NavigationCoordinator()

    init() {
        let settings = SettingsStore.shared
        let location = LocationService()
        let router = APIRouter(settings: settings)
        _settings = State(initialValue: settings)
        _location = State(initialValue: location)
        _router = State(initialValue: router)
        _dataStore = State(initialValue: AircraftDataStore(router: router, settings: settings, location: location))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(location)
                .environment(router)
                .environment(dataStore)
                .environment(navigation)
                .preferredColorScheme(settings.colorScheme.preferredColorScheme)
                .task {
                    location.requestAuthorization()
                    location.startUpdating()
                    dataStore.startPolling()
                }
        }
        .modelContainer(for: Favorite.self)
    }
}
