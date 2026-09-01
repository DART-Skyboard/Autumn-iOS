import SwiftUI
import SceneKit
import LEATRCore
import AutumnServices

/// Native Arc Forge — schematic / PCB / 3D / BOM / NPU from arc-forge.html.
/// Gate graph actually evaluates. Not a WKWebView.
struct ArcForgeStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @StateObject private var vm = ArcForgeViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("RADICAL DEEPSCALE EDA")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.55))
                Circle().fill(Color(hex: "#00ff88")).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(Color(hex: "#00ff88"))
                Spacer()
                Text(vm.status)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(ArcForgeViewModel.Tab.allCases, id: \.self) { tab in
                        Button {
                            vm.tab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.2)
                                .foregroundColor(vm.tab == tab ? themeVM.chrome.accent : .white.opacity(0.4))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .overlay(Rectangle().frame(height: 2)
                                    .foregroundColor(vm.tab == tab ? themeVM.chrome.accent : .clear), alignment: .bottom)
                        }
                    }
                }
            }
            .overlay(Rectangle().frame(height: 1).foregroundColor(themeVM.chrome.accent.opacity(0.15)), alignment: .bottom)

            HStack(spacing: 0) {
                partLibrary
                    .frame(width: 108)
                Divider().background(themeVM.chrome.accent.opacity(0.2))
                Group {
                    switch vm.tab {
                    case .sch: schematic
                    case .pcb: pcbView
                    case .view3d: forge3D
                    case .draft: draftsman
                    case .bom: bom
                    case .npu: npuSpec
                    }
                }
            }
            toolRail
            HStack {
                Text(String(format: "X %.0f  Y %.0f  NET %@  MODE %@", vm.cursor.x, vm.cursor.y, vm.hoverNet, vm.tool.rawValue))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("Y-BUS \(vm.busHigh ? "HIGH" : "LOW")")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(vm.busHigh ? Color(hex: "#00ff88") : Color(hex: "#ff4466"))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
        }
    }

    private var partLibrary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIBRARY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.5))
                    .padding(.top, 8)
                ForEach(ForgePartKind.gates, id: \.self) { k in libBtn(k) }
                Text("PASSIVE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.4))
                    .padding(.top, 6)
                ForEach(ForgePartKind.passives, id: \.self) { k in libBtn(k) }
                Text("IC")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.4))
                    .padding(.top, 6)
                ForEach(ForgePartKind.ics, id: \.self) { k in libBtn(k) }
            }
            .padding(.horizontal, 8)
        }
        .background(Color.black.opacity(0.25))
    }

    private func libBtn(_ k: ForgePartKind) -> some View {
        Button {
            vm.placeKind = k
            vm.tool = .place
            vm.status = "PLACE \(k.rawValue)"
        } label: {
            HStack(spacing: 4) {
                Text(k.glyph)
                Text(k.rawValue)
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundColor(vm.placeKind == k && vm.tool == .place ? Color(hex: "#00e5ff") : .white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4).padding(.horizontal, 4)
            .background(vm.placeKind == k && vm.tool == .place ? Color.cyan.opacity(0.12) : Color.clear)
            .cornerRadius(3)
        }
    }

    private var toolRail: some View {
        HStack(spacing: 6) {
            ForEach(ArcForgeViewModel.Tool.allCases, id: \.self) { t in
                Button(t.rawValue) { vm.tool = t; vm.wireFrom = nil }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(vm.tool == t ? Color(hex: "#00e5ff") : .white.opacity(0.55))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(hex: "#00e5ff").opacity(vm.tool == t ? 0.6 : 0.18), lineWidth: 1))
            }
            Spacer()
            Button("FIT") { vm.zoom = 1; vm.pan = .zero }
                .font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            Button("⬇ JSON") { vm.exportJSON() }
                .font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.chrome.accent)
            Button("↺") { vm.reset() }
                .font(.system(size: 9, design: .monospaced)).foregroundColor(Color(hex: "#ff4466"))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var schematic: some View {
        GeometryReader { geo in
            ZStack {
                ForgeGrid()
                Canvas { ctx, size in
                    let tf = vm.viewTransform(in: size)
                    for w in vm.wires {
                        guard let a = vm.pinPoint(w.from, pin: w.fromPin, in: size),
                              let b = vm.pinPoint(w.to, pin: w.toPin, in: size) else { continue }
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: CGPoint(x: (a.x + b.x) / 2, y: a.y))
                        path.addLine(to: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                        path.addLine(to: b)
                        let hot = vm.netHigh(w.net)
                        ctx.stroke(path, with: .color(hot ? Color(hex: "#00ff88") : Color(hex: "#00e5ff").opacity(0.55)), lineWidth: 1.4)
                    }
                    _ = tf
                }
                ForEach(vm.parts) { part in
                    ForgeSymbol(part: part, selected: vm.selected == part.id, high: vm.outputHigh(part))
                        .position(vm.screen(part.x, part.y, in: geo.size))
                        .gesture(DragGesture().onChanged { g in
                            if vm.tool == .select {
                                vm.selected = part.id
                                let p = vm.world(g.location, in: geo.size)
                                vm.move(part.id, to: p)
                            }
                        })
                        .onTapGesture { vm.tapPart(part, in: geo.size) }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                vm.cursor = g.location
            }.onEnded { g in
                vm.tapCanvas(g.location, in: geo.size)
            })
        }
        .background(Color(hex: "#020a14"))
    }

    private var pcbView: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(["ALL","TOP","BOT","SILK"], id: \.self) { l in
                    Button(l) { vm.pcbLayer = l }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(vm.pcbLayer == l ? Color(hex: "#00e5ff") : .white.opacity(0.45))
                        .padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                }
                Spacer()
            }.padding(.horizontal, 10)
            Canvas { ctx, size in
                let showTop = vm.pcbLayer == "ALL" || vm.pcbLayer == "TOP"
                let showBot = vm.pcbLayer == "ALL" || vm.pcbLayer == "BOT"
                for (i, part) in vm.parts.enumerated() {
                    let x = 24 + CGFloat(i % 4) * (size.width / 4.2)
                    let y = 28 + CGFloat(i / 4) * 52
                    let rect = CGRect(x: x, y: y, width: 64, height: 36)
                    if showTop {
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color(hex: part.kind.pcbHex).opacity(0.35)))
                        ctx.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color(hex: "#c4a36a")), lineWidth: 1)
                    }
                    if showBot {
                        var pads = Path()
                        pads.addEllipse(in: CGRect(x: x + 4, y: y + 14, width: 6, height: 6))
                        pads.addEllipse(in: CGRect(x: x + 54, y: y + 14, width: 6, height: 6))
                        ctx.fill(pads, with: .color(Color(hex: "#d4af37")))
                    }
                    ctx.draw(Text(part.ref).font(.system(size: 8, design: .monospaced)).foregroundColor(.white), at: CGPoint(x: x + 32, y: y + 18))
                }
            }
            .background(Color(hex: "#07140c"))
        }
    }

    private var forge3D: some View {
        ArcForge3DView(parts: vm.parts)
            .overlay(alignment: .topLeading) {
                Text("WIREFRAME · \(vm.parts.count) BODIES")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(8)
            }
    }

    private var draftsman: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TITLE  ARC FORGE SCHEMATIC")
            Text("PROJECT  ARIEL NPU / RP2350")
            Text("REV  A.1    SHEET  1 / 1")
            Text("COMPANY  Radical Deepscale LLC")
            Text("DATE  \(ISO8601DateFormatter().string(from: Date()).prefix(10))")
            Text("PARTS  \(vm.parts.count)    NETS  \(Set(vm.wires.map(\.net)).count)")
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(.white.opacity(0.8))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bom: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TOTAL REFS \(vm.parts.count)")
                Spacer()
                Text("UNIQUE \(Set(vm.parts.map(\.kind)).count)")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(themeVM.chrome.accent.opacity(0.7))
            .padding(8)
            List {
                ForEach(vm.parts) { p in
                    HStack {
                        Text(p.ref).frame(width: 48, alignment: .leading)
                        Text(p.kind.rawValue)
                        Spacer()
                        Text(p.kind.mpn)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var npuSpec: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("ARIEL NPU").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: "#c4a36a"))
                kv("PART NUMBER", "RD-ARIEL-NPU-001")
                kv("HOST", "RP2350  QFN-60-EP")
                kv("CORE", "LEATR 25-order · 7 tools · 3 BRPN shells")
                kv("DOC", "\(LEATRIdentity.DOC)  (replaces π)")
                kv("STATUS", "TRUE")
                kv("CONNECTORS", "X1 USB-C · X2 SWD · ZQ1 XTAL · SW1/SW2")
                Text("Place RP2350 from the IC library, wire VDD/GND/POWER, export JSON. Full Gerber CAM stays on the web EDA.")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
            }.padding(16)
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(v).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.85))
        }
    }
}

