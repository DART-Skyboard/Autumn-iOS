import AutumnServices
import LEATRCore
import SwiftUI

// MARK: — Ash Canvas Drawer
// Faithful port of the #ash-canvas-drawer from index.html
// The 7 natural tools (M/P/E/H/S/K/R), canvas with tap-to-place nodes,
// link/connect, apply to network, save to GitHub

// MARK: — Ash Canvas trigger
// Web #ash-canvas-trigger: padding 3px 12px, font ~0.45rem, always visible.
// Tap toggles AppNavigation.showAshCanvas. Stays visible when the drawer is open.
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
                    .fill(open ? ac : ac.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .shadow(color: ac.opacity(open ? 0.7 : 0.3), radius: open ? 5 : 3)
                Text("ASH CANVAS")
                    .font(.system(size: 7.2, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(open ? ac : ac.opacity(0.55))
                Text("NEURAL INFLUENCE")
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
// Faithful port of the #ash-canvas-drawer from index.html
// The 7 natural tools (M/P/E/H/S/K/R), canvas with tap-to-place nodes,
// link/connect, apply to network, save to GitHub.
// Collapse control is AshCanvasTrigger (no duplicate header). Expands DOWN over chat.

public struct AshCanvasView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @StateObject private var vm = AshCanvasViewModel()

    private var ac: Color { Color(hex: "#a78bfa") }
    private var chrome: AutumnTheme { themeVM.chrome }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Tool instructions ────────────────────────────────
            Text("NATURAL TOOLS — drag onto canvas or tap to place")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(chrome.textSecondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 8)

            // ── 7 Natural Tools ──────────────────────────────────
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

            // ── Action buttons ───────────────────────────────────
            HStack(spacing: 8) {
                canvasActionBtn("↑ SAVE TO GITHUB", color: chrome.accent) { vm.saveToGitHub() }
                canvasActionBtn("→ SEND TO AUTUMN", color: ac) { vm.sendToAutumn() }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // ── Canvas label ─────────────────────────────────────
            Text("CANVAS — tap/click to place node · tap node then socket to connect")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(chrome.textSecondary.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 6)

            // ── Canvas area ──────────────────────────────────────
            AshCanvasBoard(vm: vm)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 80)
                .frame(maxHeight: .infinity)
                .background(chrome.base.opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(ac.opacity(0.25), lineWidth: 0.7))
                .padding(.horizontal, 14)
                .padding(.top, 4)

            // ── Bottom action bar ────────────────────────────────
            HStack(spacing: 6) {
                canvasActionBtn("↪ APPLY TO NETWORK", color: chrome.accent) { vm.applyToNetwork() }
                canvasActionBtn("→ LINK", color: chrome.accent) {
                    vm.isLinkMode.toggle()
                }
                .overlay(vm.isLinkMode ?
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(chrome.accent, lineWidth: 1) : nil)
                canvasActionBtn("✕ DEL", color: .red) { vm.deleteSelected() }
                canvasActionBtn("↺ RESET", color: chrome.text.opacity(0.5)) { vm.reset() }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(chrome.surface.opacity(0.97))
        .overlay(Rectangle().frame(height: 0.7)
            .foregroundColor(ac.opacity(0.22)), alignment: .top)
    }

    private func toolBtn(_ tool: NaturalTool) -> some View {
        Button {
            vm.selectedTool = tool
            vm.placeNode(tool: tool)
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
            .background(vm.selectedTool == tool
                ? chrome.accent.opacity(0.15) : chrome.text.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(vm.selectedTool == tool
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

// MARK: — Canvas board (SVG-equivalent tap-to-place)
struct AshCanvasBoard: View {
    @ObservedObject var vm: AshCanvasViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Nodes
                ForEach(vm.nodes) { node in
                    AshCanvasNodeView(node: node, isSelected: vm.selectedNodeId == node.id)
                        .position(x: node.x * geo.size.width,
                                  y: node.y * geo.size.height)
                        .onTapGesture { vm.tapNode(id: node.id) }
                }
                // Connections
                ForEach(vm.connections, id: \.id) { conn in
                    if let a = vm.nodes.first(where: { $0.id == conn.from }),
                       let b = vm.nodes.first(where: { $0.id == conn.to }) {
                        Path { p in
                            p.move(to: CGPoint(x: a.x * geo.size.width,
                                               y: a.y * geo.size.height))
                            p.addLine(to: CGPoint(x: b.x * geo.size.width,
                                                  y: b.y * geo.size.height))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundColor(.cyan.opacity(0.5))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { loc in
                vm.tapCanvas(x: loc.x / geo.size.width, y: loc.y / geo.size.height)
            }
        }
        .cornerRadius(6)
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

// MARK: — AshCanvasViewModel
class AshCanvasViewModel: ObservableObject {
    @Published var nodes: [AshCanvasNode] = []
    @Published var connections: [AshConnection] = []
    @Published var selectedTool: NaturalTool = .maze
    @Published var selectedNodeId: UUID? = nil
    @Published var isLinkMode = false
    @Published var statusMessage: String? = nil

    func tapCanvas(x: Double, y: Double) {
        if isLinkMode { return }
        placeNodeAt(tool: selectedTool, x: x, y: y)
    }

    func placeNode(tool: NaturalTool) {
        placeNodeAt(tool: tool, x: Double.random(in: 0.1...0.9),
                    y: Double.random(in: 0.1...0.9))
    }

    private func placeNodeAt(tool: NaturalTool, x: Double, y: Double) {
        let node = AshCanvasNode(tool: tool, x: x, y: y)
        nodes.append(node)
        selectedNodeId = node.id
    }

    func tapNode(id: UUID) {
        if isLinkMode {
            if let from = selectedNodeId, from != id {
                let conn = AshConnection(from: from, to: id)
                if !connections.contains(where: { $0.from == from && $0.to == id }) {
                    connections.append(conn)
                }
                isLinkMode = false
                selectedNodeId = nil
                statusMessage = "Nodes linked"
            } else {
                selectedNodeId = id
            }
        } else {
            selectedNodeId = id
        }
    }

    func deleteSelected() {
        guard let id = selectedNodeId else { return }
        nodes.removeAll { $0.id == id }
        connections.removeAll { $0.from == id || $0.to == id }
        selectedNodeId = nil
    }

    func reset() {
        nodes.removeAll(); connections.removeAll()
        selectedNodeId = nil; isLinkMode = false; statusMessage = nil
    }

    func applyToNetwork() {
        statusMessage = "Applied to BRPN network (\(nodes.count) nodes)"
        // Sync to leatr-ash via GAS
        Task {
            await AutumnGASClient.shared.pingPresence(
                message: "AshCanvas: \(nodes.map { $0.tool.displayName }.joined(separator: ","))",
                response: "Applied to network",
                emotion: "neutral",
                buoyancy: 0.5
            )
        }
    }

    func saveToGitHub() {
        statusMessage = "Saved to Autumn-Ash vault"
        Task {
            let content = nodes.map { "\($0.tool.displayName):\($0.x),\($0.y)" }.joined(separator: "\n")
            await UserVaultService.shared.write(
                folder: .projects,
                filename: "ash-canvas-\(Int(Date().timeIntervalSince1970)).txt",
                content: content
            )
        }
    }

    func sendToAutumn() {
        let pattern = nodes.map { $0.tool.displayName }.joined(separator: " → ")
        statusMessage = "Sent: \(pattern)"
    }
}

// MARK: — Models
struct AshCanvasNode: Identifiable {
    let id = UUID()
    let tool: NaturalTool
    var x: Double; var y: Double
}

struct AshConnection: Identifiable {
    let id = UUID()
    let from: UUID; let to: UUID
}

// MARK: — NaturalTool (7 tools matching index.html)
extension NaturalTool {
    var prefix: String {
        switch self {
        case .maze:     return "M"
        case .puzzle:   return "P"
        case .envelope: return "E"
        case .hammer:   return "H"
        case .stick:    return "S"
        case .knife:    return "K"
        case .scissors: return "R"
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
