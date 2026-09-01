import SwiftUI
import SceneKit
import AutumnServices
import LEATRCore

/// MIST overlay — js/mist-module.js generateMaze/solveMaze 2D + LEMAC cubic sigma.
public struct MISTOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @ObservedObject private var mist = MISTModule.shared
    @State private var difficulty = 1
    @State private var status = "DRAG ● FROM ENTRY TO EXIT"
    @State private var maze: MazeEngine.MistMaze?
    @State private var dragPath: [MazeEngine.MistPt] = []
    @State private var dragging = false
    @State private var cubicMode = false
    @StateObject private var cubeVM = LEMACCubeViewModel()

    public var body: some View {
        OverlayPanel(title: "MIST · LEAD EDGE MAZE", onClose: { appNav.rightTab = .none }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach([1, 2, 3], id: \.self) { d in
                        Button(d == 1 ? "★ STAR" : d == 2 ? "♥ HEART" : "◈ MIST") {
                            difficulty = d
                            newMaze()
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .foregroundColor(difficulty == d ? Color(hex: "#00e5ff") : .white.opacity(0.45))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#00e5ff").opacity(difficulty == d ? 0.6 : 0.2), lineWidth: 1))
                    }
                }

                HStack(spacing: 6) {
                    Button("2D") { cubicMode = false; newMaze() }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(!cubicMode ? Color.cyan : .white.opacity(0.45))
                    Button("CUBE") { cubicMode = true; cubeVM.generate(difficulty: difficulty) }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(cubicMode ? Color.cyan : .white.opacity(0.45))
                    Spacer()
                    Text("DIFF \(["", "I", "II", "III"][difficulty])")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }

                if cubicMode {
                    LEMACCubeKitView(vm: cubeVM)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if let maze {
                    MistMazeCanvas(maze: maze, dragPath: dragPath, onDrag: handleDrag)
                        .frame(height: 180)
                }

                HStack(spacing: 8) {
                    Button("⬡ SIGMA SOLVE") {
                        if cubicMode {
                            // JS: ASH_MAZE_solvePath → LEMAC_ENGINE_ASH.solveCubic (degree-map sigma)
                            cubeVM.sigmaSolve()
                            mist.emitSolve(uid: authVM.sessionUID, slot: difficulty)
                            sceneVM.emitMist(fromLocal: true)
                            status = "SIGMA REMAINDER"
                        } else if var m = maze, let sol = MazeEngine.solveMaze(m) {
                            dragPath = sol
                            m.solved = true
                            maze = m
                            mist.emitSolve(uid: authVM.sessionUID, slot: difficulty)
                            sceneVM.emitMist(fromLocal: true)
                            status = "✓ PATH"
                        }
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.cyan.opacity(0.1))
                    .clipShape(Capsule())

                    Button("NEW MAZE") {
                        newMaze()
                        status = "DRAG ● FROM ENTRY TO EXIT"
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }

                Text("PRESENCE · \(mist.activeSignals.count) LIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.7))
                Text(status)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.5))
            }
            .padding(12)
        }
        .onAppear { newMaze() }
        .task {
            await mist.refresh()
            sceneVM.rebuildSplines()
        }
    }

    private func newMaze() {
        if cubicMode {
            cubeVM.generate(difficulty: difficulty)
            return
        }
        let cfg = MazeEngine.mistDIFF[difficulty] ?? (5, 5)
        maze = MazeEngine.generateMaze(cfg.w, cfg.h)
        dragPath = []
        dragging = false
    }

    private func handleDrag(_ cell: MazeEngine.MistPt, _ ended: Bool) {
        guard var m = maze, !m.solved else { return }
        if !dragging {
            if cell.x == m.entry.x && cell.y == m.entry.y {
                dragging = true
                dragPath = [cell]
                status = "NAVIGATE TO ◉ EXIT"
            }
            return
        }
        if ended {
            dragging = false
            if !m.solved {
                dragPath = []
                status = "DRAG ● FROM ENTRY TO EXIT"
            }
            return
        }
        guard let prev = dragPath.last else { return }
        if cell.x == prev.x && cell.y == prev.y { return }
        let dx = cell.x - prev.x, dy = cell.y - prev.y
        if abs(dx) + abs(dy) != 1 { return }
        let wd = dx == 1 ? "e" : dx == -1 ? "w" : dy == 1 ? "s" : "n"
        if m.grid[prev.y][prev.x][wd] != 0 { return }
        if dragPath.count >= 2, dragPath[dragPath.count - 2].x == cell.x && dragPath[dragPath.count - 2].y == cell.y {
            dragPath.removeLast()
        } else {
            dragPath.append(cell)
        }
        if cell.x == m.exit.x && cell.y == m.exit.y {
            dragging = false
            m.solved = true
            maze = m
            status = "✓ WELL DONE"
            mist.emitSolve(uid: authVM.sessionUID, slot: difficulty)
            sceneVM.emitMist(fromLocal: true)
        }
    }
}

