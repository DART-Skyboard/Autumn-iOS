import SwiftUI
import AutumnServices

/// Ash Shard — textile + contacts, send along plasma splines (js/ash-shard-module.js).
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

    public var body: some View {
        OverlayPanel(title: "ASH SHARD", onClose: { appNav.rightTab = .none }) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Build a textile, pick contacts, send along plasma curves.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                HStack(spacing: 6) {
                    ForEach(["rect", "tri", "pent", "slash", "cross"], id: \.self) { t in
                        Button(t.uppercased()) { tool = t }
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .foregroundColor(tool == t ? themeVM.chrome.accent : .white.opacity(0.4))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(themeVM.chrome.accent.opacity(tool == t ? 0.6 : 0.15), lineWidth: 1))
                    }
                }
                GeometryReader { g in
                    ZStack {
                        Color(hex: "#0a0e1a")
                        ForEach(shapes) { s in
                            shardMark(s, in: g.size)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                        shapes.append(ShardShape(tool: tool, x: Double(v.location.x / g.size.width), y: Double(v.location.y / g.size.height), color: color.hexString))
                    })
                }
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(themeVM.chrome.accent.opacity(0.2), lineWidth: 1))
                .cornerRadius(6)

                HStack {
                    ColorPicker("", selection: $color).labelsHidden().frame(width: 32, height: 22)
                    Button("CLEAR") { shapes.removeAll() }
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Button("⬡ SEND SHARD") {
                        sceneVM.spawnShard(color: UIColor.fromSwiftUI(color))
                        sceneVM.emitMist(fromLocal: true)
                        Task {
                            let payload: [String: Any] = [
                                "type": "shard",
                                "fromUid": authVM.sessionUID,
                                "toUids": Array(starred),
                                "textile": ["shapes": shapes.map { ["type": $0.tool, "x": $0.x, "y": $0.y, "color": $0.color] }],
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
                            ForEach(contacts.prefix(20)) { c in
                                Button {
                                    if starred.contains(c.login) { starred.remove(c.login) } else { starred.insert(c.login) }
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
                    .frame(maxHeight: 90)
                }
                Text(status).font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.chrome.accent.opacity(0.5))
            }
            .padding(12)
        }
        .task { await loadContacts() }
    }

    @ViewBuilder
    private func shardMark(_ s: ShardShape, in size: CGSize) -> some View {
        let p = CGPoint(x: s.x * size.width, y: s.y * size.height)
        RoundedRectangle(cornerRadius: s.tool == "rect" ? 2 : 8)
            .fill(Color(hex: s.color).opacity(0.8))
            .frame(width: 16, height: 16)
            .rotationEffect(.degrees(s.tool == "tri" ? 45 : (s.tool == "slash" ? 30 : 0)))
            .position(p)
    }

    private func loadContacts() async {
        guard authVM.githubConnected else { return }
        do {
            contacts = try await GitHubClient.shared.fetchFollowing()
        } catch {
            status = "CONTACTS: \(error.localizedDescription)"
        }
    }
}

struct ShardShape: Identifiable {
    let id = UUID()
    let tool: String
    let x: Double
    let y: Double
    let color: String
}

extension Color {
    var hexString: String {
        let ui = UIColor.fromSwiftUI(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}
