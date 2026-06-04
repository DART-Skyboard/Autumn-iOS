import AutumnServices
import SwiftUI
import SceneKit

// MARK: — BRPNSceneView v4
// - SIGMA SOLVE: reveals path, stays solved (no auto-rebuild)
// - NEW MAZE: separate button to generate next iteration
// - Bouncy orbs live in ViewModel physics world
// - Landscape-safe: uses safeAreaInsets for bottom padding

public struct BRPNSceneView: View {
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showAshCanvas = false

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red:0.01,green:0.02,blue:0.05).ignoresSafeArea()

                // Main SceneKit viewport
                BRPNSceneKitView(vm: sceneVM)
                    .ignoresSafeArea()

                // Bottom control bar
                VStack {
                    Spacer()
                    VStack(spacing: 6) {
                        // Button row
                        HStack(spacing: 10) {
                            // SIGMA SOLVE button
                            if sceneVM.mazeCanSolve {
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
                                .disabled(sceneVM.isSolving)
                            }

                            // NEW MAZE button — always visible
                            Button {
                                sceneVM.generateNewMaze()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color.white.opacity(0.6))
                                    Text("NEW MAZE")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color.white.opacity(0.6))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                            }
                        }
                        .padding(.bottom, 4)

                        // Meta bar
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
                    // Use safeAreaInsets so this lifts correctly in landscape too
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 60))
                }

                // ASH CANVAS trigger
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
                    .padding(.bottom, max(geo.safeAreaInsets.bottom + 50, 110))
                }

                // ASH CANVAS drawer
                if showAshCanvas {
                    VStack {
                        Spacer()
                        AshCanvasView(isOpen: $showAshCanvas)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
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