/// JS: _renderMaze — cyan walls with ticks, entry green, exit cyan glow
struct MistMazeCanvas: View {
    let maze: MazeEngine.MistMaze
    let dragPath: [MazeEngine.MistPt]
    var onDrag: (MazeEngine.MistPt, Bool) -> Void

    var body: some View {
        Canvas { ctx, size in
            let cs = min(size.width / CGFloat(maze.w), size.height / CGFloat(maze.h))
            for y in 0..<maze.h {
                for x in 0..<maze.w {
                    let cell = maze.grid[y][x]
                    let px = CGFloat(x) * cs, py = CGFloat(y) * cs
                    func wall(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
                        var fat = Path(); fat.move(to: CGPoint(x: x1, y: y1)); fat.addLine(to: CGPoint(x: x2, y: y2))
                        ctx.stroke(fat, with: .color(Color(red: 0, green: 229/255, blue: 1).opacity(0.45)), lineWidth: cs * 0.35)
                        ctx.stroke(fat, with: .color(Color(red: 0, green: 229/255, blue: 1).opacity(0.9)), lineWidth: 1)
                        for i in 0...4 {
                            let t = CGFloat(i) / 4
                            let rx = x1 + (x2 - x1) * t, ry = y1 + (y2 - y1) * t
                            let rxD = (y2 - y1) * 0.12, ryD = -(x2 - x1) * 0.12
                            var tick = Path(); tick.move(to: CGPoint(x: rx - rxD, y: ry - ryD)); tick.addLine(to: CGPoint(x: rx + rxD, y: ry + ryD))
                            ctx.stroke(tick, with: .color(Color(red: 0, green: 229/255, blue: 1).opacity(0.9)), lineWidth: 1)
                        }
                    }
                    if cell.n != 0 { wall(px, py, px + cs, py) }
                    if cell.s != 0 { wall(px, py + cs, px + cs, py + cs) }
                    if cell.w != 0 { wall(px, py, px, py + cs) }
                    if cell.e != 0 { wall(px + cs, py, px + cs, py + cs) }
                    let dot = Path(ellipseIn: CGRect(x: px - 1, y: py - 1, width: 2, height: 2))
                    ctx.fill(dot, with: .color(Color(red: 0, green: 229/255, blue: 1).opacity(0.25)))
                }
            }
            if dragPath.count > 1 {
                var p = Path()
                p.move(to: CGPoint(x: CGFloat(dragPath[0].x) * cs + cs / 2, y: CGFloat(dragPath[0].y) * cs + cs / 2))
                for pt in dragPath {
                    p.addLine(to: CGPoint(x: CGFloat(pt.x) * cs + cs / 2, y: CGFloat(pt.y) * cs + cs / 2))
                }
                ctx.stroke(p, with: .color(Color(red: 0, green: 1, blue: 136/255).opacity(0.6)), style: StrokeStyle(lineWidth: cs * 0.22, lineCap: .round, lineJoin: .round))
            }
            let ex = CGFloat(maze.exit.x) * cs + cs / 2
            let ey = CGFloat(maze.exit.y) * cs + cs / 2
            ctx.fill(Path(ellipseIn: CGRect(x: ex - cs * 0.35, y: ey - cs * 0.35, width: cs * 0.7, height: cs * 0.7)),
                     with: .color(Color(red: 0, green: 229/255, blue: 1).opacity(0.55)))
            let last = dragPath.last ?? maze.entry
            let bx = CGFloat(last.x) * cs + cs / 2
            let by = CGFloat(last.y) * cs + cs / 2
            let fill = maze.solved ? Color(red: 0, green: 1, blue: 136/255) : Color(red: 0, green: 1, blue: 136/255).opacity(0.95)
            ctx.fill(Path(ellipseIn: CGRect(x: bx - cs * 0.4, y: by - cs * 0.4, width: cs * 0.8, height: cs * 0.8)), with: .color(fill))
        }
        .background(Color.black.opacity(0.2))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let cs = min(220, 220) // cell mapping uses actual size via preference
                    _ = cs
                    // Use a GeometryReader wrapper instead — handled below via overlay
                }
        )
        .overlay(MistDragCatcher(w: maze.w, h: maze.h, onDrag: onDrag))
    }
}

