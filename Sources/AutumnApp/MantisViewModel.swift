import SwiftUI
import SceneKit
import Combine

// MARK: — MantisViewModel
// Physics engine + data layer for Mantis Navigation

public enum CameraMode: String { case follow = "Follow", fpv = "FPV", free = "Free" }
public enum PresetModel { case ariel, arrow, autumn }

@MainActor
public final class MantisViewModel: ObservableObject {

    // MARK: — Published state
    @Published public var joystickX: Float  = 0
    @Published public var joystickY: Float  = 0
    @Published public var thrust: Float     = 0
    @Published public var velocity: Float   = 0
    @Published public var altitude: Float   = 0
    @Published public var cameraMode: CameraMode = .follow
    @Published public var adsbActive       = false
    @Published public var orbitalActive    = false
    @Published public var aircraftCount    = 0
    @Published public var satelliteCount   = 0
    @Published public var rangeNm          = 200
    @Published public var flipOnLoad       = false
    @Published public var showFilePicker   = false

    // MARK: — Scene
    public let scene = SCNScene()
    private var modelNode: SCNNode?
    private var cameraNode: SCNNode!
    private var pivotNode: SCNNode!

    // Physics (matches mn.html physics object)
    private var vel  = SCNVector3(0,0,0)
    private let drag: Float    = 0.98
    private let gravity: Float = 0.00003
    private let thrustPwr: Float = 0.01
    private let yawSpeed: Float  = 0.1

    // Data timers
    private var adsbTimer: Timer?
    private var tleTimer: Timer?
    private var physicsDisplayLink: CADisplayLink?

    // MARK: — Start/Stop
    public func start() {
        setupScene()
        loadPreset(.autumn)
        startADSB()
        startTLE()
    }

    public func stop() {
        adsbTimer?.invalidate()
        tleTimer?.invalidate()
    }

    // MARK: — Scene setup
    private func setupScene() {
        scene.background.contents = UIColor(red:0.01,green:0.02,blue:0.05,alpha:1)

        // Stars
        for _ in 0..<600 {
            let s = SCNSphere(radius: CGFloat.random(in: 0.1...0.4))
            s.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(
                CGFloat.random(in:0.3...1.0))
            s.firstMaterial?.lightingModel = .constant
            let n = SCNNode(geometry:s)
            let r: Float = 3000
            n.position = SCNVector3(
                Float.random(in:-r...r),
                Float.random(in:-r...r),
                Float.random(in:-r...r))
            scene.rootNode.addChildNode(n)
        }

        // Ambient + directional light (matches mn.html)
        let amb = SCNLight(); amb.type = .ambient; amb.intensity = 120
        amb.color = UIColor.white
        let an = SCNNode(); an.light = amb
        scene.rootNode.addChildNode(an)

        let dir = SCNLight(); dir.type = .directional; dir.intensity = 800
        dir.color = UIColor(red:0.5,green:0.8,blue:1.0,alpha:1)
        let dn = SCNNode(); dn.light = dir
        dn.eulerAngles = SCNVector3(-Float.pi/4, Float.pi/6, 0)
        scene.rootNode.addChildNode(dn)

        // Grid floor
        let grid = SCNNode(); grid.name = "grid"
        for i in stride(from:-50, through:50, by:5) {
            for horiz in [true,false] {
                let c = SCNCylinder(radius:0.02, height:100)
                c.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.04)
                c.firstMaterial?.lightingModel = .constant
                let n = SCNNode(geometry:c)
                n.position = horiz ?
                    SCNVector3(Float(i),-8,0) : SCNVector3(0,-8,Float(i))
                n.eulerAngles.x = .pi/2
                grid.addChildNode(n)
            }
        }
        scene.rootNode.addChildNode(grid)

        // Pivot + camera (follow mode)
        pivotNode = SCNNode(); pivotNode.name = "pivot"
        scene.rootNode.addChildNode(pivotNode)

        cameraNode = SCNNode()
        cameraNode.camera = {
            let c = SCNCamera(); c.fieldOfView = 75
            c.zFar = 100000; c.zNear = 0.01; return c
        }()
        cameraNode.position = SCNVector3(0, 3, 12)
        cameraNode.look(at: SCNVector3(0,0,0))
        pivotNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: — Load preset models (built-in geometries mirroring the web presets)
    public func loadPreset(_ preset: PresetModel) {
        modelNode?.removeFromParentNode()

        let node: SCNNode
        switch preset {
        case .ariel:
            node = buildArielModel()
        case .arrow:
            node = buildArrowModel()
        case .autumn:
            node = buildAutumnModel()
        }

        if flipOnLoad { node.eulerAngles.y = .pi }
        node.name = "navModel"
        scene.rootNode.addChildNode(node)
        modelNode = node
        pivotNode.position = node.position
        log("Loaded \(preset) model")
    }

