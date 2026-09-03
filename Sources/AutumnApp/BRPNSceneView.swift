import AutumnServices
import SwiftUI
import SceneKit
import LEATRCore

// MARK: — BRPNSceneView
// Transparent SceneKit over theme video (JS renderer alpha:true, setClearColor(0,0)).
// NO extra dark Color wash — video shows through like web. Scrim is AppShell #vid-scrim only.

public struct BRPNSceneView: View {
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    private let nodeCapVals: [(Int, String)] = [
        (50, "50"), (150, "150"), (300, "300"), (1000, "1K"), (100_000, "100K"), (1_000_000, "1M")
    ]

    public var body: some View {
        ZStack {
            // JS: renderer.setClearColor(0x000000, 0) — scene is transparent
            BRPNSceneKitView(vm: sceneVM)
                .ignoresSafeArea()

            VStack {
                Spacer()
                VStack(spacing: 6) {
                    // Node cap — JS #node-cap-track in #multi-user-bar (on-scene HUD)
                    HStack(spacing: 4) {
                        Text("NODES")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.cyan.opacity(0.45))
                            .tracking(1.5)
                        ForEach(nodeCapVals, id: \.0) { val, label in
                            Button {
                                sceneVM.mantisNodeMax = val
                            } label: {
                                Text(label)
                                    .font(.system(size: 8, weight: sceneVM.mantisNodeMax == val ? .bold : .regular, design: .monospaced))
                                    .foregroundColor(sceneVM.mantisNodeMax == val ? Color.cyan : Color.cyan.opacity(0.35))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(sceneVM.mantisNodeMax == val ? Color.cyan.opacity(0.18) : Color.clear)
                                    .cornerRadius(2)
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.cyan.opacity(0.15), lineWidth: 1))

                    HStack(spacing: 10) {
                        if sceneVM.mazeCanSolve {
                            Button { sceneVM.autumnSolveMaze() } label: {
                                HStack(spacing: 6) {
                                    Text("⬡")
                                        .font(.system(size: 10))
                                        .foregroundColor(.cyan)
                                    Text(sceneVM.isSolving ? "SOLVING…" : "SIGMA SOLVE")
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

                        Button { sceneVM.generateNewMaze() } label: {
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
                    .background(Color.white.opacity(0.04))
                }
                .padding(.bottom, 8)
            }
        }
        .onAppear { sceneVM.setupScene() }
        .onDisappear { sceneVM.teardown() }
        .onChange(of: chatVM.isThinking) { thinking in
            sceneVM.setOrbThinking(thinking)
        }
    }

}

// MARK: — SceneKit UIViewRepresentable  JS WebGLRenderer({antialias:true,alpha:true})
struct BRPNSceneKitView: UIViewRepresentable {
    @ObservedObject var vm: BRPNSceneViewModel

    func makeUIView(context: Context) -> SCNView {
        let v = QuietSCNView()
        v.scene = vm.scene
        v.allowsCameraControl = false // JS custom pointer drag on rotX/rotY, not orbit camera
        v.autoenablesDefaultLighting = false
        v.backgroundColor = .clear
        v.isOpaque = false
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.delegate = context.coordinator

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        v.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        v.addGestureRecognizer(pinch)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        v.backgroundColor = .clear
        v.isOpaque = false
        if v.pointOfView !== vm.cameraNode {
            v.pointOfView = vm.cameraNode
        }
        context.coordinator.vm = vm
    }

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm, animator: vm.animator) }

    class Coordinator: NSObject, SCNSceneRendererDelegate {
        var vm: BRPNSceneViewModel
        let animator: BRPNAnimator
        private var lastPan = CGPoint.zero
        private var pinch0: Float = 5
        init(vm: BRPNSceneViewModel, animator: BRPNAnimator) {
            self.vm = vm
            self.animator = animator
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // Tick on the render thread — matches JS RAF. Do not hop to main.
            animator.tick()
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let p = g.location(in: g.view)
            if g.state == .began { lastPan = p; return }
            let dx = Float(p.x - lastPan.x)
            let dy = Float(p.y - lastPan.y)
            lastPan = p
            // JS: rotY+=(e.clientX-prevX)*0.005; rotX+=(e.clientY-prevY)*0.005; clamp rotX ±1.2
            animator.rotY += dx * 0.005
            animator.rotX += dy * 0.005
            animator.rotX = max(-1.2, min(1.2, animator.rotX))
            if animator.looking { animator.camIdle = 0 }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            if g.state == .began {
                pinch0 = animator.camera?.position.z ?? 5
            }
            // JS wheel: camera.position.z += deltaY*0.005; pinch scale maps similarly
            let z = pinch0 / Float(max(0.2, g.scale))
            let minZ: Float = animator.looking ? 0.85 : 2.5
            animator.camera?.position.z = max(minZ, min(10, z))
        }
    }
}


/// SceneKit must not steal first responder from Ask Autumn.
final class QuietSCNView: SCNView {
    override var canBecomeFirstResponder: Bool { false }
}