private struct ForgeGrid: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            let step: CGFloat = 16
            var x: CGFloat = 0
            while x < size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y < size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(p, with: .color(Color.white.opacity(0.05)), lineWidth: 0.5)
        }
    }
}

private struct ForgeSymbol: View {
    let part: ForgePart
    let selected: Bool
    let high: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(selected ? Color.yellow : (high ? Color(hex: "#00ff88") : Color(hex: part.kind.pcbHex)), lineWidth: selected ? 2 : 1))
            VStack(spacing: 1) {
                Text(part.ref).font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                Text(part.kind.glyph + " " + part.kind.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(high ? Color(hex: "#00ff88") : Color(hex: "#00e5ff"))
            }
        }
        .frame(width: 72, height: 40)
    }
}

struct ArcForge3DView: UIViewRepresentable {
    var parts: [ForgePart]
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(); v.scene = SCNScene(); v.backgroundColor = .black
        v.allowsCameraControl = true; v.autoenablesDefaultLighting = true
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.position = SCNVector3(0, 4, 10)
        v.scene?.rootNode.addChildNode(cam)
        return v
    }
    func updateUIView(_ v: SCNView, context: Context) {
        guard let root = v.scene?.rootNode else { return }
        root.childNodes.filter { $0.name == "board" }.forEach { $0.removeFromParentNode() }
        let g = SCNNode(); g.name = "board"
        let board = SCNBox(width: 6, height: 0.08, length: 4, chamferRadius: 0.02)
        board.firstMaterial?.diffuse.contents = UIColor(red: 0.05, green: 0.25, blue: 0.12, alpha: 1)
        g.addChildNode(SCNNode(geometry: board))
        for (i, p) in parts.enumerated() {
            let box = SCNBox(width: 0.4, height: 0.18, length: 0.4, chamferRadius: 0.02)
            box.firstMaterial?.emission.contents = UIColor.fromSwiftUI(Color(hex: p.kind.pcbHex))
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(Float((i % 5) - 2) * 0.9, 0.16, Float(i / 5) * 0.8 - 1)
            g.addChildNode(n)
        }
        root.addChildNode(g)
    }
}

