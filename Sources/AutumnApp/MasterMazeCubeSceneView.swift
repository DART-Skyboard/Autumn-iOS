import SwiftUI
import SceneKit
import LEATRCore

/// Master Maze Cube 3D display for the Admin Console.
///
/// Draws the ACTIVE live-feed master maze (LiveFeedController.masterMaze --
/// the same `ashtree/analytics-live/config.json` grid the web Admin Console
/// and cube.leatr.xyz read) the way the Session Cube's live view does:
/// frosted red wall panes (brighter where they line the solved walk, dimmer
/// on the outer shell and quiet interior), a cyan wireframe lattice around
/// the corridor, the blue solved path with event nodes sized by how many
/// analytics events the shared latest-export.json nested there, green/red
/// entrance/exit markers, and a traveler walking the path on a loop. Slow
/// turntable; drag to orbit, pinch to zoom. Rebuilds the instant a new
/// master maze arrives -- generated here OR pulled from the web.
struct MasterMazeCubeDisplay: View {
    @ObservedObject var liveFeed: LiveFeedController
    var accent: Color = Color(hex: "#3aa8ff")

    init(liveFeed: LiveFeedController, accent: Color = Color(hex: "#3aa8ff")) {
        self.liveFeed = liveFeed
        self.accent = accent
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MasterMazeCubeSceneView(
                cubic: liveFeed.masterMaze,
                solution: liveFeed.masterMazeSolution,
                eventCounts: liveFeed.liveExportEventCounts,
                revision: liveFeed.masterMazeRevision
            )
            if liveFeed.masterMaze == nil {
                VStack(spacing: 6) {
                    ProgressView().tint(accent)
                    Text("Waiting for the master maze…")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            hud
        }
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(liveFeed.isEnabled ? Color(hex: "#6dff9e") : Color(hex: "#8ea39a"))
                    .frame(width: 7, height: 7)
                Text("MASTER MAZE CUBE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
            Text("\(liveFeed.masterMazeWidth)×\(liveFeed.masterMazeHeight)×\(liveFeed.masterMazeDepth) · \(liveFeed.masterMazeId.isEmpty ? "—" : liveFeed.masterMazeId)")
            Text("PATH \(liveFeed.masterMazeSolution.count) cells · \(liveFeed.liveExportTotalEvents) events")
            if let at = liveFeed.lastSyncAt {
                Text("SYNCED \(Self.timeFormatter.string(from: at))")
            }
            Spacer(minLength: 0)
            ForEach(Array(liveFeed.liveExportRecentLabels.enumerated()), id: \.offset) { _, label in
                Text(label.replacingOccurrences(of: "_", with: " "))
                    .foregroundColor(Color(hex: "#bfe6ff").opacity(0.85))
            }
            if !liveFeed.syncNote.isEmpty {
                Text(liveFeed.syncNote)
                    .foregroundColor(accent.opacity(0.9))
                    .lineLimit(2)
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundColor(.white.opacity(0.6))
        .shadow(color: .black, radius: 2)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

struct MasterMazeCubeSceneView: UIViewRepresentable {
    let cubic: LEMACEngineASH.CubicResult?
    let solution: [MazePt]
    let eventCounts: [Int]
    let revision: Int

    // Session Cube live palette (cube/public/live-cube.js COLORS).
    static let corridor = UIColor(red: 1.0, green: 0x54 / 255.0, blue: 0x46 / 255.0, alpha: 1)
    static let shell = UIColor(red: 0xd2 / 255.0, green: 0x3c / 255.0, blue: 0x32 / 255.0, alpha: 1)
    static let quiet = UIColor(red: 0xb3 / 255.0, green: 0x30 / 255.0, blue: 0x2a / 255.0, alpha: 1)
    static let path = UIColor(red: 0x3a / 255.0, green: 0xa8 / 255.0, blue: 1.0, alpha: 1)
    static let event = UIColor(red: 0x9f / 255.0, green: 0xdc / 255.0, blue: 1.0, alpha: 1)
    static let head = UIColor(red: 0xe6 / 255.0, green: 0xf6 / 255.0, blue: 1.0, alpha: 1)
    static let lattice = UIColor(red: 0, green: 0.9, blue: 1.0, alpha: 1)

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        v.rendersContinuously = true
        v.isPlaying = true

        let scene = SCNScene()
        let cam = SCNCamera()
        cam.fieldOfView = 36
        cam.zNear = 0.1
        cam.zFar = 500
        cam.wantsHDR = true
        cam.bloomIntensity = 0.9
        cam.bloomThreshold = 0.55
        cam.bloomBlurRadius = 6
        let camNode = SCNNode()
        camNode.name = "mmCamera"
        camNode.camera = cam
        scene.rootNode.addChildNode(camNode)

        // tilt -> turntable -> (maze, path) so the auto-rotation survives
        // every rebuild instead of snapping back to 0 on each new maze.
        let tilt = SCNNode()
        tilt.name = "mmTilt"
        tilt.eulerAngles.x = 0.18
        scene.rootNode.addChildNode(tilt)
        let turntable = SCNNode()
        turntable.name = "mmTurntable"
        tilt.addChildNode(turntable)
        turntable.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 52)))

        v.scene = scene
        v.pointOfView = camNode
        rebuild(v, context: context)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        rebuild(v, context: context)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var lastRevision = -1
        var lastCounts: [Int] = []
        var lastSpan = 0
    }

    // MARK: — Build

    private func rebuild(_ v: SCNView, context: Context) {
        guard let scene = v.scene,
              let turntable = scene.rootNode.childNode(withName: "mmTurntable", recursively: true) else { return }
        let co = context.coordinator
        let structureChanged = co.lastRevision != revision
        let countsChanged = co.lastCounts != eventCounts
        guard structureChanged || countsChanged else { return }
        co.lastRevision = revision
        co.lastCounts = eventCounts

        guard let cubic, cubic.d > 0, cubic.h > 0, cubic.w > 0 else {
            turntable.childNodes.forEach { $0.removeFromParentNode() }
            return
        }

        if structureChanged || turntable.childNode(withName: "mmMaze", recursively: false) == nil {
            turntable.childNode(withName: "mmMaze", recursively: false)?.removeFromParentNode()
            let maze = buildMaze(cubic)
            maze.name = "mmMaze"
            // New master maze (local or pulled from the web): bloom it in.
            maze.opacity = 0
            maze.scale = SCNVector3(0.82, 0.82, 0.82)
            turntable.addChildNode(maze)
            maze.runAction(.group([.fadeIn(duration: 0.7), .scale(to: 1, duration: 0.7)]))

            let span = max(cubic.w, cubic.h, cubic.d)
            if co.lastSpan != span, let cam = scene.rootNode.childNode(withName: "mmCamera", recursively: false) {
                co.lastSpan = span
                let s = Float(span)
                cam.position = SCNVector3(0, s * 1.05, s * 2.95)
                cam.look(at: SCNVector3(0, 0, 0))
            }
        }

        turntable.childNode(withName: "mmPath", recursively: false)?.removeFromParentNode()
        let pathNode = buildPath(cubic)
        pathNode.name = "mmPath"
        turntable.addChildNode(pathNode)
    }

    private func center(_ x: Int, _ y: Int, _ z: Int, _ c: LEMACEngineASH.CubicResult) -> SCNVector3 {
        SCNVector3(Float(x) - Float(c.w - 1) / 2, Float(y) - Float(c.h - 1) / 2, Float(z) - Float(c.d - 1) / 2)
    }

    private static let faceStep: [String: (Int, Int, Int)] = [
        "left": (-1, 0, 0), "right": (1, 0, 0),
        "bottom": (0, -1, 0), "top": (0, 1, 0),
        "back": (0, 0, -1), "front": (0, 0, 1)
    ]
    private static let faces = ["right", "front", "top", "left", "back", "bottom"]

    private func buildMaze(_ c: LEMACEngineASH.CubicResult) -> SCNNode {
        let root = SCNNode()
        var onPath = Set<String>()
        for p in solution { onPath.insert("\(p.x),\(p.y),\(p.z)") }

        // Same wall classification as the Session Cube's buildModel(): each
        // shared wall drawn once; corridor = lines the walked path.
        var quads: [String: [SCNVector3]] = ["corridor": [], "shell": [], "quiet": []]
        var corridorEdges: [SCNVector3] = []
        let half: Float = 0.46
        for z in 0..<c.d {
            for y in 0..<c.h {
                for x in 0..<c.w {
                    guard z < c.grid.count, y < c.grid[z].count, x < c.grid[z][y].count else { continue }
                    let cell = c.grid[z][y][x]
                    for face in Self.faces {
                        guard cell[face] else { continue }
                        if face == "left" && x != 0 { continue }
                        if face == "back" && z != 0 { continue }
                        if face == "bottom" && y != 0 { continue }
                        guard let s = Self.faceStep[face] else { continue }
                        let touches = onPath.contains("\(x),\(y),\(z)") || onPath.contains("\(x + s.0),\(y + s.1),\(z + s.2)")
                        let isShell = (face == "left" && x == 0) || (face == "right" && x == c.w - 1)
                            || (face == "bottom" && y == 0) || (face == "top" && y == c.h - 1)
                            || (face == "back" && z == 0) || (face == "front" && z == c.d - 1)
                        let kind = touches ? "corridor" : (isShell ? "shell" : "quiet")
                        let cc = center(x, y, z, c)
                        let m = SCNVector3(cc.x + Float(s.0) * 0.5, cc.y + Float(s.1) * 0.5, cc.z + Float(s.2) * 0.5)
                        let corners: [SCNVector3]
                        if s.0 != 0 {
                            corners = [SCNVector3(m.x, m.y - half, m.z - half), SCNVector3(m.x, m.y + half, m.z - half),
                                       SCNVector3(m.x, m.y + half, m.z + half), SCNVector3(m.x, m.y - half, m.z + half)]
                        } else if s.1 != 0 {
                            corners = [SCNVector3(m.x - half, m.y, m.z - half), SCNVector3(m.x + half, m.y, m.z - half),
                                       SCNVector3(m.x + half, m.y, m.z + half), SCNVector3(m.x - half, m.y, m.z + half)]
                        } else {
                            corners = [SCNVector3(m.x - half, m.y - half, m.z), SCNVector3(m.x + half, m.y - half, m.z),
                                       SCNVector3(m.x + half, m.y + half, m.z), SCNVector3(m.x - half, m.y + half, m.z)]
                        }
                        quads[kind, default: []].append(contentsOf: corners)
                        if kind == "corridor" {
                            for i in 0..<4 { corridorEdges.append(corners[i]); corridorEdges.append(corners[(i + 1) % 4]) }
                        }
                    }
                }
            }
        }
        let styles: [(String, UIColor, CGFloat)] = [("quiet", Self.quiet, 0.16), ("shell", Self.shell, 0.26), ("corridor", Self.corridor, 0.5)]
        for (kind, color, opacity) in styles {
            guard let verts = quads[kind], !verts.isEmpty else { continue }
            let n = SCNNode(geometry: Self.quadGeometry(verts, material: Self.paneMaterial(color, opacity: opacity)))
            n.renderingOrder = 1
            root.addChildNode(n)
        }
        // Wireframe lattice: glowing outlines on the corridor panes plus the
        // cube's own bounding frame.
        if let edges = Self.lineGeometry(corridorEdges, color: Self.lattice, opacity: 0.35) {
            let n = SCNNode(geometry: edges); n.renderingOrder = 2; root.addChildNode(n)
        }
        let bx = Float(c.w) / 2, by = Float(c.h) / 2, bz = Float(c.d) / 2
        let b: [SCNVector3] = [
            SCNVector3(-bx, -by, -bz), SCNVector3(bx, -by, -bz), SCNVector3(bx, by, -bz), SCNVector3(-bx, by, -bz),
            SCNVector3(-bx, -by, bz), SCNVector3(bx, -by, bz), SCNVector3(bx, by, bz), SCNVector3(-bx, by, bz)
        ]
        let pairs = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
        if let frame = Self.lineGeometry(pairs.flatMap { [b[$0.0], b[$0.1]] }, color: Self.lattice, opacity: 0.55) {
            root.addChildNode(SCNNode(geometry: frame))
        }

        // Entrance / exit openings, same green/red as the BRPN maze markers.
        func opening(_ p: LEMACEngineASH.Perimeter3D, _ color: UIColor) -> SCNNode {
            let s = Self.faceStep[p.face] ?? (0, 0, 0)
            let cc = center(p.x, p.y, p.z, c)
            let sphere = SCNSphere(radius: 0.32)
            sphere.firstMaterial = Self.glowMaterial(color, intensity: 1.2)
            let n = SCNNode(geometry: sphere)
            n.position = SCNVector3(cc.x + Float(s.0) * 0.75, cc.y + Float(s.1) * 0.75, cc.z + Float(s.2) * 0.75)
            n.runAction(.repeatForever(.sequence([.scale(to: 1.25, duration: 0.8), .scale(to: 1.0, duration: 0.8)])))
            return n
        }
        root.addChildNode(opening(c.start, UIColor(red: 0, green: 1, blue: 0x88 / 255.0, alpha: 1)))
        root.addChildNode(opening(c.end, UIColor(red: 1, green: 0x44 / 255.0, blue: 0x66 / 255.0, alpha: 1)))
        return root
    }

    private func buildPath(_ c: LEMACEngineASH.CubicResult) -> SCNNode {
        let root = SCNNode()
        guard !solution.isEmpty else { return root }
        let pts = solution.map { center($0.x, $0.y, $0.z, c) }
        if pts.count > 1 {
            var segs: [SCNVector3] = []
            for i in 1..<pts.count { segs.append(pts[i - 1]); segs.append(pts[i]) }
            if let line = Self.lineGeometry(segs, color: Self.path, opacity: 0.7) {
                let n = SCNNode(geometry: line); n.renderingOrder = 3; root.addChildNode(n)
            }
        }
        let nodeGeo = SCNBox(width: 0.26, height: 0.26, length: 0.26, chamferRadius: 0.03)
        nodeGeo.firstMaterial = Self.glowMaterial(Self.path, intensity: 0.55)
        let eventGeo = SCNBox(width: 0.44, height: 0.44, length: 0.44, chamferRadius: 0.05)
        eventGeo.firstMaterial = Self.glowMaterial(Self.event, intensity: 1.0)
        let maxCount = max(1, eventCounts.max() ?? 1)
        for (i, p) in pts.enumerated() {
            let count = i < eventCounts.count ? eventCounts[i] : 0
            let n = SCNNode(geometry: count > 0 ? eventGeo : nodeGeo)
            n.position = p
            n.renderingOrder = 4
            if count > 0 {
                let base = 1 + 0.6 * CGFloat(count) / CGFloat(maxCount)
                n.scale = SCNVector3(Float(base), Float(base), Float(base))
                n.runAction(.repeatForever(.sequence([
                    .wait(duration: Double(i % 12) * 0.08),
                    .scale(to: base * 1.18, duration: 0.6),
                    .scale(to: base, duration: 0.6)
                ])))
            }
            root.addChildNode(n)
        }

        // Traveler: walks the solved path on a loop, like the Session Cube's
        // play mode, so the cube always reads as "live".
        if pts.count > 1 {
            let traveler = SCNNode(geometry: {
                let s = SCNSphere(radius: 0.3)
                s.firstMaterial = Self.glowMaterial(Self.head, intensity: 1.4)
                return s
            }())
            let halo = SCNNode(geometry: {
                let s = SCNSphere(radius: 0.62)
                let m = Self.glowMaterial(Self.path, intensity: 1)
                m.transparency = 0.45
                m.blendMode = .add
                m.writesToDepthBuffer = false
                s.firstMaterial = m
                return s
            }())
            halo.runAction(.repeatForever(.sequence([.scale(to: 1.2, duration: 0.31), .scale(to: 0.95, duration: 0.31)])))
            traveler.addChildNode(halo)
            traveler.position = pts[0]
            traveler.renderingOrder = 10
            let step = 1.0 / 14.0
            var moves: [SCNAction] = pts.dropFirst().map { .move(to: $0, duration: step) }
            moves.append(.wait(duration: 0.8))
            moves.append(.move(to: pts[0], duration: 0))
            traveler.runAction(.repeatForever(.sequence(moves)))
            root.addChildNode(traveler)
        }
        return root
    }

    // MARK: — Geometry / materials

    static func paneMaterial(_ color: UIColor, opacity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color.withAlphaComponent(0.35)
        m.transparency = opacity
        m.blendMode = .alpha
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        return m
    }

    static func glowMaterial(_ color: UIColor, intensity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color
        m.emission.intensity = intensity
        return m
    }

    static func quadGeometry(_ verts: [SCNVector3], material: SCNMaterial) -> SCNGeometry {
        var indices: [Int32] = []
        indices.reserveCapacity(verts.count / 4 * 6)
        var q: Int32 = 0
        while Int(q) + 3 < verts.count {
            indices.append(contentsOf: [q, q + 1, q + 2, q, q + 2, q + 3])
            q += 4
        }
        let src = SCNGeometrySource(vertices: verts)
        let el = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let g = SCNGeometry(sources: [src], elements: [el])
        g.materials = [material]
        return g
    }

    static func lineGeometry(_ verts: [SCNVector3], color: UIColor, opacity: CGFloat) -> SCNGeometry? {
        guard verts.count >= 2 else { return nil }
        let indices: [Int32] = (0..<Int32(verts.count)).map { $0 }
        let src = SCNGeometrySource(vertices: verts)
        let el = SCNGeometryElement(indices: indices, primitiveType: .line)
        let g = SCNGeometry(sources: [src], elements: [el])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color
        m.transparency = opacity
        m.blendMode = .add
        m.writesToDepthBuffer = false
        g.materials = [m]
        return g
    }
}
