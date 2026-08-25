import Foundation

struct AirportDetail: Sendable {
    let icao: String
    let iata: String?
    let name: String
    let city: String
    let country: String
    let elevationFeet: Int
    let latitude: Double
    let longitude: Double
    let metar: MetarData?
    let taf: String?
    let frequencies: [AirportFrequency]
    let photoURL: URL?
    let wikipediaURL: URL?
    /// Second paragraph of the Wikipedia article intro — more informative than the first.
    let wikipediaDescription: String?
}

struct MetarData: Sendable {
    let raw: String
    let windDirection: Int?
    let windSpeed: Int?
    let windGust: Int?
    let temperature: Double?
    let dewpoint: Double?
    let altimeterInHg: Double?
    let flightCategory: String?
    let reportTime: Date?

    var activeRunwayHint: String? {
        guard let dir = windDirection, (windSpeed ?? 0) > 2 else { return nil }
        var rwyNum = Int(round(Double(dir) / 10.0))
        if rwyNum == 0 { rwyNum = 36 }
        if rwyNum > 36 { rwyNum = 36 }
        let reciprocal = rwyNum <= 18 ? rwyNum + 18 : rwyNum - 18
        return "\(String(format: "%02d", rwyNum)) / \(String(format: "%02d", reciprocal))"
    }

    var windSummary: String {
        guard let spd = windSpeed else { return "—" }
        if spd == 0 { return "Calm" }
        let dirStr = windDirection.map { String(format: "%03d°", $0) } ?? "VRB"
        var s = "\(dirStr) at \(spd) kt"
        if let g = windGust { s += ", gusting \(g) kt" }
        return s
    }
}

struct AirportFrequency: Sendable, Identifiable {
    var id: String { type + frequency }
    let type: String
    let frequency: String
    let name: String?
}
