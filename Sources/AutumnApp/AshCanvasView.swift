import AutumnServices
import LEATRCore
import SwiftUI

// MARK: — Ash Canvas Drawer
// Faithful port of the #ash-canvas-drawer from index.html
// The 7 natural tools (M/P/E/H/S/K/R), canvas with tap-to-place nodes,
// link/connect, apply to network, save to GitHub

public struct AshCanvasView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @StateObject private var vm = AshCanvasViewModel()
    @Binding var isOpen: Bool

    public var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.purple.opacity(0.6))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.purple, lineWidth: 0.5))
                    Text("ASH CANVAS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.purple.opacity(0.9))
                        .tracking(2)
                    Text("NEURAL INFLUENCE")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Color.purple.opacity(0.4))
                }
                Spacer()
                Button { isOpen = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.6))
            .overlay(Rectangle().frame(height: 0.5)
                .foregroundColor(Color.purple.opacity(0.2)), alignment: .bottom)

            // ── Tool instructions ────────────────────────────────
            Text("NATURAL TOOLS — drag onto canvas or tap to place")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
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
                canvasActionBtn("↑ SAVE TO GITHUB", color: .cyan) { vm.saveToGitHub() }
                canvasActionBtn("→ SEND TO AUTUMN", color: .purple) { vm.sendToAutumn() }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // ── Canvas label ─────────────────────────────────────
            Text("CANVAS — tap/click to place node · tap node then socket to connect")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 6)

            // ── Canvas area ──────────────────────────────────────
            AshCanvasBoard(vm: vm)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(Color.black.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 0.7))
                .padding(.horizontal, 14)
                .padding(.top, 4)

            // ── Bottom action bar ────────────────────────────────
            HStack(spacing: 6) {
                canvasActionBtn("↪ APPLY TO NETWORK", color: .cyan) { vm.applyToNetwork() }
                canvasActionBtn("→ LINK", color: .cyan) {
                    vm.isLinkMode.toggle()
                }
                .overlay(vm.isLinkMode ?
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.cyan, lineWidth: 1) : nil)
                canvasActionBtn("✕ DEL", color: .red) { vm.deleteSelected() }
                canvasActionBtn("↺ RESET", color: .white.opacity(0.5)) { vm.reset() }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if let status = vm.statusMessage {
                Text(status)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(red:0.04,green:0.05,blue:0.12).opacity(0.97))
        .overlay(RoundedRectangle(cornerRadius: 0)
            .stroke(Color.purple.opacity(0.15), lineWidth: 0.7), alignment: .top)
    }

    private func toolBtn(_ tool: NaturalTool) -> some View {
        Button {
            vm.selectedTool = tool
            vm.placeNode(tool: tool)
        } label: {
            HStack(spacing: 3) {
                Text(tool.prefix)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                Text(tool.displayName.uppercased())
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(vm.selectedTool == tool
                ? Color.cyan.opacity(0.15) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(vm.selectedTool == tool
                    ? Color.cyan.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 0.7))
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