enum ForgePartKind: String, CaseIterable, Hashable {
    case AND, OR, XOR, NAND, NOR, NOT, BUF, DFF, MUX
    case RES, CAP, LED, XTAL, VREG, NPN, SW, CONN
    case RP2350, VDD, GND
    static let gates: [ForgePartKind] = [.AND, .OR, .XOR, .NAND, .NOR, .NOT, .BUF, .DFF, .MUX]
    static let passives: [ForgePartKind] = [.RES, .CAP, .LED, .XTAL, .VREG, .NPN, .SW, .CONN]
    static let ics: [ForgePartKind] = [.RP2350, .VDD, .GND]
    var glyph: String {
        switch self {
        case .AND: return "&"; case .OR: return "≥1"; case .XOR: return "=1"
        case .NAND: return "&̄"; case .NOR: return "≥1̄"; case .NOT: return "1"
        case .BUF: return "1"; case .DFF: return "FF"; case .MUX: return "MUX"
        case .RES: return "R"; case .CAP: return "C"; case .LED: return "D"
        case .XTAL: return "Y"; case .VREG: return "U"; case .NPN: return "Q"
        case .SW: return "S"; case .CONN: return "J"; case .RP2350: return "U"
        case .VDD: return "+"; case .GND: return "⊥"
        }
    }
    var pcbHex: String {
        switch self {
        case .AND, .OR, .XOR, .NAND, .NOR, .NOT, .BUF, .DFF, .MUX: return "#00e5ff"
        case .RP2350: return "#c4a36a"
        case .VDD: return "#ff4466"
        case .GND: return "#888888"
        default: return "#7ddc8e"
        }
    }
    var mpn: String {
        switch self {
        case .RP2350: return "RP2350-QFN60"
        case .VREG: return "AP2112K"
        case .XTAL: return "12MHz"
        default: return rawValue
        }
    }
    var pins: [String] {
        switch self {
        case .NOT, .BUF: return ["A", "Y"]
        case .DFF: return ["D", "CLK", "Y"]
        case .MUX: return ["I0", "I1", "S", "Y"]
        case .VDD, .GND: return ["Y"]
        case .SW, .LED: return ["A", "Y"]
        case .RP2350: return ["A", "B", "Y"]
        default: return ["A", "B", "Y"]
        }
    }
}

