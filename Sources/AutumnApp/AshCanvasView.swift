import AutumnServices
import LEATRCore
import SwiftUI

// MARK: — Ash Canvas trigger
// Web #ash-canvas-trigger. Tap toggles AppNavigation.showAshCanvas.
struct AshCanvasTrigger: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation

    private var ac: Color { Color(hex: "#a78bfa") }

    var body: some View {
        let chrome = themeVM.chrome
        let open = appNav.showAshCanvas
        Button {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35)) {
                appNav.showAshCanvas.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(appNav.ashApplied || open ? ac : ac.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .shadow(color: ac.opacity(appNav.ashApplied || open ? 0.7 : 0.3), radius: open ? 5 : 3)
                Text("ASH CANVAS")
                    .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(appNav.ashApplied || open ? ac : ac.opacity(0.55))
                Text(appNav.ashStatusLabel)
                    .font(.system(size: 6, design: .monospaced))
                    .foregroundColor(ac.opacity(0.4))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(open ? ac.opacity(0.06) : chrome.surface.opacity(0.55))
            .overlay(Rectangle().frame(height: 0.5)
                .foregroundColor(ac.opacity(open ? 0.35 : 0.12)), alignment: .bottom)
        }
        .buttonStyle(.plain)
    }
}

// MARK: — Ash Canvas Drawer
// Full web layout when OPEN: tools, SAVE/SEND, 200px canvas + G/M/A sockets, APPLY/LINK/DEL/RESET.
// Never clip those rows. Collapse control is AshCanvasTrigger.

