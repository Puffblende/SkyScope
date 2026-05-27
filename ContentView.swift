import SwiftUI

/// Root TabView for the app. Selection is bound to NavigationCoordinator so that the
/// detail sheet can deep-link to the Map tab via "Show on Map".
struct ContentView: View {
    @Environment(NavigationCoordinator.self) private var navigation
    @Environment(AircraftDataStore.self) private var dataStore

    var body: some View {
        @Bindable var navigation = navigation

        TabView(selection: $navigation.selectedTab) {
            Tab("Map", systemImage: "map", value: NavigationCoordinator.Tab.map) {
                MapView()
            }
            Tab("List", systemImage: "list.bullet", value: NavigationCoordinator.Tab.list) {
                ListView()
            }
            Tab("Favorites", systemImage: "star.fill", value: NavigationCoordinator.Tab.favorites) {
                FavoritesView()
            }
            Tab("Settings", systemImage: "gear", value: NavigationCoordinator.Tab.settings) {
                SettingsView()
            }
        }
        // On every tab switch: immediate refresh + reset the polling timer.
        // Prevents aircraft from disappearing because the timer fires mid-session.
        .onChange(of: navigation.selectedTab) { _, _ in
            dataStore.startPolling()
        }
    }
}

#Preview {
    ContentView()
        .environment(SettingsStore.shared)
        .environment(LocationService())
        .environment(APIRouter(settings: SettingsStore.shared))
        .environment(NavigationCoordinator())
}
