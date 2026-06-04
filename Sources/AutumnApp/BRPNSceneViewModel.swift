import LEATRCore
import SwiftUI
import SceneKit
import Combine

// MARK: — BRPNSceneViewModel (Full web-app faithful port)
// Mirrors initBRPN() from index.html exactly:
// - 3 IcosahedronGeometry shells (radii 1.9/1.4/0.9, colors cyan/blue/pink)
// - Maze orb at core: orbGenMaze (recursive backtracker 3D) + orbSolveMaze (BFS)
// - Animated path solve reveal (Autumn-only: she can trigger solve for users)
// - Orbital tool-shape particles (knife/stick/hammer/envelope/scissors)
// - Per-user session nodes with mini icosahedron shells + plasma splines
// - CatmullRom plasma splines between nodes
// - Rotate-on-drag / auto-rotate

@MainActor
public final class BRPNSceneViewModel: ObservableObject {

    // MARK: — Published
    @Published public var shellStates: [BRPNShell: String] = [
        .geological: "FOUNDATION",
        .maritime:   "REFLEX",
        .aerospace:  "PERFORMANCE"
    ]
    @Published public var activeNodes: Int = 1
    @Published public var sessionId = String(UUID().uuidString.prefix(8))
    @Published public var quantumSocket: Double = 6.9120
    @Published public var mazeCanSolve = false
    @Published public var isSolving = false

    // MARK: — Scene
    public let scene = SCNScene()
    public var shells: [SCNNode] = []
    private var coreNode: SCNNode!
    private var mazeOrbGroup: SCNNode!
    private var toolShapeNodes: [SCNNode] = []
    private var sessionGroupNodes: [String: SCNNode] = [:]
    private var splineNodes: [SCNNode] = []

    // Maze state (matches mazeOrbState in index.html)
    private var mazeGrid: [[[MazeCell]]] = []
    private var mazeSolution: [(x:Int,y:Int,z:Int)] = []
    private var pathMeshNodes: [SCNNode] = []
    private var solveStep = 0
    private var solveTimer: Timer?
    private let mazeW = 4, mazeH = 4, mazeD = 3
    private let cellSize: Float = 0.065

    // Shell radii + colors (exact from index.html)
    private let shellRadii: [Float] = [1.9, 1.4, 0.9]
    private let shellColors: [UIColor] = [
        UIColor(red:0.0, green:1.0, blue:0.8, alpha:1),   // 0x00ffcc
        UIColor(red:0.0, green:0.53, blue:1.0, alpha:1),  // 0x0088ff
        UIColor(red:1.0, green:0.27, blue:0.4, alpha:1)   // 0xff4466
    ]

    // Particles
    private var particleNodes: [SCNNode] = []
    private var particleData: [(r:Float, spd:Float, off:Float, yOff:Float)] = []

    // Rotation
    var rotX: Float = 0.35
    var rotY: Float = 0.4

    // Presence timer
    private var presenceTimer: Timer?
    private var frameCount: Int = 0

    // MARK: — Setup (mirrors initBRPN exactly)
    public func setupScene() {
        scene.background.contents = UIColor.clear

        // Ambient light
        let amb = SCNNode(); amb.light = { let l = SCNLight(); l.type = .ambient; l.intensity = 200; return l }()
        scene.rootNode.addChildNode(amb)

        // ── 3 buoyancy shells (IcosahedronGeometry equiv = SCNSphere subdiv 2) ──
        for (i, radius) in shellRadii.enumerated() {
            let geo = SCNSphere(radius: CGFloat(radius))
            geo.segmentCount = 6  // low-poly icosahedron approximation
            geo.firstMaterial = {
                let m = SCNMaterial()
                m.diffuse.contents = shellColors[i].withAlphaComponent(0)
                m.emission.contents = shellColors[i]
                m.fillMode = .lines
                m.isDoubleSided = true
                m.transparency = CGFloat(0.18 + Float(i) * 0.08)
                return m
            }()
            let node = SCNNode(geometry: geo)
            node.name = "shell_\(i)"
            scene.rootNode.addChildNode(node)
            shells.append(node)

            // Slow auto-rotate per shell
            let rotAction = SCNAction.repeatForever(
                SCNAction.rotateBy(x: CGFloat(i == 0 ? 0.3 : i == 1 ? -0.2 : 0.4),
                                   y: CGFloat(i == 0 ? 1.0 : i == 1 ? -0.8 : 0.6),
                                   z: 0, duration: Double(25 + i * 8)))
            node.runAction(rotAction)
        }

        // ── Core sphere (hidden behind maze) ──
        let cg = SCNSphere(radius: 0.18)
        cg.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor.clear
            m.emission.contents = UIColor(red:0.0, green:1.0, blue:0.8, alpha:1)
            m.fillMode = .lines
            m.transparency = 0.82
            return m
        }()
        coreNode = SCNNode(geometry: cg)
        scene.rootNode.addChildNode(coreNode)

