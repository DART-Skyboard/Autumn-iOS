import SwiftUI
import SceneKit
import LEATRCore

// MARK: — BRPNSceneViewModel
// Live port of index.html initBRPN / animate / buildOrbMazeGeometry.
// JS names kept in comments. SceneKit, not WKWebView.

@MainActor
public final class BRPNSceneViewModel: ObservableObject {

    @Published public var shellStates: [BRPNShell: String] = [
        .geological: "FOUNDATION", .maritime: "REFLEX", .aerospace: "PERFORMANCE"
    ]
    @Published public var activeNodes: Int = 1
    @Published public var sessionId = String(UUID().uuidString.prefix(8).uppercased())
    @Published public var quantumSocket: Double = 6.9120
    @Published public var mazeCanSolve = false
    @Published public var isSolving = false
    /// JS: `_mantisNodeMax` default 100 — node cap HUD 10/50/100/300/1200/2e6
    @Published public var mantisNodeMax: Int = 100

    public let scene = SCNScene()
    public var shells: [SCNNode] = []
    public var pathMeshNodes: [SCNNode] = []
    public static weak var shared: BRPNSceneViewModel?

    let animator = BRPNAnimator()
    var cameraNode: SCNNode?
    private var coreNode: SCNNode!
    private var mazeOrbGroup: SCNNode!
    private var particleNodes: [SCNNode] = []
    private var sessionGroupNodes: [String: SCNNode] = [:]
    private var splineGroup: SCNNode?
    private var splineSamples: [[SCNVector3]] = []
    private var presenceTimer: Timer?
    private var mantisNodes: [SCNNode] = []
    private var toolPivots: [SCNNode] = []

    // JS: shellColors=[0x00ffcc,0x0088ff,0xff4466]; shellRadii=[1.9,1.4,0.9]
    private let shellColors: [UIColor] = [
        ThreeJSGeometry.hex(0x00ffcc),
        ThreeJSGeometry.hex(0x0088ff),
        ThreeJSGeometry.hex(0xff4466),
    ]
    private let shellRadii: [Float] = [1.9, 1.4, 0.9]

    // MARK: — Setup  (JS initBRPN)
    public func setupScene() {
        Self.shared = self
        scene.background.contents = UIColor.clear

        // Clear previous
        scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        shells.removeAll()
        particleNodes.removeAll()
        sessionGroupNodes.removeAll()
        pathMeshNodes.removeAll()
        toolPivots.removeAll()
        mantisNodes.removeAll()

        let amb = SCNNode()
        amb.light = { let l = SCNLight(); l.type = .ambient; l.intensity = 280; l.color = UIColor.white; return l }()
        scene.rootNode.addChildNode(amb)

        // Camera — JS: PerspectiveCamera(50,…,0.1,100) position.set(0,1.5,5) lookAt(0,0,0)
        let cam = SCNCamera()
        cam.fieldOfView = 50
        cam.zNear = 0.1
        cam.zFar = 100
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 1.5, 5)
        camNode.look(at: SCNVector3(0, 0, 0))
        camNode.name = "brpnCam"
        scene.rootNode.addChildNode(camNode)
        cameraNode = camNode

        // Buoyancy shells — JS: IcosahedronGeometry(shellRadii[i], 1) opacity 0.18+i*0.08
        for (i, radius) in shellRadii.enumerated() {
            let geo = ThreeJSGeometry.icosahedron(radius: radius, detail: 1)
            geo.materials = [ThreeJSGeometry.wireMat(shellColors[i], opacity: CGFloat(0.18 + Float(i) * 0.08))]
            let mesh = SCNNode(geometry: geo)
            mesh.name = "shell_\(i)" // GEO / MAR / AERO
            scene.rootNode.addChildNode(mesh)
            shells.append(mesh)
        }

        // Core sphere — JS: SphereGeometry(0.18, 12, 12) opacity 0.18 wireframe 0x00ffcc
        let cg = SCNSphere(radius: 0.18)
        cg.segmentCount = 12
        cg.materials = [ThreeJSGeometry.wireMat(ThreeJSGeometry.hex(0x00ffcc), opacity: 0.18)]
        coreNode = SCNNode(geometry: cg)
        coreNode.name = "core"
        scene.rootNode.addChildNode(coreNode)

        // LEMAC 3D maze at core — JS: mazeOrbGroup + buildOrbMazeGeometry()
        mazeOrbGroup = SCNNode()
        mazeOrbGroup.name = "mazeOrb"
        scene.rootNode.addChildNode(mazeOrbGroup)
        buildOrbMazeGeometry()

        // Orbital particles — JS: 30 × SphereGeometry(0.025,4,4) r=0.55+rand*1.45
        var pdata: [(r: Float, spd: Float, off: Float, yOff: Float)] = []
        for i in 0..<30 {
            let pg = SCNSphere(radius: 0.025)
            pg.segmentCount = 4
            pg.materials = [ThreeJSGeometry.basicMat(shellColors[i % 3], opacity: 0.7)]
            let p = SCNNode(geometry: pg)
            let r = 0.55 + Float.random(in: 0..<1) * 1.45
            let spd = 0.3 + Float.random(in: 0..<1) * 1.2
            let off = Float.random(in: 0..<(Float.pi * 2))
            let yOff = (Float.random(in: 0..<1) - 0.5) * 1.6
            pdata.append((r, spd, off, yOff))
            scene.rootNode.addChildNode(p)
            particleNodes.append(p)
        }

