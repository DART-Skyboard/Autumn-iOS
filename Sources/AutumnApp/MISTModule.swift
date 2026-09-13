import Foundation
import SceneKit
import AutumnServices

/// MIST module — js/mist-module.js
/// Presence + maze-solve signals. Writes via GAS ashwrite. No PAT.
@MainActor
public final class MISTModule: ObservableObject {
    public static let shared = MISTModule()

    private let STALE_MS: Double = 600_000

    @Published public var activeSignals: [MISTSignal] = []
    @Published public var ashStarActive = false

    /// Web `_ashNodes._localUid` — sid of this device session (not a per-chat ghost).
    public var localUid: String = "ios-guest"
    public var localSid: String = "ios-guest"

    private var timer: Timer?

    public struct MISTSignal: Identifiable {
        public let id: String
        public var uid: String
        public var position: SIMD3<Float>
        public var intensity: Float
        public var timestamp: Date
        public var isAsh: Bool
    }

    private init() {
        startPolling()
    }

    public func refresh() async {
        await fetchPresence()
    }

    public func bindIdentity(uid: String, sid: String) {
        localUid = uid
        localSid = sid
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.fetchPresence() }
        }
    }

    private func fetchPresence() async {
        // Heartbeat this device into the shared CacheService (web writenode).
        await AutumnGASClient.shared.writeNode(sid: localSid, uid: localUid, label: localUid)
        await AutumnGASClient.shared.writeSession(uid: localUid, sid: localSid, extra: [
            "type": "presence",
            "platform": "ios"
        ])

        var collected: [MISTSignal] = []
        // PRIMARY: GAS readnodes — same source as web `_pollAshNodes`.
        let nodes = await AutumnGASClient.shared.readNodes()
        if !nodes.isEmpty {
            collected.append(contentsOf: parseSessionRows(nodes))
        }
        // SECONDARY: GAS sessions (full heartbeat + mist/ashstar).
        if collected.isEmpty {
            let sessions = await AutumnGASClient.shared.readSessions()
            collected.append(contentsOf: parseSessionRows(sessions))
            ingestAshStarsFromSessions(sessions)
        }
        // TERTIARY: public GitHub session listing (web fallback, no PAT).
        if collected.isEmpty {
            collected.append(contentsOf: await fetchGitHubSessions())
        }
        // Mist events are FX / ashstar only — never user buoyancy nodes.
        if let gas = await AutumnGASClient.shared.ashread(path: "ashtree/mist/events.json") {
            ingestAshStars(gas)
        }

        let now = Date().timeIntervalSince1970 * 1000
        let sessionStale: Double = 6 * 60 * 1000 // web STALE_MS
        let fresh = collected.filter { now - ($0.timestamp.timeIntervalSince1970 * 1000) < sessionStale }
        var seen: [String: MISTSignal] = [:]
        for s in fresh {
            if isLocal(s.uid) { continue }
            seen[s.uid] = s
        }
        activeSignals = Array(seen.values)
    }

    private func isLocal(_ id: String) -> Bool {
        id == localUid || id == localSid
    }

    /// Web session row: `{ sid, uid, ts }` — skip rows with no identity (do not mint UUIDs).
    private func parseSessionRows(_ rows: [[String: Any]]) -> [MISTSignal] {
        let now = Date()
        return rows.compactMap { node in
            let sid = (node["sid"] as? String) ?? ""
            let uid = (node["uid"] as? String) ?? ""
            let nodeId = sid.isEmpty ? uid : sid
            guard !nodeId.isEmpty else { return nil }
            var tsMs: Double = now.timeIntervalSince1970 * 1000
            if let t = node["ts"] as? Double { tsMs = t }
            else if let t = node["ts"] as? Int { tsMs = Double(t) }
            else if let t = node["timestamp"] as? Double { tsMs = t }
            else if let t = node["timestamp"] as? Int { tsMs = Double(t) }
            else if let t = node["ts"] as? String, let d = ISO8601DateFormatter().date(from: t) {
                tsMs = d.timeIntervalSince1970 * 1000
            }
            let isAsh = nodeId.lowercased() == "autumn" || uid.lowercased() == "autumn" || (node["type"] as? String) == "ash"
            return MISTSignal(
                id: nodeId,
                uid: nodeId,
                position: SIMD3<Float>(0, 0, 0),
                intensity: 1,
                timestamp: Date(timeIntervalSince1970: tsMs / 1000),
                isAsh: isAsh
            )
        }
    }

    private func ingestAshStarsFromSessions(_ rows: [[String: Any]]) {
        for s in rows {
            guard let asStar = s["ashStar"] as? [String: Any], asStar["ts"] != nil else { continue }
            var row = asStar
            if (row["type"] as? String)?.isEmpty != false { row["type"] = "ashstar" }
            if row["uid"] == nil { row["uid"] = s["sid"] ?? s["uid"] ?? "autumn" }
            ingestAshStars(row)
        }
    }

    private func fetchGitHubSessions() async -> [MISTSignal] {
        guard let url = URL(string: "https://api.github.com/repos/DART-Skyboard/leatr-ash/contents/ashtree/sessions") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let files = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let mine = localSid + ".json"
        let recent = files
            .filter { ($0["name"] as? String)?.hasSuffix(".json") == true && ($0["name"] as? String) != mine }
            .prefix(20)
        var out: [MISTSignal] = []
        for f in recent {
            guard let dl = f["download_url"] as? String, let u = URL(string: dl) else { continue }
            guard let (d, _) = try? await URLSession.shared.data(from: u),
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            out.append(contentsOf: parseSessionRows([json]))
        }
        return out
    }

    private func parse(_ json: Any) -> [MISTSignal] {
        var arr: [[String: Any]] = []
        if let a = json as? [[String: Any]] { arr = a }
        else if let d = json as? [String: Any] {
            if let inner = d["nodes"] as? [[String: Any]] { arr = inner }
            else { arr = [d] }
        }
        let now = Date()
        return arr.compactMap { node in
            let uid = (node["uid"] as? String) ?? (node["id"] as? String) ?? (node["sid"] as? String) ?? ""
            guard !uid.isEmpty else { return nil }
            var tsMs: Double = now.timeIntervalSince1970 * 1000
            if let t = node["timestamp"] as? Double { tsMs = t }
            else if let t = node["ts"] as? Double { tsMs = t }
            else if let t = node["ts"] as? String, let d = ISO8601DateFormatter().date(from: t) {
                tsMs = d.timeIntervalSince1970 * 1000
            }
            let x = floatVal(node["x"]) ?? Float.random(in: -2...2)
            let y = floatVal(node["y"]) ?? Float.random(in: -2...2)
            let z = floatVal(node["z"]) ?? Float.random(in: -2...2)
            let isAsh = uid.lowercased() == "autumn" || (node["type"] as? String) == "ash"
            return MISTSignal(
                id: uid,
                uid: uid,
                position: SIMD3<Float>(x, y, z),
                intensity: Float(max(0, min(1, 1.0 - ((now.timeIntervalSince1970 * 1000) - tsMs) / STALE_MS))),
                timestamp: Date(timeIntervalSince1970: tsMs / 1000),
                isAsh: isAsh
            )
        }
    }

    private func ingestAshStars(_ json: Any) {
        var arr: [[String: Any]] = []
        if let a = json as? [[String: Any]] { arr = a }
        else if let d = json as? [String: Any] { arr = [d] }
        for node in arr {
            let type = (node["type"] as? String) ?? ""
            guard type == "ashstar" else { continue }
            let uid = (node["uid"] as? String) ?? "autumn"
            let ts: Any = node["ts"] ?? node["timestamp"] ?? ""
            let key = "\(uid)-\(ts)"
            if seenStarKeys.contains(key) { continue }
            seenStarKeys.insert(key)
            if seenStarKeys.count > 200 { seenStarKeys = Set(seenStarKeys.suffix(120)) }
            let thought = AshStarThought.sanitize((node["thought"] as? String) ?? "")
            let color = (node["color"] as? String) ?? "#00d4ff"
            NotificationCenter.default.post(
                name: .autumnIncomingAshStar,
                object: nil,
                userInfo: ["thought": thought, "color": color, "uid": uid]
            )
        }
    }

    private func floatVal(_ any: Any?) -> Float? {
        if let f = any as? Float { return f }
        if let d = any as? Double { return Float(d) }
        if let i = any as? Int { return Float(i) }
        if let s = any as? String, let d = Double(s) { return Float(d) }
        return nil
    }

    public func emitSolve(uid: String, slot: Int) {
        let payload: [String: Any] = [
            "type": "solve",
            "uid": uid,
            "slot": slot,
            "ts": Date().timeIntervalSince1970 * 1000,
            "platform": "ios"
        ]
        Task {
            _ = await AutumnGASClient.shared.ashwrite(
                path: "ashtree/mist/events.json",
                uid: uid,
                append: true,
                payload: [payload]
            )
            await AutumnGASClient.shared.pingPresence(
                message: "mist-solve",
                response: "slot \(slot)",
                emotion: slot == 1 ? "inspiring" : (slot == 2 ? "love" : "spiritual"),
                buoyancy: 0.7,
                uid: uid,
                sid: localSid
            )
        }
    }

    private var seenStarKeys: Set<String> = []

    public func emitAshStar(at position: SIMD3<Float>) {
        emitAshStarPacket(thought: "", toUids: ["all"], uid: "autumn")
        ashStarActive = true
        Task { await MainActor.run { self.ashStarActive = false } }
        _ = position
    }

    /// js fireAshStar payload — type ashstar, thought capped 120, no user chat.
    public func emitAshStarPacket(thought: String, toUids: [String], uid: String) {
        ashStarActive = true
        let t = AshStarThought.sanitize(thought)
        let payload: [String: Any] = [
            "type": "ashstar",
            "uid": uid,
            "from": "autumn",
            "toUids": toUids.isEmpty ? ["all"] : toUids,
            "color": "#00d4ff",
            "thought": String(t.prefix(120)),
            "ts": Date().timeIntervalSince1970 * 1000,
            "platform": "ios"
        ]
        Task {
            _ = await AutumnGASClient.shared.ashwrite(
                path: "ashtree/mist/events.json",
                uid: uid,
                append: true,
                payload: [payload]
            )
            await AutumnGASClient.shared.pingPresence(
                message: "ashstar",
                response: "star",
                emotion: "inspiring",
                buoyancy: 0.8,
                uid: uid,
                sid: localSid
            )
            await MainActor.run { self.ashStarActive = false }
        }
    }

    public func buildMISTParticles(for signal: MISTSignal) -> SCNNode {
        let root = SCNNode()
        let count = Int(signal.intensity * 80) + 20
        let color: UIColor = signal.isAsh
            ? UIColor(red: 0.8, green: 0.8, blue: 1.0, alpha: Double(signal.intensity))
            : UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: Double(signal.intensity * 0.7))
        let geo = SCNSphere(radius: 0.015)
        geo.segmentCount = 4
        geo.firstMaterial?.diffuse.contents = color
        geo.firstMaterial?.emission.contents = color
        geo.firstMaterial?.lightingModel = .constant
        let spread: Float = signal.isAsh ? 0.8 : 0.5
        for _ in 0..<count {
            let n = SCNNode(geometry: geo)
            n.position = SCNVector3(
                signal.position.x + Float.random(in: -spread...spread),
                signal.position.y + Float.random(in: -spread...spread),
                signal.position.z + Float.random(in: -spread...spread))
            let drift = SCNAction.sequence([
                SCNAction.move(by: SCNVector3(
                    Float.random(in: -0.1...0.1),
                    Float.random(in: 0.05...0.2),
                    Float.random(in: -0.1...0.1)),
                    duration: Double.random(in: 1.5...3.0)),
                SCNAction.fadeOut(duration: 0.5),
                SCNAction.removeFromParentNode()
            ])
            n.runAction(drift)
            root.addChildNode(n)
        }
        return root
    }
}
