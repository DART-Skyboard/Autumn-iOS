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

    private static let tleCacheKey = "autumn_radar_tle_cache"

    /// ISS / ZARYA + Tiangong + Hubble — copied from mr.html fetchSatelliteData
    /// "Absolute fallback — embed ISS" so the globe is never empty.
    static let bundledFallbackTLE = """
ISS (ZARYA)
1 25544U 98067A   26102.50000000  .00020000  00000-0  23000-3 0  9991
2 25544  51.6404 100.0000 0002345 100.0000 260.0000 15.49500000494321
TIANGONG
1 48274U 21035A   26102.50000000  .00010000  00000-0  12000-3 0  9990
2 48274  41.4756 200.0000 0005678 200.0000 160.0000 15.60100000274567
HST
1 20580U 90037B   26102.50000000  .00001000  00000-0  50000-4 0  9993
2 20580  28.4697 150.0000 0002567 150.0000 210.0000 15.09300000274567
"""

    @Published var aircraft: [RadarAircraft] = []
    @Published var satellites: [RadarSat] = []
    @Published var userLat: Double = 40.7128
    @Published var userLon: Double = -74.0060
    @Published var hasFix = false
    @Published var authSettled = false
    @Published var adsbStatus = "ADS-B OFFLINE"
    @Published var orbitStatus = "ORBITAL OFFLINE"
    @Published var rangeMiles: Double = 50
    @Published var selectedSat: RadarSat? = nil
    @Published var selectedAircraft: RadarAircraft? = nil
    @Published var selectedUser = false

    var rangeKm: Double { min(600, max(10, rangeMiles)) * 1.60934 }

    private let loc = CLLocationManager()
    private var adsbTimer: Timer?
    private var tleTimer: Timer?
    private var posTimer: Timer?
    private var deadReckonTimer: Timer?
    private var rangeDebounce: Timer?
    private var started = false

    override init() {
        super.init()
        loc.delegate = self
        loc.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        loc.requestWhenInUseAuthorization()
        loc.startUpdatingLocation()
        if let c = loc.location?.coordinate {
            userLat = c.latitude
            userLon = c.longitude
            hasFix = true
        }
        if started { return }
        started = true
        Task { await refreshADSB(); await refreshTLE() }
        adsbTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshADSB() }
        }
        tleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshTLE() }
        }
        deadReckonTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.deadReckonAircraft() }
        }
    }

    func stop() {
        adsbTimer?.invalidate(); adsbTimer = nil
        tleTimer?.invalidate(); tleTimer = nil
        posTimer?.invalidate(); posTimer = nil
        deadReckonTimer?.invalidate(); deadReckonTimer = nil
        rangeDebounce?.invalidate(); rangeDebounce = nil
        loc.stopUpdatingLocation()
        started = false
    }

    func scheduleADSBFromRange() {
        rangeMiles = min(600, max(10, rangeMiles))
        rangeDebounce?.invalidate()
        rangeDebounce = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refreshADSB() }
        }
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
            if let c = manager.location?.coordinate {
                userLat = c.latitude
                userLon = c.longitude
                hasFix = true
            }
        case .denied, .restricted:
            hasFix = false
            authSettled = true
            userLat = 40.7128; userLon = -74.0060
            Task { await refreshADSB() }
        case .notDetermined:
            loc.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func refreshADSB() async {
        let distNm = max(1, Int((rangeKm * 0.539957).rounded()))
        let lat = userLat, lon = userLon
        let selId = selectedAircraft?.id
        let sources: [(String, URL)] = [
            ("LOL", URL(string: "https://api.adsb.lol/v2/lat/\(lat.fmt4)/lon/\(lon.fmt4)/dist/\(distNm)")!),
            ("ADSB.FI", URL(string: "https://opendata.adsb.fi/api/v2/lat/\(lat.fmt4)/lon/\(lon.fmt4)/dist/\(distNm)")!),
            ("LIVE", URL(string: "https://api.airplanes.live/v2/point/\(lat.fmt4)/\(lon.fmt4)/\(distNm)")!),
        ]
        for (label, url) in sources {
            if let ac = await fetchAcList(url) {
                aircraft = ac
                if let selId { selectedAircraft = aircraft.first(where: { $0.id == selId }) }
                adsbStatus = "ADS-B LIVE (\(label) \(ac.count))"
                return
            }
        }
        if let ac = await fetchOpenSky(lat: lat, lon: lon) {
            aircraft = ac
            if let selId { selectedAircraft = aircraft.first(where: { $0.id == selId }) }
            adsbStatus = "ADS-B LIVE (OPENSKY \(ac.count))"
            return
        }
        adsbStatus = "ADS-B OFFLINE"
    }

    func refreshTLE() async {
        let groups = ["stations", "visual", "active", "starlink"]
        var parts = Array(repeating: "", count: groups.count)
        await withTaskGroup(of: (Int, String).self) { tg in
            for (i, g) in groups.enumerated() {
                tg.addTask {
                    let text = await RadarNet.fetchTLEGroup(g) ?? ""
                    return (i, text)
                }
            }
            for await (i, text) in tg {
                parts[i] = text
            }
        }
        let combined = parts.joined(separator: "\n")
        let parsed = Self.parseGroups(parts, cap: 220)
        if !parsed.isEmpty {
            UserDefaults.standard.set(combined, forKey: Self.tleCacheKey)
            applySatellites(parsed, live: true)
            return
        }

        // Network failed — never wipe a good set.
        if !satellites.isEmpty {
            orbitStatus = "ORBITAL STALE (\(satellites.count))"
            startPosTimer()
            return
        }
        if let cached = UserDefaults.standard.string(forKey: Self.tleCacheKey),
           cached.contains("1 "), cached.contains("2 ") {
            let fromCache = TLEKepler.parse(cached)
            let sats = Self.sats(from: fromCache, cap: 220)
            if !sats.isEmpty {
                applySatellites(sats, live: false)
                return
            }
        }
        let fallback = TLEKepler.parse(Self.bundledFallbackTLE)
        let bundled = Self.sats(from: fallback, cap: 220)
        if !bundled.isEmpty {
            applySatellites(bundled, live: false)
            return
        }
        if satellites.isEmpty {
            orbitStatus = "ORBITAL OFFLINE"
        }
    }

    private func applySatellites(_ parsed: [RadarSat], live: Bool) {
        satellites = parsed
        if let sel = selectedSat {
            selectedSat = satellites.first(where: { $0.id == sel.id })
        }
        orbitStatus = live
            ? "ORBITAL LIVE (\(satellites.count))"
            : "ORBITAL STALE (\(satellites.count))"
        startPosTimer()
    }

    private func startPosTimer() {
        guard posTimer == nil else { return }
        posTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.propagateSats() }
        }
    }

    /// Re-propagate TLE bodies in place. Does not refetch.
    private func propagateSats() {
        guard !satellites.isEmpty else { return }
        let now = Date()
        var next = satellites
        for i in next.indices {
            let p = next[i].keplerBody().geodetic(at: now)
            next[i].lat = p.lat
            next[i].lon = p.lon
            next[i].altKm = p.altKm
        }
        satellites = next
        if let sel = selectedSat, let updated = satellites.first(where: { $0.id == sel.id }) {
            selectedSat = updated
        }
    }

    private func deadReckonAircraft() {
        guard !aircraft.isEmpty else { return }
        var next = aircraft
        for i in next.indices {
            next[i].deadReckon(dt: 0.5)
        }
        aircraft = next
        if let sel = selectedAircraft, let updated = aircraft.first(where: { $0.id == sel.id }) {
            selectedAircraft = updated
        }
    }

    private static func parseGroups(_ parts: [String], cap: Int) -> [RadarSat] {
        var out: [RadarSat] = []
        var seen = Set<String>()
        for text in parts {
            guard text.contains("1 "), text.contains("2 ") else { continue }
            for body in TLEKepler.parse(text) {
                if seen.contains(body.id) { continue }
                seen.insert(body.id)
                let now = Date()
                let p = body.geodetic(at: now)
                out.append(RadarSat(
                    id: body.id, name: body.name,
                    lat: p.lat, lon: p.lon, altKm: p.altKm,
                    inc: body.inc, raan: body.raan, ecc: body.ecc,
                    argp: body.argp, m0: body.m0, n: body.n, epoch: body.epoch
                ))
                if out.count >= cap { return out }
            }
        }
        return out
    }

    private static func sats(from bodies: [TLEKepler.Body], cap: Int) -> [RadarSat] {
        let now = Date()
        var out: [RadarSat] = []
        var seen = Set<String>()
        for body in bodies {
            if seen.contains(body.id) { continue }
            seen.insert(body.id)
            let p = body.geodetic(at: now)
            out.append(RadarSat(
                id: body.id, name: body.name,
                lat: p.lat, lon: p.lon, altKm: p.altKm,
                inc: body.inc, raan: body.raan, ecc: body.ecc,
                argp: body.argp, m0: body.m0, n: body.n, epoch: body.epoch
            ))
            if out.count >= cap { break }
        }
        return out
    }

    private func fetchAcList(_ url: URL) async -> [RadarAircraft]? {
        guard let data = await RadarNet.get(url, timeout: 12) else { return nil }
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
        guard let data = await RadarNet.get(url, timeout: 12),
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
            let onGround = (s.count > 8) && ((s[8] as? Bool) == true || (s[8] as? NSNumber)?.boolValue == true)
            var cat = 0
            if s.count > 17 {
                if let n = s[17] as? Int { cat = n }
                else if let n = s[17] as? NSNumber { cat = n.intValue }
            }
            var gs: Double? = nil
            if s.count > 9 {
                if let vel = s[9] as? Double { gs = vel * 1.94384 }
                else if let vel = s[9] as? NSNumber { gs = vel.doubleValue * 1.94384 }
            }
            return RadarAircraft(id: icao, callsign: cs, lat: la, lon: lo, altitude: alt, track: track, gs: gs, category: cat, typeCode: "", onGround: onGround)
        }
        return mapped.isEmpty ? nil : mapped
    }
}

