import Foundation
import CoreLocation
import AutumnServices

/// A tracked vessel from AISStream.io's global AIS feed.
public struct RadarVessel: Identifiable, Equatable {
    public let id: String            // MMSI, as a string
    public var name: String
    public var type: String          // human-readable ship type
    public var lat: Double
    public var lon: Double
    public var prevLat: Double?      // previous fix — lets the globe animate a
    public var prevLon: Double?      // smooth move instead of snapping, since
                                      // AIS reports arrive periodically, not
                                      // continuously.
    public var speedKn: Double?      // knots, over ground
    public var courseDeg: Double?    // degrees, over ground
    public var lastUpdate: Date

    public var displayName: String { name.isEmpty ? "MMSI \(id)" : name }
}

/// TF128: real-time global vessel tracking — the maritime counterpart to
/// RadarFeed's satellite/aircraft tracking, same globe framework. Requires a
/// free AISStream.io API key (Settings > AI Backend), since that's how the
/// service works — there's no keyless free tier, the same as any other
/// "free" API that still requires self-serve signup.
@MainActor
public final class MaritimeFeed: ObservableObject {
    public static let shared = MaritimeFeed()

    @Published public var vessels: [RadarVessel] = []
    @Published public var selectedVessel: RadarVessel?
    @Published public var status: String = "AIS IDLE"

    private var task: URLSessionWebSocketTask?
    private var vesselMap: [String: RadarVessel] = [:]
    private var reconnectAttempt = 0
    private var wantsConnection = false

    private var apiKey: String? {
        KeychainService.shared.load(key: "aisstream_api_key")
    }

    public func start() {
        guard let key = apiKey, !key.isEmpty else {
            status = "AIS — add a free API key in Settings"
            return
        }
        wantsConnection = true
        connect(key: key)
    }

    public func stop() {
        wantsConnection = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        status = "AIS IDLE"
    }

    private func connect(key: String) {
        guard let url = URL(string: "wss://stream.aisstream.io/v0/stream") else { return }
        let session = URLSession(configuration: .default)
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()
        status = "AIS CONNECTING…"

        // Global coverage in one subscription — AISStream accepts a single
        // bounding box spanning the whole planet. PositionReport-only keeps
        // volume manageable; ShipStaticData would add names/types but roughly
        // doubles message volume for a mobile client, so it's left off for now
        // (vessels without a name yet just show as "MMSI <n>").
        let sub: [String: Any] = [
            "APIKey": key,
            "BoundingBoxes": [[[-90.0, -180.0], [90.0, 180.0]]],
            "FilterMessageTypes": ["PositionReport"]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: sub),
              let text = String(data: body, encoding: .utf8) else { return }
        t.send(.string(text)) { [weak self] error in
            if let error {
                Task { @MainActor in self?.status = "AIS error: \(error.localizedDescription)" }
            }
        }
        receiveLoop()
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .failure(let error):
                    self.status = "AIS disconnected: \(error.localizedDescription)"
                    self.scheduleReconnect()
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receiveLoop()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard wantsConnection, let key = apiKey else { return }
        reconnectAttempt += 1
        let delay = min(30.0, Double(reconnectAttempt) * 3.0)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.wantsConnection else { return }
            self.connect(key: key)
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["MessageType"] as? String == "PositionReport",
              let msg = obj["Message"] as? [String: Any],
              let report = msg["PositionReport"] as? [String: Any],
              let lat = report["Latitude"] as? Double,
              let lon = report["Longitude"] as? Double
        else { return }

        let meta = obj["MetaData"] as? [String: Any] ?? [:]
        let mmsi = (meta["MMSI"] as? Int).map(String.init)
            ?? (report["UserID"] as? Int).map(String.init)
            ?? UUID().uuidString
        let name = (meta["ShipName"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let speed = report["Sog"] as? Double
        let course = report["Cog"] as? Double

        reconnectAttempt = 0
        status = "AIS LIVE (\(vesselMap.count))"

        var vessel = vesselMap[mmsi] ?? RadarVessel(
            id: mmsi, name: name, type: "vessel", lat: lat, lon: lon,
            prevLat: nil, prevLon: nil, speedKn: speed, courseDeg: course, lastUpdate: Date()
        )
        vessel.prevLat = vessel.lat
        vessel.prevLon = vessel.lon
        vessel.lat = lat
        vessel.lon = lon
        if !name.isEmpty { vessel.name = name }
        vessel.speedKn = speed
        vessel.courseDeg = course
        vessel.lastUpdate = Date()
        vesselMap[mmsi] = vessel

        // Cap what's actually rendered — thousands of global position reports
        // a minute would overwhelm both the scene and the screen; keep the
        // most recently updated ones, which in practice favors busier
        // shipping lanes near wherever the feed currently has coverage.
        if vesselMap.count > 300 {
            let oldest = vesselMap.values.sorted { $0.lastUpdate < $1.lastUpdate }.prefix(vesselMap.count - 300)
            for v in oldest { vesselMap.removeValue(forKey: v.id) }
        }
        vessels = Array(vesselMap.values)
        if let sel = selectedVessel, let updated = vesselMap[sel.id] {
            selectedVessel = updated
        }
    }
}
