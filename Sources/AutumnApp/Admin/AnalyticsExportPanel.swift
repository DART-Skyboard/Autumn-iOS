import SwiftUI
import SceneKit
import LEATRCore
import AutumnServices

public struct AnalyticsExportPanel: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @StateObject private var maze = AnalyticsExportMaze.shared
    @State private var showGenerateInline = false
    @State private var genWidth = "10"
    @State private var genHeight = "10"
    @State private var genDepth = "10"
    @State private var isSolving = false
    @State private var animateSolveStep = 0
    @State private var animTimer: Timer?
    @State private var exportMode: ExportMode = .session
    @State private var rangeStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var rangeEnd = Date()
    @State private var isExporting = false
    @State private var exportStatus = ""
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false

    enum ExportMode: String, CaseIterable { case session = "THIS SESSION", range = "DATE RANGE" }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                MazeOrbitSceneView(maze: maze, isSolving: $isSolving, revealCount: $animateSolveStep)
                    .frame(height: 260)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(themeVM.chrome.accent.opacity(0.25), lineWidth: 1))

                HStack(spacing: 14) {
                    Button {
                        isSolving = true
                        animateSolveStep = maze.solutionCells().count
                    } label: {
                        Label("INSTANT SOLVE", systemImage: "bolt.fill")
                    }
                    Button {
                        startAnimatedSolve()
                    } label: {
                        Label("ANIMATED", systemImage: "play.fill")
                    }
                    Button {
                        isSolving = false
                        animTimer?.invalidate()
                        animateSolveStep = 0
                    } label: {
                        Label("HIDE", systemImage: "eye.slash")
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(themeVM.chrome.accent)

                Button {
                    withAnimation { showGenerateInline.toggle() }
                    genWidth = "\(maze.width)"; genHeight = "\(maze.height)"; genDepth = "\(maze.depth)"
                } label: {
                    Label(showGenerateInline ? "CANCEL" : "GENERATE NEW MAZE", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#ff9d6a"))

                // TF158: inline on the same frosted panel now, no separate
                // sheet, and no Face ID step — a plain in-panel action per
                // direct instruction.
                if showGenerateInline {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("New dimensions (\(AnalyticsExportMaze.minDimension)–\(AnalyticsExportMaze.maxDimension) per axis)")
                            .font(.system(size: 10)).foregroundColor(.white.opacity(0.55))
                        HStack(spacing: 8) {
                            dimField("W", $genWidth)
                            dimField("H", $genHeight)
                            dimField("D", $genDepth)
                        }
                        Button("GENERATE") {
                            let w = Int(genWidth) ?? 10, h = Int(genHeight) ?? 10, d = Int(genDepth) ?? 10
                            maze.regenerate(width: w, height: h, depth: d)
                            isSolving = false; animateSolveStep = 0
                            showGenerateInline = false
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(themeVM.chrome.accent)
                        .cornerRadius(6)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }

                Divider().background(Color.white.opacity(0.15))

                exportCard
            }
            .padding(14)
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportedFileURL { ShareSheet(items: [exportedFileURL]) }
        }
    }

    private func dimField(_ label: String, _ binding: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            TextField("", text: binding)
                .keyboardType(.numberPad)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .padding(6)
                .background(Color.black.opacity(0.3))
                .cornerRadius(6)
                .frame(width: 50)
        }
    }

    private func startAnimatedSolve() {
        animTimer?.invalidate()
        isSolving = true
        animateSolveStep = 0
        let path = maze.solutionCells()
        guard !path.isEmpty else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
            DispatchQueue.main.async {
                animateSolveStep += 1
                if animateSolveStep >= path.count { t.invalidate() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REAL-TIME SCENE ANALYTICS").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(themeVM.chrome.accent)
            Text(headerSubtitle).font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
        }
    }

    private var headerSubtitle: String {
        let genStr = maze.generatedAt.map { relDate($0) } ?? "—"
        return "Fixed \(maze.width)×\(maze.height)×\(maze.depth) cube — generated \(genStr). Regenerates automatically on a fresh sign-in."
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXPORT").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            Picker("", selection: $exportMode) {
                ForEach(ExportMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if exportMode == .range {
                DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                DatePicker("To", selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)
                    .font(.system(size: 12))
            }
            Button {
                Task { await runExport() }
            } label: {
                if isExporting {
                    HStack { ProgressView().tint(.white); Text("EXPORTING…") }
                } else {
                    Label("EXPORT ANALYTICS (.zip)", systemImage: "square.and.arrow.down")
                }
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.vertical, 8).frame(maxWidth: .infinity)
            .background(themeVM.chrome.accent.opacity(0.25))
            .cornerRadius(8)
            .disabled(isExporting)
            if !exportStatus.isEmpty {
                Text(exportStatus).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func relDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    /// The cube is the full container/casing for the export — every
    /// (x,y,z) cell in the grid is addressable storage, described in full
    /// (its wall state) so the JSON genuinely represents the whole
    /// three-dimensional allocation, not just the path. The solution path
    /// is layered on top as the fast-access index into that container —
    /// entrance and exit openings included as real markers, and the
    /// actual analytics events nested one-per-path-cell in chronological
    /// order (grouping onto the last cells when there are more events
    /// than path cells) — "the icing at the very core," a quick way to
    /// reach exactly the data a given research pass needs without
    /// scanning the whole cube.
    private func runExport() async {
        isExporting = true
        exportStatus = "Gathering analytics…"
        let events = exportMode == .session
            ? AnalyticsEventLogger.shared.eventsThisSession()
            : await AnalyticsEventLogger.shared.fetchRange(from: rangeStart, to: rangeEnd)

        let path = maze.solutionCells()
        var cellBuckets: [[AnalyticsEvent]] = Array(repeating: [], count: max(path.count, 1))
        if !path.isEmpty {
            for (i, event) in events.enumerated() {
                let idx = min(i * path.count / max(events.count, 1), path.count - 1)
                cellBuckets[idx].append(event)
            }
        }

        var pathJSON: [[String: Any]] = []
        for (i, pt) in path.enumerated() {
            let cellEvents = cellBuckets[i].map { e -> [String: Any] in
                var d: [String: Any] = ["ts": ISO8601DateFormatter().string(from: e.ts), "category": e.category, "label": e.label]
                if let detail = e.detail { d["detail"] = detail }
                return d
            }
            pathJSON.append(["order": i, "x": pt.x, "y": pt.y, "z": pt.z, "events": cellEvents])
        }

        func openingJSON(_ p: LEMACEngineASH.Perimeter3D?) -> Any {
            guard let p else { return NSNull() }
            return ["x": p.x, "y": p.y, "z": p.z, "face": p.face]
        }

        // Full cube container: every cell's wall state, addressable by
        // (x,y,z) — the casing around the path index above.
        var cubeCells: [[String: Any]] = []
        if let grid = maze.cubic?.grid {
            for z in 0..<maze.depth {
                for y in 0..<maze.height {
                    for x in 0..<maze.width {
                        let c = grid[z][y][x]
                        cubeCells.append([
                            "x": x, "y": y, "z": z,
                            "walls": ["top": c.top, "bottom": c.bottom, "left": c.left, "right": c.right, "front": c.front, "back": c.back]
                        ])
                    }
                }
            }
        }

        let root: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "mode": exportMode.rawValue,
            "rangeStart": exportMode == .range ? ISO8601DateFormatter().string(from: rangeStart) : NSNull(),
            "rangeEnd": exportMode == .range ? ISO8601DateFormatter().string(from: rangeEnd) : NSNull(),
            "cube": [
                "width": maze.width, "height": maze.height, "depth": maze.depth,
                "generatedAt": maze.generatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                "entrance": openingJSON(maze.startOpening),
                "exit": openingJSON(maze.endOpening),
                "cells": cubeCells
            ],
            "pathIndex": pathJSON,
            "totalEvents": events.count
        ]

        guard JSONSerialization.isValidJSONObject(root),
              let jsonData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
        else {
            exportStatus = "Export failed — could not serialize."
            isExporting = false
            return
        }

        exportStatus = "Compressing…"
        let zipData = MiniZip.write(entries: [.init(name: "analytics-export.json", data: jsonData)])
        let fileName = "autumn-analytics-\(Int(Date().timeIntervalSince1970)).zip"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try zipData.write(to: url)
            exportedFileURL = url
            exportStatus = "\(events.count) events, \(cubeCells.count) cube cells — \(zipData.count / 1024) KB."
            showShareSheet = true
        } catch {
            exportStatus = "Export failed writing file."
        }
        isExporting = false
    }
}

/// Real per-cell wall + passage wireframe, matching exactly how the live
/// BRPN scene's own maze renders (same MazeEngine.cubicShellAndPassageVerts
/// call, same ThreeJSGeometry.lineSegments, same green/red start/end
/// markers) — copied and made independent, not reimplemented differently.
struct MazeOrbitSceneView: UIViewRepresentable {
    let maze: AnalyticsExportMaze
    @Binding var isSolving: Bool
    @Binding var revealCount: Int

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = SCNScene()
        v.backgroundColor = .clear
        v.autoenablesDefaultLighting = true
        v.allowsCameraControl = true
        rebuild(v, context: context)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        rebuild(v, context: context)
    }

    private func rebuild(_ v: SCNView, context: Context) {
        let signature = "\(maze.width)x\(maze.height)x\(maze.depth)-\(maze.generatedAt?.timeIntervalSince1970 ?? 0)"
        let revealChanged = context.coordinator.lastReveal != revealCount || context.coordinator.lastSolving != isSolving
        guard context.coordinator.lastSignature != signature || revealChanged else { return }
        let structureChanged = context.coordinator.lastSignature != signature
        context.coordinator.lastSignature = signature
        context.coordinator.lastReveal = revealCount
        context.coordinator.lastSolving = isSolving

        guard let cubic = maze.cubic else { return }
        let u: Float = 0.11
        let w = maze.width, h = maze.height, d = maze.depth

        if structureChanged || v.scene?.rootNode.childNode(withName: "mazeRoot", recursively: false) == nil {
            let scene = SCNScene()
            let root = SCNNode()
            root.name = "mazeRoot"
            scene.rootNode.addChildNode(root)

            let pair = MazeEngine.cubicShellAndPassageVerts(
                grid: cubic.grid, w: w, h: h, d: d, u: u,
                openings: [
                    (cubic.start.x, cubic.start.y, cubic.start.z, cubic.start.face),
                    (cubic.end.x, cubic.end.y, cubic.end.z, cubic.end.face)
                ]
            )
            if let shell = ThreeJSGeometry.lineSegments(pair.shell, color: ThreeJSGeometry.hex(0x00ffcc), opacity: 0.9) {
                shell.name = "mazeShell"
                root.addChildNode(shell)
            }
            if let passages = ThreeJSGeometry.lineSegments(pair.passages, color: ThreeJSGeometry.hex(0x00d9ff), opacity: 0.4) {
                passages.name = "mazePassages"
                root.addChildNode(passages)
            }

            func openingPos(_ p: LEMACEngineASH.Perimeter3D) -> SCNVector3 {
                var c = MazeEngine.orbCellCenter(x: p.x, y: p.y, z: p.z, w: w, h: h, d: d, u: u)
                let bump = u * 0.45
                switch p.face {
                case "left": c.0 -= bump
                case "right": c.0 += bump
                case "bottom": c.1 -= bump
                case "top": c.1 += bump
                case "back": c.2 -= bump
                default: c.2 += bump
                }
                return SCNVector3(c.0, c.1, c.2)
            }
            let startNode = SCNNode(geometry: SCNSphere(radius: CGFloat(u * 0.32)))
            startNode.geometry?.materials = [ThreeJSGeometry.basicMat(ThreeJSGeometry.hex(0x00ff88), opacity: 1)]
            startNode.position = openingPos(cubic.start)
            root.addChildNode(startNode)
            let endNode = SCNNode(geometry: SCNSphere(radius: CGFloat(u * 0.32)))
            endNode.geometry?.materials = [ThreeJSGeometry.basicMat(ThreeJSGeometry.hex(0xff4466), opacity: 1)]
            endNode.position = openingPos(cubic.end)
            root.addChildNode(endNode)

            let path = maze.solutionCells()
            for pt in path {
                let sphere = SCNSphere(radius: CGFloat(u * 0.2))
                sphere.materials = [ThreeJSGeometry.basicMat(ThreeJSGeometry.hex(0x00ffff), opacity: 0)]
                let node = SCNNode(geometry: sphere)
                let c = MazeEngine.orbCellCenter(x: pt.x, y: pt.y, z: pt.z, w: w, h: h, d: d, u: u)
                node.position = SCNVector3(c.0, c.1, c.2)
                node.name = "pathNode"
                root.addChildNode(node)
            }

            let cam = SCNCamera()
            let camNode = SCNNode()
            camNode.camera = cam
            camNode.position = SCNVector3(0, 0, u * Float(max(w, h, d)) * 2.2)
            scene.rootNode.addChildNode(camNode)
            v.pointOfView = camNode
            v.scene = scene
        }

        // Reveal/hide path nodes up to revealCount — instant solve sets
        // revealCount to the full path length at once; animated solve
        // steps it up over time via a Timer in the panel above.
        guard let root = v.scene?.rootNode.childNode(withName: "mazeRoot", recursively: false) else { return }
        let pathNodes = root.childNodes.filter { $0.name == "pathNode" }
        for (i, node) in pathNodes.enumerated() {
            let visible = isSolving && i < revealCount
            node.geometry?.firstMaterial?.transparency = visible ? 1 : 0
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var lastSignature = ""
        var lastReveal = -1
        var lastSolving = false
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
