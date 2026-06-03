import SwiftUI
import LEATRCore
import SceneKit
import AutumnServices

// MARK: — BRPN Scene View
// Shell badges now live in AutumnHeader (RootView.swift) — not duplicated here
public struct BRPNSceneView: View {
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var themeVM: ThemeViewModel

    public var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()

            SceneKitView(scene: sceneVM.scene)
                .ignoresSafeArea()

            // Bottom meta bar only
            VStack {
                Spacer()
                BRPNMetaBar()
            }
        }
        .onAppear { sceneVM.setupScene() }
    }
}

// MARK: — SceneKit UIKit wrapper
struct SceneKitView: UIViewRepresentable {
    let scene: SCNScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        view.scene = scene
    }
}

// MARK: — BRPN Scene ViewModel
@MainActor
public final class BRPNSceneViewModel: ObservableObject {

    public let scene = SCNScene()
    @Published public var shellStates: [BRPNShell: String] = [
        .geological: "FOUNDATION",
        .maritime:   "REFLEX",
        .aerospace:  "PERFORMANCE"
    ]
    @Published public var activeNodes: Int = 1
    @Published public var sessionId = UUID().uuidString.prefix(8).description

    private var cameraNode: SCNNode!
    var shellNodes: [BRPNShell: SCNNode] = [:]

    let shellRadii: [BRPNShell: CGFloat] = [
        .geological: 2.8,
        .maritime:   1.9,
        .aerospace:  1.1
    ]
    let shellColors: [BRPNShell: UIColor] = [
        .geological: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.12),
        .maritime:   UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.18),
        .aerospace:  UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.25)
    ]

    public func setupScene() {
        scene.background.contents = UIColor(red: 0.01, green: 0.04, blue: 0.08, alpha: 1)

        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 7)
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = {
            let l = SCNLight(); l.type = .ambient
            l.color = UIColor(white: 0.3, alpha: 1); return l
        }()
        scene.rootNode.addChildNode(ambient)

        for shell in BRPNShell.allCases { buildShellNode(shell) }
        buildCoreNode()

        let rotate = SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 30)
        )
        shellNodes[.geological]?.runAction(rotate)
        shellNodes[.maritime]?.runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0.2, y: -2 * .pi, z: 0, duration: 20)
        ))
    }

    private func buildShellNode(_ shell: BRPNShell) {
        let radius = shellRadii[shell] ?? 2.0
        let geo = SCNSphere(radius: radius)
        geo.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents  = shellColors[shell] ?? .clear
            m.emission.contents = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.05)
            m.isDoubleSided = true
            m.fillMode = .lines
            return m
        }()
        let node = SCNNode(geometry: geo)
        shellNodes[shell] = node
        scene.rootNode.addChildNode(node)
    }

    private func buildCoreNode() {
        let geo = SCNSphere(radius: 0.15)
        geo.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents  = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.9)
            m.emission.contents = UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.5)
            return m
        }()
        let node = SCNNode(geometry: geo)
        node.position = SCNVector3(0, 0, 0)
        let pulse = SCNAction.sequence([
            SCNAction.scale(to: 1.3, duration: 0.8),
            SCNAction.scale(to: 1.0, duration: 0.8)
        ])
        node.runAction(.repeatForever(pulse))
        scene.rootNode.addChildNode(node)
    }

    public func addRemoteNode(uid: String, color: UIColor) {
        let angle = Float.random(in: 0...(2 * .pi))
        let radius: Float = 2.0
        let x = radius * cos(angle)
        let z = radius * sin(angle)
        let geo = SCNSphere(radius: 0.08)
        geo.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = color.withAlphaComponent(0.7)
            m.emission.contents = color.withAlphaComponent(0.4)
            return m
        }()
        let node = SCNNode(geometry: geo)
        node.position = SCNVector3(x, 0, z)
        node.name = "remote_\(uid)"
        scene.rootNode.addChildNode(node)
        addSignalLine(from: SCNVector3(0,0,0), to: node.position)
        activeNodes += 1
    }

    private func addSignalLine(from: SCNVector3, to: SCNVector3) {
        let positions: [SCNVector3] = [from, to]
        let src = SCNGeometrySource(vertices: positions)
        let idx: [Int32] = [0, 1]
        let data = Data(bytes: idx, count: idx.count * MemoryLayout<Int32>.size)
        let elem = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: 1, bytesPerIndex: 4)
        let geo = SCNGeometry(sources: [src], elements: [elem])
        geo.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: 0, green: 0.9, blue: 1.0, alpha: 0.3)
            return m
        }()
        scene.rootNode.addChildNode(SCNNode(geometry: geo))
    }
}

// MARK: — Bottom Meta Bar
struct BRPNMetaBar: View {
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var themeVM: ThemeViewModel

    var body: some View {
        HStack {
            Text("SID: \(sceneVM.sessionId)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeVM.current.textSecondary)
            Spacer()
            Text("QS: \(String(format: "%.4f", LEATRIdentity.quantumSocket(b: 1.2, p: 0.8, a: 3.0, r: 1.5)))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeVM.current.accent)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
    }
}