public struct AshCanvasView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var journalVM: JournalViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appNav: AppNavigation
    @StateObject private var vm = AshCanvasViewModel()

    private var ac: Color { Color(hex: "#a78bfa") }
    private var chrome: AutumnTheme { themeVM.chrome }

    public var body: some View {
        VStack(spacing: 0) {
            Text("NATURAL TOOLS — drag onto canvas or tap to place")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(chrome.textSecondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 8)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(NaturalTool.allCases.prefix(4), id: \.self) { tool in
                        toolBtn(tool)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(NaturalTool.allCases.suffix(3), id: \.self) { tool in
                        toolBtn(tool)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            HStack(spacing: 8) {
                canvasActionBtn("☁ SAVE TO GITHUB", color: chrome.accent) { vm.saveToGitHub(auth: authVM) }
                canvasActionBtn("→ SEND TO AUTUMN", color: ac) { vm.sendToAutumn(chat: chatVM) }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Text("CANVAS — tap/click to place node · tap node then socket to connect")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(chrome.textSecondary.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 6)

            AshCanvasBoard(vm: vm)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(chrome.base.opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(ac.opacity(0.25), lineWidth: 0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 14)
                .padding(.top, 4)

            HStack(spacing: 6) {
                canvasActionBtn("▸ APPLY TO NETWORK", color: ac) {
                    vm.applyToNetwork(scene: sceneVM, journal: journalVM, appNav: appNav)
                }
                canvasActionBtn("⟷ LINK", color: chrome.accent) {
                    vm.isLinkMode.toggle()
                    vm.pendingLink = nil
                }
                .overlay(vm.isLinkMode ?
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ac, lineWidth: 1) : nil)
                canvasActionBtn("✕ DEL", color: .red) { vm.deleteSelected() }
                canvasActionBtn("↺ RESET", color: Color(hex: "#ff4466").opacity(0.7)) {
                    vm.reset(scene: sceneVM, journal: journalVM, appNav: appNav)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)

            if let status = vm.statusMessage {
                Text(status)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(chrome.accent.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(chrome.surface.opacity(0.97))
        .overlay(Rectangle().frame(height: 0.7)
            .foregroundColor(ac.opacity(0.22)), alignment: .top)
    }

    private func toolBtn(_ tool: NaturalTool) -> some View {
        Button {
            vm.selectedTool = vm.selectedTool == tool && vm.toolArmed ? nil : tool
            vm.toolArmed = vm.selectedTool != nil
        } label: {
            HStack(spacing: 3) {
                Text(tool.prefix)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(chrome.accent)
                Text(tool.displayName.uppercased())
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(chrome.text.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(vm.selectedTool == tool && vm.toolArmed
                ? chrome.accent.opacity(0.15) : chrome.text.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(vm.selectedTool == tool && vm.toolArmed
                    ? chrome.accent.opacity(0.5) : chrome.text.opacity(0.12), lineWidth: 0.7))
        }
    }

    private func canvasActionBtn(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(color.opacity(0.25), lineWidth: 0.6))
        }
    }
}

// MARK: — Canvas board + G/M/A sockets (web #ac-shell-socket)
struct AshCanvasBoard: View {
    @ObservedObject var vm: AshCanvasViewModel

    var body: some View {
        GeometryReader { geo in
            let socks = socketCenters(in: geo.size)
            ZStack {
                ForEach(vm.connections) { conn in
                    if let a = vm.nodes.first(where: { $0.id == conn.from }),
                       let b = vm.nodes.first(where: { $0.id == conn.to }) {
                        Path { p in
                            p.move(to: CGPoint(x: a.x * geo.size.width, y: a.y * geo.size.height))
                            p.addLine(to: CGPoint(x: b.x * geo.size.width, y: b.y * geo.size.height))
                        }
                        .stroke(Color(hex: "#a78bfa").opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: []))
                    }
                }
                ForEach(vm.nodes) { node in
                    ForEach(node.shellLinks, id: \.self) { shell in
                        if let dest = socks[shell.replacingOccurrences(of: "__route", with: "")] {
                            Path { p in
                                p.move(to: CGPoint(x: node.x * geo.size.width, y: node.y * geo.size.height))
                                p.addLine(to: dest)
                            }
                            .stroke(shellColor(shell), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                }
                ForEach(vm.socketRoutes) { route in
                    if let a = socks[route.from], let b = socks[route.to] {
                        Path { p in
                            p.move(to: a); p.addLine(to: b)
                        }
                        .stroke(shellColor(route.from), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                    }
                }
                ForEach(vm.nodes) { node in
                    AshCanvasNodeView(node: node, isSelected: vm.selectedNodeId == node.id)
                        .position(x: node.x * geo.size.width, y: node.y * geo.size.height)
                        .onTapGesture { vm.tapNode(id: node.id) }
                }
                VStack(spacing: 6) {
                    socketBtn("G", shell: "geo", color: Color(hex: "#00e5ff"))
                    socketBtn("M", shell: "mar", color: Color(hex: "#0088ff"))
                    socketBtn("A", shell: "aero", color: Color(hex: "#ff4466"))
                }
                .position(x: geo.size.width - 19, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { loc in
                vm.tapCanvas(x: loc.x / geo.size.width, y: loc.y / geo.size.height)
            }
        }
    }

    private func socketCenters(in size: CGSize) -> [String: CGPoint] {
        let x = size.width - 19
        let groupH: CGFloat = 22 * 3 + 6 * 2
        let top = (size.height - groupH) / 2
        return [
            "geo": CGPoint(x: x, y: top + 11),
            "mar": CGPoint(x: x, y: top + 22 + 6 + 11),
            "aero": CGPoint(x: x, y: top + 44 + 12 + 11)
        ]
    }

    private func shellColor(_ shell: String) -> Color {
        switch shell.replacingOccurrences(of: "__route", with: "") {
        case "geo": return Color(red: 0, green: 229/255, blue: 1).opacity(0.5)
        case "mar": return Color(red: 0, green: 136/255, blue: 1).opacity(0.5)
        case "aero": return Color(red: 1, green: 68/255, blue: 102/255).opacity(0.5)
        default: return Color.white.opacity(0.3)
        }
    }

    private func socketBtn(_ letter: String, shell: String, color: Color) -> some View {
        let on = vm.socketConnected(shell)
        return Button {
            vm.connectSocket(shell)
        } label: {
            Text(letter)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(on ? color : color.opacity(0.7))
                .frame(width: 22, height: 22)
                .background(color.opacity(0.07))
                .clipShape(Circle())
                .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 2))
                .shadow(color: on ? color.opacity(0.8) : .clear, radius: on ? 6 : 0)
        }
        .buttonStyle(.plain)
    }
}

struct AshCanvasNodeView: View {
    let node: AshCanvasNode
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(node.tool.ashColor).opacity(0.3))
                .frame(width: isSelected ? 26 : 22, height: isSelected ? 26 : 22)
                .overlay(Circle()
                    .stroke(Color(node.tool.ashColor), lineWidth: isSelected ? 1.5 : 0.8))
            Text(node.tool.prefix)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(node.tool.ashColor))
        }
        .shadow(color: Color(node.tool.ashColor).opacity(0.4), radius: isSelected ? 8 : 4)
    }
}

// MARK: — AshCanvasViewModel  (acConnectSocket ~20861, acApplyToNetwork ~21000)
@MainActor
class AshCanvasViewModel: ObservableObject {
    @Published var nodes: [AshCanvasNode] = []
    @Published var connections: [AshConnection] = []
    @Published var socketRoutes: [AshSocketRoute] = []
    @Published var selectedTool: NaturalTool? = .maze
    @Published var toolArmed = true
    @Published var selectedNodeId: UUID? = nil
    @Published var isLinkMode = false
    @Published var pendingLink: UUID? = nil
    @Published var sockPending: String? = nil
    @Published var statusMessage: String? = nil
    @Published var influence: (geo: Double, mar: Double, aero: Double) = (0, 0, 0)
    @Published var applied = false

    static let toolWeights: [NaturalTool: Double] = [
        .maze: 1.0, .puzzle: 0.85, .envelope: 0.7, .hammer: 0.9,
        .stick: 0.65, .knife: 0.8, .scissors: 0.75
    ]

    func socketConnected(_ shell: String) -> Bool {
        nodes.contains { $0.shellLinks.contains(shell) }
            || socketRoutes.contains { $0.from == shell || $0.to == shell }
    }

    func tapCanvas(x: Double, y: Double) {
        if isLinkMode { return }
        guard let tool = selectedTool, toolArmed else { return }
        placeNodeAt(tool: tool, x: min(0.82, max(0.06, x)), y: min(0.88, max(0.08, y)))
    }

    func placeNode(tool: NaturalTool) {
        placeNodeAt(tool: tool, x: Double.random(in: 0.12...0.7), y: Double.random(in: 0.15...0.85))
    }

    private func placeNodeAt(tool: NaturalTool, x: Double, y: Double) {
        let node = AshCanvasNode(tool: tool, x: x, y: y)
        nodes.append(node)
        selectedNodeId = node.id
        pendingLink = node.id
    }

    func tapNode(id: UUID) {
        if isLinkMode {
            if let from = pendingLink ?? selectedNodeId, from != id {
                if !connections.contains(where: { $0.from == from && $0.to == id }) {
                    connections.append(AshConnection(from: from, to: id))
                }
                isLinkMode = false
                pendingLink = nil
                selectedNodeId = nil
                statusMessage = "Nodes linked"
            } else {
                selectedNodeId = id
                pendingLink = id
            }
        } else {
            selectedNodeId = id
            pendingLink = id
        }
    }

    /// JS window.acConnectSocket
    func connectSocket(_ shell: String) {
        if let fromSock = sockPending {
            sockPending = nil
            if !socketRoutes.contains(where: { $0.from == fromSock && $0.to == shell }) {
                socketRoutes.append(AshSocketRoute(from: fromSock, to: shell))
            }
            statusMessage = "Routed \(fromSock.uppercased()) → \(shell.uppercased())"
            return
        }
        let targetId = pendingLink ?? selectedNodeId ?? nodes.last?.id
        if targetId == nil {
            sockPending = shell
            statusMessage = "Socket \(shell.uppercased()) — tap a node or another socket"
            return
        }
        guard let idx = nodes.firstIndex(where: { $0.id == targetId }) else { return }
        if nodes[idx].shellLinks.contains(shell) {
            nodes[idx].shellLinks.removeAll { $0 == shell }
        } else {
            nodes[idx].shellLinks.append(shell)
        }
        pendingLink = nil
        statusMessage = "Linked to \(shell.uppercased())"
    }

    func deleteSelected() {
        var ids: [UUID] = []
        if let id = selectedNodeId { ids.append(id) }
        if let id = pendingLink, !ids.contains(id) { ids.append(id) }
        guard !ids.isEmpty else { return }
        nodes.removeAll { ids.contains($0.id) }
        connections.removeAll { ids.contains($0.from) || ids.contains($0.to) }
        selectedNodeId = nil
        pendingLink = nil
    }

    func reset(scene: BRPNSceneViewModel, journal: JournalViewModel, appNav: AppNavigation) {
        nodes.removeAll(); connections.removeAll(); socketRoutes.removeAll()
        selectedNodeId = nil; pendingLink = nil; sockPending = nil
        isLinkMode = false; applied = false; statusMessage = nil
        influence = (0, 0, 0)
        scene.clearAshInfluence()
        appNav.ashApplied = false
        appNav.ashStatusLabel = "NEURAL INFLUENCE"
        journal.append(content: "Ash Canvas reset — neural influence layer cleared.",
                       emotion: .neutral, buoyancy: 0.5, isInternal: true)
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35)) {
            appNav.showAshCanvas = false
        }
    }

    /// JS window.acApplyToNetwork
    func applyToNetwork(scene: BRPNSceneViewModel, journal: JournalViewModel, appNav: AppNavigation) {
        guard !nodes.isEmpty else { return }
        for route in socketRoutes {
            if nodes.contains(where: { $0.shellLinks.contains(route.from) }) {
                if !nodes.contains(where: { $0.shellLinks.contains(route.to) }) {
                    if let i = nodes.firstIndex(where: { $0.shellLinks.contains(route.from) }) {
                        if !nodes[i].shellLinks.contains(route.to) {
                            nodes[i].shellLinks.append(route.to + "__route")
                        }
                    }
                }
            }
        }
        var shellWeights = (geo: 0.0, mar: 0.0, aero: 0.0)
        var toolCounts: [String: Int] = [:]
        for node in nodes {
            let w = Self.toolWeights[node.tool] ?? 0.7
            toolCounts[node.tool.webKey, default: 0] += 1
            for shell in node.shellLinks {
                let key = shell.replacingOccurrences(of: "__route", with: "")
                switch key {
                case "geo": shellWeights.geo += w
                case "mar": shellWeights.mar += w
                case "aero": shellWeights.aero += w
                default: break
                }
            }
            if node.shellLinks.isEmpty {
                shellWeights.geo += w * 0.33
                shellWeights.mar += w * 0.33
                shellWeights.aero += w * 0.33
            }
        }
        influence = shellWeights
        applied = true
        scene.applyAshInfluence(geo: shellWeights.geo, mar: shellWeights.mar, aero: shellWeights.aero)
        scene.pulseShells(1.3)
        let n = nodes.count
        appNav.ashApplied = true
        appNav.ashStatusLabel = "APPLIED · \(n) NODE" + (n > 1 ? "S" : "")
        let toolSummary = toolCounts.map { "\($0.value)×\($0.key)" }.joined(separator: ", ")
        let shellSummary = String(format: "GEO:%.2f MAR:%.2f AERO:%.2f",
                                  shellWeights.geo, shellWeights.mar, shellWeights.aero)
        journal.append(
            content: "Ash Canvas applied. Tools: \(toolSummary). Shell weights: \(shellSummary). \(n) nodes, \(connections.count) links.",
            emotion: .inspiring, buoyancy: 0.7, isInternal: true
        )
        statusMessage = "Ash Canvas applied — \(n) nodes influencing network"
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35)) {
            appNav.showAshCanvas = false
        }
    }

    func saveToGitHub(auth: AuthViewModel) {
        if !auth.githubConnected {
            statusMessage = "Sign in with GitHub to save Ash Canvas"
            return
        }
        let snapshot: [String: Any] = [
            "version": "1.0",
            "saved": ISO8601DateFormatter().string(from: Date()),
            "username": auth.githubUsername,
            "nodes": nodes.map { [
                "id": $0.id.uuidString,
                "tool": $0.tool.webKey,
                "x": $0.x, "y": $0.y,
                "shellLinks": $0.shellLinks
            ] as [String: Any] },
            "links": connections.map { ["from": $0.from.uuidString, "to": $0.to.uuidString] as [String: Any] },
            "influence": ["geo": influence.geo, "mar": influence.mar, "aero": influence.aero],
            "applied": applied
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted]),
              let content = String(data: data, encoding: .utf8) else { return }
        let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let filename = "ash-canvas-\(day).json"
        let user = auth.githubUsername
        statusMessage = "Saving Ash Canvas…"
        Task {
            await UserVaultService.shared.write(
                folder: .projects,
                filename: filename,
                content: content,
                githubUsername: user
            )
            await MainActor.run { statusMessage = "✓ Ash Canvas saved to GitHub" }
        }
    }

    func sendToAutumn(chat: ChatViewModel) {
        let msg = "Ash Canvas state: \(nodes.count) nodes, \(connections.count) connections. Influence: GEO \(String(format: "%.2f", influence.geo)) MAR \(String(format: "%.2f", influence.mar)) AERO \(String(format: "%.2f", influence.aero)). What do you see in this arrangement?"
        Task { await chat.injectAndSend(msg) }
        statusMessage = "Sent to Autumn"
    }
}

