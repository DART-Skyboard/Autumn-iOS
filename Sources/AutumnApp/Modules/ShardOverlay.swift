import SwiftUI
import Darwin
import AutumnServices

/// Ash Shard — textile + contacts, send along plasma splines (js/ash-shard-module.js).
/// CYCLE/AUTO regenerates _randomizeTextile() iterations before SEND.
public struct ShardOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @State private var color = Color(hex: "#00e5ff")
    @State private var tool = "rect"
    @State private var shapes: [ShardShape] = []
    @State private var contacts: [GitHubFollowUser] = []
    @State private var starred: Set<String> = []
    @State private var status = "DESIGN A SHARD THEN SEND"
    @State private var seed: Int = 0
    @State private var generation = 0

    private static let autoColors = ["#00e5ff", "#bf5fff", "#ff6b35", "#00ff88", "#ffd700", "#ff4488", "#44aaff"]
    private static let autoTools = ["rect", "tri", "pent", "slash", "cross"]

    public var body: some View {
        OverlayPanel(title: "ASH SHARD", onClose: { appNav.rightTab = .none }) {
            GeometryReader { geo in
                // Landscape textile fills overlay width; shapes stay proportional (uniform scale).
                // Contacts list taller so more than four names show (valour was clipped).
                let pad: CGFloat = 12
                let innerW = max(80, geo.size.width - pad * 2)
                let chrome: CGFloat = 214
                let contactsFloor: CGFloat = 260
                let canvasBudget = max(90, geo.size.height - chrome - contactsFloor)
                let canvasW = innerW
                let canvasH = min(canvasBudget, canvasW * 0.58)
                let leftover = max(contactsFloor, geo.size.height - chrome - canvasH)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Build a textile, pick contacts, send along plasma curves.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                    HStack(spacing: 6) {
                        ForEach(Self.autoTools, id: \.self) { t in
                            Button(t.uppercased()) { tool = t }
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 5)
                                .foregroundColor(tool == t ? themeVM.chrome.accent : .white.opacity(0.4))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(themeVM.chrome.accent.opacity(tool == t ? 0.6 : 0.15), lineWidth: 1))
                        }
                    }
                    textileCanvas
                        .frame(width: canvasW, height: canvasH)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(themeVM.chrome.accent.opacity(0.2), lineWidth: 1))
                        .cornerRadius(6)

                    HStack(spacing: 8) {
                        ColorPicker("", selection: $color).labelsHidden().frame(width: 32, height: 22)
                        Button("CLEAR") { shapes.removeAll(); status = "DESIGN A SHARD THEN SEND" }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Button("↻ CYCLE") { cycleAuto() }
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(themeVM.chrome.accent)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(themeVM.chrome.accent.opacity(0.45), lineWidth: 1))
                        if generation > 0 {
                            Text("GEN \(generation)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        Spacer()
                        Button("⬡ SEND SHARD") { sendShard() }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(themeVM.chrome.accent)
                    }

                    Text("CONTACTS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(themeVM.chrome.accent.opacity(0.6))
                    if contacts.isEmpty {
                        Text(authVM.githubConnected ? "NO FOLLOWING LOADED" : "CONNECT GITHUB TO LOAD FOLLOWING")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(contacts) { c in
                                    Button {
                                        if starred.contains(c.login) { starred.remove(c.login) } else { starred.insert(c.login) }
                                        persistStarred()
                                    } label: {
                                        HStack {
                                            Text(starred.contains(c.login) ? "★" : "☆").foregroundColor(Color(hex: "#ffdd00"))
                                            Text(c.login).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                        .frame(minHeight: min(contactsFloor, leftover), maxHeight: .infinity)
                    }
                    Text(status).font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.chrome.accent.opacity(0.5))
                }
                .padding(12)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .task { await loadContacts() }
        .onAppear { restoreStarred() }
    }

    private var textileCanvas: some View {
        GeometryReader { g in
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "#0a0e1a")))
                for s in shapes {
                    drawShape(&ctx, s, in: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                let w = 0.10 + Double.random(in: 0...0.12)
                let h = 0.10 + Double.random(in: 0...0.12)
                shapes.append(ShardShape(
                    tool: tool,
                    x: Double(v.location.x / g.size.width),
                    y: Double(v.location.y / g.size.height),
                    color: color.hexString,
                    w: w, h: h, opacity: 0.75
                ))
            })
        }
    }

    private func drawShape(_ ctx: inout GraphicsContext, _ s: ShardShape, in size: CGSize) {
        // Uniform pixel scale so a rect/circle keeps aspect on a wide landscape canvas.
        // x/y still map across the full canvas; mark size uses width as the unit.
        let unit = size.width
        let rect = CGRect(
            x: s.x * size.width,
            y: s.y * size.height,
            width: max(12, s.w * unit),
            height: max(12, s.h * unit)
        )
        let col = Color(hex: s.color).opacity(s.opacity)
        switch s.tool {
        case "tri":
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            ctx.fill(p, with: .color(col))
            ctx.stroke(p, with: .color(col.opacity(0.9)), lineWidth: 1)
        case "pent":
            var p = Path()
            let cx = rect.midX, cy = rect.midY
            let rx = rect.width / 2, ry = rect.height / 2
            for i in 0..<5 {
                let a = Double(i) * .pi * 2 / 5 - .pi / 2
                let pt = CGPoint(x: cx + CGFloat(Darwin.cos(a)) * rx, y: cy + CGFloat(Darwin.sin(a)) * ry)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            ctx.fill(p, with: .color(col))
            ctx.stroke(p, with: .color(col.opacity(0.9)), lineWidth: 1)
        case "slash":
            var p = Path(); p.move(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        case "cross":
            var a = Path(); a.move(to: CGPoint(x: rect.minX, y: rect.maxY)); a.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            var b = Path(); b.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY)); b.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2))
            ctx.stroke(a, with: .color(col), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            ctx.stroke(b, with: .color(col), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        default:
            let p = Path(roundedRect: rect, cornerRadius: 2)
            ctx.fill(p, with: .color(col))
            ctx.stroke(p, with: .color(col.opacity(0.9)), lineWidth: 1)
        }
    }

    /// Web `_randomizeTextile()` — 8–22 random auto-shaped marks, new seed each tap.
    private func cycleAuto() {
        generation += 1
        seed = Int(Date().timeIntervalSince1970 * 1000)
        var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: seed))
        let count = 8 + Int(rng.next() % 14)
        var next: [ShardShape] = []
        for _ in 0..<count {
            let w = 0.08 + Double(rng.next() % 1000) / 1000.0 * 0.22
            let h = 0.08 + Double(rng.next() % 1000) / 1000.0 * 0.22
            next.append(ShardShape(
                tool: Self.autoTools[Int(rng.next() % UInt64(Self.autoTools.count))],
                x: Double(rng.next() % 1000) / 1000.0 * (1.0 - w),
                y: Double(rng.next() % 1000) / 1000.0 * (1.0 - h),
                color: Self.autoColors[Int(rng.next() % UInt64(Self.autoColors.count))],
                w: w, h: h,
                opacity: 0.4 + Double(rng.next() % 500) / 1000.0
            ))
        }
        shapes = next
        status = "AUTO GEN \(generation) — CYCLE AGAIN OR SEND"
    }

    private func sendShard() {
        if shapes.isEmpty {
            status = "DESIGN YOUR SHARD FIRST"
            return
        }
        sceneVM.spawnShard(color: UIColor.fromSwiftUI(color))
        sceneVM.emitMist(fromLocal: true)
        Task {
            let payload: [String: Any] = [
                "type": "shard",
                "fromUid": authVM.sessionUID,
                "toUids": Array(starred),
                "textile": [
                    "shapes": shapes.map { ["type": $0.tool, "x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h, "color": $0.color, "opacity": $0.opacity] },
                    "seed": seed
                ],
                "ts": Date().timeIntervalSince1970 * 1000
            ]
            _ = await AutumnGASClient.shared.ashwrite(
                path: "ashtree/shards/events.json",
                uid: authVM.sessionUID,
                append: true,
                payload: [payload]
            )
        }
        status = starred.isEmpty ? "SENT ON ORB (NO CONTACTS SELECTED)" : "SENT TO \(starred.count) CONTACTS"
    }

    private func loadContacts() async {
        restoreStarred()
        guard authVM.githubConnected else { return }
        do {
            contacts = try await GitHubClient.shared.fetchFollowing()
        } catch {
            status = "CONTACTS: \(error.localizedDescription)"
        }
        // Restore from the user's Autumn-Ash repo if local cache is empty.
        if starred.isEmpty, let user = authVM.githubUsername.isEmpty ? nil : authVM.githubUsername {
            if let raw = await UserVaultService.shared.readRemote(folder: .shard, filename: "starred.json", githubUsername: user),
               let data = raw.data(using: .utf8),
               let arr = try? JSONDecoder().decode([String].self, from: data) {
                starred = Set(arr)
                persistStarred(localOnly: true)
            }
        }
    }

    private func restoreStarred() {
        if let data = UserDefaults.standard.data(forKey: "_as_starred"),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            starred = Set(arr)
        }
    }

    private func persistStarred(localOnly: Bool = false) {
        let arr = Array(starred).sorted()
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: "_as_starred")
        }
        guard !localOnly, authVM.githubConnected, !authVM.githubUsername.isEmpty else { return }
        let user = authVM.githubUsername
        let json = String(data: (try? JSONEncoder().encode(arr)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        let index: [[String: Any]] = contacts.map { c in
            ["login": c.login, "avatar_url": c.avatarURL ?? "", "starred": starred.contains(c.login)]
        }
        Task {
            await UserVaultService.shared.write(
                folder: .shard, filename: "starred.json",
                content: json, githubUsername: user
            )
            _ = await AutumnGASClient.shared.ashwrite(
                path: "ashtree/contacts/index.json",
                uid: user,
                append: false,
                payload: index
            )
        }
    }
}

struct ShardShape: Identifiable {
    let id = UUID()
    let tool: String
    let x: Double
    let y: Double
    let color: String
    var w: Double = 0.10
    var h: Double = 0.10
    var opacity: Double = 0.75
}

/// Tiny deterministic RNG so CYCLE is a real new iteration, not Swift.random in a View redraw.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension Color {
    var hexString: String {
        let ui = UIColor.fromSwiftUI(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}
