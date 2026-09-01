import Foundation
import CoreLocation
import Combine

/// Live ADS-B + CelesTrak TLE for Mantis Radar. User lat/lon, never a hardcoded city
/// except NYC as the same geo-denied fallback as mr.html.
@MainActor
final class RadarFeed: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = RadarFeed()

    /// Empty until dispatcher wires the free leatr.xyz CARTO basemap key.
    static let cartoBasemapKey = ""

    @Published var aircraft: [RadarAircraft] = []
    @Published var satellites: [RadarSat] = []
    @Published var userLat: Double = 40.7128
    @Published var userLon: Double = -74.0060
    @Published var hasFix = false
    @Published var adsbStatus = "ADS-B OFFLINE"
    @Published var orbitStatus = "ORBITAL OFFLINE"
    @Published var rangeKm: Double = 50

    private let loc = CLLocationManager()
    private var adsbTimer: Timer?
    private var tleTimer: Timer?
    private var started = false
    private let ua = "Autumn-iOS/1.0.2 (com.dartmeadow.autumn; +https://leatr.xyz)"

    override init() {
        super.init()
        loc.delegate = self
        loc.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        if started { return }
        started = true
        loc.requestWhenInUseAuthorization()
        loc.startUpdatingLocation()
        Task { await refreshADSB(); await refreshTLE() }
        adsbTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshADSB() }
        }
        tleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshTLE() }
        }
    }

    func stop() {
        adsbTimer?.invalidate(); adsbTimer = nil
        tleTimer?.invalidate(); tleTimer = nil
        loc.stopUpdatingLocation()
        started = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        userLat = c.latitude
        userLon = c.longitude
        if !hasFix {
            hasFix = true
            Task { await refreshADSB() }
        } else {
            hasFix = true
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            loc.startUpdatingLocation()
        case .denied, .restricted:
            hasFix = false
            userLat = 40.7128; userLon = -74.0060
            Task { await refreshADSB() }
        default:
            break
        }
    }

    func refreshADSB() async {
        let distNm = max(1, Int((rangeKm * 0.539957).rounded()))
        let lat = userLat, lon = userLon
        let sources: [(String, URL)] = [
            ("LOL", URL(string: "https://api.adsb.lol/v2/lat/\(lat.fmt4)/lon/\(lon.fmt4)/dist/\(distNm)")!),
            ("ADSB.FI", URL(string: "https://opendata.adsb.fi/api/v2/lat/\(lat.fmt4)/lon/\(lon.fmt4)/dist/\(distNm)")!),
            ("LIVE", URL(string: "https://api.airplanes.live/v2/point/\(lat.fmt4)/\(lon.fmt4)/\(distNm)")!),
        ]
        for (label, url) in sources {
            if let ac = await fetchAcList(url) {
                aircraft = ac
                adsbStatus = "ADS-B LIVE (\(label) \(ac.count))"
                return
            }
        }
        if let ac = await fetchOpenSky(lat: lat, lon: lon) {
            aircraft = ac
            adsbStatus = "ADS-B LIVE (OPENSKY \(ac.count))"
            return
        }
        adsbStatus = "ADS-B OFFLINE"
    }

    func refreshTLE() async {
        let urls = [
            "https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=TLE",
            "https://celestrak.org/NORAD/elements/gp.php?GROUP=visual&FORMAT=TLE",
        ]
        var combined = ""
        for u in urls {
            if let text = await fetchText(URL(string: u)!) { combined += text + "\n" }
        }
        if combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            orbitStatus = "ORBITAL OFFLINE"
            return
        }
        let parsed = TLEKepler.parse(combined)
        let now = Date()
        satellites = parsed.compactMap { body in
            let p = body.geodetic(at: now)
            return RadarSat(id: body.id, name: body.name, lat: p.lat, lon: p.lon, altKm: p.altKm)
        }
        orbitStatus = "ORBITAL LIVE (\(satellites.count))"
    }

    private func fetchAcList(_ url: URL) async -> [RadarAircraft]? {
        guard let data = await get(url) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = obj["ac"] as? [[String: Any]] else { return nil }
        let mapped = rows.compactMap(RadarAircraft.init(ac:))
        return mapped.isEmpty ? nil : mapped
    }

    private func fetchOpenSky(lat: Double, lon: Double) async -> [RadarAircraft]? {
        let deg = rangeKm / 111.32
        let lamin = lat - deg, lamax = lat + deg
        let cos = max(0.2, cos(lat * .pi / 180))
        let lomin = lon - deg / cos, lomax = lon + deg / cos
        let url = URL(string:
            "https://opensky-network.org/api/states/all?lamin=\(lamin.fmt4)&lomin=\(lomin.fmt4)&lamax=\(lamax.fmt4)&lomax=\(lomax.fmt4)")!
        guard let data = await get(url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = obj["states"] as? [[Any]] else { return nil }
        let mapped: [RadarAircraft] = states.compactMap { s in
            guard s.count > 6,
                  let icao = s[0] as? String,
                  let la = s[6] as? Double,
                  let lo = s[5] as? Double else { return nil }
            let cs = ((s[1] as? String) ?? icao).trimmingCharacters(in: .whitespaces)
            let alt = s[7] as? Double
            let track = s[10] as? Double
            return RadarAircraft(id: icao, callsign: cs, lat: la, lon: lo, altitude: alt, track: track)
        }
        return mapped.isEmpty ? nil : mapped
    }

    private func fetchText(_ url: URL) async -> String? {
        guard let data = await get(url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func get(_ url: URL) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { return nil }
            return data
        } catch { return nil }
    }
}

