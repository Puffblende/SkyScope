import Foundation
import CoreLocation
import SwiftUI

// MARK: - Model

struct WeatherData {
    let temperature: Double     // °C
    let cloudCoverTotal: Int    // %
    let cloudCoverLow: Int      // % — below ~6,500 ft, most relevant for VFR
    let cloudCoverMid: Int      // % — 6,500–18,000 ft
    let cloudCoverHigh: Int     // % — FL180+
    let windSpeed: Double       // knots
    let windDirection: Int      // °
    let windGusts: Double       // knots
    let visibility: Double      // metres
    let pressure: Double        // hPa (QNH)
    let weatherCode: Int        // WMO code
    let fetchedAt: Date

    var description: String { Self.describe(weatherCode) }
    var symbolName: String { Self.symbol(for: weatherCode) }

    /// Simplified VFR/MVFR/IFR classification based on low-cloud cover and visibility.
    var flightCondition: FlightCondition {
        let visKm = visibility / 1_000
        if cloudCoverLow > 75 || visKm < 1.5 { return .ifr }
        if cloudCoverLow > 50 || visKm < 5.0 { return .mvfr }
        return .vfr
    }

    private static func describe(_ code: Int) -> String {
        switch code {
        case 0:       return "Clear sky"
        case 1:       return "Mainly clear"
        case 2:       return "Partly cloudy"
        case 3:       return "Overcast"
        case 45, 48:  return "Fog"
        case 51...55: return "Drizzle"
        case 61...65: return "Rain"
        case 71...75: return "Snow"
        case 80...82: return "Showers"
        case 95:      return "Thunderstorm"
        case 96, 99:  return "Thunderstorm + hail"
        default:      return "—"
        }
    }

    private static func symbol(for code: Int) -> String {
        switch code {
        case 0:       return "sun.max.fill"
        case 1:       return "sun.min.fill"
        case 2:       return "cloud.sun.fill"
        case 3:       return "cloud.fill"
        case 45, 48:  return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default:      return "cloud.questionmark.fill"
        }
    }
}

enum FlightCondition {
    case vfr, mvfr, ifr

    var label: String {
        switch self { case .vfr: return "VFR"; case .mvfr: return "MVFR"; case .ifr: return "IFR" }
    }

    var color: Color {
        switch self {
        case .vfr:  return .green
        case .mvfr: return Color(red: 1.0, green: 0.75, blue: 0.0)
        case .ifr:  return .red
        }
    }
}

// MARK: - Service

struct WeatherService {
    /// Fetches current weather from Open-Meteo (free, no API key required).
    static func fetch(at coordinate: CLLocationCoordinate2D) async throws -> WeatherData {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude",  value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current",   value: [
                "temperature_2m",
                "cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high",
                "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m",
                "visibility", "surface_pressure", "weather_code",
            ].joined(separator: ",")),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "timezone",        value: "auto"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let resp = try JSONDecoder().decode(OMResponse.self, from: data)
        let c = resp.current
        return WeatherData(
            temperature:     c.temperature2m,
            cloudCoverTotal: c.cloudCover,
            cloudCoverLow:   c.cloudCoverLow,
            cloudCoverMid:   c.cloudCoverMid,
            cloudCoverHigh:  c.cloudCoverHigh,
            windSpeed:       c.windSpeed10m,
            windDirection:   c.windDirection10m,
            windGusts:       c.windGusts10m,
            visibility:      c.visibility,
            pressure:        c.surfacePressure,
            weatherCode:     c.weatherCode,
            fetchedAt:       Date()
        )
    }
}

// MARK: - Decodable DTOs

private struct OMResponse: Decodable {
    let current: Current
    struct Current: Decodable {
        let temperature2m:    Double
        let cloudCover:       Int
        let cloudCoverLow:    Int
        let cloudCoverMid:    Int
        let cloudCoverHigh:   Int
        let windSpeed10m:     Double
        let windDirection10m: Int
        let windGusts10m:     Double
        let visibility:       Double
        let surfacePressure:  Double
        let weatherCode:      Int
        enum CodingKeys: String, CodingKey {
            case temperature2m    = "temperature_2m"
            case cloudCover       = "cloud_cover"
            case cloudCoverLow    = "cloud_cover_low"
            case cloudCoverMid    = "cloud_cover_mid"
            case cloudCoverHigh   = "cloud_cover_high"
            case windSpeed10m     = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
            case windGusts10m     = "wind_gusts_10m"
            case visibility
            case surfacePressure  = "surface_pressure"
            case weatherCode      = "weather_code"
        }
    }
}