        spawnToolShapes()

        animator.configure(
            shells: shells,
            core: coreNode,
            mazeOrbGroup: mazeOrbGroup,
            particles: particleNodes,
            particleData: pdata,
            camera: camNode,
            shellColors: shellColors
        )
        animator.onPublishedSolve = { [weak self] solving, can in
            DispatchQueue.main.async {
                self?.isSolving = solving
                self?.mazeCanSolve = can
            }
        }
        animator.onRegen = { [weak self] in
            DispatchQueue.main.async { self?.buildOrbMazeGeometry() }
        }
        animator.pathMeshNodes = pathMeshNodes

        presenceTimer?.invalidate()
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { await self?.pollPresence() }
        }
    }

    // MARK: — Tool shape swarm  (JS makeToolShape / toolDefs)
    private func spawnToolShapes() {
        struct Def { let type: String; let color: UInt32; let count: Int }
        let toolDefs: [Def] = [
            Def(type: "knife", color: 0xff4466, count: 4),
            Def(type: "stick", color: 0x00ffcc, count: 4),
            Def(type: "hammer", color: 0x0088ff, count: 3),
            Def(type: "envelope", color: 0x88ccff, count: 3),
            Def(type: "scissors", color: 0xff8844, count: 3),
        ]
        var insts: [BRPNAnimator.ToolInst] = []
        for def in toolDefs {
            for i in 0..<def.count {
                let shellLayer = i % 3
                let baseR = shellRadii[shellLayer]
                let r = baseR * (0.85 + Float.random(in: 0..<1) * 0.3)
                let spd = 0.004 + Float.random(in: 0..<1) * 0.012
                let off = Float.random(in: 0..<(Float.pi * 2))
                let verts = BRPNToolShapes.verts(def.type)
                guard let mesh = ThreeJSGeometry.lineSegments(verts, color: ThreeJSGeometry.hex(def.color), opacity: 0) else { continue }
                mesh.scale = SCNVector3(0.55, 0.55, 0.55)
                let pivot = SCNNode()
                pivot.addChildNode(mesh)
                scene.rootNode.addChildNode(pivot)
                toolPivots.append(pivot)
                var inst = BRPNAnimator.ToolInst()
                inst.pivot = pivot
                inst.mesh = mesh
                inst.orbitRadius = r
                inst.orbitSpeed = spd
                inst.orbitOffset = off
                inst.shellLayer = shellLayer
                inst.tiltX = (Float.random(in: 0..<1) - 0.5) * Float.pi
                inst.tiltZ = (Float.random(in: 0..<1) - 0.5) * Float.pi
                insts.append(inst)
            }
        }
        animator.tools = insts
    }

    // MARK: — buildOrbMazeGeometry  index.html 13076–13148
    public func buildOrbMazeGeometry() {
        mazeOrbGroup.childNodes.forEach { $0.removeFromParentNode() }
        pathMeshNodes.removeAll()
        animator.mazeOrbState.solveStep = 0
        animator.mazeOrbState.solveActive = false

        let w = animator.mazeOrbState.width
        let h = animator.mazeOrbState.height
        let d = animator.mazeOrbState.depth
        let grid = MazeEngine.orbGenMaze(w, h, d)
        animator.mazeOrbState.grid = grid
        let solution = MazeEngine.orbSolveMaze(grid, w, h, d)
        animator.mazeOrbState.solution = solution
        mazeCanSolve = !solution.isEmpty
        isSolving = false

        let u = MazeOrbState.u
        let verts = MazeEngine.orbMazeWallVerts(grid: grid, w: w, h: h, d: d, u: u)
        // JS: LineBasicMaterial({color:0x00ffcc,transparent:true,opacity:0.55})
        if let wall = ThreeJSGeometry.lineSegments(verts, color: ThreeJSGeometry.hex(0x00ffcc), opacity: 0.55) {
            wall.name = "mazeWalls"
            mazeOrbGroup.addChildNode(wall)
        }

        // Path spheres hidden, revealed during solve — JS: SphereGeometry(u*0.22,4,4) opacity 0
        for pt in solution {
            let pg = SCNSphere(radius: CGFloat(u * 0.22))
            pg.segmentCount = 4
            pg.materials = [ThreeJSGeometry.basicMat(ThreeJSGeometry.hex(0x00ffff), opacity: 0)]
            let mesh = SCNNode(geometry: pg)
            let c = MazeEngine.orbCellCenter(x: pt.x, y: pt.y, z: pt.z, w: w, h: h, d: d, u: u)
            mesh.position = SCNVector3(c.0, c.1, c.2)
            mesh.name = "pathNode"
            mazeOrbGroup.addChildNode(mesh)
            pathMeshNodes.append(mesh)
        }

        // Start/end markers — JS: start 0x00ffcc Sphere u*0.35 at (0,0,0); end 0xff4466 at last
        if !solution.isEmpty {
            let mgeo = SCNSphere(radius: CGFloat(u * 0.35))
            mgeo.segmentCount = 6
            let sMat = ThreeJSGeometry.basicMat(ThreeJSGeometry.hex(0x00ffcc), opacity: 1)
            let eMat = ThreeJSGeometry.basicMat(ThreeJSGeometry.hex(0xff4466), opacity: 1)
            let sm = SCNNode(geometry: { let g = mgeo.copy() as! SCNSphere; g.materials = [sMat]; return g }())
            let sc = MazeEngine.orbCellCenter(x: 0, y: 0, z: 0, w: w, h: h, d: d, u: u)
            sm.position = SCNVector3(sc.0, sc.1, sc.2)
            mazeOrbGroup.addChildNode(sm)
            let last = solution[solution.count - 1]
            let em = SCNNode(geometry: { let g = mgeo.copy() as! SCNSphere; g.materials = [eMat]; return g }())
            let ec = MazeEngine.orbCellCenter(x: last.x, y: last.y, z: last.z, w: w, h: h, d: d, u: u)
            em.position = SCNVector3(ec.0, ec.1, ec.2)
            mazeOrbGroup.addChildNode(em)
        }
        animator.pathMeshNodes = pathMeshNodes
        animator.mazeOrbGroup = mazeOrbGroup
    }

    public func generateNewMaze() {
        // JS: regenOrbMazeCube
        buildOrbMazeGeometry()
        if !animator.looking { dollyInOrbCube() }
        else {
            animator.camIdle = 0
            animator.postSolveIdle = 0
            animator.postRegenIdle = 1
        }
    }

    /// JS: window.solveOrbMazeCube — dolly in + reveal BFS path of the 7×7×7 orb maze
    public func autumnSolveMaze() {
        guard mazeCanSolve, !isSolving else { return }
        dollyInOrbCube()
        animator.mazeOrbState.solveActive = true
        animator.mazeOrbState.solveStep = 0
        animator.mazeOrbState.regenTimer = 0
        for m in pathMeshNodes {
            m.geometry?.firstMaterial?.emission.contents = ThreeJSGeometry.hex(0x00ffff).withAlphaComponent(0)
            m.geometry?.firstMaterial?.diffuse.contents = ThreeJSGeometry.hex(0x00ffff).withAlphaComponent(0)
        }
        isSolving = true
    }

    /// JS: window.dollyInOrbCube
    public func dollyInOrbCube() {
        animator.looking = true
        animator.camMode = "in"
        animator.camIdle = 0
        animator.postSolveIdle = 0
        animator.postRegenIdle = 0
    }

    public func dollyOutOrbCube() {
        if !animator.looking && animator.camMode == "wide" { return }
        animator.camMode = "out"
        animator.postSolveIdle = 0
        animator.postRegenIdle = 0
        animator.camIdle = 0
    }

    /// JS: setOrbThinking(active)
    public func setOrbThinking(_ active: Bool) {
        animator.orbThinking = active
        if active {
            pulseShells(1.2)
        } else {
            if !animator.looking { animator.mazeOrbState.regenTimer = 60 }
            pulseShells(0.6)
        }
    }

    public func pulseShells(_ intensity: Float = 0.4) {
        // JS: shellPulse=Math.min(shellPulse+intensity,3)
        animator.shellPulse = min(animator.shellPulse + intensity, 3)
        if intensity > 0.5 && !animator.looking {
            animator.mazeOrbState.solveActive = true
            animator.mazeOrbState.solveStep = 0
            for m in pathMeshNodes {
                m.geometry?.firstMaterial?.emission.contents = ThreeJSGeometry.hex(0x00ffff).withAlphaComponent(0)
            }
        }
    }

    public func updateFrame() {
        animator.tick()
    }

    public func applyDrag(dx: Float, dy: Float) {
        // JS: rotY+=(e.clientX-prevX)*0.005; rotX+=(e.clientY-prevY)*0.005; clamp rotX ±1.2
        animator.rotY += dx * 0.005
        animator.rotX += dy * 0.005
        animator.rotX = max(-1.2, min(1.2, animator.rotX))
        if animator.looking { animator.camIdle = 0 }
    }

    public func applyZoom(_ delta: Float) {
        guard let cam = cameraNode else { return }
        let minZ: Float = animator.looking ? 0.85 : 2.5
        cam.position.z = max(minZ, min(10, cam.position.z + delta))
        if animator.looking {
            animator.camIdle = 0
            if animator.postSolveIdle > 0 { animator.postSolveIdle = 1 }
            if animator.postRegenIdle > 0 { animator.postRegenIdle = 1 }
        }
    }

    // MARK: — Remote session icosahedrons  JS _makeSessionGroup IcosahedronGeometry(r,1)
    public func addRemoteNode(uid: String, emotion: String = "neutral") {
        if sessionGroupNodes[uid] != nil { return }
        let pos = nodeBasePosition(uid: uid)
        let group = SCNNode(); group.name = "session_\(uid)"
        let colors = uidShellColors(uid: uid)
        let miniR: [Float] = [1.9 * 0.28, 1.4 * 0.28, 0.9 * 0.28]
        for (i, r) in miniR.enumerated() {
            let geo = ThreeJSGeometry.icosahedron(radius: r, detail: 1)
            geo.materials = [ThreeJSGeometry.wireMat(colors[i], opacity: CGFloat(0.22 + Float(i) * 0.06))]
            group.addChildNode(SCNNode(geometry: geo))
        }
        let cg = SCNSphere(radius: 0.032); cg.segmentCount = 6
        cg.materials = [ThreeJSGeometry.wireMat(colors[0], opacity: 0.55)]
        group.addChildNode(SCNNode(geometry: cg))
        group.position = SCNVector3(pos.x, pos.y, pos.z)
        scene.rootNode.addChildNode(group)
        sessionGroupNodes[uid] = group
        activeNodes += 1
    }

    /// JS: _brpnInjectMantisContacts — aircraft TetrahedronGeometry(0.032,0), satellite OctahedronGeometry(0.045,0)
    public func injectMantisContacts(_ contacts: [(type: String, lat: Double, lon: Double, alt: Double)]) {
        while mantisNodes.count + contacts.count > mantisNodeMax && !mantisNodes.isEmpty {
            let incoming = contacts.first?.type
            var evictIdx = -1
            if let incoming {
                if let i = mantisNodes.firstIndex(where: { $0.name == incoming }) { evictIdx = i }
            }
            let old = evictIdx > -1 ? mantisNodes.remove(at: evictIdx) : mantisNodes.removeFirst()
            old.removeFromParentNode()
        }
        for c in contacts {
            let phi = (90 - c.lat) * (.pi / 180)
            let theta = (c.lon + 180) * (.pi / 180)
            var r = c.type == "satellite"
                ? 1.6 + (c.alt) / 50000 * 0.6
                : 0.9 + Double.random(in: 0..<0.5)
            r = min(r, 2.4)
            let x = r * sin(phi) * cos(theta)
            let y = r * cos(phi)
            let z = r * sin(phi) * sin(theta)
            let geo: SCNGeometry
            let color: UIColor
            if c.type == "satellite" {
                geo = ThreeJSGeometry.octahedron(radius: 0.045, detail: 0)
                color = ThreeJSGeometry.hex(0xff2d78)
            } else {
                geo = ThreeJSGeometry.tetrahedron(radius: 0.032, detail: 0)
                color = ThreeJSGeometry.hex(0x00e5ff)
            }
            geo.materials = [ThreeJSGeometry.wireMat(color, opacity: 0.55)]
            let mesh = SCNNode(geometry: geo)
            mesh.position = SCNVector3(Float(x), Float(y), Float(z))
            mesh.name = c.type
            scene.rootNode.addChildNode(mesh)
            mantisNodes.append(mesh)
            animator.mantis.append(BRPNAnimator.MantisInst(
                node: mesh,
                spawn: animator.orbFrame,
                type: c.type,
                orbitR: Float(r),
                orbitSpd: Float((c.type == "satellite" ? 0.0008 : 0.0022) + Double.random(in: 0..<0.001)),
                orbitOff: Float.random(in: 0..<(Float.pi * 2)),
                alt: Float(y)
            ))
        }
        pulseShells(0.15)
    }

    public func spawnAshStar(color: UIColor = UIColor(red: 1, green: 0.87, blue: 0, alpha: 1), target: String = "all") {
        rebuildSplines()
        let geo = ThreeJSGeometry.icosahedron(radius: 0.09, detail: 0)
        geo.materials = [ThreeJSGeometry.wireMat(color, opacity: 1)]
        let star = SCNNode(geometry: geo)
        star.name = "ashstar"
        scene.rootNode.addChildNode(star)
        let path = sampledSpline(from: SCNVector3(0, 0, 0), to: SCNVector3(0.4, 1.8, -0.3))
        var actions: [SCNAction] = []
        for i in 1..<path.count { actions.append(SCNAction.move(to: path[i], duration: 0.12)) }
        actions.append(SCNAction.fadeOut(duration: 0.4))
        actions.append(SCNAction.removeFromParentNode())
        star.runAction(SCNAction.group([
            SCNAction.repeatForever(SCNAction.rotateBy(x: 0.5, y: 1.4, z: 0.3, duration: 3.2)),
            SCNAction.sequence(actions)
        ]))
        emitMist(fromLocal: true)
        pulseShells(0.6)
    }

    public func spawnShard(color: UIColor) {
        rebuildSplines()
        let geo = SCNBox(width: 0.08, height: 0.11, length: 0.04, chamferRadius: 0.012)
        geo.materials = [ThreeJSGeometry.basicMat(color, opacity: 0.55)]
        let node = SCNNode(geometry: geo)
        node.name = "shard"
        scene.rootNode.addChildNode(node)
        let dest: SCNVector3
        if let last = sessionGroupNodes.values.first { dest = last.position }
        else { dest = SCNVector3(1.6, 0.9, -1.1) }
        let path = sampledSpline(from: SCNVector3(0, 0, 0), to: dest)
        var actions: [SCNAction] = []
        for i in 1..<path.count { actions.append(SCNAction.move(to: path[i], duration: 0.1)) }
        actions.append(SCNAction.fadeOut(duration: 0.35))
        actions.append(SCNAction.removeFromParentNode())
        node.runAction(SCNAction.group([
            SCNAction.repeatForever(SCNAction.rotateBy(x: 1, y: 0.4, z: 0.8, duration: 1.6)),
            SCNAction.sequence(actions)
        ]))
        pulseShells(0.45)
    }

    public func rebuildSplines() {
        splineGroup?.removeFromParentNode()
        let g = SCNNode(); g.name = "splines"
        splineSamples.removeAll()
        var targets: [SCNVector3] = sessionGroupNodes.values.map { $0.position }
        if targets.isEmpty {
            targets = [SCNVector3(2.2, 0.8, -1.2), SCNVector3(-1.8, 1.1, 1.4)]
        }
        let origin = SCNVector3(0, 0, 0)
        for t in targets {
            let samples = sampledSpline(from: origin, to: t)
            splineSamples.append(samples)
            if let line = ThreeJSGeometry.lineSegments(polylineFloats(samples), color: UIColor(red: 0, green: 0.9, blue: 1, alpha: 0.35), opacity: 0.35) {
                g.addChildNode(line)
            }
        }
        scene.rootNode.addChildNode(g)
        splineGroup = g
    }

    public func emitMist(fromLocal: Bool) {
        rebuildSplines()
        let curves = splineSamples.isEmpty ? [sampledSpline(from: SCNVector3(0, 0, 0), to: SCNVector3(1.5, 1.0, -1.0))] : splineSamples
        for samples in curves.prefix(6) {
            let s = SCNSphere(radius: 0.03); s.segmentCount = 6
            s.materials = [ThreeJSGeometry.basicMat(UIColor(red: 0, green: 0.9, blue: 1, alpha: 1), opacity: 0.9)]
            let n = SCNNode(geometry: s)
            n.position = samples.first ?? SCNVector3(0, 0, 0)
            scene.rootNode.addChildNode(n)
            var acts: [SCNAction] = []
            let seq = fromLocal ? samples : samples.reversed()
            for p in seq.dropFirst() { acts.append(SCNAction.move(to: p, duration: 0.08)) }
            acts.append(SCNAction.fadeOut(duration: 0.3))
            acts.append(SCNAction.removeFromParentNode())
            n.runAction(SCNAction.sequence(acts))
        }
        pulseShells(0.35)
    }

    private func sampledSpline(from a: SCNVector3, to b: SCNVector3, steps: Int = 12) -> [SCNVector3] {
        let mid = SCNVector3(
            (a.x + b.x) * 0.5 + Float.random(in: -0.4...0.4),
            (a.y + b.y) * 0.5 + 0.8 + Float.random(in: 0...0.4),
            (a.z + b.z) * 0.5 + Float.random(in: -0.4...0.4)
        )
        var out: [SCNVector3] = []
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let omt = 1 - t
            out.append(SCNVector3(
                omt * omt * a.x + 2 * omt * t * mid.x + t * t * b.x,
                omt * omt * a.y + 2 * omt * t * mid.y + t * t * b.y,
                omt * omt * a.z + 2 * omt * t * mid.z + t * t * b.z
            ))
        }
        return out
    }

    private func polylineFloats(_ pts: [SCNVector3]) -> [Float] {
        var floats: [Float] = []
        for i in 0..<(pts.count - 1) {
            floats += [pts[i].x, pts[i].y, pts[i].z, pts[i + 1].x, pts[i + 1].y, pts[i + 1].z]
        }
        return floats
    }

    public func teardown() { presenceTimer?.invalidate(); Self.shared = nil }

    private func pollPresence() async {
        await MISTModule.shared.refresh()
        let signals = MISTModule.shared.activeSignals
        for sig in signals {
            if sessionGroupNodes[sig.uid] == nil {
                addRemoteNode(uid: sig.uid, emotion: sig.isAsh ? "inspiring" : "neutral")
            }
        }
        rebuildSplines()
    }

    /// JS: _nodeBasePos / _uidHash
    private func nodeBasePosition(uid: String) -> (x: Float, y: Float, z: Float) {
        let h = uidHash(uid)
        let h2 = uidHash(uid + "y")
        let h3 = uidHash(uid + "z")
        let theta = h * .pi * 2
        let phi = acos(2 * h2 - 1)
        let r = 3.2 + h3 * 1.6
        return (r * sin(phi) * cos(theta), r * sin(phi) * sin(theta), r * cos(phi))
    }

    private func uidHash(_ uid: String) -> Float {
        // JS: h = 0; for i: h = (h*31 + charCode) & 0x7fffffff; return h / 0x7fffffff
        var h: Int = 0
        for ch in uid.utf8 {
            h = (h &* 31 &+ Int(ch)) & 0x7fffffff
        }
        return Float(h) / Float(0x7fffffff)
    }

    private func uidShellColors(uid: String) -> [UIColor] {
        let h = uidHash(uid)
        let hue = h
        return [
            UIColor(hue: CGFloat(hue), saturation: 0.9, brightness: 0.65, alpha: 1),
            UIColor(hue: CGFloat((hue + 0.333).truncatingRemainder(dividingBy: 1)), saturation: 0.85, brightness: 0.6, alpha: 1),
            UIColor(hue: CGFloat((hue + 0.667).truncatingRemainder(dividingBy: 1)), saturation: 0.8, brightness: 0.55, alpha: 1),
        ]
    }
}

