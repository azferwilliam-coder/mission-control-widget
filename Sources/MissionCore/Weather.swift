import Foundation

public struct WeatherNow: Equatable, Sendable {
    public var celsius: Double
    public var code: Int
    public var fetchedAt: Date

    public init(celsius: Double, code: Int, fetchedAt: Date) {
        self.celsius = celsius
        self.code = code
        self.fetchedAt = fetchedAt
    }

    /// "29° showers"
    public var summary: String {
        "\(Format.degrees(celsius)) \(Weather.words(for: code))"
    }
}

public enum Weather {
    /// Bandar Seri Begawan.
    public static let latitude = 4.9031
    public static let longitude = 114.9398

    /// Open-Meteo: free, no account or key. Only the place's coordinates are sent.
    public static var url: URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "Asia/Brunei"),
        ]
        return c.url!
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
        }
        let current: Current
    }

    public static func parse(_ data: Data, now: Date) -> WeatherNow? {
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        guard r.current.temperature_2m.isFinite, (-90.0...70.0).contains(r.current.temperature_2m) else { return nil }
        return WeatherNow(celsius: r.current.temperature_2m, code: r.current.weather_code, fetchedAt: now)
    }

    /// WMO weather codes in plain, lowercase words.
    public static func words(for code: Int) -> String {
        switch code {
        case 0: return "clear"
        case 1: return "mostly clear"
        case 2: return "partly cloudy"
        case 3: return "cloudy"
        case 45, 48: return "fog"
        case 51, 53, 55, 56, 57: return "drizzle"
        case 61, 63, 66: return "rain"
        case 65, 67: return "heavy rain"
        case 71, 73, 75, 77: return "snow"
        case 80, 81: return "showers"
        case 82: return "heavy showers"
        case 85, 86: return "snow showers"
        case 95: return "thunderstorms"
        case 96, 99: return "storms, hail"
        default: return "—"
        }
    }

    /// Weather older than this is hidden rather than shown as if it were current.
    public static let staleAfter: TimeInterval = 3 * 60 * 60

    public static func isFresh(_ w: WeatherNow, now: Date) -> Bool {
        now.timeIntervalSince(w.fetchedAt) < staleAfter
    }
}
