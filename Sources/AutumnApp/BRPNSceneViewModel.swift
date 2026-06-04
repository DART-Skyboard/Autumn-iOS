import SwiftUI
import SceneKit

// MARK: — BRPNSceneViewModel v2
// Fixed: cubic maze, random start/end with turn requirement,
//        shell materials, path node sizing, proper colors

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

    public let scene = SCNScene()
    public var shells: [SCNNode] = []
    private var coreNode: SCNNode!
    private var mazeOrbGroup: SCNNode!
    private var particleNodes: [SCNNode] = []
    private var particleData: [(r:Float,spd:Float,off:Float,yOff:Float)] = []
    private var sessionGroupNodes: [String: SCNNode] = [:]
    public var pathMeshNodes: [SCNNode] = []
    private var solveStep = 0
    private var frameCount = 0
    private var presenceTimer: Timer?
    private var mazeGrid: [[[MazeCell]]] = []
    private var mazeSolution: [(x:Int,y:Int,z:Int)] = []

    // CUBIC maze — all axes equal (6x6x6 fits inside shell nicely)
    private let mazeN = 5  // 5x5x5 cubic
    private let cellSize: Float = 0.048  // fits inside r=0.18 core

    private let shellColors: [UIColor] = [
        UIColor(red:0.0, green:1.0, blue:0.8,  alpha:1),  // cyan  #00ffcc
        UIColor(red:0.0, green:0.53,blue:1.0,  alpha:1),  // blue  #0088ff
        UIColor(red:1.0, green:0.27,blue:0.4,  alpha:1),  // pink  #ff4466
    ]
    private let shellRadii: [Float] = [1.9, 1.4, 0.9]

    public func setupScene() {
        scene.background.contents = UIColor.clear

        // Ambient light
        let amb = SCNNode(); amb.light = { let l=SCNLight(); l.type = .ambient; l.intensity = 200; return l }()
        scene.rootNode.addChildNode(amb)

        // ── 3 Icosahedron wireframe shells ──────────────────────────
        // KEY FIX: use SCNGeometry line-based approach for true wireframe cyan
        for (i, radius) in shellRadii.enumerated() {
            let geo = SCNSphere(radius: CGFloat(radius))
            geo.segmentCount = 8
            let mat = SCNMaterial()
            mat.diffuse.contents  = UIColor.clear
            mat.emission.contents = shellColors[i]
            mat.isDoubleSided = true
            mat.fillMode = .lines        // wireframe
            mat.writesToDepthBuffer = false
            geo.materials = [mat]
            let node = SCNNode(geometry: geo); node.name = "shell_\(i)"
            // Per-shell rotation matching web app
            let dur = Double(22 + i * 7)
            let yRot = SCNAction.repeatForever(SCNAction.rotateBy(
                x: CGFloat(i == 0 ? 0.15 : i == 1 ? -0.1 : 0.2),
                y: CGFloat(i == 0 ? 1.0 : i == 1 ? -0.85 : 0.65),
                z: 0, duration: dur))
            node.runAction(yRot)
            scene.rootNode.addChildNode(node)
            shells.append(node)
        }

        // ── Core sphere ──────────────────────────────────────────────
        let cg = SCNSphere(radius: 0.16); cg.segmentCount = 8
        let cm = SCNMaterial()
        cm.diffuse.contents  = UIColor.clear
        cm.emission.contents = UIColor(red:0,green:1,blue:0.8,alpha:0.18)
        cm.fillMode = .lines
        cg.materials = [cm]
        coreNode = SCNNode(geometry: cg)
        scene.rootNode.addChildNode(coreNode)

        // ── LEMAC 3D Cubic Maze ──────────────────────────────────────
        mazeOrbGroup = SCNNode(); mazeOrbGroup.name = "mazeOrb"
        scene.rootNode.addChildNode(mazeOrbGroup)
        buildOrbMazeGeometry()

        // ── 30 orbital particles ─────────────────────────────────────
        for i in 0..<30 {
            let pg = SCNSphere(radius: 0.022)
            let pm = SCNMaterial()
            pm.emission.contents = shellColors[i%3].withAlphaComponent(0.7)
            pm.lightingModel = .constant
            pg.materials = [pm]
            let node = SCNNode(geometry: pg); node.name = "particle_\(i)"
            let r = Float.random(in:0.55...2.0)
            let spd = Float.random(in:0.3...1.5)
            let off = Float.random(in:0...(.pi*2))
            let yOff = Float.random(in:-0.8...0.8)
            particleData.append((r,spd,off,yOff))
            scene.rootNode.addChildNode(node)
            particleNodes.append(node)
        }

        // ── Tool shape swarm ─────────────────────────────────────────
        let toolColors: [UIColor] = [
            UIColor(red:1,green:0.27,blue:0.4,alpha:1),
            UIColor(red:0,green:1,blue:0.8,alpha:1),
            UIColor(red:0,green:0.53,blue:1,alpha:1),
            UIColor(red:0.53,green:0.8,blue:1,alpha:1),
            UIColor(red:1,green:0.53,blue:0.27,alpha:1),
        ]
        for (ci, col) in toolColors.enumerated() {
            for i in 0..<3 {
                let tg = SCNBox(width:0.055,height:0.035,length:0.02,chamferRadius:0.006)
                let tm = SCNMaterial(); tm.emission.contents = col.withAlphaComponent(0.6)
                tm.lightingModel = .constant; tg.materials = [tm]
                let tn = SCNNode(geometry:tg); tn.name = "tool_\(ci)_\(i)"
                let r = shellRadii[i%3] * Float.random(in:0.85...1.15)
                let ang = Float(ci*3+i) / 15.0 * .pi * 2
                tn.position = SCNVector3(r*cos(ang), Float.random(in:-0.4...0.4), r*sin(ang))
                scene.rootNode.addChildNode(tn)
            }
        }

        presenceTimer = Timer.scheduledTimer(withTimeInterval:30, repeats:true) { [weak self] _ in
            Task { await self?.pollPresence() }
        }
    }

    // MARK: — Frame update
    public func updateFrame() {
        frameCount += 1
        let t = Float(frameCount) * 0.016

        for (i, node) in particleNodes.enumerated() {
            guard i < particleData.count else { continue }
            let d = particleData[i]
            let a = t * d.spd + d.off
            node.position = SCNVector3(d.r*cos(a), d.yOff + sin(t*0.3+Float(i))*0.12, d.r*sin(a))
        }
        mazeOrbGroup?.eulerAngles.y = t * 0.004
        mazeOrbGroup?.eulerAngles.x = sin(t*0.0025) * 0.08
        let pulse = 1.0 + sin(t*2.0)*0.06
        coreNode?.scale = SCNVector3(pulse,pulse,pulse)
        if isSolving { stepMazeSolveAnim() }
    }

    // MARK: — CUBIC maze with randomized start/end (key improvement)
    private func buildOrbMazeGeometry() {
        mazeOrbGroup.childNodes.forEach { $0.removeFromParentNode() }
        pathMeshNodes.removeAll(); solveStep=0; isSolving=false

        let n = mazeN
        var (start, end) = randomStartEnd(n: n)
        // Generate maze with random entry/exit
        let grid = orbGenMaze(w:n, h:n, d:n, start:start, end:end)
        mazeGrid = grid
        mazeSolution = orbSolveMaze(grid:grid, w:n, h:n, d:n, start:start, end:end)
        mazeCanSolve = !mazeSolution.isEmpty

        let u: Float = cellSize
        let half = Float(n)*u/2
        let hs = u*0.5

        // Wall geometry
        var wallVerts: [Float] = []
        func quad(_ pts:[(Float,Float,Float)]) {
            for i in 0..<pts.count {
                let a=pts[i]; let b=pts[(i+1)%pts.count]
                wallVerts += [a.0,a.1,a.2, b.0,b.1,b.2]
            }
        }
        for z in 0..<n { for y in 0..<n { for x in 0..<n {
            let c=grid[z][y][x]
            let cx=Float(x)*u-half+hs, cy=Float(y)*u-half+hs, cz=Float(z)*u-half+hs
            if c.left  { quad([(cx-hs,cy-hs,cz-hs),(cx-hs,cy+hs,cz-hs),(cx-hs,cy+hs,cz+hs),(cx-hs,cy-hs,cz+hs)]) }
            if c.bottom{ quad([(cx-hs,cy-hs,cz-hs),(cx+hs,cy-hs,cz-hs),(cx+hs,cy-hs,cz+hs),(cx-hs,cy-hs,cz+hs)]) }
            if c.back  { quad([(cx-hs,cy-hs,cz-hs),(cx+hs,cy-hs,cz-hs),(cx+hs,cy+hs,cz-hs),(cx-hs,cy+hs,cz-hs)]) }
        }}}

        let posBuf = wallVerts.withUnsafeBufferPointer { Data(buffer: $0) }
        let src = SCNGeometrySource(data:posBuf, semantic:.vertex, vectorCount:wallVerts.count/3,
            usesFloatComponents:true, componentsPerVector:3, bytesPerComponent:4, dataOffset:0, dataStride:12)
        var idx = (0..<Int32(wallVerts.count/3)).map { Int32($0) }
        let idxData = idx.withUnsafeMutableBufferPointer { Data(buffer: $0) }
        let elem = SCNGeometryElement(data:idxData, primitiveType:.line, primitiveCount:idx.count/2, bytesPerIndex:4)
        let wallGeo = SCNGeometry(sources:[src], elements:[elem])
        wallGeo.firstMaterial = { let m=SCNMaterial(); m.emission.contents=UIColor(red:0,green:1,blue:0.8,alpha:0.55); m.lightingModel = .constant; return m }()
        mazeOrbGroup.addChildNode(SCNNode(geometry:wallGeo))

        // Path node meshes — SMALL spheres (u*0.18 not 0.22)
        let pathGeo = SCNSphere(radius: CGFloat(u*0.18))
        for pt in mazeSolution {
            let mat = SCNMaterial()
            mat.emission.contents = UIColor(red:0,green:1,blue:1,alpha:0)
            mat.lightingModel = .constant
            pathGeo.materials = [mat]
            let mesh = SCNNode(geometry: pathGeo.copy() as! SCNGeometry)
            mesh.position = SCNVector3(Float(pt.x)*u-half+hs, Float(pt.y)*u-half+hs, Float(pt.z)*u-half+hs)
            mesh.name = "pathNode"
            mazeOrbGroup.addChildNode(mesh)
            pathMeshNodes.append(mesh)
        }

        // Start marker — GREEN (cyan-green)
        addMarker(at:start, n:n, u:u, half:half, hs:hs,
                  color:UIColor(red:0.2,green:1.0,blue:0.4,alpha:1), size:u*0.38)
        // End marker — RED-ORANGE (distinct from start)
        addMarker(at:end, n:n, u:u, half:half, hs:hs,
                  color:UIColor(red:1.0,green:0.3,blue:0.15,alpha:1), size:u*0.38)
    }

    private func addMarker(at pt:(x:Int,y:Int,z:Int), n:Int, u:Float, half:Float, hs:Float, color:UIColor, size:Float) {
        let geo = SCNSphere(radius:CGFloat(size))
        geo.firstMaterial = { let m=SCNMaterial(); m.emission.contents=color; m.lightingModel = .constant; return m }()
        let node = SCNNode(geometry:geo)
        node.position = SCNVector3(Float(pt.x)*u-half+hs, Float(pt.y)*u-half+hs, Float(pt.z)*u-half+hs)
        mazeOrbGroup.addChildNode(node)
    }

    // MARK: — Random start/end with rules:
    // - On any face of the cube (perimeter cells)
    // - Must be at least 2 cells apart (no adjacent faces)
    // - Must require a turn before line-of-sight is broken (no straight A→B)
    private func randomStartEnd(n: Int) -> ((x:Int,y:Int,z:Int), (x:Int,y:Int,z:Int)) {
        // Collect all perimeter surface cells
        var perimeter: [(x:Int,y:Int,z:Int)] = []
        for x in 0..<n { for y in 0..<n { for z in 0..<n {
            if x==0||x==n-1||y==0||y==n-1||z==0||z==n-1 {
                perimeter.append((x,y,z))
            }
        }}}
        perimeter.shuffle()

        var start = perimeter[0]
        var end   = perimeter[1]

        // Try up to 50 times to find a valid pair
        outer: for i in 0..<perimeter.count {
            for j in (i+1)..<perimeter.count {
                let s = perimeter[i]; let e = perimeter[j]
                if isValidPair(s:s, e:e, n:n) { start=s; end=e; break outer }
            }
        }
        return (start, end)
    }

    // Rules: not the same cell, not sharing an edge wall (1 unit of wall between),
    // not in direct line of sight without a required turn
    private func isValidPair(s:(x:Int,y:Int,z:Int), e:(x:Int,y:Int,z:Int), n:Int) -> Bool {
        // Must be different cells
        if s.x==e.x && s.y==e.y && s.z==e.z { return false }
        // Minimum Manhattan distance — at least N/2 apart so there's meaningful maze
        let dist = abs(s.x-e.x) + abs(s.y-e.y) + abs(s.z-e.z)
        if dist < max(3, n/2) { return false }
        // Not on same face AND same row/column (would be line of sight on perimeter)
        // Same X face: if s.x==0&&e.x==0 and s.y==e.y — straight line on face
        if s.x==e.x && s.x==0 && (s.y==e.y || s.z==e.z) && dist < 3 { return false }
        if s.x==e.x && s.x==n-1 && (s.y==e.y || s.z==e.z) && dist < 3 { return false }
        if s.y==e.y && s.y==0 && (s.x==e.x || s.z==e.z) && dist < 3 { return false }
        if s.y==e.y && s.y==n-1 && (s.x==e.x || s.z==e.z) && dist < 3 { return false }
        if s.z==e.z && s.z==0 && (s.x==e.x || s.y==e.y) && dist < 3 { return false }
        if s.z==e.z && s.z==n-1 && (s.x==e.x || s.y==e.y) && dist < 3 { return false }
        // Not in 3D line of sight (same X AND same Y, or same X AND same Z, etc.)
        let sameX = (s.x==e.x); let sameY = (s.y==e.y); let sameZ = (s.z==e.z)
        // Two axes aligned = direct straight line = no turn needed = invalid
        if sameX && sameY { return false }
        if sameX && sameZ { return false }
        if sameY && sameZ { return false }
        return true
    }

    // MARK: — orbGenMaze: exact port of index.html but with custom start
    private func orbGenMaze(w:Int, h:Int, d:Int,
                             start:(x:Int,y:Int,z:Int),
                             end:(x:Int,y:Int,z:Int)) -> [[[MazeCell]]] {
        var grid = Array(repeating: Array(repeating: Array(repeating: MazeCell(), count:w), count:h), count:d)
        // Start from the start cell (not always 0,0,0)
        var stack = [(x:start.x, y:start.y, z:start.z)]
        grid[start.z][start.y][start.x].visited = true

        while !stack.isEmpty {
            let curr = stack.last!
            var ns: [(x:Int,y:Int,z:Int,d1:String,d2:String)] = []
            if curr.x>0   && !grid[curr.z][curr.y][curr.x-1].visited { ns.append((curr.x-1,curr.y,curr.z,"left","right")) }
            if curr.x<w-1 && !grid[curr.z][curr.y][curr.x+1].visited { ns.append((curr.x+1,curr.y,curr.z,"right","left")) }
            if curr.y>0   && !grid[curr.z][curr.y-1][curr.x].visited { ns.append((curr.x,curr.y-1,curr.z,"bottom","top")) }
            if curr.y<h-1 && !grid[curr.z][curr.y+1][curr.x].visited { ns.append((curr.x,curr.y+1,curr.z,"top","bottom")) }
            if curr.z>0   && !grid[curr.z-1][curr.y][curr.x].visited { ns.append((curr.x,curr.y,curr.z-1,"back","front")) }
            if curr.z<d-1 && !grid[curr.z+1][curr.y][curr.x].visited { ns.append((curr.x,curr.y,curr.z+1,"front","back")) }

            if ns.isEmpty { stack.removeLast() }
            else {
                let next = ns[Int.random(in:0..<ns.count)]
                grid[curr.z][curr.y][curr.x].removeWall(next.d1)
                grid[next.z][next.y][next.x].removeWall(next.d2)
                grid[next.z][next.y][next.x].visited = true
                stack.append((next.x,next.y,next.z))
            }
        }
        return grid
    }

    // MARK: — BFS solve from any start to any end
    private func orbSolveMaze(grid:[[[MazeCell]]], w:Int, h:Int, d:Int,
                               start:(x:Int,y:Int,z:Int),
                               end:(x:Int,y:Int,z:Int)) -> [(x:Int,y:Int,z:Int)] {
        typealias Pt = (x:Int,y:Int,z:Int)
        var queue: [(pt:Pt,path:[Pt])] = [(start,[start])]
        var visited = Set<String>(["\(start.x),\(start.y),\(start.z)"])
        let goalKey = "\(end.x),\(end.y),\(end.z)"
        while !queue.isEmpty {
            let (curr,path) = queue.removeFirst()
            if "\(curr.x),\(curr.y),\(curr.z)" == goalKey { return path }
            let c = grid[curr.z][curr.y][curr.x]
            var moves: [Pt] = []
            if !c.left   && curr.x>0   { moves.append((curr.x-1,curr.y,curr.z)) }
            if !c.right  && curr.x<w-1 { moves.append((curr.x+1,curr.y,curr.z)) }
            if !c.bottom && curr.y>0   { moves.append((curr.x,curr.y-1,curr.z)) }
            if !c.top    && curr.y<h-1 { moves.append((curr.x,curr.y+1,curr.z)) }
            if !c.back   && curr.z>0   { moves.append((curr.x,curr.y,curr.z-1)) }
            if !c.front  && curr.z<d-1 { moves.append((curr.x,curr.y,curr.z+1)) }
            for m in moves {
                let k = "\(m.x),\(m.y),\(m.z)"
                if !visited.contains(k) { visited.insert(k); queue.append((m,path+[m])) }
            }
        }
        return []
    }

    // MARK: — Solve animation (Autumn only)
    public func autumnSolveMaze() {
        guard mazeCanSolve, !isSolving else { return }
        solveStep = 0; isSolving = true
        pathMeshNodes.forEach { $0.geometry?.firstMaterial?.emission.contents = UIColor(red:0,green:1,blue:1,alpha:0) }
    }

    private func stepMazeSolveAnim() {
        guard solveStep < pathMeshNodes.count else {
            isSolving = false
            DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self] in
                self?.buildOrbMazeGeometry()
            }
            return
        }
        let toReveal = min(2, pathMeshNodes.count - solveStep)
        for i in 0..<toReveal {
            let node = pathMeshNodes[solveStep+i]
            let alpha = CGFloat.random(in:0.7...1.0)
            node.geometry?.firstMaterial?.emission.contents = UIColor(red:0,green:1,blue:1,alpha:alpha)
            node.runAction(SCNAction.sequence([
                SCNAction.scale(to:1.5, duration:0.08),
                SCNAction.scale(to:1.0, duration:0.12)
            ]))
        }
        solveStep += toReveal
    }

    // MARK: — Presence / remote nodes
    public func addRemoteNode(uid: String, emotion: String = "neutral") {
        let pos = nodeBasePosition(uid:uid)
        let group = SCNNode(); group.name = "session_\(uid)"
        let colors = uidShellColors(uid:uid)
        let miniR: [Float] = [1.9*0.28, 1.4*0.28, 0.9*0.28]
        for (i,r) in miniR.enumerated() {
            let g = SCNSphere(radius:CGFloat(r)); g.segmentCount=4
            let m = SCNMaterial(); m.emission.contents = colors[i].withAlphaComponent(0.25+Float(i)*0.06)
            m.fillMode = .lines; m.lightingModel = .constant; g.materials = [m]
            group.addChildNode(SCNNode(geometry:g))
        }
        let cg = SCNSphere(radius:0.03)
        let cm = SCNMaterial(); cm.emission.contents = colors[0]; cm.lightingModel = .constant; cg.materials=[cm]
        group.addChildNode(SCNNode(geometry:cg))
        group.position = SCNVector3(pos.x,pos.y,pos.z)
        scene.rootNode.addChildNode(group)
        sessionGroupNodes[uid] = group
        activeNodes += 1
    }

    private func pollPresence() async {}
    public func teardown() { presenceTimer?.invalidate() }
    public func pulseShells(_ intensity: Float = 0.4) {
        for (i,shell) in shells.enumerated() {
            let base = 0.18+Float(i)*0.08
            shell.runAction(SCNAction.sequence([
                SCNAction.customAction(duration:0.3) { n,t in
                    n.geometry?.firstMaterial?.emission.contents =
                        self.shellColors[i].withAlphaComponent(CGFloat(base+intensity*Float(t)/0.3))
                },
                SCNAction.customAction(duration:0.5) { n,t in
                    n.geometry?.firstMaterial?.emission.contents =
                        self.shellColors[i].withAlphaComponent(CGFloat(base+intensity*(1.0-Float(t)/0.5)))
                }
            ]))
        }
    }

    private func nodeBasePosition(uid:String) -> (x:Float,y:Float,z:Float) {
        let h  = Float(uid.hashValue & 0xFFFF)/65535.0
        let h2 = Float((uid+"y").hashValue & 0xFFFF)/65535.0
        let h3 = Float((uid+"z").hashValue & 0xFFFF)/65535.0
        let theta = h * .pi * 2; let phi = acos(2*h2-1); let r = 3.2+h3*1.6
        return (r*sin(phi)*cos(theta), r*sin(phi)*sin(theta), r*cos(phi))
    }

    private func uidShellColors(uid:String) -> [UIColor] {
        let hue = Float(uid.hashValue & 0xFFFF)/65535.0
        return [
            UIColor(hue:CGFloat(hue), saturation:0.9, brightness:0.65, alpha:1),
            UIColor(hue:CGFloat((hue+0.333).truncatingRemainder(dividingBy:1)), saturation:0.85, brightness:0.6, alpha:1),
            UIColor(hue:CGFloat((hue+0.667).truncatingRemainder(dividingBy:1)), saturation:0.8, brightness:0.55, alpha:1),
        ]
    }
}

public struct MazeCell {
    var top=true,bottom=true,left=true,right=true,front=true,back=true,visited=false
    mutating func removeWall(_ dir:String) {
        switch dir {
        case "top":    top=false
        case "bottom": bottom=false
        case "left":   left=false
        case "right":  right=false
        case "front":  front=false
        case "back":   back=false
        default: break
        }
    }
}