// MARK: — Per-frame animator (JS animate())  not MainActor — called from SCN renderer
final class BRPNAnimator {
    struct ToolInst {
        var pivot: SCNNode?
        var mesh: SCNNode?
        var orbitRadius: Float = 1
        var orbitSpeed: Float = 0.008
        var orbitOffset: Float = 0
        var shellLayer: Int = 0
        var active = false
        var spawnT: Int = 0
        var tiltX: Float = 0
        var tiltZ: Float = 0
    }
    struct MantisInst {
        var node: SCNNode
        var spawn: Int
        var type: String
        var orbitR: Float
        var orbitSpd: Float
        var orbitOff: Float
        var alt: Float
    }

    var shells: [SCNNode] = []
    var core: SCNNode?
    var mazeOrbGroup: SCNNode?
    var particles: [SCNNode] = []
    var particleData: [(r: Float, spd: Float, off: Float, yOff: Float)] = []
    var pathMeshNodes: [SCNNode] = []
    var tools: [ToolInst] = []
    var camera: SCNNode?
    var shellColors: [UIColor] = []
    var mantis: [MantisInst] = []

    var rotX: Float = 0
    var rotY: Float = 0
    var orbFrame = 0
    var shellPulse: Float = 0
    var orbThinking = false
    var mazeOrbState = MazeOrbState()
    var looking = false
    var camMode = "wide"
    var camIdle = 0
    var postSolveIdle = 0
    var postRegenIdle = 0
    let home = SCNVector3(0, 1.5, 5)
    let close = SCNVector3(0, 0.32, 1.38)
    var onRegen: (() -> Void)?
    var onPublishedSolve: ((Bool, Bool) -> Void)?
    private var toolSeqTimer = 0
    private var toolSeqIndex = 0
    private let shellRadiiRef: [Float] = [1.9, 1.4, 0.9]

