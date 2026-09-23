import Foundation
import CoreLocation
import AutumnServices

/// A tracked vessel, mirrored from the maritime relay.
public struct RadarVessel: Identifiable, Equatable {
    public let id: String            // MMSI, as a string
    public var name: String
    public var type: String          // human-readable ship type
    public var lat: Double
    public var lon: Double
    public var prevLat: Double?
    public var prevLon: Double?
    public var speedKn: Double?
    public var courseDeg: Double?
    public var lastUpdate: Date

    public var displayName: String { name.isEmpty ? "MMSI \(id)" : name }
}

/// TF130: real-time global vessel tracking, via a public, keyless REST
/// endpoint on `AutumnConfig.maritimeRelayURL` — the maritime counterpart to
/// RadarFeed's satellite/aircraft tracking, matching how those are
/// genuinely open to every app user with no signup.
///
/// This does NOT talk to AISStream.io directly, and that's deliberate:
/// AISStream's own terms say direct client connections aren't permitted —
/// "connect from your own server and proxy only the information your
/// clients need." `leatr-ash/services/ais-relay` is that server: it holds
/// the one AISStream connection (Justin's key, server-side, never in this
/// app) and re-serves the data here as plain JSON. No app user needs an
/// AISStream account or key at all — the relay's URL is the only thing this
/// class knows about.
@MainActor
public final class MaritimeFeed: ObservableObject {
    public static let shared = MaritimeFeed()

    @Published public var vessels: [RadarVessel] = []
    @Published public var selectedVessel: RadarVessel?
    @Published public var status: String = "AIS IDLE"

    private var pollTask: Task<Void, Never>?
    private var vesselMap: [String: RadarVessel] = [:]
    private let pollInterval: TimeInterval = 5.0

    public func start() {
        guard pollTask == nil else { return }
        guard !AutumnConfig.maritimeRelayURL.contains("REPLACE-WITH") else {
            status = "AIS relay not deployed yet"
            return
        }
        status = "AIS CONNECTING…"
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: UInt64((self?.pollInterval ?? 5) * 1_000_000_000))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        status = "AIS IDLE"
    }

    private func poll() async {
        guard let url = URL(string: "\(AutumnConfig.maritimeRelayURL)/vessels") else { return }
        do {
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue("Autumn-iOS/1.0.2", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                status = "AIS relay error"
                return
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["vessels"] as? [[String: Any]]
            else {
                status = "AIS relay: bad response"
                return
            }
            let relayStatus = obj["status"] as? String ?? "live"
            var next: [String: RadarVessel] = [:]
            let df = ISO8601DateFormatter()
            for entry in arr {
                guard let id = (entry["id"] as? String) ?? (entry["id"] as? Int).map(String.init),
                      let lat = entry["lat"] as? Double,
                      let lon = entry["lon"] as? Double
                else { continue }
                var v = vesselMap[id] ?? RadarVessel(
                    id: id, name: entry["name"] as? String ?? "", type: "vessel",
                    lat: lat, lon: lon, prevLat: nil, prevLon: nil,
                    speedKn: entry["speedKn"] as? Double, courseDeg: entry["courseDeg"] as? Double,
                    lastUpdate: Date()
                )
                v.prevLat = v.lat
                v.prevLon = v.lon
                v.lat = lat
                v.lon = lon
                if let n = entry["name"] as? String, !n.isEmpty { v.name = n }
                v.speedKn = entry["speedKn"] as? Double
                v.courseDeg = entry["courseDeg"] as? Double
                if let ts = entry["lastUpdate"] as? String, let d = df.date(from: ts) {
                    v.lastUpdate = d
                }
                next[id] = v
            }
            vesselMap = next
            vessels = Array(vesselMap.values)
            status = "AIS \(relayStatus.uppercased()) (\(vessels.count))"
            if let sel = selectedVessel, let updated = vesselMap[sel.id] {
                selectedVessel = updated
            }
        } catch {
            status = "AIS relay unreachable: \(error.localizedDescription)"
        }
    }
}