/// Network helpers off the main actor so TLE groups fetch in parallel.
enum RadarNet {
    static let ua = "Autumn-iOS/1.0.2 (com.dartmeadow.autumn; +https://leatr.xyz)"

    static func percentEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func get(_ url: URL, timeout: TimeInterval = 25) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { return nil }
            return data
        } catch { return nil }
    }

    static func fetchText(_ url: URL, timeout: TimeInterval = 25) async -> String? {
        guard let data = await get(url, timeout: timeout) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Try mirrors in order until the body looks like TLE (line-1 / line-2).
    static func fetchTLEGroup(_ group: String) async -> String? {
        let path = "/NORAD/elements/gp.php?GROUP=\(group)&FORMAT=TLE"
        let org = "https://celestrak.org" + path
        let com = "https://celestrak.com" + path
        let enc = percentEncode(org)
        let mirrors = [
            org,
            com,
            "https://corsproxy.io/?url=" + enc,
            "https://api.allorigins.win/raw?url=" + enc,
            "https://api.codetabs.com/v1/proxy?quest=" + enc,
        ]
        for raw in mirrors {
            guard let url = URL(string: raw) else { continue }
            guard let text = await fetchText(url, timeout: 25) else { continue }
            if text.contains("1 ") && text.contains("2 ") { return text }
        }
        return nil
    }
}