struct ForgePart: Identifiable, Hashable {
    let id: UUID
    var kind: ForgePartKind
    var ref: String
    var x: CGFloat
    var y: CGFloat
    var a: Bool
    var b: Bool
    var clk: Bool
}

struct ForgeWire: Identifiable, Hashable {
    let id: UUID
    var from: UUID
    var fromPin: String
    var to: UUID
    var toPin: String
    var net: String
}

@MainActor
final class ArcForgeViewModel: ObservableObject {
    enum Tab: String, CaseIterable { case sch = "SCH", pcb = "PCB", view3d = "3D", draft = "DRAFT", bom = "BOM", npu = "NPU" }
    enum Tool: String, CaseIterable { case select = "SELECT", wire = "WIRE", place = "PLACE", net = "NET", power = "POWER" }

    @Published var tab: Tab = .sch
    @Published var tool: Tool = .select
    @Published var placeKind: ForgePartKind = .AND
    @Published var parts: [ForgePart] = []
    @Published var wires: [ForgeWire] = []
    @Published var selected: UUID?
    @Published var wireFrom: (UUID, String)?
    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published var cursor: CGPoint = .zero
    @Published var status = "SCH READY"
    @Published var pcbLayer = "ALL"
    @Published var hoverNet = "—"
    private var seq: [ForgePartKind: Int] = [:]

    var busHigh: Bool {
        parts.contains { outputHigh($0) && ($0.kind == .AND || $0.kind == .OR || $0.kind == .XOR || $0.kind == .NAND || $0.kind == .NOR || $0.kind == .NOT || $0.kind == .BUF || $0.kind == .DFF || $0.kind == .MUX) }
    }

    init() {
        // Seed a working AND demo so the bus is live on first open.
        let vdd = add(.VDD, x: 0.12, y: 0.22, a: true)
        let swA = add(.SW, x: 0.12, y: 0.45, a: true)
        let swB = add(.SW, x: 0.12, y: 0.68, a: false)
        let gate = add(.AND, x: 0.45, y: 0.56)
        let led = add(.LED, x: 0.78, y: 0.56)
        _ = vdd
        connect(swA, "Y", gate, "A")
        connect(swB, "Y", gate, "B")
        connect(gate, "Y", led, "A")
        status = "DEMO NET · toggle SWITCHES"
    }

    @discardableResult
    func add(_ kind: ForgePartKind, x: CGFloat, y: CGFloat, a: Bool = false) -> ForgePart {
        let n = (seq[kind] ?? 0) + 1
        seq[kind] = n
        let p = ForgePart(id: UUID(), kind: kind, ref: "\(kind.glyph)\(n)", x: x, y: y, a: a, b: false, clk: false)
        parts.append(p)
        return p
    }

    func connect(_ a: ForgePart, _ ap: String, _ b: ForgePart, _ bp: String) {
        wires.append(ForgeWire(id: UUID(), from: a.id, fromPin: ap, to: b.id, toPin: bp, net: "N\(wires.count + 1)"))
    }

    func reset() {
        parts.removeAll(); wires.removeAll(); seq.removeAll(); selected = nil; wireFrom = nil
        status = "CLEARED"
    }