struct MistDragCatcher: View {
    let w: Int, h: Int
    var onDrag: (MazeEngine.MistPt, Bool) -> Void
    var body: some View {
        GeometryReader { geo in
            Color.clear.contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let csW = geo.size.width / CGFloat(w)
                            let csH = geo.size.height / CGFloat(h)
                            let x = min(max(0, Int(v.location.x / csW)), w - 1)
                            let y = min(max(0, Int(v.location.y / csH)), h - 1)
                            onDrag(MazeEngine.MistPt(x: x, y: y), false)
                        }
                        .onEnded { _ in
                            onDrag(MazeEngine.MistPt(x: 0, y: 0), true)
                        }
                )
        }
    }
}

// MARK: — LEMAC cubic studio cube (generateCubic + solveCubic sigma)
final class LEMACCubeViewModel: ObservableObject {
    let scene = SCNScene()
    private var root = SCNNode()
    private var result: LEMACEngineASH.CubicResult?
    private var pathNodes: [SCNNode] = []
    private var solveStep = 0
    var isSolving = false

    func generate(difficulty: Int) {
        let n = difficulty == 1 ? 5 : difficulty == 2 ? 7 : 9
        scene.rootNode.childNodes.filter { $0.name != "lemacCam" }.forEach { $0.removeFromParentNode() }
        root = SCNNode()
        scene.rootNode.addChildNode(root)
        scene.background.contents = UIColor.clear
        let amb = SCNNode()
        amb.light = { let l = SCNLight(); l.type = .ambient; l.intensity = 400; return l }()
        scene.rootNode.addChildNode(amb)

        let mr = LEMACEngineASH.generateCubic(n, n, n)
        result = mr
        let u: Float = 0.22
        let verts = MazeEngine.orbMazeWallVerts(grid: mr.grid, w: n, h: n, d: n, u: u)
        if let wall = ThreeJSGeometry.lineSegments(verts, color: ThreeJSGeometry.hex(0x00ffcc), opacity: 0.55) {
            root.addChildNode(wall)
        }
        // Markers
        func pos(_ t: LEMACEngineASH.Perimeter3D) -> SCNVector3 {
            let ox = Float(n) * u / 2, oy = Float(n) * u / 2, oz = Float(n) * u / 2
            return SCNVector3(Float(t.x) * u - ox + u / 2, Float(t.y) * u - oy + u / 2, Float(t.z) * u - oz + u / 2)
        }
        let sg = SCNSphere(radius: CGFloat(u * 0.35)); sg.segmentCount = 6
        sg.materials = [ThreeJSGeometry.basicMat(ThreeJSGeometry.hex(0x00d9ff), opacity: 1)]
        let sn = SCNNode(geometry: sg); sn.position = pos(mr.start); root.addChildNode(sn)
        let eg = SCNSphere(radius: CGFloat(u * 0.35)); eg.segmentCount = 6
        eg.materials = [ThreeJSGeometry.basicMat(ThreeJSGeometry.hex(0xff0000), opacity: 1)]
        let en = SCNNode(geometry: eg); en.position = pos(mr.end); root.addChildNode(en)

        pathNodes.removeAll()
        solveStep = 0
        isSolving = false
        root.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0.15, y: 0.4, z: 0, duration: 8)))
    }

    func sigmaSolve() {
        guard let mr = result else { return }
        pathNodes.forEach { $0.removeFromParentNode() }
        pathNodes.removeAll()
        // JS: LEMAC_ENGINE_ASH.solveCubic — degree-map sigma prune, NOT BFS
        let ordered = LEMACEngineASH.solveCubic(mr)
        let n = mr.w
        let u: Float = 0.22
        let ox = Float(n) * u / 2, oy = Float(n) * u / 2, oz = Float(n) * u / 2
        for p in ordered {
            let g = SCNSphere(radius: CGFloat(u * 0.16)); g.segmentCount = 4
            g.materials = [ThreeJSGeometry.basicMat(ThreeJSGeometry.hex(0x00d9ff), opacity: 0.95)]
            let node = SCNNode(geometry: g)
            node.position = SCNVector3(Float(p.x) * u - ox + u / 2, Float(p.y) * u - oy + u / 2, Float(p.z) * u - oz + u / 2)
            root.addChildNode(node)
            pathNodes.append(node)
        }
    }
}

struct LEMACCubeKitView: UIViewRepresentable {
    @ObservedObject var vm: LEMACCubeViewModel
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = vm.scene
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = true
        v.backgroundColor = .clear
        v.isOpaque = false
        v.antialiasingMode = .multisampling2X
        let cam = SCNCamera(); cam.fieldOfView = 50
        let n = SCNNode(); n.name = "lemacCam"; n.camera = cam; n.position = SCNVector3(0, 0.4, 3.2); n.look(at: SCNVector3(0,0,0))
        vm.scene.rootNode.addChildNode(n)
        v.pointOfView = n
        return v
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
