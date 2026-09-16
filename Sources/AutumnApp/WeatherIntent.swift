import Foundation
import CoreLocation
import AutumnServices

/// TF118: routes weather questions to actually FETCH real weather data
/// (AutumnWeather → WeatherKit, already correctly implemented but — like
/// AutumnMusic before it — never called from anywhere) instead of letting
/// them fall into GrammarEngine's generic conversational templates.
///
/// This is the concrete fix for the "prescriptive, not proportional" critique:
/// a template picked from a phrase bank can never be a real answer to "what's
/// the weather today" — there's nothing to compute from in a template, only
/// in real fetched data. Anything with an actual answerable capability behind
/// it (weather today; more could follow the same pattern) should route to
/// that capability and report what it actually finds, honestly, including
/// when it can't check (no location permission, fetch failed) — never a
/// templated non-answer standing in for a real one.
enum WeatherIntent {
    static func wantsWeather(_ raw: String) -> Bool {
        let s = raw.lowercased()
        return s.range(of: #"\b(weather|temperature|forecast|how (hot|cold|warm) is it|is it (raining|snowing|sunny|cloudy)|will it rain|humidity|wind speed)\b"#, options: .regularExpression) != nil
    }

    /// Returns a real, computed answer, or an honest explanation of why it
    /// couldn't check — never a generic template standing in for either.
    @MainActor
    static func answer() async -> String {
        guard let location = await currentLocation() else {
            return "I don't have location access yet, so I can't check the actual weather — enable location for Autumn in Settings and ask me again."
        }
        do {
            let w = try await AutumnWeather.shared.currentWeather(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
            let temp = Int(w.temperature.rounded())
            let feels = Int(w.feelsLike.rounded())
            var sentence = "It's \(temp)\(w.unit) and \(w.condition.lowercased()) right now"
            if abs(feels - temp) >= 3 {
                sentence += ", feels like \(feels)\(w.unit)"
            }
            sentence += "."
            if w.uvIndex >= 6 {
                sentence += " UV index is \(w.uvIndex) — worth sunscreen if you're heading out."
            }
            return sentence
        } catch {
            return "I tried to check the actual weather but the request failed (\(error.localizedDescription)) — worth trying again in a moment."
        }
    }

    @MainActor
    private static func currentLocation() async -> CLLocation? {
        if let loc = AutumnMaps.shared.currentLocation { return loc }
        AutumnMaps.shared.requestLocationPermission()
        AutumnMaps.shared.startUpdating()
        // Give the location manager a brief window to deliver a fix rather
        // than failing immediately on a cold start.
        for _ in 0..<10 {
            if let loc = AutumnMaps.shared.currentLocation { return loc }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return AutumnMaps.shared.currentLocation
    }
}
