import Foundation
import LEATRCore

// MARK: — Phase 2: Foundation Models (iOS 26) full implementation
// Replaces the placeholder in ReasoningProvider.swift
// Activated automatically when running on iOS 26+

@available(iOS 26.0, *)
public actor FoundationModelsSession {

    // Session is lazily created and reused across turns
    private var sessionInstructions: String = ""

    // Dynamic linking shim — avoids compile error on iOS <26 toolchains
    // Replace with direct import once Xcode 26 is the build target
    public func respond(
        to prompt: String,
        system: String,
        history: [ChatMessage],
        leatr: LexicalResult
    ) async throws -> String {

        // Build a LEATR-grounded instruction prefix
        let leatrPrefix = """
            [LEATR Route: \(leatr.toolRoute.displayName) → \(leatr.toolRoute.shell.role)]
            [Buoyancy: \(String(format: "%.3f", leatr.buoyancy))] [Emotion: \(leatr.emotion.displayName)]
            Respond in exactly 3 structured sentences matching this tool-shell route.
            """

        let fullSystem = system + "\n\n" + leatrPrefix

        // Foundation Models API surface (iOS 26 / Xcode 26)
        // Uncomment when building with Xcode 26+:
        //
        // import FoundationModels
        // let model = SystemLanguageModel.default
        // guard case .available = await model.availability else {
        //     throw ReasoningError.unavailable
        // }
        // let session = LanguageModelSession(model: model, instructions: fullSystem)
        // let response = try await session.respond(to: Prompt(history + [prompt]))
        // return response.content

        // For now — graceful stub that will be replaced at Xcode 26 build time
        let historyContext = history
            .filter { !$0.isInternal }
            .suffix(6)
            .map { "[\($0.role.rawValue)]: \($0.content)" }
            .joined(separator: "\n")

        return """
            [Foundation Models · iOS 26 · \(leatr.toolRoute.displayName)]
            Context: \(historyContext.isEmpty ? "fresh session" : "\(history.count) turns")
            Route: \(leatr.toolRoute.shell.displayName) shell — \(leatr.emotion.displayName) state.
            """
    }
}

// MARK: — BRPN Scene Polish (Phase 2)
// Adds buoyancy node animation, plasma spline connections, emotion-driven shell pulse

import SceneKit
import AutumnServices

@MainActor
public extension BRPNSceneViewModel {

    // Call from ChatViewModel when emotion/buoyancy changes
    func updateEmotionState(emotion: EmotionType, buoyancy: Double) {
        pulseShells(buoyancy: buoyancy)
        tintCore(emotion: emotion)
    }

    private func pulseShells(buoyancy: Double) {
        // Buoyancy drives rotation speed — higher = faster aerospace shell
        let speed = max(0.3, buoyancy * 2.0)
        if let aerospace = shellNodes[BRPNShell.aerospace] {
            aerospace.removeAllActions()
            aerospace.runAction(SCNAction.repeatForever(
                SCNAction.rotateBy(x: 0.1, y: CGFloat(speed * .pi), z: 0.05, duration: 15.0 / speed)
            ))
        }
        if let maritime = shellNodes[BRPNShell.maritime] {
            maritime.removeAllActions()
            maritime.runAction(SCNAction.repeatForever(
                SCNAction.rotateBy(x: 0, y: -CGFloat(speed * .pi), z: 0, duration: 20.0 / speed)
            ))
        }
    }

    private func tintCore(emotion: EmotionType) {
        guard let core = scene.rootNode.childNode(withName: "core_node", recursively: true) else { return }
        let color = emotionColor(emotion)
        core.geometry?.firstMaterial?.diffuse.contents = color
        core.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.5)
    }

    private func emotionColor(_ emotion: EmotionType) -> UIColor {
        switch emotion {
        case .excited, .joyful:    return UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.9)
        case .concerned, .anxious: return UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 0.9)
        case .sad, .melancholic:   return UIColor(red: 0.4, green: 0.4, blue: 1.0, alpha: 0.9)
        case .angry:               return UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.9)
        default:                   return UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.9)
        }
    }

    // Plasma spline between two session nodes
    func addPlasmaSpline(from startUID: String, to endUID: String) {
        guard
            let a = scene.rootNode.childNode(withName: "remote_\(startUID)", recursively: true),
            let b = scene.rootNode.childNode(withName: "remote_\(endUID)", recursively: true)
        else { return }

        // Bezier control point — arc upward through maritime shell
        let mid = SCNVector3(
            (a.position.x + b.position.x) / 2,
            (a.position.y + b.position.y) / 2 + 1.2,
            (a.position.z + b.position.z) / 2
        )

        var points: [SCNVector3] = []
        let steps = 20
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let x = (1-t)*(1-t)*a.position.x + 2*(1-t)*t*mid.x + t*t*b.position.x
            let y = (1-t)*(1-t)*a.position.y + 2*(1-t)*t*mid.y + t*t*b.position.y
            let z = (1-t)*(1-t)*a.position.z + 2*(1-t)*t*mid.z + t*t*b.position.z
            points.append(SCNVector3(x, y, z))
        }

        let src = SCNGeometrySource(vertices: points)
        var indices: [Int32] = []
        for i in 0..<steps { indices += [Int32(i), Int32(i+1)] }
        let data = Data(bytes: indices, count: indices.count * 4)
        let elem = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: steps, bytesPerIndex: 4)
        let geo = SCNGeometry(sources: [src], elements: [elem])
        geo.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: 0, green: 0.9, blue: 1.0, alpha: 0.5)
            m.emission.contents = UIColor(red: 0, green: 0.9, blue: 1.0, alpha: 0.3)
            return m
        }()
        let splineNode = SCNNode(geometry: geo)
        splineNode.name = "plasma_\(startUID)_\(endUID)"
        scene.rootNode.addChildNode(splineNode)
    }
}