    private func buildArrowModel() -> SCNNode {
        let n = SCNNode()
        // Body
        let body = SCNCone(topRadius:0, bottomRadius:0.3, height:2.5)
        body.firstMaterial?.diffuse.contents = UIColor.cyan
        body.firstMaterial?.emission.contents = UIColor.cyan.withAlphaComponent(0.3)
        n.addChildNode(SCNNode(geometry:body))
        // Fins
        for angle in [0, Float.pi/2, Float.pi, 3*Float.pi/2] {
            let fin = SCNBox(width:0.8, height:0.05, length:0.5, chamferRadius:0)
            fin.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.7)
            let fn = SCNNode(geometry:fin)
            fn.position = SCNVector3(cos(angle)*0.4, -0.8, sin(angle)*0.4)
            n.addChildNode(fn)
        }
        return n
    }

    private func buildArielModel() -> SCNNode {
        let n = SCNNode()
        // Sphere body
        let body = SCNSphere(radius:0.8)
        body.firstMaterial?.diffuse.contents = UIColor(red:0.3,green:0.1,blue:0.8,alpha:1)
        body.firstMaterial?.emission.contents = UIColor.purple.withAlphaComponent(0.4)
        n.addChildNode(SCNNode(geometry:body))
        // Ring
        let ring = SCNTorus(ringRadius:1.4, pipeRadius:0.06)
        ring.firstMaterial?.diffuse.contents = UIColor.cyan
        ring.firstMaterial?.emission.contents = UIColor.cyan.withAlphaComponent(0.5)
        n.addChildNode(SCNNode(geometry:ring))
        return n
    }

    private func buildAutumnModel() -> SCNNode {
        let n = SCNNode()
        // Main body
        let body = SCNCapsule(capRadius:0.4, height:2.0)
        body.firstMaterial?.diffuse.contents = UIColor(red:0.0,green:0.7,blue:0.9,alpha:1)
        body.firstMaterial?.emission.contents = UIColor.cyan.withAlphaComponent(0.25)
        n.addChildNode(SCNNode(geometry:body))
        // Wings
        for side: Float in [-1,1] {
            let wing = SCNBox(width:1.8, height:0.06, length:0.5, chamferRadius:0.05)
            wing.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.6)
            let wn = SCNNode(geometry:wing)
            wn.position = SCNVector3(side*1.0, 0, 0)
            n.addChildNode(wn)
        }
        return n
    }

    // MARK: — Physics update (called each frame by SceneKit renderer delegate)
    public func updatePhysics() {
        guard let model = modelNode else { return }

        // Thrust force (forward = -Z in local space)
        if thrust > 0 {
            let fwd = model.presentation.simdTransform.columns.2
            vel.x -= fwd.x * thrustPwr * thrust
            vel.y -= fwd.y * thrustPwr * thrust
            vel.z -= fwd.z * thrustPwr * thrust
        }

        // Gravity
        vel.y -= gravity

        // Drag
        vel.x *= drag; vel.y *= drag; vel.z *= drag

        // Joystick yaw/pitch
        model.eulerAngles.y -= joystickX * yawSpeed * 0.05
        model.eulerAngles.x  = max(-Float.pi/4,
                               min(Float.pi/4, joystickY * Float.pi/6))

        // Apply velocity
        model.position.x += vel.x
        model.position.y += vel.y
        model.position.z += vel.z

        // Computed values
        velocity = sqrt(vel.x*vel.x + vel.y*vel.y + vel.z*vel.z) * 1000
        altitude = model.position.y + 8

        // Camera follow
        switch cameraMode {
        case .follow:
            let target = model.presentation.position
            let behind = SCNVector3(target.x, target.y + 3, target.z + 12)
            cameraNode.position.x += (behind.x - cameraNode.position.x) * 0.05
            cameraNode.position.y += (behind.y - cameraNode.position.y) * 0.05
            cameraNode.position.z += (behind.z - cameraNode.position.z) * 0.05
            cameraNode.look(at: target)
        case .fpv:
            cameraNode.position = model.presentation.position
            cameraNode.eulerAngles = model.eulerAngles
        case .free:
            break
        }
    }

    public func idle() {
        vel = SCNVector3(0,0,0)
        thrust = 0; joystickX = 0; joystickY = 0
        log("IDLE")
    }

    public func toggleCameraMode() {
        switch cameraMode {
        case .follow: cameraMode = .fpv
        case .fpv:    cameraMode = .free
        case .free:   cameraMode = .follow
        }
    }

    // MARK: — ADS-B (real aircraft via ADSB Exchange public API)
    private func startADSB() {
        fetchADSB()
        adsbTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { await self?.fetchADSBAsync() }
        }
    }

    private func fetchADSB() {
        Task { await fetchADSBAsync() }
    }

    private func fetchADSBAsync() async {
        // Using adsbexchange.com rapid API — public endpoint
        guard let url = URL(string: "https://api.adsb.lol/v2/lat/25.77/lon/-80.19/dist/\(rangeNm)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct ADSBResponse: Decodable { let ac: [ADSBAircraft]? }
            struct ADSBAircraft: Decodable { let flight: String?; let alt_baro: AnyCodable? }
            struct AnyCodable: Decodable { init(from decoder: Decoder) throws {} }
            if let resp = try? JSONDecoder().decode(ADSBResponse.self, from: data),
               let ac = resp.ac {
                await MainActor.run {
                    self.aircraftCount = ac.count
                    self.adsbActive = true
                }
                addAircraftNodes(count: ac.count)
            }
        } catch {
            await MainActor.run { self.adsbActive = false }
        }
    }

    private func addAircraftNodes(count: Int) {
        // Remove old
        scene.rootNode.childNodes.filter{$0.name=="aircraft"}.forEach{$0.removeFromParentNode()}
        // Add simplified markers
        let geo = SCNSphere(radius: 0.15)
        geo.firstMaterial?.diffuse.contents = UIColor.orange.withAlphaComponent(0.8)
        geo.firstMaterial?.emission.contents = UIColor.orange.withAlphaComponent(0.4)
        geo.firstMaterial?.lightingModel = .constant
        for _ in 0..<min(count, 30) {
            let n = SCNNode(geometry: geo)
            n.name = "aircraft"
            n.position = SCNVector3(
                Float.random(in:-80...80),
                Float.random(in:20...60),
                Float.random(in:-80...80))
            scene.rootNode.addChildNode(n)
        }
    }

    // MARK: — TLE / Orbital (CelesTrak)
    private func startTLE() {
        fetchTLE()
        tleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.fetchTLEAsync() }
        }
    }

    private func fetchTLE() { Task { await fetchTLEAsync() } }

    private func fetchTLEAsync() async {
        guard let url = URL(string: "https://celestrak.org/SOCRATES/query.php?CODE=ISS&FORMAT=JSON") else { return }
        // Simpler: ISS TLE from CelesTrak
        guard let tleURL = URL(string: "https://celestrak.org/satcat/tle.php?CATNR=25544") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: tleURL)
            let lines = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) ?? []
            let count = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count / 3
            await MainActor.run {
                self.satelliteCount = max(1, count)
                self.orbitalActive = true
            }
            addSatelliteNodes(count: max(1, count))
        } catch {
            // Fallback — use known satellite count
            await MainActor.run { self.orbitalActive = false }
        }
    }

    private func addSatelliteNodes(count: Int) {
        scene.rootNode.childNodes.filter{$0.name=="satellite"}.forEach{$0.removeFromParentNode()}
        let geo = SCNSphere(radius:0.2)
        geo.firstMaterial?.diffuse.contents = UIColor.purple.withAlphaComponent(0.8)
        geo.firstMaterial?.emission.contents = UIColor.purple.withAlphaComponent(0.5)
        geo.firstMaterial?.lightingModel = .constant
        for _ in 0..<min(count, 20) {
            let n = SCNNode(geometry:geo)
            n.name = "satellite"
            let r: Float = 200
            n.position = SCNVector3(
                Float.random(in:-r...r),
                Float.random(in:100...300),
                Float.random(in:-r...r))
            scene.rootNode.addChildNode(n)
        }
    }

    private func log(_ msg:String) {
        print("[Mantis] \(msg)")
    }
}
