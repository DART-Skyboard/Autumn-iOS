import Foundation
import MapKit
import CoreLocation

/// AutumnMaps — MapKit integration
/// Provides location search, directions, and map data for Autumn
public final class AutumnMaps: NSObject, CLLocationManagerDelegate, Sendable {
    public static let shared = AutumnMaps()
    private let locationManager = CLLocationManager()
    public var currentLocation: CLLocation?
    public var onLocationUpdate: ((CLLocation) -> Void)?

    public override init() {
        super.init()
        locationManager.delegate       = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Location
    public func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    public func startUpdating() { locationManager.startUpdatingLocation() }
    public func stopUpdating()  { locationManager.stopUpdatingLocation() }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentLocation = loc
        onLocationUpdate?(loc)
    }

    // MARK: - Search
    public func search(query: String, near location: CLLocation? = nil) async throws -> [MapResult] {
        let req                  = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        if let loc               = location ?? currentLocation {
            req.region           = MKCoordinateRegion(center: loc.coordinate,
                                    latitudinalMeters: 10000, longitudinalMeters: 10000)
        }
        let search  = MKLocalSearch(request: req)
        let resp    = try await search.start()
        return resp.mapItems.map {
            MapResult(
                name:      $0.name ?? "",
                address:   $0.placemark.title ?? "",
                latitude:  $0.placemark.coordinate.latitude,
                longitude: $0.placemark.coordinate.longitude,
                phone:     $0.phoneNumber,
                url:       $0.url?.absoluteString
            )
        }
    }

    // MARK: - Directions
    public func getDirections(to destination: MapResult, mode: MKDirectionsTransportType = .automobile) async throws -> DirectionsSummary {
        let dest     = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)))
        let req      = MKDirections.Request()
        req.source   = MKMapItem.forCurrentLocation()
        req.destination = dest
        req.transportType = mode
        let dirs     = MKDirections(request: req)
        let response = try await dirs.calculate()
        guard let route = response.routes.first else { throw MapError.noRoute }
        return DirectionsSummary(
            distance:    route.distance,
            travelTime:  route.expectedTravelTime,
            steps:       route.steps.map { $0.instructions }.filter { !$0.isEmpty }
        )
    }
}

public struct MapResult: Sendable {
    public let name, address: String
    public let latitude, longitude: Double
    public let phone, url: String?
}

public struct DirectionsSummary: Sendable {
    public let distance, travelTime: Double
    public let steps: [String]
}

public enum MapError: Error { case noRoute }
