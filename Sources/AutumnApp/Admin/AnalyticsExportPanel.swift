import SwiftUI
import SceneKit
import LEATRCore
import AutumnServices

public struct AnalyticsExportPanel: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @StateObject private var maze = AnalyticsExportMaze.shared
    @StateObject private var liveFeed = LiveFeedController.shared
    @State private var showGenerateInline = false
    @State private var genWidth = "10"
    @State private var genHeight = "10"
    @State private var genDepth = "10"
    @State private var showLiveGenerateInline = false
    @State private var liveGenWidth = "10"
    @State private var liveGenHeight = "10"
    @State private var liveGenDepth = "10"
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

    enum ExportMode: String, CaseIterable { case session = "THIS SESSION", range = "DATE RANGE", live = "LIVE FEED" }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                liveFeedCard

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

    /// TF161: separate from the manual maze/export above entirely — its
    /// own master maze, its own toggle, its own chunk stream. Turning this
    /// on writes the shared flag every active session checks, so this
    /// isn't a "record what I do" switch, it's "the sentient journal is
    /// active" for everyone, matching what was actually asked for.
    private var liveFeedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LIVE FEED").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { liveFeed.isEnabled },
                    set: { newValue in Task { await liveFeed.setEnabled(newValue) } }
                ))
                .labelsHidden()
                .tint(Color(hex: "#6dff9e"))
            }
            Text(liveFeed.isEnabled
                 ? "Active — collecting from every signed-in session, chunk \(liveFeed.currentChunkIndex) (\(liveFeed.currentChunkBytes / 1024) KB). Closes at 5 MB and starts a new chunk automatically."
                 : "Stopped. It's on by default the moment anyone signs in — this only pauses collection; resuming continues the same master maze and chunk position, it doesn't start fresh.")
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.5))

            if liveFeed.masterMaze != nil {
                Text("Master maze: \(liveFeed.masterMazeWidth)×\(liveFeed.masterMazeHeight)×\(liveFeed.masterMazeDepth) — \(liveFeed.masterMazeId)")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            }

            Button {
                withAnimation { showLiveGenerateInline.toggle() }
                liveGenWidth = "\(liveFeed.masterMazeWidth)"; liveGenHeight = "\(liveFeed.masterMazeHeight)"; liveGenDepth = "\(liveFeed.masterMazeDepth)"
            } label: {
                Label(showLiveGenerateInline ? "CANCEL" : "NEW MASTER MAZE", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(Color(hex: "#ff9d6a"))

            if showLiveGenerateInline {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Replaces the master maze — existing chunks stay under the old one; a fresh chunk stream starts under the new one.")
                        .font(.system(size: 9)).foregroundColor(.white.opacity(0.45))
                    HStack(spacing: 8) {
                        dimField("W", $liveGenWidth); dimField("H", $liveGenHeight); dimField("D", $liveGenDepth)
                    }
                    Button("GENERATE") {
                        let w = Int(liveGenWidth) ?? 10, h = Int(liveGenHeight) ?? 10, d = Int(liveGenDepth) ?? 10
                        Task { await liveFeed.regenerateMasterMaze(width: w, height: h, depth: d) }
                        showLiveGenerateInline = false
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color(hex: "#6dff9e"))
                    .cornerRadius(6)
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXPORT").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            Picker("", selection: $exportMode) {
                ForEach(ExportMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if exportMode == .range || exportMode == .live {
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
    /// TF159: even distribution first assigns events round-robin across
    /// path cells, same as before. What's new is what happens when a
    /// session/range genuinely has more events than reasonably belongs in
    /// one cell's entry — rather than letting one cell's JSON balloon
    /// arbitrarily, overflow spills into a new *layer*: a second full pass
    /// through the same path structure, stacked under the first, and a
    /// third if that also fills, and so on. This is a deliberate,
    /// simplified stand-in for "let dense stretches spread into the
    /// maze's own dead-end branches" — actually tracing which off-path
    /// cells are reachable near a given path point (a real walled-maze
    /// flood-fill) is a substantially larger piece of work on its own;
    /// layering the same path repeatedly captures the same real intent —
    /// nothing gets dropped or truncated when volume is high, nesting
    /// grows in an orderly, addressable way instead — without that
    /// separate undertaking. Worth flagging plainly rather than silently
    /// presenting this as the literal geometric version.
    private let perCellCapacity = 25

    private func runExport() async {
        isExporting = true
        exportStatus = "Gathering analytics…"
        let events: [AnalyticsEvent]
        var pathSource: [MazePt]
        var cubeForExport: LEMACEngineASH.CubicResult?
        var startOpeningForExport: LEMACEngineASH.Perimeter3D?
        var endOpeningForExport: LEMACEngineASH.Perimeter3D?
        var dimsForExport = (maze.width, maze.height, maze.depth)

        switch exportMode {
        case .session:
            events = AnalyticsEventLogger.shared.eventsThisSession()
            pathSource = maze.solutionCells()
            cubeForExport = maze.cubic; startOpeningForExport = maze.startOpening; endOpeningForExport = maze.endOpening
        case .range:
            events = await AnalyticsEventLogger.shared.fetchRange(from: rangeStart, to: rangeEnd)
            pathSource = maze.solutionCells()
            cubeForExport = maze.cubic; startOpeningForExport = maze.startOpening; endOpeningForExport = maze.endOpening
        case .live:
            // TF161: compiles the live feed's own chunk files under its
            // own master maze — a genuinely different data source and
            // structure from the manual export above, per direct
            // instruction that these stay independent.
            events = await fetchLiveFeedEvents(from: rangeStart, to: rangeEnd)
            if let cubic = liveFeed.masterMaze {
                pathSource = LEMACEngineASH.solveCubic(cubic)
                cubeForExport = cubic; startOpeningForExport = cubic.start; endOpeningForExport = cubic.end
                dimsForExport = (liveFeed.masterMazeWidth, liveFeed.masterMazeHeight, liveFeed.masterMazeDepth)
            } else {
                pathSource = []
            }
        }
        let path = pathSource

        // TF160: was pure chronological round-robin — the actual ask is
        // that events of the SAME occurrence type stay grouped together
        // as they fill the path, with a new layer (depth) only starting
        // when the current one genuinely runs out of room — not that
        // different types get interleaved by raw arrival time. Groups
        // events by (category,label) first, keeping group order to each
        // type's own first real occurrence (so the layering still
        // reflects the actual order of operations/patterns as they first
        // appeared), then feeds that grouped sequence through the same
        // path-filling/overflow logic. Same-type events land contiguously
        // along the path and, if one type alone has more events than the
        // path can hold, its own overflow continues into the next layer
        // before the next type begins — exactly "start back at the top on
        // a new layer for the next category" rather than everything
        // reshuffled by time.
        var groupOrder: [String] = []
        var groups: [String: [AnalyticsEvent]] = [:]
        for event in events {
            let key = "\(event.category):\(event.label)"
            if groups[key] == nil { groupOrder.append(key); groups[key] = [] }
            groups[key]?.append(event)
        }
        let groupedEvents = groupOrder.flatMap { groups[$0] ?? [] }

        // layers[layerIndex][cellIndex] = events assigned to that cell in that layer
        var layers: [[[AnalyticsEvent]]] = path.isEmpty ? [] : [Array(repeating: [], count: path.count)]
        if !path.isEmpty {
            for (i, event) in groupedEvents.enumerated() {
                let cellIdx = min(i * path.count / max(groupedEvents.count, 1), path.count - 1)
                var layerIdx = 0
                while layers[layerIdx][cellIdx].count >= perCellCapacity {
                    layerIdx += 1
                    if layerIdx == layers.count { layers.append(Array(repeating: [], count: path.count)) }
                }
                layers[layerIdx][cellIdx].append(event)
            }
        }

        func eventJSON(_ e: AnalyticsEvent) -> [String: Any] {
            var d: [String: Any] = ["ts": ISO8601DateFormatter().string(from: e.ts), "category": e.category, "label": e.label]
            if let detail = e.detail { d["detail"] = detail }
            return d
        }

        var pathLayersJSON: [[String: Any]] = []
        for (layerIdx, cells) in layers.enumerated() {
            var pathJSON: [[String: Any]] = []
            for (i, pt) in path.enumerated() {
                pathJSON.append(["order": i, "x": pt.x, "y": pt.y, "z": pt.z, "events": cells[i].map(eventJSON)])
            }
            pathLayersJSON.append(["layer": layerIdx, "path": pathJSON])
        }

        func openingJSON(_ p: LEMACEngineASH.Perimeter3D?) -> Any {
            guard let p else { return NSNull() }
            return ["x": p.x, "y": p.y, "z": p.z, "face": p.face]
        }

        // Full cube container: every cell's wall state, addressable by
        // (x,y,z) — the casing around the path index above. Uses whichever
        // maze this export mode actually pulled from (manual or live).
        var cubeCells: [[String: Any]] = []
        if let grid = cubeForExport?.grid {
            for z in 0..<dimsForExport.2 {
                for y in 0..<dimsForExport.1 {
                    for x in 0..<dimsForExport.0 {
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
            "rangeStart": exportMode != .session ? ISO8601DateFormatter().string(from: rangeStart) : NSNull(),
            "rangeEnd": exportMode != .session ? ISO8601DateFormatter().string(from: rangeEnd) : NSNull(),
            "cube": [
                "width": dimsForExport.0, "height": dimsForExport.1, "depth": dimsForExport.2,
                "mazeId": exportMode == .live ? liveFeed.masterMazeId : "",
                "entrance": openingJSON(startOpeningForExport),
                "exit": openingJSON(endOpeningForExport),
                "cells": cubeCells
            ],
            "pathIndex": pathLayersJSON,
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
            exportStatus = "\(events.count) events across \(layers.count) layer\(layers.count == 1 ? "" : "s"), \(cubeCells.count) cube cells — \(zipData.count / 1024) KB."
            showShareSheet = true
        } catch {
            exportStatus = "Export failed writing file."
        }
        isExporting = false
    }

    /// TF161: fetches every chunk file under the live feed's current
    /// master maze, filters to events actually inside the requested date
    /// range, and flattens them into the same AnalyticsEvent shape the
    /// rest of the export pipeline already works with — reusing the exact
    /// same layering/nesting/zip logic for both manual and live exports
    /// rather than a second export pipeline to maintain.
    private func fetchLiveFeedEvents(from start: Date, to end: Date) async -> [AnalyticsEvent] {
        var out: [AnalyticsEvent] = []
        for path in liveFeed.allChunkPaths() {
            let url = URL(string: "https://raw.githubusercontent.com/DART-Skyboard/leatr-ash/main/\(path)")!
            guard let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { continue }
            for dict in arr {
                guard let tsStr = dict["ts"] as? String, let ts = ISO8601DateFormatter().date(from: tsStr),
                      ts >= start, ts <= end,
                      let category = dict["category"] as? String, let label = dict["label"] as? String
                else { continue }
                out.append(AnalyticsEvent(ts: ts, category: category, label: label, detail: dict["detail"] as? String))
            }
        }
        return out.sorted { $0.ts < $1.ts }
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
        //
        // TF159: the actual bug — basicMat(color, opacity:) bakes that
        // opacity directly into diffuse/emission's own alpha channel via
        // color.withAlphaComponent(opacity), it never touches
        // SCNMaterial.transparency at all. Setting .transparency here did
        // nothing, since the underlying color already had zero alpha
        // baked in permanently — 0 alpha × any transparency multiplier is
        // still 0. Revealing now replaces the color itself with a fresh,
        // fully-opaque one instead.
        guard let root = v.scene?.rootNode.childNode(withName: "mazeRoot", recursively: false) else { return }
        let pathNodes = root.childNodes.filter { $0.name == "pathNode" }
        let cyan = ThreeJSGeometry.hex(0x00ffff)
        for (i, node) in pathNodes.enumerated() {
            let visible = isSolving && i < revealCount
            let color = cyan.withAlphaComponent(visible ? 1 : 0)
            node.geometry?.firstMaterial?.diffuse.contents = color
            node.geometry?.firstMaterial?.emission.contents = color
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
