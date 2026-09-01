import SwiftUI
import SwiftData
import UIKit
import CoreLocation

/// Root container. Uses a custom floating pill tab bar so the map can extend full-screen
/// while the bar floats above the content on all tabs.
struct ContentView: View {
    @Environment(NavigationCoordinator.self) private var navigation
    @Environment(AircraftDataStore.self) private var dataStore
    @Environment(FollowStore.self) private var follow
    @Environment(LocationService.self) private var location
    @Environment(ARPermissionStore.self) private var arPermission
    @Query private var favorites: [Favorite]

    var body: some View {
        @Bindable var navigation = navigation

        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch navigation.selectedTab {
                case .map:       MapView()
                case .list:      ListView()
                case .favorites: FavoritesView()
                case .settings:  SettingsView()
                }
            }
            // Inset all non-map tabs so content isn't hidden behind the tab bar
            .safeAreaInset(edge: .bottom) {
                if navigation.selectedTab != .map {
                    Color.clear.frame(height: 82)
                }
            }

            // Floating pill tab bar
            FloatingTabBar(selection: $navigation.selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
        .onOpenURL { url in
            navigation.handleOpenURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            arPermission.refreshCameraStatus()
            dataStore.isForeground = true
            dataStore.startPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            dataStore.isForeground = false
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            dataStore.startPolling()
        }
        .onChange(of: favorites) { _, newFavorites in
            dataStore.cachedFavorites = newFavorites
        }
        .onAppear {
            dataStore.cachedFavorites = favorites
        }
        .onChange(of: location.currentLocation) { _, newLoc in
            LiveActivityManager.shared.currentUserLocation = newLoc?.coordinate
        }
        .onChange(of: dataStore.aircraft) { _, aircraft in
            LiveActivityManager.shared.currentTotalCount = aircraft.count
        }
        .onChange(of: follow.followedId) { _, _ in
            guard LiveActivityManager.shared.isRunning else { return }
            let target = dataStore.activityTarget(favorites: favorites)
            Task {
                await LiveActivityManager.shared.update(target: target)
            }
        }
        #if DEBUG
        .overlay {
            if DebugStore.shared.isEnabled {
                Rectangle()
                    .stroke(Color.red, lineWidth: 4)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if DebugStore.shared.isEnabled {
                DebugBadge(dataStore: dataStore)
            }
        }
        #endif
    }
}

// MARK: - Floating pill tab bar

private struct FloatingTabBar: View {
    @Binding var selection: NavigationCoordinator.Tab

    private let tabs: [(NavigationCoordinator.Tab, String, String)] = [
        (.map,       "Map",       "map"),
        (.list,      "List",      "list.bullet"),
        (.favorites, "Favorites", "star.fill"),
        (.settings,  "Settings",  "gearshape"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { tab, label, icon in
                let isActive = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: isActive ? icon : inactiveIcon(icon))
                            .font(.system(size: 23))
                            .foregroundStyle(isActive ? Color.accentColor : Color(.secondaryLabel))
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isActive ? Color.accentColor : Color(.secondaryLabel))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        isActive
                            ? Color(.systemFill).opacity(0.7)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 26)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 31))
        .overlay(
            RoundedRectangle(cornerRadius: 31)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.14), radius: 14, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
    }

    private func inactiveIcon(_ icon: String) -> String {
        switch icon {
        case "star.fill": return "star"
        case "gearshape": return "gearshape"
        default: return icon
        }
    }
}

// MARK: - Debug overlay views

private struct DebugBadge: View {
    let dataStore: AircraftDataStore
    @State private var showLog = false

    var body: some View {
        Button { showLog = true } label: {
            HStack(spacing: 5) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Text("DEBUG").font(.caption2.bold()).foregroundStyle(.red)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: .capsule)
            .overlay(Capsule().stroke(.red, lineWidth: 1))
        }
        .padding(.top, 56)
        .padding(.trailing, 12)
        .sheet(isPresented: $showLog) {
            DebugLogSheet(dataStore: dataStore)
        }
    }
}

private struct DebugLogSheet: View {
    let dataStore: AircraftDataStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Aircraft in radius", value: "\(dataStore.aircraft.count)")
                    LabeledContent("Mode", value: dataStore.isForeground ? "Foreground (30 s)" : "Background")
                    if let last = dataStore.lastFetchAt {
                        LabeledContent("Last fetch", value: last.formatted(.relative(presentation: .named)))
                    }
                    if let error = dataStore.lastError {
                        LabeledContent("Error", value: error).foregroundStyle(.red)
                    }
                }

                Section {
                    if DebugStore.shared.entries.isEmpty {
                        Text("No entries yet").foregroundStyle(.secondary).font(.caption)
                    } else {
                        ForEach(DebugStore.shared.entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 68, alignment: .leading)
                                Text(entry.message)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(entry.isError ? .red : .primary)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        }
                    }
                } header: {
                    HStack {
                        Text("Log (\(DebugStore.shared.entries.count))")
                        Spacer()
                        Button("Clear") { DebugStore.shared.clear() }.font(.caption)
                    }
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Disable") {
                        DebugStore.shared.toggle()
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }
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
        .environment(ARPermissionStore())
        .modelContainer(for: Favorite.self, inMemory: true)
}