struct RadarAircraft: Identifiable {
    let id: String
    let callsign: String
    var lat: Double
    var lon: Double
    let altitude: Double?
    let track: Double?
    var gs: Double?
    let category: Int
    let typeCode: String
    let onGround: Bool
    let icon: String
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var rotatesWithTrack: Bool {
        switch icon {
        case "✈", "🛩", "🚁", "🛸", "🚀": return true
        default: return false
        }
    }

    var typeLabel: String {
        switch icon {
        case "🚁": return "helicopter"
        case "🛸": return "drone"
        case "🛩": return "light aircraft"
        case "🚀": return "rocket"
        case "🎈": return "balloon"
        case "🪂": return "parachute"
        case "🪖": return "military"
        case "🚑": return "medevac"
        case "📦": return "cargo"
        case "🚗": return "ground"
        default: return "airplane"
        }
    }

    init(id: String, callsign: String, lat: Double, lon: Double, altitude: Double?, track: Double?, gs: Double? = nil, category: Int = 0, typeCode: String = "", onGround: Bool = false) {
        self.id = id; self.callsign = callsign; self.lat = lat; self.lon = lon
        self.altitude = altitude; self.track = track; self.gs = gs
        self.category = category; self.typeCode = typeCode; self.onGround = onGround
        self.icon = RadarAircraft.resolveIcon(callsign: callsign, category: category, typeCode: typeCode, onGround: onGround)
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
        let gs = (ac["gs"] as? NSNumber)?.doubleValue ?? (ac["gs"] as? Double)
        let typeCode = ((ac["t"] as? String) ?? (ac["type"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        self.init(
            id: hex, callsign: cs, lat: lat, lon: lon, altitude: alt, track: track, gs: gs,
            category: Self.parseCategory(ac["category"]),
            typeCode: typeCode,
            onGround: Self.parseOnGround(ac)
        )
    }

    mutating func deadReckon(dt: TimeInterval) {
        guard !onGround, let gs, gs > 0.5, let track, dt > 0 else { return }
        let nm = gs * (dt / 3600.0)
        let rad = track * .pi / 180
        let dlat = (nm / 60.0) * cos(rad)
        let cosLat = cos(lat * .pi / 180)
        let dlon = (nm / 60.0) * sin(rad) / max(0.15, abs(cosLat))
        lat = min(90, max(-90, lat + dlat))
        lon += dlon
        if lon > 180 { lon -= 360 }
        if lon < -180 { lon += 360 }
    }

    /// mr.html getAircraftIcon + ADS-B hex categories + ICAO type `t`.
    static func resolveIcon(callsign: String, category: Int, typeCode: String, onGround: Bool) -> String {
        let cs = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        if onGround {
            if cs.range(of: "^(LIFE|MED|HEMS|AIR1|RESCUE|STARS)", options: .regularExpression) != nil { return "🚑" }
            return "🚗"
        }
        if cs.range(of: "^(AF\\d|RCH|REACH|EVAC|PAT\\d|GHOST|BONE|COBRA|HAWK|EAGLE|BUCK|KNIFE|VIPER|JOLLY|PEDRO|RANGER|VIKING|SWORD|LANCE|ARROW|TALON|FURY|BRONCO|RAVEN|STORM|GRIM|REAPER|DEATH|SKULL|DARK|SPECTRE|SPOOKY|SHADOW|NIGHT|WRATH|OMEN|ABYSS)", options: .regularExpression) != nil {
            return "🪖"
        }
        if cs.range(of: "^(N\\d.*P$|USAF|NASA\\d)", options: .regularExpression) != nil { return "🛩" }
        if cs.range(of: "^(LIFE|MED|HEMS|AIR1|RESCUE|STARS|FLIGHT FOR LIFE)", options: .regularExpression) != nil { return "🚑" }

        switch category {
        case 2, 9, 12: return "🛩"
        case 8: return "🚁"
        case 10: return "🎈"
        case 11: return "🪂"
        case 13: return "🛸"
        case 14: return "🚀"
        case 15: return "🚑"
        case 16: return "🚗"
        case 1, 3, 4, 5, 6, 7: return "✈"
        default: break
        }
        // ADS-B emitter category hex (A0–A7 = 160–167, B0–B7 = 176–183)
        switch category {
        case 161: return "🛩"   // A1 light
        case 167: return "🚁"   // A7 rotorcraft
        case 176: return "🛩"   // B0 glider
        case 177: return "🎈"   // B1 LTA
        case 178: return "🪂"   // B2 parachute
        case 179: return "🛩"   // B3 ultralight
        case 180: return "🛸"   // B4 UAV
        case 181: return "🚀"   // B5 space
        case 182: return "🚑"   // B6 emergency
        case 183: return "🚗"   // B7 service
        default: break
        }

        if let fromType = iconFromTypeCode(typeCode) { return fromType }

        if cs.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil { return "✈" }
        if cs.range(of: "DRONE|UAV|UAS", options: .regularExpression) != nil { return "🛸" }
        if cs.range(of: "HELI|CHOP|ROTOR", options: .regularExpression) != nil { return "🚁" }
        if cs.range(of: "BALLOON|BLIMP|AIRSHIP", options: .regularExpression) != nil { return "🎈" }
        if cs.range(of: "CARGO|ATLAS|FDX|UPS|DHL|ABX|GTI|SKW", options: .regularExpression) != nil { return "📦" }
        return "✈"
    }

    static func iconFromTypeCode(_ t: String) -> String? {
        let u = t.uppercased().trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty else { return nil }
        let heli: Set<String> = [
            "R22", "R44", "R66", "B06", "B47", "B407", "B429", "B212", "B412",
            "EC20", "EC25", "EC30", "EC35", "EC45", "EC55", "EC75",
            "AS50", "AS55", "AS65", "A109", "A119", "A139", "A169",
            "S76", "S92", "H60", "H64", "UH1", "AH64", "CH47",
            "MD50", "MD52", "MD60", "H500"
        ]
        if heli.contains(u) { return "🚁" }
        if u.hasPrefix("EC") || u.hasPrefix("UH") || u.hasPrefix("AH") || u.hasPrefix("MH") || u.hasPrefix("CH") { return "🚁" }
        if u.hasPrefix("R2") || u.hasPrefix("R4") || u.hasPrefix("R6") { return "🚁" }
        if u.hasPrefix("Q") || u.hasPrefix("MQ") || u.hasPrefix("RQ") || u.contains("UAV") { return "🛸" }
        if u.hasPrefix("BALL") || u == "BIMP" { return "🎈" }
        if u.hasPrefix("GLID") || u.hasPrefix("ASK") { return "🛩" }
        return nil
    }

    static func parseCategory(_ raw: Any?) -> Int {
        if let n = raw as? Int { return n }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return 0 }
            let hexChars = CharacterSet(charactersIn: "ABCDEFabcdef")
            if t.rangeOfCharacter(from: hexChars) != nil { return Int(t, radix: 16) ?? 0 }
            return Int(t) ?? 0
        }
        return 0
    }

    static func parseOnGround(_ ac: [String: Any]) -> Bool {
        if let b = ac["on_ground"] as? Bool { return b }
        if let n = ac["on_ground"] as? NSNumber { return n.boolValue }
        if let s = ac["alt_baro"] as? String, s.lowercased() == "ground" { return true }
        if let s = ac["alt_geom"] as? String, s.lowercased() == "ground" { return true }
        return false
    }
}

struct RadarSat: Identifiable {
    let id: String
    let name: String
    var lat: Double
    var lon: Double
    var altKm: Double
    let inc: Double
    let raan: Double
    let ecc: Double
    let argp: Double
    let m0: Double
    let n: Double
    let epoch: Date