    func viewTransform(in size: CGSize) -> CGAffineTransform { .identity }
    func screen(_ x: CGFloat, _ y: CGFloat, in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }
    func world(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(0.92, max(0.08, p.x / max(size.width, 1))),
                y: min(0.92, max(0.08, p.y / max(size.height, 1))))
    }
    func pinPoint(_ id: UUID, pin: String, in size: CGSize) -> CGPoint? {
        guard let p = parts.first(where: { $0.id == id }) else { return nil }
        let c = screen(p.x, p.y, in: size)
        switch pin {
        case "A", "D", "I0": return CGPoint(x: c.x - 36, y: c.y - 8)
        case "B", "CLK", "I1", "S": return CGPoint(x: c.x - 36, y: c.y + 8)
        default: return CGPoint(x: c.x + 36, y: c.y)
        }
    }

    func move(_ id: UUID, to p: CGPoint) {
        if let i = parts.firstIndex(where: { $0.id == id }) {
            parts[i].x = p.x; parts[i].y = p.y
        }
    }

    func tapCanvas(_ loc: CGPoint, in size: CGSize) {
        cursor = loc
        let w = world(loc, in: size)
        if tool == .place {
            _ = add(placeKind, x: w.x, y: w.y)
            status = "PLACED \(placeKind.rawValue)"
        } else if tool == .power {
            _ = add(.VDD, x: w.x, y: w.y, a: true)
            status = "POWER RAIL"
        }
    }

    func tapPart(_ part: ForgePart, in size: CGSize) {
        switch tool {
        case .select:
            selected = part.id
            if part.kind == .SW || part.kind == .VDD {
                toggle(part.id)
            }
        case .wire:
            if let from = wireFrom {
                connect(parts.first { $0.id == from.0 }!, from.1, part, "A")
                wireFrom = nil
                status = "WIRED"
            } else {
                wireFrom = (part.id, "Y")
                status = "WIRE FROM \(part.ref).Y"
            }
        case .place:
            break
        case .net:
            status = "NET \(part.ref)"
            hoverNet = part.ref
        case .power:
            toggle(part.id)
        }
    }

    func toggle(_ id: UUID) {
        if let i = parts.firstIndex(where: { $0.id == id }) {
            parts[i].a.toggle()
            status = "\(parts[i].ref) = \(parts[i].a ? "1" : "0")"
        }
    }

    func netHigh(_ net: String) -> Bool {
        guard let w = wires.first(where: { $0.net == net }) else { return false }
        if let p = parts.first(where: { $0.id == w.from }) { return outputHigh(p) }
        return false
    }

    func outputHigh(_ part: ForgePart) -> Bool {
        let ins = inputs(for: part)
        switch part.kind {
        case .AND: return ins.a && ins.b
        case .OR: return ins.a || ins.b
        case .XOR: return ins.a != ins.b
        case .NAND: return !(ins.a && ins.b)
        case .NOR: return !(ins.a || ins.b)
        case .NOT: return !ins.a
        case .BUF, .LED, .SW, .VDD, .RES, .CAP, .CONN, .NPN, .VREG, .XTAL, .RP2350: return ins.a || part.a
        case .GND: return false
        case .DFF: return ins.a
        case .MUX: return ins.s ? ins.b : ins.a
        }
    }

    private func inputs(for part: ForgePart) -> (a: Bool, b: Bool, s: Bool) {
        var a = part.a, b = part.b, s = part.clk
        for w in wires where w.to == part.id {
            let src = parts.first { $0.id == w.from }
            let v = src.map { drive($0) } ?? false
            switch w.toPin {
            case "A", "D", "I0": a = v
            case "B", "I1": b = v
            case "S", "CLK": s = v
            default: a = v
            }
        }
        return (a, b, s)
    }

    private func drive(_ part: ForgePart) -> Bool {
        switch part.kind {
        case .SW, .VDD: return part.a
        case .GND: return false
        default: return outputHigh(part)
        }
    }

    func exportJSON() {
        let payload: [String: Any] = [
            "title": "ARC FORGE",
            "rev": "A.1",
            "parts": parts.map { ["ref": $0.ref, "kind": $0.kind.rawValue, "x": Double($0.x), "y": Double($0.y)] },
            "wires": wires.map { ["from": $0.from.uuidString, "to": $0.to.uuidString, "net": $0.net] }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let s = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = s
            status = "JSON COPIED · \(parts.count) PARTS"
            Task {
                await UserVaultService.shared.write(
                    folder: .projects,
                    filename: "arc-forge-\(Int(Date().timeIntervalSince1970)).json",
                    content: s
                )
            }
        }
    }
}