    func configure(shells: [SCNNode], core: SCNNode?, mazeOrbGroup: SCNNode?, particles: [SCNNode],
                   particleData: [(r: Float, spd: Float, off: Float, yOff: Float)], camera: SCNNode?,
                   shellColors: [UIColor]) {
        self.shells = shells
        self.core = core
        self.mazeOrbGroup = mazeOrbGroup
        self.particles = particles
        self.particleData = particleData
        self.camera = camera
        self.shellColors = shellColors
        orbFrame = 0
        rotX = 0
        rotY = 0
        shellPulse = 0
    }

    func tick() {
        orbFrame = (orbFrame + 1) % 1_000_000
        let f = Float(orbFrame)
        let isThinking = orbThinking
        let thinkBoost: Float = isThinking ? 1.0 : 0.0

        // Shells — JS: rot x=rotX+f*0.0015*(i+1) y=rotY+f*0.002*(i+1) scale 1+sin(f*0.03+i)*0.03
        for (i, m) in shells.enumerated() {
            m.eulerAngles.x = rotX + f * 0.0015 * Float(i + 1)
            m.eulerAngles.y = rotY + f * 0.002 * Float(i + 1)
            let baseScale = 1 + sin(f * 0.03 + Float(i)) * 0.03
            let pulseExtra = shellPulse * (0.04 + Float(i) * 0.015) * sin(f * 0.06 + Float(i) * 1.2)
            let thinkExtra: Float = isThinking ? sin(f * 0.05 + Float(i) * 2.1) * 0.03 : 0
            let s = baseScale + pulseExtra + thinkExtra
            m.scale = SCNVector3(s, s, s)
            let baseOp = 0.15 + Float(i) * 0.06
            let pulseOp = shellPulse * 0.04 * sin(f * 0.04 + Float(i))
            let thinkOp: Float = isThinking ? 0.06 * sin(f * 0.08 + Float(i)) : 0
            let op = max(0.05, min(0.7, baseOp + pulseOp + thinkOp))
            if i < shellColors.count {
                let col = shellColors[i].withAlphaComponent(CGFloat(op))
                m.geometry?.firstMaterial?.emission.contents = col
                m.geometry?.firstMaterial?.diffuse.contents = col
            }
        }

        // Core + maze group — JS: mazeOrbGroup.rotation.x=rotX+f*0.003 y=rotY+f*0.004
        let mazePulse = 1 + shellPulse * 0.12 * sin(f * 0.08) + (isThinking ? 0.06 * sin(f * 0.12) : 0)
        let mz = mazePulse * (1 + thinkBoost * 0.04 * sin(f * 0.07))
        mazeOrbGroup?.eulerAngles.x = rotX + f * 0.003
        mazeOrbGroup?.eulerAngles.y = rotY + f * 0.004
        mazeOrbGroup?.scale = SCNVector3(mz, mz, mz)
        core?.eulerAngles.x = rotX + f * 0.002
        core?.eulerAngles.y = rotY + f * 0.003
        let coreOp = 0.1 + shellPulse * 0.06 * sin(f * 0.04)
        core?.geometry?.firstMaterial?.emission.contents = ThreeJSGeometry.hex(0x00ffcc).withAlphaComponent(CGFloat(coreOp))

        if let wall = mazeOrbGroup?.childNodes.first {
            let wop = 0.35 + 0.2 * sin(f * 0.04) + (isThinking ? 0.15 * sin(f * 0.09) : 0) + shellPulse * 0.08
            wall.geometry?.firstMaterial?.emission.contents = ThreeJSGeometry.hex(0x00ffcc).withAlphaComponent(CGFloat(wop))
        }

        mazeOrbState.frame += 1
        if !looking && (isThinking || shellPulse > 0.3) {
            if !mazeOrbState.solveActive && !mazeOrbState.solution.isEmpty {
                mazeOrbState.solveActive = true
                mazeOrbState.solveStep = 0
                for m in pathMeshNodes {
                    m.geometry?.firstMaterial?.emission.contents = ThreeJSGeometry.hex(0x00ffff).withAlphaComponent(0)
                }
                onPublishedSolve?(true, true)
            }
        }
        if mazeOrbState.solveActive {
            let revealEvery = isThinking ? 2 : 4
            if mazeOrbState.frame % revealEvery == 0 && mazeOrbState.solveStep < pathMeshNodes.count {
                let pm = pathMeshNodes[mazeOrbState.solveStep]
                let col = ThreeJSGeometry.hex(isThinking ? 0x00ffff : 0x00ffcc)
                pm.geometry?.firstMaterial?.emission.contents = col.withAlphaComponent(0.9)
                pm.geometry?.firstMaterial?.diffuse.contents = col.withAlphaComponent(0.9)
                mazeOrbState.solveStep += 1
            }
            if mazeOrbState.solveStep >= pathMeshNodes.count {
                mazeOrbState.solveActive = false
                onPublishedSolve?(false, true)
                if looking {
                    mazeOrbState.regenTimer = 0
                    postSolveIdle = 1
                    postRegenIdle = 0
                    camIdle = 0
                } else {
                    mazeOrbState.regenTimer = isThinking ? 90 : 240
                }
            }
        }
        if !looking && mazeOrbState.regenTimer > 0 {
            mazeOrbState.regenTimer -= 1
            if mazeOrbState.regenTimer == 0 {
                onRegen?()
                if isThinking { mazeOrbState.solveActive = true }
            }
        }
        if !isThinking && !mazeOrbState.solveActive {
            for pm in pathMeshNodes {
                if let mat = pm.geometry?.firstMaterial,
                   let c = mat.emission.contents as? UIColor {
                    var a: CGFloat = 0, r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                    c.getRed(&r, green: &g, blue: &b, alpha: &a)
                    if a > 0 {
                        let na = max(0, a - 0.008)
                        mat.emission.contents = c.withAlphaComponent(na)
                        mat.diffuse.contents = c.withAlphaComponent(na)
                    }
                }
            }
        }

        // Particles — JS: t=f*0.007*spd+off; x=cos(t)*r; z=sin(t)*r; y=yOff+sin(t*2)*0.2
        for (i, p) in particles.enumerated() where i < particleData.count {
            let d = particleData[i]
            let spd = d.spd * (isThinking ? 1.6 : 1.0)
            let t = f * 0.007 * spd + d.off
            let r = d.r * (1 + shellPulse * 0.1 * sin(f * 0.05))
            p.position = SCNVector3(cos(t) * r, d.yOff + sin(t * 2) * 0.2, sin(t) * r)
        }

        // Tool orbits
        if isThinking {
            toolSeqTimer += 1
            if toolSeqTimer > 22 {
                toolSeqTimer = 0
                toolSeqIndex = (toolSeqIndex + 1) % max(1, tools.count)
                if toolSeqIndex < tools.count {
                    tools[toolSeqIndex].active = true
                    tools[toolSeqIndex].spawnT = orbFrame
                }
            }
        }
        for (ti, ts) in tools.enumerated() {
            guard let pivot = ts.pivot, let mesh = ts.mesh else { continue }
            let t = f * ts.orbitSpeed + ts.orbitOffset
            let shellR = shellRadiiRef[ts.shellLayer]
            let buoyancyT = f * 0.012 + Float(ti) * 1.1
            let layerShift = sin(buoyancyT) * 0.35
            let effectiveR = shellR * (0.72 + 0.28 * abs(sin(buoyancyT))) + layerShift * 0.4
            pivot.position = SCNVector3(cos(t) * effectiveR, sin(t * 0.7) * 0.55, sin(t) * effectiveR)
            mesh.eulerAngles.x = ts.tiltX + f * 0.01
            mesh.eulerAngles.z = ts.tiltZ + f * 0.008
            var op: Float = 0
            if ts.active || isThinking {
                op = min(0.85, 0.35 + 0.25 * abs(sin(f * 0.05 + Float(ti))))
            } else {
                op = 0.08
            }
            mesh.geometry?.firstMaterial?.emission.contents = (mesh.geometry?.firstMaterial?.emission.contents as? UIColor)?.withAlphaComponent(CGFloat(op))
                ?? UIColor.cyan.withAlphaComponent(CGFloat(op))
            let pulseFactor = 1 + 0.18 * sin(f * 0.08 + Float(ti) * 1.3 + shellPulse)
            let sc = pulseFactor * (1 + shellPulse * 0.08) * 0.55
            mesh.scale = SCNVector3(sc, sc, sc)
        }

        // Mantis drift — JS _brpnTickMantisNodes
        var keep: [MantisInst] = []
        for m in mantis {
            let age = orbFrame - m.spawn
            let life = m.type == "satellite" ? 108000 : 1800
            let tt = Float(age) / Float(life)
            if tt >= 1 { m.node.removeFromParentNode(); continue }
            let op: Float = tt < 0.8 ? 0.55 : 0.55 * (1 - (tt - 0.8) / 0.2)
            m.node.geometry?.firstMaterial?.emission.contents = (m.node.geometry?.firstMaterial?.emission.contents as? UIColor)?.withAlphaComponent(CGFloat(op))
            m.node.position.x = m.orbitR * cos(f * m.orbitSpd + m.orbitOff)
            m.node.position.z = m.orbitR * sin(f * m.orbitSpd + m.orbitOff)
            m.node.position.y = m.alt + sin(f * m.orbitSpd * 0.4 + m.orbitOff) * 0.08
            m.node.eulerAngles.x += 0.008
            m.node.eulerAngles.y += 0.012
            keep.append(m)
        }
        mantis = keep

        shellPulse *= 0.994

        // Camera dolly — JS _orbCam in/out/hold
        if let cam = camera {
            if camMode == "in" {
                cam.position.x += (close.x - cam.position.x) * 0.055
                cam.position.y += (close.y - cam.position.y) * 0.055
                cam.position.z += (close.z - cam.position.z) * 0.055
                cam.look(at: SCNVector3(0, 0, 0))
                if abs(cam.position.z - close.z) < 0.05 { camMode = "hold" }
            } else if camMode == "out" {
                cam.position.x += (home.x - cam.position.x) * 0.055
                cam.position.y += (home.y - cam.position.y) * 0.055
                cam.position.z += (home.z - cam.position.z) * 0.055
                cam.look(at: SCNVector3(0, 0, 0))
                if abs(cam.position.z - home.z) < 0.08 { camMode = "wide"; looking = false }
            } else if looking {
                cam.look(at: SCNVector3(0, 0, 0))
                camIdle += 1
                if postSolveIdle > 0 {
                    postSolveIdle += 1
                    if postSolveIdle > 420 {
                        postSolveIdle = 0
                        onRegen?()
                        postRegenIdle = 1
                        camIdle = 0
                    }
                } else if postRegenIdle > 0 {
                    postRegenIdle += 1
                    if postRegenIdle > 540 {
                        postRegenIdle = 0
                        camMode = "out"
                    }
                } else if camIdle > 720 && !mazeOrbState.solveActive {
                    camMode = "out"
                }
            }
        }
    }
}