    var orbitClass: String {
        if altKm < 2000 { return "LEO" }
        if altKm < 35000 { return "MEO" }
        return "GEO"
    }

    var periodMin: Double {
        guard n > 1e-9 else { return 90 }
        return min(max(1440.0 / n, 80), 1440)
    }

    var objectType: String { Self.classify(name) }

    func keplerBody() -> TLEKepler.Body {
        TLEKepler.Body(name: name, id: id, inc: inc, raan: raan, ecc: ecc, argp: argp, m0: m0, n: n, epoch: epoch)
    }

    func markerColor() -> (r: Double, g: Double, b: Double) {
        let u = name.uppercased()
        if u.contains("ISS") || u.contains("ZARYA") || u.contains("TIANGONG") || u.contains("CSS") {
            return (0, 1, 0.4)
        }
        if u.contains("STARLINK") { return (0, 0.8, 1) }
        if altKm < 2000 { return (0, 0.96, 1) }
        if altKm < 35000 { return (1, 0.84, 0) }
        return (1, 0.53, 0)
    }

    static func classify(_ name: String) -> String {
        let u = name.uppercased()
        if u.contains("DEB") { return "space debris" }
        if u.contains("R/B") || u.contains("ROCKET BODY") { return "rocket body" }
        if u.contains("ISS") || u.contains("ZARYA") || u.contains("TIANGONG") || u.contains("CSS") { return "space station" }
        if u.contains("STARLINK") { return "Starlink satellite" }
        let spy = ["NROL", "NOSS", "INTRUDER", "LACROSSE", "ONYX", "KEYHOLE", "CRYSTAL", "MENTOR", "ADVANCED ORION", "CLIO", "MERCURY"]
        if u.hasPrefix("USA") || u.contains(" USA") || spy.contains(where: { u.contains($0) }) { return "spy satellite" }
        if u == "PAN" || u.hasPrefix("PAN ") || u.contains(" PAN ") { return "spy satellite" }
        return "satellite"
    }
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