struct RadarAircraft: Identifiable {
    let id: String
    let callsign: String
    let lat: Double
    let lon: Double
    let altitude: Double?
    let track: Double?
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    init(id: String, callsign: String, lat: Double, lon: Double, altitude: Double?, track: Double?) {
        self.id = id; self.callsign = callsign; self.lat = lat; self.lon = lon
        self.altitude = altitude; self.track = track
    }

    init?(ac: [String: Any]) {
        let lat = (ac["lat"] as? Double) ?? (ac["lat"] as? NSNumber)?.doubleValue
        let lon = (ac["lon"] as? Double) ?? (ac["lon"] as? NSNumber)?.doubleValue
        guard let lat, let lon else { return nil }
        let hex = (ac["hex"] as? String) ?? UUID().uuidString
        let cs = ((ac["flight"] as? String) ?? (ac["r"] as? String) ?? hex)
            .trimmingCharacters(in: .whitespaces)
        var alt: Double? = nil
        if let n = ac["alt_baro"] as? NSNumber { alt = n.doubleValue }
        else if let d = ac["alt_baro"] as? Double { alt = d }
        let track = (ac["track"] as? NSNumber)?.doubleValue ?? (ac["track"] as? Double)
        self.init(id: hex, callsign: cs, lat: lat, lon: lon, altitude: alt, track: track)
    }
}

struct RadarSat: Identifiable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let altKm: Double
}

private extension Double {
    var fmt4: String { String(format: "%.4f", self) }
}

/// Compact Kepler (not full SGP4) so TLE dots land on the globe from CelesTrak.
enum TLEKepler {
    struct Body {
        let name: String
        let id: String
        let inc: Double
        let raan: Double
        let ecc: Double
        let argp: Double
        let m0: Double
        let n: Double
        let epoch: Date

        func geodetic(at date: Date) -> (lat: Double, lon: Double, altKm: Double) {
            let dt = date.timeIntervalSince(epoch)
            let nRad = n * 2 * .pi / 86400
            var M = (m0 * .pi / 180) + nRad * dt
            M = M.truncatingRemainder(dividingBy: 2 * .pi)
            if M < 0 { M += 2 * .pi }
            var E = M
            for _ in 0..<10 { E = M + ecc * sin(E) }
            let nu = 2 * atan2(sqrt(1 + ecc) * sin(E / 2), sqrt(max(1e-9, 1 - ecc)) * cos(E / 2))
            let mu = 398600.4418
            let a = pow(mu / max(1e-9, nRad * nRad), 1.0 / 3.0)
            let r = a * (1 - ecc * cos(E))
            let u = nu + argp * .pi / 180
            let i = inc * .pi / 180
            let O = raan * .pi / 180
            let x = r * (cos(O) * cos(u) - sin(O) * sin(u) * cos(i))
            let y = r * (sin(O) * cos(u) + cos(O) * sin(u) * cos(i))
            let z = r * (sin(u) * sin(i))
            let lon = atan2(y, x) * 180 / .pi
            let hyp = sqrt(x * x + y * y)
            let lat = atan2(z, hyp) * 180 / .pi
            return (lat, lon, r - 6371.0)
        }
    }

    static func parse(_ text: String) -> [Body] {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var out: [Body] = []
        var seen = Set<String>()
        var i = 0
        while i + 2 < lines.count {
            let l1 = lines[i + 1], l2 = lines[i + 2]
            if l1.count >= 69, l2.count >= 69, l1.first == "1", l2.first == "2" {
                let id = String(l1.dropFirst(2).prefix(5)).trimmingCharacters(in: .whitespaces)
                if !seen.contains(id), let b = body(name: lines[i], id: id, l1: l1, l2: l2) {
                    seen.insert(id)
                    out.append(b)
                }
                i += 3
            } else {
                i += 1
            }
        }
        return out
    }

    private static func body(name: String, id: String, l1: String, l2: String) -> Body? {
        guard l1.count >= 32, l2.count >= 63 else { return nil }
        let yy = Int(l1.dropFirst(18).prefix(2)) ?? 26
        let doy = Double(l1.dropFirst(20).prefix(12).trimmingCharacters(in: .whitespaces)) ?? 1
        let year = yy < 57 ? 2000 + yy : 1900 + yy
        var cal = DateComponents()
        cal.timeZone = TimeZone(secondsFromGMT: 0)
        cal.year = year; cal.month = 1; cal.day = 1
        let jan1 = Calendar(identifier: .gregorian).date(from: cal) ?? Date()
        let epoch = jan1.addingTimeInterval((doy - 1) * 86400)
        let inc = Double(l2.dropFirst(8).prefix(8).trimmingCharacters(in: .whitespaces)) ?? 0
        let raan = Double(l2.dropFirst(17).prefix(8).trimmingCharacters(in: .whitespaces)) ?? 0
        let ecc = Double("0." + l2.dropFirst(26).prefix(7).trimmingCharacters(in: .whitespaces)) ?? 0
        let argp = Double(l2.dropFirst(34).prefix(8).trimmingCharacters(in: .whitespaces)) ?? 0
        let m0 = Double(l2.dropFirst(43).prefix(8).trimmingCharacters(in: .whitespaces)) ?? 0
        let n = Double(l2.dropFirst(52).prefix(11).trimmingCharacters(in: .whitespaces)) ?? 15
        return Body(name: name, id: id, inc: inc, raan: raan, ecc: ecc, argp: argp, m0: m0, n: n, epoch: epoch)
    }
}