struct AshCanvasNode: Identifiable {
    let id = UUID()
    let tool: NaturalTool
    var x: Double
    var y: Double
    var shellLinks: [String] = []
}

struct AshConnection: Identifiable {
    let id = UUID()
    let from: UUID
    let to: UUID
}

struct AshSocketRoute: Identifiable {
    let id = UUID()
    let from: String
    let to: String
}

extension NaturalTool {
    var prefix: String {
        switch self {
        case .maze: return "M"
        case .puzzle: return "P"
        case .envelope: return "E"
        case .hammer: return "H"
        case .stick: return "S"
        case .knife: return "K"
        case .scissors: return "R"
        }
    }
    var webKey: String {
        switch self {
        case .maze: return "maze"
        case .puzzle: return "puzzle"
        case .envelope: return "envelope"
        case .hammer: return "hammer"
        case .stick: return "stick"
        case .knife: return "knife"
        case .scissors: return "scissors"
        }
    }
    var ashColor: UIColor {
        switch self {
        case .maze:     return UIColor(red:0,green:1,blue:0.8,alpha:1)
        case .puzzle:   return UIColor(red:0.53,green:0.8,blue:1,alpha:1)
        case .envelope: return UIColor(red:1,green:0.85,blue:0,alpha:1)
        case .hammer:   return UIColor(red:0,green:0.53,blue:1,alpha:1)
        case .stick:    return UIColor(red:1,green:0.53,blue:0.27,alpha:1)
        case .knife:    return UIColor(red:1,green:0.27,blue:0.4,alpha:1)
        case .scissors: return UIColor(red:0.6,green:0.2,blue:1,alpha:1)
        }
    }
}
