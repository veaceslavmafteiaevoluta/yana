import Foundation
import CoreLocation

struct HourForecast: Identifiable, Equatable {
    var id: Date { time }
    let time: Date
    let temp: Double
    let code: Int
}

@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

    @Published private(set) var temperature: Double?
    @Published private(set) var code: Int = 0
    @Published private(set) var high: Double?
    @Published private(set) var low: Double?
    @Published private(set) var city = ""
    @Published private(set) var hourly: [HourForecast] = []
    @Published private(set) var denied = false

    private let manager = CLLocationManager()
    private var location: CLLocation?
    private var timer: Timer?

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            MainActor.assumeIsolated { WeatherService.shared.fetch() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let s = WeatherService.shared
                let firstFix = s.location == nil
                if firstFix || (s.location!.distance(from: loc) > 5000) {
                    s.location = loc
                    s.fetch()
                    CLGeocoder().reverseGeocodeLocation(loc) { marks, _ in
                        // YANAScreenshotCity: placeholder city for the README screenshots (keeps the real location private)
                        let name = UserDefaults.standard.string(forKey: "YANAScreenshotCity") ?? marks?.first?.locality ?? ""
                        DispatchQueue.main.async { MainActor.assumeIsolated { WeatherService.shared.city = name } }
                    }
                }
                s.manager.stopUpdatingLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let st = manager.authorizationStatus
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                WeatherService.shared.denied = (st == .denied || st == .restricted)
                if st == .authorized || st == .authorizedAlways { WeatherService.shared.manager.startUpdatingLocation() }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func fetch() {
        guard let loc = location else { return }
        let lat = String(format: "%.2f", loc.coordinate.latitude)
        let lon = String(format: "%.2f", loc.coordinate.longitude)
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&hourly=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&forecast_days=2&timezone=auto&timeformat=unixtime")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let cur = json["current"] as? [String: Any]
            let temp = cur?["temperature_2m"] as? Double
            let code = cur?["weather_code"] as? Int ?? 0
            let daily = json["daily"] as? [String: Any]
            let hi = (daily?["temperature_2m_max"] as? [Double])?.first
            let lo = (daily?["temperature_2m_min"] as? [Double])?.first
            var hours: [HourForecast] = []
            if let h = json["hourly"] as? [String: Any], let times = h["time"] as? [Double],
               let temps = h["temperature_2m"] as? [Double], let codes = h["weather_code"] as? [Int] {
                let now = Date().addingTimeInterval(-3600)
                for i in times.indices where i < temps.count && i < codes.count {
                    let t = Date(timeIntervalSince1970: times[i])
                    if t > now { hours.append(HourForecast(time: t, temp: temps[i], code: codes[i])) }
                    if hours.count >= 8 { break }
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let s = WeatherService.shared
                    s.temperature = temp; s.code = code; s.high = hi; s.low = lo; s.hourly = hours
                }
            }
        }.resume()
    }

    static func symbol(_ code: Int, night: Bool = false) -> String {
        switch code {
        case 0: return night ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: return L("Clear")
        case 1, 2: return L("Partly cloudy")
        case 3: return L("Cloudy")
        case 45, 48: return L("Fog")
        case 51...57: return L("Drizzle")
        case 61...67, 80...82: return L("Rain")
        case 71...77, 85, 86: return L("Snow")
        case 95...99: return L("Thunderstorm")
        default: return "—"
        }
    }
}
