import SwiftUI
import SceneKit

// MARK: — BRPNSceneView (full web-app faithful iOS port)
// Matches the BRPN tab from index.html:
// - 3-shell IcosahedronGeometry wireframe
// - LEMAC maze cube at core (Autumn-only solve)
// - ASH CANVAS drawer (slides up from bottom-right)
// - Shell badges in header (wired to AutumnHeader)
// - Presence nodes from leatr-ash GAS
// - Autumn sentience state pulses shells

public struct BRPNSceneView: View {
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showAshCanvas = false
    @State private var showSolveBtn = false

    public var body: some View {
        ZStack {
            Color(red:0.01,green:0.02,blue:0.05).ignoresSafeArea()

            // ── Main SceneKit viewport ────────────────────────────
            BRPNSceneKitView(vm: sceneVM)
                .ignoresSafeArea()

            // ── Bottom meta bar ───────────────────────────────────
            VStack {
                Spacer()
                VStack(spacing: 0) {
                    // Maze solve button (shown when solvable)
                    if sceneVM.mazeCanSolve && authVM.username == "dartsolarpunk" {
                        Button {
                            sceneVM.autumnSolveMaze()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.cyan)
                                Text(sceneVM.isSolving ? "SOLVING…" : "⬡ SIGMA SOLVE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.cyan.opacity(0.4), lineWidth: 0.8))
                        }
                        .padding(.bottom, 8)
                    }

                    // Bottom meta bar
                    HStack {
                        Text("SID: \(sceneVM.sessionId.uppercased())")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                        Spacer()
                        Text("QS: \(String(format: "%.4f", sceneVM.quantumSocket))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .overlay(Rectangle().frame(height: 0.5)
                        .foregroundColor(.cyan.opacity(0.15)), alignment: .top)
                }
            }
            .padding(.bottom, 60) // above tab bar

            // ── ASH CANVAS trigger (bottom-right, matches index.html button) ──
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button { withAnimation(.spring(response: 0.35)) { showAshCanvas.toggle() } } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.purple.opacity(showAshCanvas ? 0.8 : 0.4))
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("ASH CANVAS")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.purple.opacity(0.9))
                                Text("NEURAL INFLUENCE")
                                    .font(.system(size: 6, design: .monospaced))
                                    .foregroundColor(Color.purple.opacity(0.4))
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.purple.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.purple.opacity(showAshCanvas ? 0.5 : 0.2), lineWidth: 0.7))
                    }
                    .padding(.trailing, 14)
                }
                .padding(.bottom, 110)
            }

            // ── ASH CANVAS DRAWER (slides up) ────────────────────
            if showAshCanvas {
                VStack {
                    Spacer()
                    AshCanvasView(isOpen: $showAshCanvas)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .onAppear { sceneVM.setupScene() }
        .onDisappear { sceneVM.teardown() }
    }
}

// MARK: — SceneKit UIViewRepresentable
struct BRPNSceneKitView: UIViewRepresentable {
    @ObservedObject var vm: BRPNSceneViewModel

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = vm.scene
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = false
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.delegate = context.coordinator

        // Camera
        let cam = SCNCamera(); cam.fieldOfView = 50; cam.zFar = 100; cam.zNear = 0.1
        let camNode = SCNNode(); camNode.camera = cam
        camNode.position = SCNVector3(0, 1.5, 5)
        camNode.look(at: SCNVector3(0,0,0))
        vm.scene.rootNode.addChildNode(camNode)

        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    class Coordinator: NSObject, SCNSceneRendererDelegate {
        let vm: BRPNSceneViewModel
        init(vm: BRPNSceneViewModel) { self.vm = vm }
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            DispatchQueue.main.async { self.vm.updateFrame() }
        }
    }
}
