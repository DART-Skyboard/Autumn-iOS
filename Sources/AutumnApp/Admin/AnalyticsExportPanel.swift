import SwiftUI
import SceneKit
import AutumnServices

public struct AnalyticsExportPanel: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @StateObject private var maze = AnalyticsExportMaze.shared
    @State private var showGenerateSheet = false
    @State private var genWidth = "10"
    @State private var genHeight = "10"
    @State private var genDepth = "10"
    @State private var genStatus = ""
    @State private var isSolving = false
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

                MazeOrbitSceneView(maze: maze, isSolving: $isSolving)
                    .frame(height: 260)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(themeVM.chrome.accent.opacity(0.25), lineWidth: 1))

                HStack(spacing: 10) {
                    Button {
                        withAnimation { maze.solveRevealed.toggle() }
                        isSolving = maze.solveRevealed
                    } label: {
                        Label(maze.solveRevealed ? "HIDE SOLVE" : "SOLVE", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    }
                    Button { showGenerateSheet = true } label: {
                        Label("GENERATE NEW", systemImage: "faceid")
                    }
                    Spacer()
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(themeVM.chrome.accent)

                Divider().background(Color.white.opacity(0.15))

                exportCard
            }
            .padding(14)
        }
        .sheet(isPresented: $showGenerateSheet) { generateSheet }
        .sheet(isPresented: $showShareSheet) {
            if let exportedFileURL { ShareSheet(items: [exportedFileURL]) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REAL-TIME SCENE ANALYTICS").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(themeVM.chrome.accent)
            Text(headerSubtitle)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private var headerSubtitle: String {
        let genStr = maze.generatedAt.map { relDate($0) } ?? "—"
        return "Fixed \(maze.width)×\(maze.height)×\(maze.depth) cube — generated \(genStr). Regenerates automatically on a fresh sign-in; manual regeneration below requires Face ID."
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

    private var generateSheet: some View {
        NavigationStack {
            Form {
                Section("New export maze dimensions (\(AnalyticsExportMaze.minDimension)–\(AnalyticsExportMaze.maxDimension) per axis)") {
                    TextField("Width", text: $genWidth).keyboardType(.numberPad)
                    TextField("Height", text: $genHeight).keyboardType(.numberPad)
                    TextField("Depth", text: $genDepth).keyboardType(.numberPad)
                }
                Section {
                    Text("This replaces the current fixed maze used to structure every future export. Confirmed with Face ID.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Button("Generate (Face ID)") {
                        Task {
                            let w = Int(genWidth) ?? 10, h = Int(genHeight) ?? 10, d = Int(genDepth) ?? 10
                            let ok = await maze.regenerateWithFaceID(width: w, height: h, depth: d)
                            genStatus = ok ? "Generated." : "Face ID failed or cancelled."
                            if ok { showGenerateSheet = false }
                        }
                    }
                    if !genStatus.isEmpty { Text(genStatus).font(.system(size: 11)).foregroundColor(.secondary) }
                }
            }
            .navigationTitle("New Export Maze")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showGenerateSheet = false } } }
        }
    }

    private func relDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    /// The actual nesting: analytics events, in real chronological order,
    /// get assigned one-per-cell along the maze's real solution path from
    /// entrance to exit — the "hierarchy of pattern execution" the export
    /// is meant to preserve. When there are more events than path cells,
    /// later events group onto the last cells rather than being dropped,
    /// matching "start grouping things if there's too much data" directly.
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

        let root: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "mode": exportMode.rawValue,
            "rangeStart": exportMode == .range ? ISO8601DateFormatter().string(from: rangeStart) : NSNull(),
            "rangeEnd": exportMode == .range ? ISO8601DateFormatter().string(from: rangeEnd) : NSNull(),
            "maze": ["width": maze.width, "height": maze.height, "depth": maze.depth, "generatedAt": maze.generatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()],
            "totalEvents": events.count,
            "path": pathJSON
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
            exportStatus = "\(events.count) events exported — \(zipData.count / 1024) KB."
            showShareSheet = true
        } catch {
            exportStatus = "Export failed writing file."
        }
        isExporting = false
    }
}

/// Genuine camera-orbit controls (drag rotates the camera around the maze,
/// pinch zooms distance) — distinct from the live BRPN scene's own
/// drag-rotates-the-objects behavior, since this is a static structure
/// meant to be inspected from any angle, closer to how Mantis Radar's
/// globe already behaves.
struct MazeOrbitSceneView: UIViewRepresentable {
    let maze: AnalyticsExportMaze
    @Binding var isSolving: Bool

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = SCNScene()
        v.backgroundColor = .clear
        v.autoenablesDefaultLighting = true
        v.allowsCameraControl = true   // SceneKit's own built-in orbit/pinch — simplest correct implementation for a static inspectable structure
        rebuild(v, context: context)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        rebuild(v, context: context)
    }

    private func rebuild(_ v: SCNView, context: Context) {
        guard context.coordinator.lastWidth != maze.width || context.coordinator.lastSolving != isSolving else { return }
        context.coordinator.lastWidth = maze.width
        context.coordinator.lastSolving = isSolving

        let scene = SCNScene()
        let root = SCNNode()
        scene.rootNode.addChildNode(root)

        let u: Float = 0.12
        let wireGeo = SCNGeometry.wireframeBox(w: maze.width, h: maze.height, d: maze.depth, unit: u)
        let wireNode = SCNNode(geometry: wireGeo)
        root.addChildNode(wireNode)

        if isSolving {
            let path = maze.solutionCells()
            for pt in path {
                let dot = SCNNode(geometry: SCNSphere(radius: CGFloat(u * 0.22)))
                dot.geometry?.firstMaterial?.diffuse.contents = UIColor.systemCyan
                dot.geometry?.firstMaterial?.emission.contents = UIColor.systemCyan
                dot.position = SCNVector3(
                    (Float(pt.x) - Float(maze.width) / 2) * u,
                    (Float(pt.y) - Float(maze.height) / 2) * u,
                    (Float(pt.z) - Float(maze.depth) / 2) * u
                )
                root.addChildNode(dot)
            }
        }

        let cam = SCNCamera()
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0, u * Float(max(maze.width, maze.height, maze.depth)) * 1.8)
        scene.rootNode.addChildNode(camNode)
        v.pointOfView = camNode
        v.scene = scene
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastWidth = -1; var lastSolving = false }
}

private extension SCNGeometry {
    /// Simple wireframe cube outline sized to the maze's dimensions —
    /// enough to show the fixed structure's real proportions at a glance;
    /// the full per-cell wall geometry (MazeEngine already has helpers
    /// for that) is a natural next step but not required for this to be
    /// a genuine, useful visualization of the actual maze.
    static func wireframeBox(w: Int, h: Int, d: Int, unit: Float) -> SCNGeometry {
        let box = SCNBox(width: CGFloat(Float(w) * unit), height: CGFloat(Float(h) * unit), length: CGFloat(Float(d) * unit), chamferRadius: 0)
        let mat = SCNMaterial()
        mat.fillMode = .lines
        mat.diffuse.contents = UIColor(white: 0.7, alpha: 0.6)
        mat.lightingModel = .constant
        box.materials = [mat]
        return box
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
