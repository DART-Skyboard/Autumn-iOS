import SwiftUI
import SceneKit
import LEATRCore
import AutumnServices

/// Native World Studio — viewport + generate tools from worldstudio.html.
/// Procedural SceneKit meadow from seed/prompt. HF/GLB generation is later; this viewport operates.
struct WorldStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @StateObject private var vm = WorldStudioViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DART MEADOW WORLD STUDIO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.6))
                Spacer()
                Text(vm.status)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            WorldViewport(seed: vm.seedHash, style: vm.style, altitude: vm.altitude, rotate: vm.rotate)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if vm.generating {
                        ProgressView(value: vm.progress)
                            .tint(themeVM.chrome.accent)
                            .padding()
                    }
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        tabBtn("GENERATE", .generate)
                        tabBtn("VIEWER", .viewer)
                        tabBtn("SETTINGS", .settings)
                    }
                    if vm.sheet == .generate {
                        TextField("text prompt", text: $vm.prompt)
                            .textFieldStyle(.plain).foregroundColor(.white)
                            .padding(8).background(themeVM.chrome.surface).cornerRadius(6)
                        Picker("STYLE", selection: $vm.style) {
                            ForEach(WorldStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.menu).tint(themeVM.chrome.accent)
                        HStack {
                            Text("SEED").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                            TextField("seed", text: $vm.seed)
                                .textFieldStyle(.plain).foregroundColor(.white)
                                .padding(6).background(themeVM.chrome.surface).cornerRadius(4)
                        }
                        SliderControl(label: "STEPS", value: $vm.steps, range: 4...64, format: "%.0f")
                        SliderControl(label: "GUIDANCE", value: $vm.guidance, range: 1...15, format: "%.1f")
                        SliderControl(label: "ALTITUDE", value: $vm.altitude, range: 20...400, format: "%.0f")
                        Button {
                            vm.generate()
                        } label: {
                            Text(vm.generating ? "GENERATING…" : "⬡ GENERATE WORLD")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "#00e5ff"))
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(Color.cyan.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                        }
                        .disabled(vm.generating)
                    } else if vm.sheet == .viewer {
                        Toggle("↻ AUTOROTATE", isOn: $vm.rotate)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                        HStack {
                            Button("⬡ RESET") { vm.resetCamera() }
                            Button("↓ JSON") { vm.exportJSON() }
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(themeVM.chrome.accent)
                    } else {
                        Text("Procedural viewport is local. HuggingFace/TripoSR GLB stays on web World Studio when a token is set there — this native studio does not embed HF keys.")
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 280)
        }
    }

    private func tabBtn(_ title: String, _ s: WorldStudioViewModel.Sheet) -> some View {
        Button(title) { vm.sheet = s }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(vm.sheet == s ? Color(hex: "#00e5ff") : .white.opacity(0.45))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(Color.cyan.opacity(vm.sheet == s ? 0.5 : 0.18), lineWidth: 1))
    }
}

enum WorldStyle: String, CaseIterable {
    case meadow = "MEADOW"
    case lake = "LAKE"
    case ash = "ASH TREE"
    case night = "NIGHT"
    case void = "VOID"
}

@MainActor
final class WorldStudioViewModel: ObservableObject {
    enum Sheet { case generate, viewer, settings }
    @Published var sheet: Sheet = .generate
    @Published var prompt = "autumn meadow over dart water"
    @Published var seed = "autumn"
    @Published var style: WorldStyle = .meadow
    @Published var steps: Double = 16
    @Published var guidance: Double = 7.5
    @Published var altitude: Double = 120
    @Published var rotate = true
    @Published var generating = false
    @Published var progress: Double = 0
    @Published var status = "VIEWPORT READY"
    @Published var seedHash: UInt64 = 0x6175746d

    func generate() {
        generating = true
        progress = 0
        status = "GENERATING…"
        let hashed = Self.hash(seed + "|" + prompt + "|" + style.rawValue + "|\(Int(steps))|\(guidance)")
        Task {
            for i in 1...8 {
                try? await Task.sleep(nanoseconds: 80_000_000)
                progress = Double(i) / 8.0
            }
            seedHash = hashed
            generating = false
            status = String(format: "WORLD · seed %llx · steps %.0f", hashed, steps)
        }
    }

    func resetCamera() {
        altitude = 120
        rotate = true
        status = "CAM RESET"
    }

