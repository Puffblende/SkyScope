import SwiftUI
import SwiftData
import CoreLocation

/// Tab 3 — list of favorited registrations. Tapping shows current status if airborne now.
struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var location
    @Environment(AircraftDataStore.self) private var dataStore
    @Query(sort: \Favorite.createdAt, order: .reverse) private var favorites: [Favorite]

    @State private var showingAddSheet = false
    @State private var selectedAircraft: Aircraft?

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    ContentUnavailableView {
                        Label("No Favorites", systemImage: "star")
                    } description: {
                        Text("Add aircraft registrations to track them — e.g. your club's plane.")
                    } actions: {
                        Button("Add Favorite") { showingAddSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(favorites) { favorite in
                            favoriteRow(for: favorite)
                        }
                        .onDelete(perform: deleteFavorites)
                    }
                }
            }
            .navigationTitle("Favorites")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddFavoriteSheet()
            }
            .sheet(item: $selectedAircraft) { aircraft in
                AircraftDetailSheet(
                    aircraft: aircraft,
                    userLocation: location.currentLocation?.coordinate
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private func favoriteRow(for favorite: Favorite) -> some View {
        let liveAircraft = dataStore.aircraft.first { $0.registration?.uppercased() == favorite.registration }

        Button {
            if let liveAircraft { selectedAircraft = liveAircraft }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: liveAircraft != nil ? "airplane" : "airplane.circle")
                    .font(.title2)
                    .foregroundStyle(liveAircraft != nil ? Color.accentColor : .secondary)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(favorite.registration).font(.headline)
                    if let label = favorite.label, !label.isEmpty {
                        Text(label).font(.caption).foregroundStyle(.secondary)
                    } else if liveAircraft != nil {
                        Text("In the air").font(.caption).foregroundStyle(.green)
                    } else if let last = favorite.lastSeenInTheAir {
                        Text("Last seen \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Not currently tracked")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if liveAircraft != nil {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(liveAircraft == nil)
    }

    private func deleteFavorites(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
        try? modelContext.save()
    }
}

/// Modal for manually adding a registration.
private struct AddFavoriteSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var registration: String = ""
    @State private var label: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Registration") {
                    TextField("D-EVGK", text: $registration)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section("Label (optional)") {
                    TextField("Club aircraft", text: $label)
                }
            }
            .navigationTitle("Add Favorite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .disabled(registration.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let favorite = Favorite(
            registration: registration,
            label: label.isEmpty ? nil : label
        )
        modelContext.insert(favorite)
        try? modelContext.save()
        dismiss()
    }
}
