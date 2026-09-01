import SwiftUI
import SwiftData
import CoreLocation

/// Bottom sheet shown when an aircraft is tapped on the map or in the list.
/// `showMapNavigationButton` controls whether the "Show on Map" action appears — it
/// should be hidden when the sheet is already presented from the map itself.
struct AircraftDetailSheet: View {
    let aircraft: Aircraft
    let userLocation: CLLocationCoordinate2D?
    var showMapNavigationButton: Bool = true

    @Environment(SettingsStore.self) private var settings
    @Environment(NavigationCoordinator.self) private var navigation
    @Environment(FollowStore.self) private var follow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var favorites: [Favorite]

    @State private var showSilhouette = false
    @State private var showPhoto = false
    @State private var showFollowInfo = false
    @State private var selectedAirport: SelectedAirportCode?
    @State private var routeProgress: Double? = nil
    @State private var totalRouteDistanceMeters: Double? = nil
    @State private var originCity: String? = nil
    @State private var destCity: String? = nil
    @State private var airlineLogoImage: UIImage? = nil

    private var isFavorite: Bool {
        guard let reg = aircraft.registration?.uppercased() else { return false }
        return favorites.contains { $0.registration == reg }
    }

    private var isFollowing: Bool {
        follow.isFollowing(aircraft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                dragIndicator
                headerSection

                routeSection

                if aircraft.airline != nil || aircraft.callsign != nil {
                    airlineCard
                }

                telemetrySection

                if showMapNavigationButton {
                    showOnMapButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showSilhouette) {
            AircraftSilhouetteView(aircraftType: aircraft.aircraftType)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPhoto) {
            if let reg = aircraft.registration {
                AircraftPhotoView(registration: reg)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $selectedAirport) { airport in
            AirportCardView(icao: airport.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task(id: aircraft.id) {
            let result = await computeRouteProgress()
            routeProgress = result.0
            totalRouteDistanceMeters = result.1
        }
        .task(id: "\(aircraft.originAirport ?? "")-\(aircraft.destinationAirport ?? "")") {
            async let oc = fetchAirportCity(aircraft.originAirport)
            async let dc = fetchAirportCity(aircraft.destinationAirport)
            let (o, d) = await (oc, dc)
            originCity = o
            destCity = d
        }
        .task(id: airlineCode ?? "") {
            airlineLogoImage = await fetchAirlineLogo(icao: airlineCode)
        }
    }

    // MARK: - Drag Indicator

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color(.systemFill))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    // MARK: - Header
    // Row 1: Manufacturer + Type (medium-large, tappable → silhouette)
    // Row 2: Registration (slightly smaller, tappable → photo)
    // Right: ☆ favorite + Follow pill

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Manufacturer + Type — first row, medium-large bold
                Button {
                    showSilhouette = true
                } label: {
                    Text(fullTypeName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(aircraft.aircraftType == nil)

                // Registration — second row, accent colour, slightly smaller
                Button {
                    showPhoto = true
                } label: {
                    Text(aircraft.registration ?? aircraft.id)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(aircraft.registration == nil)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if aircraft.registration != nil {
                    favoriteButton
                }
                followButton
            }
            .padding(.top, 2)
        }
    }

    private var favoriteButton: some View {
        Button {
            toggleFavorite()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private var followButton: some View {
        Button {
            follow.toggle(aircraft)
        } label: {
            Text(isFollowing ? "Unfollow" : "Follow")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isFollowing ? Color.secondary : Color.white)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(isFollowing ? Color(.tertiarySystemBackground) : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Route Card

    @ViewBuilder
    private var routeSection: some View {
        if aircraft.originAirport != nil || aircraft.destinationAirport != nil {
            routeCard
        } else {
            routeUnavailableCard
        }
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: ICAO codes + progress text centered
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let origin = aircraft.originAirport {
                        Button(origin) {
                            selectedAirport = SelectedAirportCode(id: origin)
                        }
                        .font(.system(.title2, design: .monospaced).bold())
                        .foregroundStyle(Color.accentColor)
                        .buttonStyle(.plain)
                        if let city = originCity {
                            Text(city)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        missingRouteEndpoint(label: "Origin")
                    }
                }

                Spacer()

                if let text = progressDisplayText {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let dest = aircraft.destinationAirport {
                        Button(dest) {
                            selectedAirport = SelectedAirportCode(id: dest)
                        }
                        .font(.system(.title2, design: .monospaced).bold())
                        .foregroundStyle(Color.accentColor)
                        .buttonStyle(.plain)
                        if let city = destCity {
                            Text(city)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        missingRouteEndpoint(label: "Destination", alignment: .trailing)
                    }
                }
            }

            // Progress bar — plane icon ON the line (no y-offset)
            GeometryReader { geo in
                let progress = routeProgress ?? 0.5
                let planeX   = geo.size.width * progress

                ZStack(alignment: .leading) {
                    Capsule()
                        .frame(height: 3)
                        .foregroundStyle(Color(.systemFill))
                    Capsule()
                        .frame(width: max(planeX, 0), height: 3)
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                    // Plane sits ON the line — no y-offset so it's vertically centred
                    // in the ZStack alongside the 3 pt capsule
                    Image(systemName: "airplane")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, height: 20)
                        .offset(x: planeX - 10)
                }
            }
            .frame(height: 20)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var routeUnavailableCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(.secondaryLabel))
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text("Route not available")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Origin and destination are not published by the available data sources.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func missingRouteEndpoint(
        label: String,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Not published")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Airline Card

    private var airlineCard: some View {
        HStack(spacing: 12) {
            // Logo box — only rendered when the image was fetched successfully
            if let logo = airlineLogoImage {
                Image(uiImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 3) {
                if let name = displayAirlineName {
                    Text(name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                }
                if let callsign = aircraft.callsign, !callsign.isEmpty {
                    Text(callsign)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)
                }
            }

            Spacer()

            statusBadge
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Telemetry Section

    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TELEMETRY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showFollowInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .popover(isPresented: $showFollowInfo, arrowEdge: .trailing) {
                    Text("Follow locks the Live Activity to this aircraft until it leaves your search radius. Priority order: Follow › Favorite › Nearest.")
                        .font(.callout)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            }
            .padding(.bottom, 8)

            Divider()

            if let alt = aircraft.altitudeMeters {
                telemetryRow(
                    label: "Altitude",
                    value: UnitFormat.altitude(meters: alt, unit: settings.altitudeUnit)
                )
                Divider()
            }

            if let speed = aircraft.groundSpeedMps {
                telemetryRow(
                    label: "Ground Speed",
                    value: UnitFormat.speed(mps: speed, unit: settings.speedUnit)
                )
                Divider()
            }

            telemetryRow(
                label: "Course",
                value: UnitFormat.heading(aircraft.headingDegrees)
            )

            if let userLocation {
                Divider()
                telemetryRow(
                    label: "Distance",
                    value: UnitFormat.distance(
                        meters: aircraft.distance(to: userLocation),
                        unit: settings.distanceUnit
                    )
                )
            }

            if let squawk = aircraft.squawk, !squawk.isEmpty {
                Divider()
                telemetryRow(label: "Squawk", value: squawk)
            }
        }
        .padding(.top, 6)
    }

    private func telemetryRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .fontWeight(.medium)
                .foregroundStyle(valueColor)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Show on Map Button

    private var showOnMapButton: some View {
        Button {
            navigation.showOnMap(aircraft)
            dismiss()
        } label: {
            Label("Show on Map", systemImage: "map.fill")
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Computed Properties

    private var fullTypeName: String {
        guard let code = aircraft.aircraftType?.uppercased(), !code.isEmpty else {
            return "Unknown Aircraft"
        }
        let humanType = aircraftTypeFullName(code) ?? code
        if let mfr = aircraftManufacturer {
            return "\(mfr) \(humanType)"
        }
        return humanType
    }

    // Maps ICAO type designators to human-readable model names.
    // Falls back to the raw code for anything not listed.
    private func aircraftTypeFullName(_ code: String) -> String? {
        let lookup: [String: String] = [
            // Boeing narrowbody
            "B736": "737-600",  "B737": "737-700",  "B738": "737-800",  "B739": "737-900",
            "B73G": "737-700",  "B73H": "737-800",
            "B37M": "737 MAX 7", "B38M": "737 MAX 8", "B39M": "737 MAX 9", "B3XM": "737 MAX 10",
            "B752": "757-200",  "B753": "757-300",
            // Boeing widebody
            "B741": "747-100",  "B742": "747-200",  "B743": "747-300",  "B744": "747-400",
            "B748": "747-8",    "B74F": "747F",      "B74S": "747SP",
            "B762": "767-200",  "B763": "767-300",   "B764": "767-400",
            "B772": "777-200",  "B77L": "777-200LR", "B773": "777-300",  "B77W": "777-300ER",
            "B788": "787-8",    "B789": "787-9",     "B78X": "787-10",
            "717":  "717-200",
            // Airbus narrowbody
            "A318": "A318",     "A319": "A319",      "A320": "A320",     "A321": "A321",
            "A19N": "A319neo",  "A20N": "A320neo",   "A21N": "A321neo",
            // Airbus widebody
            "A332": "A330-200", "A333": "A330-300",  "A338": "A330-800neo", "A339": "A330-900neo",
            "A342": "A340-200", "A343": "A340-300",  "A345": "A340-500",    "A346": "A340-600",
            "A359": "A350-900", "A35K": "A350-1000",
            "A380": "A380",     "A388": "A380",
            // Embraer E-Jet
            "E170": "E170", "E175": "E175", "E190": "E190", "E195": "E195",
            "E290": "E190-E2",  "E295": "E195-E2",
            "E135": "ERJ-135",  "E145": "ERJ-145",
            // Bombardier CRJ
            "CRJ1": "CRJ-100",  "CRJ2": "CRJ-200",
            "CRJ7": "CRJ-700",  "CRJ9": "CRJ-900",  "CRJX": "CRJ-1000",
            // De Havilland Dash 8
            "DH8A": "Dash 8-100", "DH8B": "Dash 8-200",
            "DH8C": "Dash 8-300", "DH8D": "Dash 8-400",
            // ATR
            "AT43": "ATR 42-300", "AT45": "ATR 42-500", "AT46": "ATR 42-600",
            "AT72": "ATR 72",     "AT75": "ATR 72-500", "AT76": "ATR 72-600",
            // Fokker
            "F50": "F50", "F70": "F70", "F100": "F100",
            // Cessna
            "C172": "172 Skyhawk", "C182": "182 Skylane", "C208": "208 Caravan",
            "C510": "Citation Mustang", "C525": "Citation CJ",
            "C550": "Citation II", "C56X": "Citation Excel",
            "C680": "Citation Sovereign", "C700": "Citation Longitude",
            // Piper
            "PA28": "PA-28 Cherokee", "PA32": "PA-32",
            "PA44": "PA-44 Seminole", "PA46": "PA-46 Malibu",
            // Beechcraft
            "BE36": "Bonanza",    "BE58": "Baron",
            "BE9L": "King Air 90", "B350": "King Air 350",
            // Diamond
            "DA40": "DA40", "DA42": "DA42", "DA62": "DA62",
            // Cirrus
            "SR20": "SR20", "SR22": "SR22",
            // TBM / Pilatus
            "TBM7": "TBM 700", "TBM8": "TBM 850", "TBM9": "TBM 900",
            "PC12": "PC-12",    "PC24": "PC-24",
        ]
        return lookup[code]
    }

    private var aircraftManufacturer: String? {
        guard let t = aircraft.aircraftType?.uppercased() else { return nil }
        let prefixMap: [(String, String)] = [
            ("B7", "Boeing"), ("717", "Boeing"), ("727", "Boeing"),
            ("737", "Boeing"), ("747", "Boeing"), ("757", "Boeing"),
            ("767", "Boeing"), ("777", "Boeing"), ("787", "Boeing"),
            ("A2", "Airbus"), ("A3", "Airbus"),
            ("E13", "Embraer"), ("E14", "Embraer"), ("E17", "Embraer"),
            ("E19", "Embraer"), ("ERJ", "Embraer"), ("EMB", "Embraer"),
            ("CRJ", "Bombardier"), ("BD", "Bombardier"),
            ("DH8", "De Havilland"), ("DHC", "De Havilland"),
            ("ATR", "ATR"),
            ("MD", "McDonnell Douglas"), ("DC", "McDonnell Douglas"),
            ("F7", "Fokker"), ("F10", "Fokker"),
            ("BE", "Beechcraft"), ("PA", "Piper"),
            ("DA", "Diamond"), ("SR", "Cirrus"),
            ("TBM", "Daher"), ("PC", "Pilatus"),
            ("C1", "Cessna"), ("C2", "Cessna"), ("C3", "Cessna"),
        ]
        return prefixMap.first(where: { t.hasPrefix($0.0) })?.1
    }

    // Airline display name: prefer the API-supplied value, fall back to ICAO code lookup.
    // Needed because AirplanesLive always sets aircraft.airline = nil.
    private var displayAirlineName: String? {
        if let name = aircraft.airline, !name.isEmpty { return name }
        guard let code = airlineCode else { return nil }
        let icaoNames: [String: String] = [
            "AAL": "American Airlines",   "DAL": "Delta Air Lines",
            "UAL": "United Airlines",     "SWA": "Southwest Airlines",
            "BAW": "British Airways",     "DLH": "Lufthansa",
            "AFR": "Air France",          "KLM": "KLM Royal Dutch Airlines",
            "SWR": "SWISS",              "IBE": "Iberia",
            "TAP": "TAP Air Portugal",    "AZA": "Alitalia",
            "ACA": "Air Canada",          "WJA": "WestJet",
            "ETH": "Ethiopian Airlines",  "EZY": "easyJet",
            "RYR": "Ryanair",             "VIR": "Virgin Atlantic",
            "LOT": "LOT Polish Airlines", "UAE": "Emirates",
            "TRA": "Transavia",           "WZZ": "Wizz Air",
            "ANA": "All Nippon Airways",  "JAL": "Japan Airlines",
            "CCA": "Air China",           "CES": "China Eastern",
            "CPA": "Cathay Pacific",      "SIA": "Singapore Airlines",
            "THA": "Thai Airways",        "MAS": "Malaysia Airlines",
            "KAL": "Korean Air",          "EIN": "Aer Lingus",
            "THY": "Turkish Airlines",    "QTR": "Qatar Airways",
            "ETD": "Etihad Airways",      "DLV": "DHL Aviation",
            "UPS": "UPS Airlines",        "FDX": "FedEx Express",
            "SAS": "Scandinavian Airlines", "FIN": "Finnair",
            "AUA": "Austrian Airlines",   "BEL": "Brussels Airlines",
            "VLG": "Vueling",             "NAX": "Norwegian Air",
            "EXS": "Jet2",                "SVA": "Saudia",
            "EGY": "EgyptAir",            "VOI": "Volotea",
            "TOM": "TUI Airways",         "TCX": "TUI Airways",
            "FFT": "Frontier Airlines",   "AWE": "US Airways",
        ]
        return icaoNames[code]
    }

    // 3-letter ICAO airline code extracted from the callsign (e.g. "DLH" from "DLH2312")
    private var airlineCode: String? {
        guard let cs = aircraft.callsign?.uppercased() else { return nil }
        let code = String(cs.prefix(while: { $0.isLetter }))
        return code.isEmpty ? nil : String(code.prefix(3))
    }

    private var progressDisplayText: String? {
        guard let progress = routeProgress else { return nil }
        let pct = Int(progress * 100)
        if let totalDist = totalRouteDistanceMeters,
           let speed = aircraft.groundSpeedMps,
           speed > 5 {
            let remainingDist = totalDist * (1 - progress)
            let secondsLeft   = remainingDist / speed
            let minutesLeft   = Int(secondsLeft / 60)
            let hours         = minutesLeft / 60
            let mins          = minutesLeft % 60
            let timeStr       = hours > 0
                ? "\(hours):\(String(format: "%02d", mins))"
                : "0:\(String(format: "%02d", mins))"
            return "\(pct)% · \(timeStr) left"
        }
        return "\(pct)%"
    }

    private var statusBadge: some View {
        Text(aircraft.onGround ? "On Ground" : "Airborne")
            .font(.caption2.bold())
            .foregroundStyle(aircraft.onGround ? Color.secondary : Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                aircraft.onGround ? Color(.quaternarySystemFill) : Color.accentColor,
                in: Capsule()
            )
    }

    // MARK: - Actions

    private func toggleFavorite() {
        guard let reg = aircraft.registration?.uppercased() else { return }
        if let existing = favorites.first(where: { $0.registration == reg }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(Favorite(registration: reg))
        }
        try? modelContext.save()
    }

    // MARK: - Async Helpers

    private func computeRouteProgress() async -> (Double?, Double?) {
        guard let originCode = aircraft.originAirport,
              let destCode   = aircraft.destinationAirport else { return (nil, nil) }

        async let originCoord = AirportCoordinatesService.shared.coordinates(for: originCode)
        async let destCoord   = AirportCoordinatesService.shared.coordinates(for: destCode)

        guard let o = await originCoord, let d = await destCoord else { return (nil, nil) }

        let originLoc  = CLLocation(latitude: o.latitude,  longitude: o.longitude)
        let destLoc    = CLLocation(latitude: d.latitude,  longitude: d.longitude)
        let currentLoc = CLLocation(latitude: aircraft.coordinate.latitude,
                                    longitude: aircraft.coordinate.longitude)

        let totalDist = originLoc.distance(from: destLoc)
        guard totalDist > 0 else { return (nil, nil) }

        let flown    = originLoc.distance(from: currentLoc)
        let progress = min(max(flown / totalDist, 0.02), 0.98)
        return (progress, totalDist)
    }

    private func fetchAirportCity(_ icao: String?) async -> String? {
        guard let icao, !icao.isEmpty else { return nil }
        guard let url = URL(string: "https://aviationweather.gov/api/data/airport?ids=\(icao)&format=json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct LightAirport: Decodable { let city: String? }
            return try JSONDecoder().decode([LightAirport].self, from: data).first?.city
        } catch { return nil }
    }

    /// Fetches an airline logo from the FlightAware CDN using the 3-letter ICAO airline code.
    /// Returns nil (and hides the logo box) when the request fails or the response is too
    /// small to be a real logo (e.g. a transparent 1×1 placeholder).
    private func fetchAirlineLogo(icao: String?) async -> UIImage? {
        guard let icao, !icao.isEmpty else { return nil }
        let urlString = "https://www.flightaware.com/images/airline_logos/180px/\(icao).png"
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count > 500 else { return nil }
            return UIImage(data: data)
        } catch { return nil }
    }
}

private struct SelectedAirportCode: Identifiable {
    let id: String
}
