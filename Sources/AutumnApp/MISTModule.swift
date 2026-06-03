
import Foundation
import SceneKit

/// MIST module — matches web app js/mist-module.js
/// Sends visual mist signals across BRPN world scene between active users when maze solved
/// Mist emits only from the solving node's position
/// STALE_MS = 600 seconds (10 minutes)
public final class MISTModule: ObservableObject {
    public static let shared = MISTModule()

    private let STALE_MS: Double = 600_000

    @Published public var activeSignals: [MISTSignal] = []
    @Published public var ashStarActive = false

    private var timer: Timer?
    private let presenceURL = "https://raw.githubusercontent.com/DART-Skyboard/Autumn/main/presence.json"

    public struct MISTSignal: Identifiable {
        public let id = UUID()
        public var position: SIMD3<Float>
        public var intensity: Float
        public var timestamp: Date
        public var isAsh: Bool  // true = Autumn's own Ash Star signal
    }

    private init() {
        startPolling()
    }

    // MARK: — Polling (matches web app STALE_MS pattern)
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.fetchPresence() }
        }
    }

    private func fetchPresence() async {
        guard let url = URL(string: presenceURL) else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        let now = Date()
        let signals: [MISTSignal] = json.compactMap { node in
            guard let ts = node["timestamp"] as? Double else { return nil }
            let age = (now.timeIntervalSince1970 * 1000) - ts
            guard age < STALE_MS else { return nil }
            let x = node["x"] as? Float ?? Float.random(in: -2...2)
            let y = node["y"] as? Float ?? Float.random(in: -2...2)
            let z = node["z"] as? Float ?? Float.random(in: -2...2)
            let isAsh = (node["id"] as? String) == "autumn"
            return MISTSignal(position: SIMD3<Float>(x, y, z),
                             intensity: Float(1.0 - age / STALE_MS),
                             timestamp: Date(timeIntervalSince1970: ts/1000),
                             isAsh: isAsh)
        }

        await MainActor.run { self.activeSignals = signals }
    }

    // MARK: — Emit Ash Star (Autumn's own signal)
    public func emitAshStar(at position: SIMD3<Float>, pat: String) async {
        await MainActor.run { ashStarActive = true }
        // Write to GitHub presence (direct write, no batch)
        let payload: [String: Any] = [
            "id": "autumn",
            "x": position.x, "y": position.y, "z": position.z,
            "timestamp": Date().timeIntervalSince1970 * 1000,
            "type": "ash"
        ]
        // In production: write to presence.gs endpoint
        print("[MIST] Ash Star emitted at \(position)")
        await MainActor.run { ashStarActive = false }
    }

    // MARK: — Build particle geometry for MIST signals
    public func buildMISTParticles(for signal: MISTSignal) -> SCNNode {
        let root = SCNNode()
        let count = Int(signal.intensity * 80) + 20

        let color: UIColor = signal.isAsh
            ? UIColor(red:0.8, green:0.8, blue:1.0, alpha:Double(signal.intensity))
            : UIColor(red:0.0, green:0.9, blue:1.0, alpha:Double(signal.intensity * 0.7))

        // Volumetric particle cloud
        let geo = SCNSphere(radius: 0.015)
        geo.segmentCount = 4
        geo.firstMaterial?.diffuse.contents  = color
        geo.firstMaterial?.emission.contents = color
        geo.firstMaterial?.lightingModel = .constant

        let spread: Float = signal.isAsh ? 0.8 : 0.5
        for _ in 0..<count {
            let n = SCNNode(geometry: geo)
            n.position = SCNVector3(
                signal.position.x + Float.random(in: -spread...spread),
                signal.position.y + Float.random(in: -spread...spread),
                signal.position.z + Float.random(in: -spread...spread))
            // Drift animation
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
