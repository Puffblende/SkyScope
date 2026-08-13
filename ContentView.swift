import SwiftUI
import SwiftData

/// Root TabView for the app. Selection is bound to NavigationCoordinator so that the
/// detail sheet can deep-link to the Map tab via "Show on Map".
struct ContentView: View {
    @Environment(NavigationCoordinator.self) private var navigation
    @Environment(AircraftDataStore.self) private var dataStore
    @Environment(FollowStore.self) private var follow
    @Query private var favorites: [Favorite]

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
        .onOpenURL { url in
            navigation.handleOpenURL(url)
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            dataStore.startPolling()
        }
        // Keep the data store's favorites cache fresh so background refresh can resolve
        // the activity target without going through SwiftUI.
        .onChange(of: favorites) { _, newFavorites in
            dataStore.cachedFavorites = newFavorites
        }
        .onAppear {
            dataStore.cachedFavorites = favorites
        }
        // Immediately update the Live Activity when the user taps Follow/Unfollow.
        // Aircraft data hasn't changed, only the priority target has.
        .onChange(of: follow.followedId) { _, _ in
            guard LiveActivityManager.shared.isRunning else { return }
            let target = dataStore.activityTarget(favorites: favorites)
            Task {
                await LiveActivityManager.shared.update(target: target)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(SettingsStore.shared)
        .environment(LocationService())
        .environment(APIRouter(settings: SettingsStore.shared))
        .environment(NavigationCoordinator())
        .environment(FollowStore())
        .modelContainer(for: Favorite.self, inMemory: true)
}