        // ── LEMAC 3D Maze orb at core ──
        mazeOrbGroup = SCNNode(); mazeOrbGroup.name = "mazeOrb"
        scene.rootNode.addChildNode(mazeOrbGroup)
        buildOrbMazeGeometry()

        // ── Orbital particles (30, mirrors index.html) ──
        for i in 0..<30 {
            let geo = SCNSphere(radius: 0.025)
            geo.firstMaterial = {
                let m = SCNMaterial()
                m.emission.contents = shellColors[i % 3].withAlphaComponent(0.7)
                m.lightingModel = .constant
                return m
            }()
            let node = SCNNode(geometry: geo)
            node.name = "particle_\(i)"
            let r = Float.random(in: 0.55...2.0)
            let spd = Float.random(in: 0.3...1.5)
            let off = Float.random(in: 0...(.pi * 2))
            let yOff = Float.random(in: -0.8...0.8)
            particleData.append((r: r, spd: spd, off: off, yOff: yOff))
            scene.rootNode.addChildNode(node)
            particleNodes.append(node)
        }

        // ── Tool shapes (knife/stick/hammer/envelope/scissors) ──
        buildToolShapes()

        // Start presence polling every 30s
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.pollPresence() }
        }
    }

    // MARK: — Frame update (called by SceneKit render delegate)
    public func updateFrame() {
        frameCount += 1
        let t = Float(frameCount) * 0.016  // ~60fps

        // Animate orbital particles
        for (i, node) in particleNodes.enumerated() {
            guard i < particleData.count else { continue }
            let d = particleData[i]
            let angle = t * d.spd + d.off
            node.position = SCNVector3(
                d.r * cos(angle),
                d.yOff + sin(t * 0.3 + Float(i)) * 0.15,
                d.r * sin(angle)
            )
        }

        // Slowly rotate maze orb
        mazeOrbGroup?.eulerAngles.y = t * 0.005
        mazeOrbGroup?.eulerAngles.x = sin(t * 0.003) * 0.1

        // Animate core pulse
        let pulse = 1.0 + sin(t * 2.0) * 0.08
        coreNode?.scale = SCNVector3(pulse, pulse, pulse)

        // Core glow color cycles gently
        let hue = (t * 0.02).truncatingRemainder(dividingBy: 1.0)
        (coreNode?.geometry?.firstMaterial?.emission.contents as? UIColor).map { _ in
            coreNode?.geometry?.firstMaterial?.emission.contents =
                UIColor(hue: CGFloat(hue * 0.15 + 0.45), saturation: 1, brightness: 1, alpha: 1)
        }

        // Advance maze solve animation
        if isSolving { stepMazeSolveAnim() }
    }

    // MARK: — LEMAC Maze Generation (exact port of orbGenMaze)
    private func buildOrbMazeGeometry() {
        // Clear previous
        mazeOrbGroup.childNodes.forEach { n in
            n.geometry?.materials.forEach { $0.diffuse.contents = UIColor.clear }
            n.removeFromParentNode()
        }
        pathMeshNodes.removeAll()
        solveStep = 0
        isSolving = false

        // Generate maze
        let grid = orbGenMaze(w: mazeW, h: mazeH, d: mazeD)
        mazeGrid = grid
        mazeSolution = orbSolveMaze(grid: grid, w: mazeW, h: mazeH, d: mazeD)
        mazeCanSolve = !mazeSolution.isEmpty

        let u: Float = cellSize
        let ox = Float(mazeW) * u / 2
        let oy = Float(mazeH) * u / 2
        let oz = Float(mazeD) * u / 2
        let hs = u * 0.5

        // Build wall LineSegments (mirrors index.html wall drawing)
        var wallVerts: [Float] = []
        for z in 0..<mazeD {
            for y in 0..<mazeH {
                for x in 0..<mazeW {
                    let c = grid[z][y][x]
                    let cx = Float(x)*u - ox + hs
                    let cy = Float(y)*u - oy + hs
                    let cz = Float(z)*u - oz + hs

                    func quad(_ pts: [(Float,Float,Float)]) {
                        for i in 0..<pts.count {
                            let a = pts[i]; let b = pts[(i+1) % pts.count]
                            wallVerts += [a.0,a.1,a.2, b.0,b.1,b.2]
                        }
                    }
                    if c.left  { quad([(cx-hs,cy-hs,cz-hs),(cx-hs,cy+hs,cz-hs),(cx-hs,cy+hs,cz+hs),(cx-hs,cy-hs,cz+hs)]) }
                    if c.bottom{ quad([(cx-hs,cy-hs,cz-hs),(cx+hs,cy-hs,cz-hs),(cx+hs,cy-hs,cz+hs),(cx-hs,cy-hs,cz+hs)]) }
                    if c.back  { quad([(cx-hs,cy-hs,cz-hs),(cx+hs,cy-hs,cz-hs),(cx+hs,cy+hs,cz-hs),(cx-hs,cy+hs,cz-hs)]) }
                }
            }
        }

        // Create SCNGeometry for walls
        let positions = wallVerts.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }
        let vertexSrc = SCNGeometrySource(
            data: positions,
            semantic: .vertex,
            vectorCount: wallVerts.count / 3,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: 4,
            dataOffset: 0,
            dataStride: 12
        )
        var indices: [Int32] = Array(0..<Int32(wallVerts.count / 3))
        let indexData = indices.withUnsafeMutableBufferPointer { ptr in
            Data(buffer: ptr)
        }
        let elem = SCNGeometryElement(data: indexData, primitiveType: .line,
                                      primitiveCount: indices.count / 2, bytesPerIndex: 4)
        let wallGeo = SCNGeometry(sources: [vertexSrc], elements: [elem])
        wallGeo.firstMaterial = {
            let m = SCNMaterial()
            m.emission.contents = UIColor(red:0.0, green:1.0, blue:0.8, alpha:0.55)
            m.lightingModel = .constant
            return m
        }()
        let wallNode = SCNNode(geometry: wallGeo)
        wallNode.name = "mazeWalls"
        mazeOrbGroup.addChildNode(wallNode)

        // Path node meshes (hidden, revealed during solve)
        let pathGeo = SCNSphere(radius: CGFloat(u * 0.22))
        for pt in mazeSolution {
            let mat = SCNMaterial()
            mat.emission.contents = UIColor(red:0, green:1, blue:1, alpha:0)
            mat.lightingModel = .constant
            pathGeo.materials = [mat]
            let mesh = SCNNode(geometry: pathGeo.copy() as! SCNGeometry)
            mesh.position = SCNVector3(
                Float(pt.x)*u - ox + hs,
                Float(pt.y)*u - oy + hs,
                Float(pt.z)*u - oz + hs
            )
            mesh.name = "pathNode"
            mazeOrbGroup.addChildNode(mesh)
            pathMeshNodes.append(mesh)
        }

        // Start/end markers
        if let first = mazeSolution.first {
            let sg = SCNSphere(radius: CGFloat(u * 0.35))
            sg.firstMaterial = { let m = SCNMaterial(); m.emission.contents = UIColor(red:0,green:1,blue:0.8,alpha:1); m.lightingModel = .constant; return m }()
            let s = SCNNode(geometry: sg)
            s.position = SCNVector3(Float(first.x)*u - ox + hs, Float(first.y)*u - oy + hs, Float(first.z)*u - oz + hs)
            mazeOrbGroup.addChildNode(s)
        }
        if let last = mazeSolution.last {
            let eg = SCNSphere(radius: CGFloat(u * 0.35))
            eg.firstMaterial = { let m = SCNMaterial(); m.emission.contents = UIColor(red:1,green:0.27,blue:0.4,alpha:1); m.lightingModel = .constant; return m }()
            let e = SCNNode(geometry: eg)
            e.position = SCNVector3(Float(last.x)*u - ox + hs, Float(last.y)*u - oy + hs, Float(last.z)*u - oz + hs)
            mazeOrbGroup.addChildNode(e)
        }
    }

    // MARK: — Autumn-only: trigger maze solve animation
    public func autumnSolveMaze() {
        guard mazeCanSolve, !isSolving else { return }
        solveStep = 0
        isSolving = true
        // Reset path nodes to invisible
        pathMeshNodes.forEach {
            $0.geometry?.firstMaterial?.emission.contents =
                UIColor(red:0, green:1, blue:1, alpha:0)
        }
    }

    private func stepMazeSolveAnim() {
        guard solveStep < pathMeshNodes.count else {
            isSolving = false
            // After solve complete, regenerate after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.buildOrbMazeGeometry()
            }
            return
        }
        // Reveal 2 nodes per frame
        let toReveal = min(2, pathMeshNodes.count - solveStep)
        for i in 0..<toReveal {
            let node = pathMeshNodes[solveStep + i]
            let opacity = 0.7 + Float.random(in: 0...0.3)
            node.geometry?.firstMaterial?.emission.contents =
                UIColor(red:0, green:1, blue:1, alpha: CGFloat(opacity))
            // Pulse scale
            node.runAction(SCNAction.sequence([
                SCNAction.scale(to: 1.4, duration: 0.1),
                SCNAction.scale(to: 1.0, duration: 0.15)
            ]))
        }
        solveStep += toReveal
    }

    // MARK: — Add remote user node (mirrors _makeSessionGroup)
    public func addRemoteNode(uid: String, emotion: String = "neutral") {
        let pos = nodeBasePosition(uid: uid)
        let group = SCNNode(); group.name = "session_\(uid)"

        // Mini 3-shell icosahedron (matches web app _makeSessionGroup)
        let colors = uidShellColors(uid: uid)
        let miniRadii: [Float] = [1.9 * 0.28, 1.4 * 0.28, 0.9 * 0.28]
        for (i, r) in miniRadii.enumerated() {
            let geo = SCNSphere(radius: CGFloat(r))
            geo.segmentCount = 4
            geo.firstMaterial = {
                let m = SCNMaterial()
                m.emission.contents = colors[i].withAlphaComponent(0.22 + Float(i) * 0.06)
                m.fillMode = .lines
                m.lightingModel = .constant
                return m
            }()
            group.addChildNode(SCNNode(geometry: geo))
        }

        // Core dot
        let cg = SCNSphere(radius: 0.032)
        cg.firstMaterial = {
            let m = SCNMaterial()
            m.emission.contents = colors[0].withAlphaComponent(0.55)
            m.lightingModel = .constant
            return m
        }()
        group.addChildNode(SCNNode(geometry: cg))

        group.position = SCNVector3(pos.x, pos.y, pos.z)
        scene.rootNode.addChildNode(group)
        sessionGroupNodes[uid] = group

        // Add plasma spline to local node
        addPlasmaSpline(from: SCNVector3(0,0,0), to: group.position, color: colors[0])

        activeNodes += 1
    }

    private func addPlasmaSpline(from: SCNVector3, to: SCNVector3, color: UIColor) {
        // CatmullRom-style curved line with 20 segments
        let segments = 20
        var verts: [Float] = []
        for i in 0...segments {
            let t = Float(i) / Float(segments)
            // Simple bezier with midpoint offset
            let mx = (from.x + to.x) / 2 + sin(t * .pi) * 0.5
            let my = (from.y + to.y) / 2 + cos(t * .pi * 2) * 0.3
            let mz = (from.z + to.z) / 2
            let bx = (1-t)*(1-t)*from.x + 2*(1-t)*t*mx + t*t*to.x
            let by = (1-t)*(1-t)*from.y + 2*(1-t)*t*my + t*t*to.y
            let bz = (1-t)*(1-t)*from.z + 2*(1-t)*t*mz + t*t*to.z
            verts += [bx, by, bz]
        }
        let data = verts.withUnsafeBufferPointer { Data(buffer: $0) }
        let src = SCNGeometrySource(data: data, semantic: .vertex, vectorCount: verts.count/3,
            usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        var idx: [Int32] = []
        for i in 0..<segments { idx += [Int32(i), Int32(i+1)] }
        let idxData = idx.withUnsafeMutableBufferPointer { Data(buffer: $0) }
        let elem = SCNGeometryElement(data: idxData, primitiveType: .line,
                                      primitiveCount: segments, bytesPerIndex: 4)
        let geo = SCNGeometry(sources: [src], elements: [elem])
        geo.firstMaterial = {
            let m = SCNMaterial()
            m.emission.contents = color.withAlphaComponent(0.35)
            m.lightingModel = .constant
            return m
        }()
        let node = SCNNode(geometry: geo)
        node.name = "spline"
        scene.rootNode.addChildNode(node)
        splineNodes.append(node)
    }

    // MARK: — Tool shapes (mirrors toolDefs in index.html)
    private func buildToolShapes() {
        let defs: [(color: UIColor, count: Int, radius: Float)] = [
            (UIColor(red:1,green:0.27,blue:0.4,alpha:1),   4, 1.9),  // knife
            (UIColor(red:0,green:1,blue:0.8,alpha:1),       4, 1.4),  // stick
            (UIColor(red:0,green:0.53,blue:1,alpha:1),      3, 0.9),  // hammer
            (UIColor(red:0.53,green:0.8,blue:1,alpha:1),    3, 1.9),  // envelope
            (UIColor(red:1,green:0.53,blue:0.27,alpha:1),   3, 1.4),  // scissors
        ]
        for def in defs {
            for i in 0..<def.count {
                let geo = SCNBox(width:0.06, height:0.04, length:0.02, chamferRadius:0.008)
                geo.firstMaterial = {
                    let m = SCNMaterial()
                    m.emission.contents = def.color.withAlphaComponent(0.6)
                    m.lightingModel = .constant
                    return m
                }()
                let node = SCNNode(geometry: geo)
                node.name = "tool_\(i)"
                let angle = Float(i) / Float(def.count) * .pi * 2
                let r = def.radius * (0.85 + Float.random(in: 0...0.3))
                node.position = SCNVector3(r * cos(angle), Float.random(in: -0.3...0.3), r * sin(angle))
                scene.rootNode.addChildNode(node)
                toolShapeNodes.append(node)
            }
        }
    }

    // MARK: — Presence polling (mirrors _pollAshNodes)
    private func pollPresence() async {
        guard let url = URL(string: "https://script.google.com/macros/s/AKfycbzBRPNAutumnGASEndpointLEATR/exec") else { return }
        let payload: [String: Any] = [
            "action": "readnodes",
            "sid": sessionId
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return }
        struct NodeResp: Decodable {
            let nodes: [RemoteNode]?
        }
        struct RemoteNode: Decodable {
            let uid: String; let shell: String?; let color: String?
        }
        if let resp = try? JSONDecoder().decode(NodeResp.self, from: data),
           let nodes = resp.nodes {
            await MainActor.run {
                for node in nodes where node.uid != sessionId {
                    if sessionGroupNodes[node.uid] == nil {
                        addRemoteNode(uid: node.uid, emotion: "neutral")
                    }
                }
            }
        }
    }

    // MARK: — Maze algorithms (faithful port from index.html)
    private func orbGenMaze(w: Int, h: Int, d: Int) -> [[[MazeCell]]] {
        var grid = Array(repeating: Array(repeating: Array(repeating:
            MazeCell(), count: w), count: h), count: d)
        var stack = [(x:0,y:0,z:0)]
        grid[0][0][0].visited = true
        while !stack.isEmpty {
            let curr = stack.last!
            var ns: [(x:Int,y:Int,z:Int,d1:String,d2:String)] = []
            if curr.x>0 && !grid[curr.z][curr.y][curr.x-1].visited { ns.append((curr.x-1,curr.y,curr.z,"left","right")) }
            if curr.x<w-1 && !grid[curr.z][curr.y][curr.x+1].visited { ns.append((curr.x+1,curr.y,curr.z,"right","left")) }
            if curr.y>0 && !grid[curr.z][curr.y-1][curr.x].visited { ns.append((curr.x,curr.y-1,curr.z,"bottom","top")) }
            if curr.y<h-1 && !grid[curr.z][curr.y+1][curr.x].visited { ns.append((curr.x,curr.y+1,curr.z,"top","bottom")) }
            if curr.z>0 && !grid[curr.z-1][curr.y][curr.x].visited { ns.append((curr.x,curr.y,curr.z-1,"back","front")) }
            if curr.z<d-1 && !grid[curr.z+1][curr.y][curr.x].visited { ns.append((curr.x,curr.y,curr.z+1,"front","back")) }

            if ns.isEmpty { stack.removeLast() }
            else {
                let next = ns[Int.random(in: 0..<ns.count)]
                grid[curr.z][curr.y][curr.x].removeWall(next.d1)
                grid[next.z][next.y][next.x].removeWall(next.d2)
                grid[next.z][next.y][next.x].visited = true
                stack.append((next.x,next.y,next.z))
            }
        }
        return grid
    }

    private func orbSolveMaze(grid: [[[MazeCell]]], w:Int, h:Int, d:Int) -> [(x:Int,y:Int,z:Int)] {
        typealias Pt = (x:Int,y:Int,z:Int)
        var queue: [(pt:Pt, path:[Pt])] = [((0,0,0), [(0,0,0)])]
        var visited = Set<String>(["0,0,0"])
        let goal = "\(w-1),\(h-1),\(d-1)"
        while !queue.isEmpty {
            let (curr, path) = queue.removeFirst()
            if "\(curr.x),\(curr.y),\(curr.z)" == goal { return path }
            let c = grid[curr.z][curr.y][curr.x]
            var moves: [Pt] = []
            if !c.left   && curr.x>0   { moves.append((curr.x-1,curr.y,curr.z)) }
            if !c.right  && curr.x<w-1 { moves.append((curr.x+1,curr.y,curr.z)) }
            if !c.bottom && curr.y>0   { moves.append((curr.x,curr.y-1,curr.z)) }
            if !c.top    && curr.y<h-1 { moves.append((curr.x,curr.y+1,curr.z)) }
            if !c.back   && curr.z>0   { moves.append((curr.x,curr.y,curr.z-1)) }
            if !c.front  && curr.z<d-1 { moves.append((curr.x,curr.y,curr.z+1)) }
            for m in moves {
                let key = "\(m.x),\(m.y),\(m.z)"
                if !visited.contains(key) {
                    visited.insert(key)
                    queue.append((m, path + [m]))
                }
            }
        }
        return []
    }

    // MARK: — Node positioning + colors (mirrors _nodeBasePos + _uidShellColors)
    private func nodeBasePosition(uid: String) -> (x:Float,y:Float,z:Float) {
        let h = Float(uid.hashValue & 0xFFFF) / 65535.0
        let h2 = Float((uid + "y").hashValue & 0xFFFF) / 65535.0
        let h3 = Float((uid + "z").hashValue & 0xFFFF) / 65535.0
        let theta = h * .pi * 2
        let phi = acos(2 * h2 - 1)
        let r = 3.2 + h3 * 1.6
        return (r * sin(phi) * cos(theta), r * sin(phi) * sin(theta), r * cos(phi))
    }

    private func uidShellColors(uid: String) -> [UIColor] {
        let hue = Float(uid.hashValue & 0xFFFF) / 65535.0
        return [
            UIColor(hue: CGFloat(hue), saturation: 0.9, brightness: 0.65, alpha: 1),
            UIColor(hue: CGFloat((hue + 0.333).truncatingRemainder(dividingBy: 1)), saturation: 0.85, brightness: 0.6, alpha: 1),
            UIColor(hue: CGFloat((hue + 0.667).truncatingRemainder(dividingBy: 1)), saturation: 0.8, brightness: 0.55, alpha: 1),
        ]
    }

    // MARK: — Pulse shells (mirrors pulseShells in index.html)
    public func pulseShells(_ intensity: Float = 0.4) {
        for (i, shell) in shells.enumerated() {
            let baseOpacity = 0.18 + Float(i) * 0.08
            let targetOpacity = min(0.9, baseOpacity + intensity)
            let action = SCNAction.sequence([
                SCNAction.customAction(duration: 0.3) { node, t in
                    node.geometry?.firstMaterial?.transparency = CGFloat(baseOpacity + (targetOpacity - baseOpacity) * Float(t) / 0.3)
                },
                SCNAction.customAction(duration: 0.5) { node, t in
                    node.geometry?.firstMaterial?.transparency = CGFloat(targetOpacity - (targetOpacity - baseOpacity) * Float(t) / 0.5)
                }
            ])
            shell.runAction(action)
        }
    }

    public func teardown() {
        presenceTimer?.invalidate()
        solveTimer?.invalidate()
    }
}

// MARK: — MazeCell model
public struct MazeCell {
    var top = true, bottom = true, left = true, right = true, front = true, back = true
    var visited = false

    mutating func removeWall(_ dir: String) {
        switch dir {
        case "top":    top    = false
        case "bottom": bottom = false
        case "left":   left   = false
        case "right":  right  = false
        case "front":  front  = false
        case "back":   back   = false
        default: break
        }
    }
}
