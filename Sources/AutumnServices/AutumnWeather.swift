import Foundation
import WeatherKit
import CoreLocation

/// AutumnWeather — WeatherKit integration
/// Autumn responds to weather queries with live data
@available(iOS 16.0, *)
public actor AutumnWeather {
    public static let shared = AutumnWeather()
    private let service = WeatherService.shared
    public init() {}

    public func currentWeather(lat: Double, lon: Double) async throws -> WeatherSummary {
        let location = CLLocation(latitude: lat, longitude: lon)
        let weather  = try await service.weather(for: location, including: .current)
        return WeatherSummary(
            condition:   weather.condition.description,
            temperature: weather.temperature.value,
            unit:        weather.temperature.unit.symbol,
            humidity:    weather.humidity,
            windSpeed:   weather.wind.speed.value,
            feelsLike:   weather.apparentTemperature.value,
            uvIndex:     weather.uvIndex.value
        )
    }

    public func hourlyForecast(lat: Double, lon: Double, hours: Int = 12) async throws -> [HourlyWeather] {
        let location = CLLocation(latitude: lat, longitude: lon)
        let weather  = try await service.weather(for: location, including: .hourly)
        return weather.forecast.prefix(hours).map {
            HourlyWeather(
                time:        $0.date,
                condition:   $0.condition.description,
                temperature: $0.temperature.value,
                precipChance: $0.precipitationChance
            )
        }
    }
}

public struct WeatherSummary: Sendable {
    public let condition, unit: String
    public let temperature, humidity, windSpeed, feelsLike: Double
    public let uvIndex: Int
}

public struct HourlyWeather: Sendable {
    public let time: Date
    public let condition: String
    public let temperature, precipChance: Double
}