    func exportJSON() {
        let payload: [String: Any] = [
            "prompt": prompt, "seed": seed, "style": style.rawValue,
            "steps": steps, "guidance": guidance, "altitude": altitude
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let s = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = s
            status = "WORLD JSON COPIED"
            Task {
                await UserVaultService.shared.write(folder: .projects, filename: "world-\(Int(Date().timeIntervalSince1970)).json", content: s)
            }
        }
    }

    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h &*= 0x100000001b3 }
        return h
    }
}

struct WorldViewport: UIViewRepresentable {
    var seed: UInt64
    var style: WorldStyle
    var altitude: Double
    var rotate: Bool

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = SCNScene()
        v.backgroundColor = .clear
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = true
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        guard let root = v.scene?.rootNode else { return }
        root.childNodes.filter { $0.name == "world" }.forEach { $0.removeFromParentNode() }
        let world = SCNNode(); world.name = "world"
        let mesh = terrain(seed: seed, style: style)
        world.addChildNode(mesh)
        let cam = root.childNodes.first { $0.camera != nil } ?? {
            let n = SCNNode(); n.camera = SCNCamera(); root.addChildNode(n); return n
        }()
        cam.position = SCNVector3(0, Float(altitude / 40.0), Float(altitude / 30.0))
        cam.look(at: SCNVector3(0, 0, 0))
        world.removeAllActions()
        if rotate {
            world.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 0.4, z: 0, duration: 8)))
        }
        root.addChildNode(world)
    }

    private func terrain(seed: UInt64, style: WorldStyle) -> SCNNode {
        let n = 28
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var idx: [Int32] = []
        for z in 0..<n {
            for x in 0..<n {
                let u = Float(x) / Float(n - 1) * 8 - 4
                let v = Float(z) / Float(n - 1) * 8 - 4
                let h = noise(u, v, seed) * (style == .void ? 0.15 : 0.9)
                verts.append(SCNVector3(u, h, v))
                norms.append(SCNVector3(0, 1, 0))
            }
        }
        for z in 0..<(n - 1) {
            for x in 0..<(n - 1) {
                let i = Int32(z * n + x)
                idx.append(contentsOf: [i, i + 1, i + Int32(n), i + 1, i + Int32(n) + 1, i + Int32(n)])
            }
        }
        let src = SCNGeometrySource(vertices: verts)
        let nrm = SCNGeometrySource(normals: norms)
        let data = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let elem = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: idx.count / 3, bytesPerIndex: 4)
        let geo = SCNGeometry(sources: [src, nrm], elements: [elem])
        let mat = SCNMaterial()
        switch style {
        case .meadow: mat.diffuse.contents = UIColor(red: 0.15, green: 0.45, blue: 0.22, alpha: 1)
        case .lake: mat.diffuse.contents = UIColor(red: 0.1, green: 0.35, blue: 0.55, alpha: 1)
        case .ash: mat.diffuse.contents = UIColor(red: 0.2, green: 0.32, blue: 0.18, alpha: 1)
        case .night: mat.diffuse.contents = UIColor(red: 0.08, green: 0.1, blue: 0.22, alpha: 1)
        case .void: mat.diffuse.contents = UIColor(white: 0.12, alpha: 1)
        }
        mat.emission.contents = mat.diffuse.contents
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        // trees
        let treeCount = style == .void ? 0 : 10
        for i in 0..<treeCount {
            let t = SCNCone(topRadius: 0.02, bottomRadius: 0.12, height: 0.7)
            t.firstMaterial?.emission.contents = UIColor(red: 0.05, green: 0.4, blue: 0.15, alpha: 1)
            let tn = SCNNode(geometry: t)
            let fx = noise(Float(i), 2.2, seed) * 3.5
            let fz = noise(4.4, Float(i), seed &* 3) * 3.5
            tn.position = SCNVector3(fx, 0.45, fz)
            node.addChildNode(tn)
        }
        return node
    }

    private func noise(_ x: Float, _ z: Float, _ seed: UInt64) -> Float {
        let s = Float(seed & 0xffff) / 65535.0
        let n = sin(x * 1.7 + s * 12.0) * cos(z * 1.3 + s * 7.0)
        let n2 = sin((x + z) * 0.6 + s * 4)
        return (n * 0.6 + n2 * 0.4)
    }
}
