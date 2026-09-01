import Foundation

actor AirportDetailService {
    static let shared = AirportDetailService()
    private var cache: [String: AirportDetail] = [:]
    private init() {}

    func fetch(icao: String) async -> AirportDetail? {
        let key = icao.uppercased()
        if let cached = cache[key] { return cached }

        async let airportTask = fetchAWAirport(icao: key)
        async let metarTask = fetchMetar(icao: key)
        async let tafTask = fetchTAF(icao: key)

        let (airportData, metar, taf) = await (airportTask, metarTask, tafTask)
        guard let airportData else { return nil }

        let wikiInfo = await fetchWikipediaInfo(name: airportData.name, city: airportData.city, icao: key)

        let detail = AirportDetail(
            icao: key,
            iata: airportData.iata,
            name: airportData.name,
            city: airportData.city,
            country: airportData.country,
            elevationFeet: airportData.elevation,
            latitude: airportData.lat,
            longitude: airportData.lon,
            metar: metar,
            taf: taf,
            frequencies: airportData.frequencies,
            photoURL: wikiInfo?.photoURL,
            wikipediaURL: wikiInfo?.articleURL,
            wikipediaDescription: wikiInfo?.description
        )

        cache[key] = detail
        return detail
    }

    // MARK: - Private fetches

    private func fetchAWAirport(icao: String) async -> ParsedAirport? {
        guard let url = URL(string: "https://aviationweather.gov/api/data/airport?ids=\(icao)&format=json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([AWAirportResponse].self, from: data).first.map { ParsedAirport(from: $0) }
        } catch {
            #if DEBUG
            print("[AirportDetailService] Airport fetch failed for \(icao): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private func fetchMetar(icao: String) async -> MetarData? {
        // hours=2 returns up to two hours of observations; we take the first (most recent).
        // "mostRecent=true" is not a valid parameter on this API and causes a 400 error response.
        guard let url = URL(string: "https://aviationweather.gov/api/data/metar?ids=\(icao)&format=json&hours=2") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let metars = try JSONDecoder().decode([AWMetarResponse].self, from: data)
            guard let first = metars.first, let raw = first.rawOb, !raw.isEmpty else { return nil }
            return MetarData(
                raw: raw,
                windDirection: first.wdir,
                windSpeed: first.wspd,
                windGust: first.wgst,
                temperature: first.temp,
                dewpoint: first.dewp,
                altimeterInHg: first.altim,
                flightCategory: first.flightCategory,
                reportTime: first.obsTime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        } catch {
            #if DEBUG
            print("[AirportDetailService] METAR fetch failed for \(icao): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private func fetchTAF(icao: String) async -> String? {
        guard let url = URL(string: "https://aviationweather.gov/api/data/taf?ids=\(icao)&format=json&mostRecent=true") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([AWTAFResponse].self, from: data).first?.rawTAF
        } catch { return nil }
    }

    // MARK: - Wikipedia

    /// Searches Wikipedia for the airport article, preferring results whose title
    /// contains "airport". Returns both the lead photo URL and the article URL so
    /// both the card header image and the "View on Wikipedia" button use the same page.
    private func fetchWikipediaInfo(name: String, city: String, icao: String) async -> WikiInfo? {
        // Name/city first: these are unambiguous and almost always find the right article.
        // ICAO codes can collide with military acronyms (e.g. HESH = tank round) so they go last.
        let candidates = [
            "\(name) airport",
            "\(city) airport",
            "\(name) international airport",
            "\(city) international airport",
            icao + " airport",
            icao,
        ].map { $0.trimmingCharacters(in: .whitespaces) }
         .filter { !$0.isEmpty }

        for term in candidates {
            if let info = await wikiSearch(term, expectedICAO: icao) { return info }
        }
        return nil
    }

    private func wikiSearch(_ query: String, expectedICAO: String? = nil) async -> WikiInfo? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://en.wikipedia.org/w/api.php?action=query&generator=search&gsrsearch=\(encoded)&gsrlimit=8&prop=pageimages%7Cextracts&piprop=thumbnail&pithumbsize=800&exintro=true&explaintext=true&format=json&redirects=1")
        else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let result = try JSONDecoder().decode(WikiSearchResult.self, from: data)
            // Sort by relevance index before any filtering — dictionary iteration order is random.
            let pages = Array(result.query?.pages?.values ?? [:].values)
                .sorted { ($0.index ?? Int.max) < ($1.index ?? Int.max) }

            // Only accept pages that are identifiably aviation-related and not for a
            // different ICAO code. The unfiltered fallback is intentionally absent.
            let airportPages = pages.filter { Self.isAviationPage($0, expectedICAO: expectedICAO) }
            guard let best = airportPages.first(where: { $0.thumbnail?.source != nil })
                              ?? airportPages.first
            else { return nil }

            let photoURL = best.thumbnail?.source.flatMap { URL(string: $0) }
            let encodedTitle = (best.title ?? "").replacingOccurrences(of: " ", with: "_")
            let articleURL = URL(string: "https://en.wikipedia.org/wiki/\(encodedTitle)")
            let description = Self.secondParagraph(from: best.extract ?? "")

            return WikiInfo(photoURL: photoURL, articleURL: articleURL, description: description)
        } catch {
            return nil
        }
    }

    // A page qualifies as an aviation article if its title or opening extract
    // contains recognizable airport vocabulary AND its stated ICAO code (if any)
    // matches the airport we searched for.
    private static func isAviationPage(_ page: WikiSearchResult.Query.Page,
                                       expectedICAO: String? = nil) -> Bool {
        let extract = page.extract ?? ""

        // Must be identifiably aviation-related
        let aviationTerms = ["airport", "aerodrome", "airfield", "airstrip", "air base", "airbase", "air terminal"]
        let title = (page.title ?? "").lowercased()
        let extractLow = extract.prefix(400).lowercased()
        let isAviation = aviationTerms.contains(where: { title.contains($0) })
            || aviationTerms.contains(where: { extractLow.contains($0) })
            || extractLow.contains("icao")
            || extractLow.contains("iata")
        guard isAviation else { return false }

        // ICAO conflict check: if the article explicitly states "ICAO: XXXX" and
        // that code differs from the airport we searched for, reject the page.
        // (e.g. ORSU search returning the ORSJ article after the airport was renamed)
        if let expected = expectedICAO?.uppercased() {
            // If the expected code appears anywhere in the extract, this is our airport.
            if extract.contains(expected) { return true }
            // Otherwise scan for "ICAO:" patterns; if a different 4-letter code is found, reject.
            var rest = extract[...]
            while let range = rest.range(of: "ICAO:") {
                let afterColon = rest[range.upperBound...].drop(while: { $0 == " " || $0 == "\u{A0}" })
                let candidate = String(afterColon.prefix(4))
                if candidate.count == 4 && candidate.allSatisfy({ $0.isUppercase && $0.isLetter }) {
                    return false // article is about a different airport
                }
                rest = rest[range.upperBound...]
            }
        }

        return true
    }

    // Splits the Wikipedia plain-text intro on double newlines and returns the second
    // non-empty paragraph (falls back to first if the intro only has one).
    private static func secondParagraph(from extract: String) -> String? {
        let paragraphs = extract
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==") }
        guard !paragraphs.isEmpty else { return nil }
        return paragraphs.count > 1 ? paragraphs[1] : paragraphs[0]
    }
}

// MARK: - Internal types

private struct WikiInfo {
    let photoURL: URL?
    let articleURL: URL?
    let description: String?
}

// MARK: - Raw API models

private nonisolated struct AWAirportResponse: Decodable {
    let icaoId: String?
    let iataId: String?
    let name: String?
    let lat: Double?
    let lon: Double?
    let elev: Int?
    let city: String?
    let country: String?
    // Semicolon-delimited: "ATIS,118.02;TWR,136.5;GND,121.9"
    let freqs: String?
}

private nonisolated struct AWMetarResponse: Decodable {
    let rawOb: String?
    let obsTime: Double?  // API returns numeric timestamp; Double covers both Int and Float forms
    let temp: Double?
    let dewp: Double?
    let wdir: Int?        // "VRB" (variable) winds arrive as a String — custom decoder below silences that
    let wspd: Int?
    let wgst: Int?
    let altim: Double?
    let flightCategory: String?

    private enum CodingKeys: String, CodingKey {
        case rawOb, obsTime, temp, dewp, wdir, wspd, wgst, altim
        case flightCategory = "fltCat"  // API field name is fltCat, not flightCategory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawOb          = try c.decodeIfPresent(String.self, forKey: .rawOb)
        obsTime        = try c.decodeIfPresent(Double.self, forKey: .obsTime)
        temp           = try c.decodeIfPresent(Double.self, forKey: .temp)
        dewp           = try c.decodeIfPresent(Double.self, forKey: .dewp)
        wspd           = try c.decodeIfPresent(Int.self,    forKey: .wspd)
        wgst           = try c.decodeIfPresent(Int.self,    forKey: .wgst)
        altim          = try c.decodeIfPresent(Double.self, forKey: .altim)
        flightCategory = try c.decodeIfPresent(String.self, forKey: .flightCategory)
        // wdir may be the string "VRB" for variable winds — silently ignore non-integer values
        wdir           = try? c.decodeIfPresent(Int.self, forKey: .wdir)
    }
}

private nonisolated struct AWTAFResponse: Decodable {
    let rawTAF: String?
}

private nonisolated struct WikiSearchResult: Decodable {
    nonisolated struct Query: Decodable {
        nonisolated struct Page: Decodable {
            let index: Int?      // relevance rank from the search generator (1 = best match)
            let title: String?
            let thumbnail: Thumbnail?
            let extract: String?
            nonisolated struct Thumbnail: Decodable { let source: String? }
        }
        let pages: [String: Page]?
    }
    let query: Query?
}

// MARK: - Intermediate mapping

private nonisolated struct ParsedAirport {
    let iata: String?
    let name: String
    let city: String
    let country: String
    let elevation: Int
    let lat: Double
    let lon: Double
    let frequencies: [AirportFrequency]

    init(from r: AWAirportResponse) {
        iata = r.iataId
        let rawName = r.name ?? r.icaoId ?? ""
        name = rawName == rawName.uppercased() && rawName.count > 4 ? rawName.capitalized : rawName
        city = r.city ?? ""
        country = r.country ?? ""
        elevation = r.elev ?? 0
        lat = r.lat ?? 0
        lon = r.lon ?? 0

        // Parse semicolon-delimited "TYPE,FREQ" pairs, e.g. "ATIS,118.02;TWR,136.5"
        let parsed: [AirportFrequency] = (r.freqs ?? "")
            .components(separatedBy: ";")
            .compactMap { entry in
                let parts = entry.trimmingCharacters(in: .whitespaces).components(separatedBy: ",")
                guard parts.count >= 2,
                      let type = parts.first?.trimmingCharacters(in: .whitespaces), !type.isEmpty,
                      let freq = parts.last?.trimmingCharacters(in: .whitespaces), !freq.isEmpty
                else { return nil }
                return AirportFrequency(type: type, frequency: freq, name: nil)
            }
        frequencies = parsed.sorted { Self.freqPriority($0.type) < Self.freqPriority($1.type) }
    }

    private static func freqPriority(_ type: String) -> Int {
        switch type.uppercased() {
        case "ATIS", "D-ATIS":         return 0
        case "DEL", "CLNC", "CLNC DEL": return 1
        case "GND", "GND/P", "GND/S": return 2
        case "TWR", "LCL/P", "LCL", "LCL/S": return 3
        case "APP", "APCH":            return 4
        case "DEP":                    return 5
        case "UNICOM":                 return 6
        case "CTAF":                   return 7
        default:                       return 8
        }
    }
}