// MARK: — JS tool shape extruded profiles (makeKnifeGeometry etc.)
enum BRPNToolShapes {
    static func extrudeProfile(_ profile2d: [[Float]], depth: Float) -> [Float] {
        let d = depth * 0.5
        var pts: [Float] = []
        for seg in profile2d {
            guard seg.count == 4 else { continue }
            let x0 = seg[0], y0 = seg[1], x1 = seg[2], y1 = seg[3]
            pts += [x0, y0, d, x1, y1, d]
            pts += [x0, y0, -d, x1, y1, -d]
        }
        var done = Set<String>()
        for seg in profile2d {
            guard seg.count == 4 else { continue }
            let x0 = seg[0], y0 = seg[1], x1 = seg[2], y1 = seg[3]
            let k0 = String(format: "%.3f,%.3f", x0, y0)
            let k1 = String(format: "%.3f,%.3f", x1, y1)
            if !done.contains(k0) { pts += [x0, y0, d, x0, y0, -d]; done.insert(k0) }
            if !done.contains(k1) { pts += [x1, y1, d, x1, y1, -d]; done.insert(k1) }
        }
        return pts
    }

    static func verts(_ type: String) -> [Float] {
        switch type {
        case "knife":
            return extrudeProfile([
                [-0.18, 0, 0.28, 0.05], [0.28, 0.05, 0.32, 0], [0.32, 0, 0.28, -0.03],
                [0.28, -0.03, -0.18, 0], [-0.18, 0.05, -0.36, 0.05], [-0.36, 0.05, -0.36, -0.05],
                [-0.36, -0.05, -0.18, -0.05], [-0.18, -0.05, -0.18, 0.05], [-0.18, -0.08, -0.18, 0.08]
            ], 0.06)
        case "stick":
            var profile: [[Float]] = [
                [-0.04, -0.3, 0.04, -0.3], [-0.04, -0.3, -0.04, 0.28], [0.04, -0.3, 0.04, 0.28]
            ]
            for i in 0..<8 {
                let a0 = Float(i) / 8 * .pi, a1 = Float(i + 1) / 8 * .pi
                profile.append([cos(a0) * 0.06, 0.28 + sin(a0) * 0.06, cos(a1) * 0.06, 0.28 + sin(a1) * 0.06])
            }
            return extrudeProfile(profile, 0.05)
        case "hammer":
            var pts = extrudeProfile([
                [-0.02, -0.32, 0.02, -0.32], [-0.02, -0.32, -0.02, 0.14],
                [0.02, -0.32, 0.02, 0.14], [-0.02, 0.14, 0.02, 0.14]
            ], 0.04)
            pts += extrudeProfile([
                [-0.14, 0.14, 0.14, 0.14], [0.14, 0.14, 0.14, 0.28],
                [0.14, 0.28, -0.14, 0.28], [-0.14, 0.28, -0.14, 0.14]
            ], 0.12)
            return pts
        case "envelope":
            return extrudeProfile([
                [-0.24, -0.15, 0.24, -0.15], [0.24, -0.15, 0.24, 0.15], [0.24, 0.15, -0.24, 0.15],
                [-0.24, 0.15, -0.24, -0.15], [-0.24, 0.15, 0, 0], [0.24, 0.15, 0, 0],
                [-0.24, -0.15, 0, -0.02], [0.24, -0.15, 0, -0.02]
            ], 0.06)
        default: // scissors
            var profile: [[Float]] = [
                [-0.04, 0.28, 0.22, -0.18], [-0.08, 0.26, 0.19, -0.2],
                [0.04, 0.28, -0.22, -0.18], [0.08, 0.26, -0.19, -0.2],
                [-0.015, 0, 0.015, 0], [0, -0.015, 0, 0.015]
            ]
            for i in 0..<10 {
                let a0 = Float(i) / 10 * .pi * 2, a1 = Float(i + 1) / 10 * .pi * 2
                profile.append([0.12 + cos(a0) * 0.07, -0.22 + sin(a0) * 0.07, 0.12 + cos(a1) * 0.07, -0.22 + sin(a1) * 0.07])
                profile.append([-0.12 + cos(a0) * 0.07, -0.22 + sin(a0) * 0.07, -0.12 + cos(a1) * 0.07, -0.22 + sin(a1) * 0.07])
            }
            return extrudeProfile(profile, 0.04)
        }
    }
}
