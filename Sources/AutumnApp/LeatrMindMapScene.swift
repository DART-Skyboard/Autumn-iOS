import Foundation
import SceneKit
import UIKit
import QuartzCore
import LEATRCore

// MARK: — Data model, decoded from Resources/leatr-mindmap.json
// That file is a flattened export of lead-edge-ash-tree-reflex.mm (FreeMind
// XML): 246 nodes / 245 edges, up to depth 6. Generated once from the
// uploaded mind map, not regenerated at runtime — this is a static asset,
// the same way elements.json or the NLP wordnet files are.

public struct MindMapNode: Decodable {
    public let id: Int
    public let text: String
    public let label: String   // short acronym/initials, precomputed at export time
    public let depth: Int
    public let parent: Int?
}

public struct MindMapEdge: Decodable {
    public let from: Int
    public let to: Int
}

public struct MindMapData: Decodable {
    public let nodes: [MindMapNode]
    public let edges: [MindMapEdge]
}

// MARK: — Color helpers for reflex feedback
private extension UIColor {
    /// Parses "#RRGGBB" (EmotionType.accentHex's format). Falls back to a
    /// neutral gray on anything unparseable rather than crashing.
    convenience init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self.init(white: 0.6, alpha: 1); return
        }
        self.init(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    /// A brighter, more saturated version of a base depth color for stages
    /// that don't have a real shell of their own to color by.
    func withEmphasis() -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: min(1, s * 1.3), brightness: min(1, b * 1.15), alpha: a)
    }

    /// Simple linear RGB blend — used to layer the classified emotion's
    /// own color as a tint on top of whichever shell/stage color is
    /// already driving a pulse, rather than one replacing the other.
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(red: r1 * (1 - t) + r2 * t, green: g1 * (1 - t) + g2 * t, blue: b1 * (1 - t) + b2 * t, alpha: 1)
    }
}

/// Builds and animates the LEATR mind map as a 3D wireframe — a toggleable
/// alternate to the buoyancy shell scene, not a replacement. Everything this
/// type creates lives under one root group (`rootGroup`) that
/// BRPNSceneViewModel adds/removes/hides as a single unit, so none of the
/// existing shell/particle/mantis code needs to change to make room for it.
public final class LeatrMindMapScene {
    public let rootGroup = SCNNode()
    /// TF147: diagnostic — reports every pulsePath call (query text, and
    /// whether it actually matched a node), regardless of match success.
    /// Exists specifically to answer "is this actually firing at all" the
    /// next time this doesn't visibly animate, rather than guessing again.
    public var onPulseAttempt: ((_ query: String, _ matched: Bool) -> Void)?
    private var nodeMeshes: [Int: SCNNode] = [:]
    private var glowMeshes: [Int: SCNNode] = [:]   // layered additive spheres for the pulse glow
    private var edgeMeshes: [Int: SCNNode] = [:]   // keyed by the CHILD node id — each non-root node has exactly one parent edge
    private var edgeList: [MindMapEdge] = []
    private var nodeByID: [Int: MindMapNode] = [:]
    private var pulseTimer: Timer?
    private var pulseFrame: Int = 0
    private var observers: [NSObjectProtocol] = []
    private var reflexPulseWorkItems: [Int: DispatchWorkItem] = [:]
    private var recentFires: [String: Date] = [:]       // detects the same reflex repeating
    private var currentEmotionTint: UIColor?

    public init?() {
        guard let url = Bundle.main.url(forResource: "leatr-mindmap", withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let data = try? JSONDecoder().decode(MindMapData.self, from: raw)
        else { return nil }

        rootGroup.name = "leatrMindMap"
        rootGroup.isHidden = true
        build(data)
        observeReflexActivity()
    }

    deinit {
        pulseTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: — Real reflex activity
    //
    // TF143: genuine, prompt-driven feedback rather than only the ambient
    // idle walk below. GrammarEngine posts a named stage (see
    // ReflexActivityBus) each time it actually passes through a real step
    // of processing a real message. Matched here against this mind map's
    // own node text — the vocabulary lines up directly (User Input Prompt,
    // Inbound, Verification, Natural Order of Operations, Allocation,
    // Outbound, AI Output Prompt, Sentience Journal) because this map
    // already represents that same pipeline conceptually. When a stage
    // fires, the matching node and its full ancestor chain back to the
    // root light up together and fade — so what's visible is the actual
    // path the reflex took through the tree for that specific message,
    // not a random pick.

    private func observeReflexActivity() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: ReflexActivityBus.notificationName, object: nil, queue: .main) { [weak self] note in
            guard let stage = note.userInfo?["stage"] as? String else { return }
            self?.pulsePath(matchingText: stage, shellColor: nil)
            if stage == ReflexStage.aiOutput.rawValue || stage == ReflexStage.connectedResources.rawValue {
                self?.scheduleSequenceReset()
            }
        })
        observers.append(nc.addObserver(forName: ReflexActivityBus.toolNotificationName, object: nil, queue: .main) { [weak self] note in
            guard let tool = note.userInfo?["tool"] as? String, let self else { return }
            let shellRaw = note.userInfo?["shell"] as? Int
            let shell = shellRaw.flatMap { BRPNShell(rawValue: $0) }
            self.pulsePath(matchingText: tool, shellColor: shell.map(self.shellColor))
        })
        observers.append(nc.addObserver(forName: ReflexActivityBus.mathOpNotificationName, object: nil, queue: .main) { [weak self] note in
            guard let op = note.userInfo?["op"] as? String else { return }
            self?.pulsePath(matchingText: op, shellColor: nil)
        })
        observers.append(nc.addObserver(forName: ReflexActivityBus.emotionNotificationName, object: nil, queue: .main) { [weak self] note in
            guard let hex = note.userInfo?["accentHex"] as? String else { return }
            self?.currentEmotionTint = UIColor(hexString: hex)
        })
    }

    /// GEO/MAR/AERO, same hex values the buoyancy shells themselves use
    /// (shellColors in BRPNSceneViewModel: 0x00ffcc / 0x0088ff / 0xff4466)
    /// — reused here rather than redefined, so a shell means the same
    /// color in both views of the scene.
    private func shellColor(_ shell: BRPNShell) -> UIColor {
        switch shell {
        case .geological: return UIColor(red: 0, green: 1.0, blue: 0.8, alpha: 1)
        case .maritime:    return UIColor(red: 0, green: 0.53, blue: 1.0, alpha: 1)
        case .aerospace:    return UIColor(red: 1.0, green: 0.27, blue: 0.4, alpha: 1)
        }
    }

    /// Finds the node whose own text best matches (case-insensitive,
    /// longest-match-wins so "Natural Order of Operations" doesn't get
    /// shadowed by a shorter incidental match), then walks its parent
    /// chain up to the root, lighting each one — and the tree edge into
    /// it — in sequence with a short stagger so it reads as a signal
    /// traveling down the tree rather than several nodes blinking at once.
    ///
    /// `shellColor`, when given (a tool actually routed through a real
    /// BRPNShell), is the color used for this path — so two prompts that
    /// both route through the same shell light up the same color, and a
    /// different shell reads as visibly different, exactly the "same or
    /// proportional colors for the same kind of reflex" ask. Stages with
    /// no shell of their own (Verification, Inbound, Outbound…) fall back
    /// to each node's normal depth color, just brighter.
    ///
    /// Also feeds the *sequence* system below: every node this prompt
    /// actually touches, in firing order, gets a temporary direct flow
    /// connector to the previous one — regardless of whether they're tree-
    /// adjacent — so the real order of operations for this specific prompt
    /// is visible even when it jumps between branches.
    private func pulsePath(matchingText query: String, shellColor: UIColor?) {
        let q = query.lowercased()
        let candidates = nodeByID.values.filter { $0.text.lowercased().contains(q) || q.contains($0.text.lowercased()) }
        guard let best = candidates.max(by: { $0.text.count < $1.text.count }) else {
            onPulseAttempt?(query, false)
            return
        }
        onPulseAttempt?(query, true)

        // Repeat detection: the same node firing again shortly after itself
        // means this reflex genuinely ran more than once for this prompt —
        // pulse harder rather than identically, so a repeating reflex
        // visibly reads as repeating.
        let now = Date()
        let isRepeat = (recentFires[query].map { now.timeIntervalSince($0) < 4.0 }) ?? false
        recentFires[query] = now

        var chain: [MindMapNode] = [best]
        var cursor = best
        while let pid = cursor.parent, let p = nodeByID[pid] {
            chain.append(p)
            cursor = p
        }
        let color = shellColor ?? depthColor(best.depth).withEmphasis()
        let ordered = chain.reversed()
        for (i, node) in ordered.enumerated() {
            reflexPulseWorkItems[node.id]?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.reflexPulse(node.id, color: color, intensity: isRepeat ? 1.6 : 1.0) }
            reflexPulseWorkItems[node.id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06, execute: work)
        }
        appendToSequence(best.id, color: color)
    }

    private func reflexPulse(_ id: Int, color: UIColor, intensity: CGFloat) {
        guard let mesh = nodeMeshes[id] else { return }
        let tinted = currentEmotionTint.map { color.blended(with: $0, amount: 0.35) } ?? color
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.12
        mesh.geometry?.materials.first?.emission.contents = tinted
        mesh.scale = SCNVector3(4.0 * Float(intensity), 4.0 * Float(intensity), 4.0 * Float(intensity))
        if let edge = edgeMeshes[id] {
            edge.geometry?.materials.first?.diffuse.contents = tinted
            edge.geometry?.materials.first?.emission.contents = tinted
            edge.geometry?.materials.first?.transparency = 1.0
            // Radius only (x/z in the cylinder's own local space, before
            // its world-space rotation) — not length — so a pulsing edge
            // visibly thickens rather than stretching.
            edge.scale = SCNVector3(4.0 * Float(intensity), 1, 4.0 * Float(intensity))
        }
        // Glow burst — recolor every layer to this pulse's real color, pop
        // it in, then let it bloom outward while fading, its own slower
        // beat than the node's quick flash so it reads as light actually
        // spreading rather than just a bigger dot.
        if let glow = glowMeshes[id] {
            for layer in glow.childNodes { layer.geometry?.materials.first?.emission.contents = tinted }
            glow.opacity = 0.9 * intensity
            glow.scale = SCNVector3(0.6, 0.6, 0.6)
        }
        SCNTransaction.completionBlock = { [weak self] in
            guard let self, let node = self.nodeByID[id] else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.9
            mesh.geometry?.materials.first?.emission.contents = UIColor.black
            mesh.geometry?.materials.first?.diffuse.contents = self.depthColor(node.depth)
            mesh.scale = SCNVector3(1, 1, 1)
            if let edge = self.edgeMeshes[id] {
                edge.geometry?.materials.first?.diffuse.contents = UIColor(white: 0.75, alpha: 1)
                edge.geometry?.materials.first?.emission.contents = UIColor.black
                edge.geometry?.materials.first?.transparency = 0.35
                edge.scale = SCNVector3(1, 1, 1)
            }
            SCNTransaction.commit()
        }
        SCNTransaction.commit()

        if let glow = glowMeshes[id] {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.7
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            glow.scale = SCNVector3(1.3, 1.3, 1.3)
            glow.opacity = 0
            SCNTransaction.commit()
        }
    }

    // MARK: — Per-prompt sequence flow (the "circuit schematic" ask)
    //
    // The static tree above always stays in its normal flowchart layout —
    // that's the default state and it's correct as-is. This layer is
    // additive: while a prompt is actively processing, each node it
    // actually touches (in the real order it touched them) gets connected
    // to the one before it with a bright temporary line — even when the
    // two aren't tree-adjacent, because the real order of operations for a
    // given prompt jumps between branches (Verification lives nowhere near
    // Maze in the tree, but a maze-solving prompt visits both). That's the
    // "figure the proper order for the user's data points" part: what's
    // drawn is the actual sequence this specific prompt took, live, for
    // its whole duration. A few seconds after the prompt finishes (AI
    // Output Prompt / Sentience Journal), these fade out and the tree
    // returns to showing only its normal static structure — nothing about
    // the base tree ever actually moves.
    private var sequenceNodeIDs: [Int] = []
    private var flowGroup: SCNNode?
    private var sequenceResetWork: DispatchWorkItem?

    private func appendToSequence(_ id: Int, color: UIColor) {
        defer { sequenceNodeIDs.append(id) }
        guard let last = sequenceNodeIDs.last, last != id,
              let a = nodeMeshes[last]?.parent?.position,
              let b = nodeMeshes[id]?.parent?.position
        else { return }

        let group = flowGroup ?? {
            let g = SCNNode()
            g.name = "mindmap_flow"
            rootGroup.addChildNode(g)
            flowGroup = g
            return g
        }()

        // TF148: same fix as the tree edges — a hairline .line primitive
        // is imperceptible against the busy scene. The flow diagram is
        // meant to be the most visually prominent thing on screen while a
        // prompt is processing, so this gets a noticeably thicker radius
        // than the tree's own resting edges (0.006 vs 0.0025) on top of
        // full opacity and real emission.
        let line = buildEdgeCylinder(from: a, to: b, radius: 0.006, color: color, opacity: 0.0)
        group.addChildNode(line)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.18
        line.geometry?.materials.first?.emission.contents = color
        line.geometry?.materials.first?.transparency = 1.0
        line.opacity = 0.95
        SCNTransaction.commit()
    }

    /// Fades the whole sequence out ~2.5s after the prompt appears to have
    /// finished, then clears it — a later stage arriving before that
    /// cancels and reschedules, so a still-processing prompt never gets
    /// cut off mid-sequence.
    private func scheduleSequenceReset() {
        sequenceResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.resetSequence() }
        sequenceResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func resetSequence() {
        guard let group = flowGroup else { sequenceNodeIDs = []; return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.6
        group.opacity = 0
        SCNTransaction.completionBlock = { [weak self] in
            group.removeFromParentNode()
            self?.flowGroup = nil
        }
        SCNTransaction.commit()
        sequenceNodeIDs = []
    }

    // MARK: — Layout
    //
    // One concentric shell per depth level (0...6), same idea as the
    // buoyancy scene's GEO/MAR/AERO shells but sized to fit 7 levels rather
    // than 3. Depth 0 (the single root) sits at the center; each deeper
    // level is a larger sphere. Within a shell, nodes are spread evenly
    // using a Fibonacci sphere distribution — the same well-known
    // even-point-spacing technique used for satellite constellations —
    // rather than randomly, so the structure reads as deliberate geometry,
    // not noise. Edges are drawn as straight lines directly between a
    // parent's and child's actual 3D positions (not curved), matching the
    // "flowchart style straight lines" ask directly.

    private func shellRadius(forDepth depth: Int) -> Float {
        // Depth 0 is the root itself (radius 0, single point at center).
        // Depths 1...6 step outward. Chosen to roughly match the visual
        // scale of the existing GEO/MAR/AERO shells (0.6...1.6) so the two
        // views feel like they belong to the same scene when swapped.
        guard depth > 0 else { return 0 }
        return 0.45 + Float(depth) * 0.32
    }

    private func fibonacciSpherePoint(index: Int, total: Int, radius: Float) -> SCNVector3 {
        guard total > 1 else { return SCNVector3(0, radius, 0) }
        let goldenAngle: Float = .pi * (3 - sqrt(5))
        let y = 1 - (Float(index) / Float(total - 1)) * 2
        let r = sqrt(max(0, 1 - y * y))
        let theta = goldenAngle * Float(index)
        let x = cos(theta) * r
        let z = sin(theta) * r
        return SCNVector3(x * radius, y * radius, z * radius)
    }

    private func depthColor(_ depth: Int) -> UIColor {
        // Cool-to-warm progression outward, distinct from the buoyancy
        // shells' GEO/MAR/AERO palette so the two views are visually
        // distinguishable at a glance even mid-transition.
        switch depth {
        case 0: return UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
        case 1: return UIColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1)
        case 2: return UIColor(red: 0.55, green: 1.0, blue: 0.75, alpha: 1)
        case 3: return UIColor(red: 0.85, green: 1.0, blue: 0.45, alpha: 1)
        case 4: return UIColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1)
        case 5: return UIColor(red: 1.0, green: 0.6, blue: 0.35, alpha: 1)
        default: return UIColor(red: 1.0, green: 0.4, blue: 0.55, alpha: 1)
        }
    }

    private func build(_ data: MindMapData) {
        edgeList = data.edges
        for n in data.nodes { nodeByID[n.id] = n }

        // Group by depth, preserving each node's position within its depth
        // group for stable Fibonacci-sphere indexing.
        var byDepth: [Int: [MindMapNode]] = [:]
        for n in data.nodes { byDepth[n.depth, default: []].append(n) }

        var positions: [Int: SCNVector3] = [:]

        for (depth, group) in byDepth {
            let radius = shellRadius(forDepth: depth)
            for (i, node) in group.enumerated() {
                let pos = radius == 0
                    ? SCNVector3(0, 0, 0)
                    : fibonacciSpherePoint(index: i, total: group.count, radius: radius)
                positions[node.id] = pos
            }
        }

        // Edges first (so node markers render on top of the lines they
        // connect to, not behind them).
        let edgeGroup = SCNNode()
        edgeGroup.name = "mindmap_edges"
        rootGroup.addChildNode(edgeGroup)
        for edge in data.edges {
            guard let a = positions[edge.from], let b = positions[edge.to] else { continue }
            let line = buildEdgeCylinder(from: a, to: b, radius: 0.0025, color: UIColor(white: 0.75, alpha: 1), opacity: 0.35)
            edgeGroup.addChildNode(line)
            edgeMeshes[edge.to] = line   // keyed by child — one parent edge per non-root node
        }

        // Nodes — small icosahedron per node (matches the existing scene's
        // wireframe aesthetic exactly, see ThreeJSGeometry.icosahedron used
        // for the buoyancy shells themselves) plus a billboarded short-label
        // text right beside it.
        for node in data.nodes {
            guard let pos = positions[node.id] else { continue }
            let group = SCNNode()
            group.position = pos

            let size: CGFloat = node.depth == 0 ? 0.055 : max(0.014, 0.032 - CGFloat(node.depth) * 0.003)
            let geo = ThreeJSGeometry.icosahedron(radius: Float(size), detail: 0)
            geo.materials = [ThreeJSGeometry.wireMat(depthColor(node.depth), opacity: 0.85)]
            let mesh = SCNNode(geometry: geo)
            mesh.name = "mindmap_node_\(node.id)"
            group.addChildNode(mesh)

            let label = billboardLabel(node.label, color: depthColor(node.depth), scale: node.depth == 0 ? 1.4 : 1.0)
            label.position = SCNVector3(0, Float(size) + 0.028, 0)
            group.addChildNode(label)

            // TF147: real 3D glow, not a 2D post-effect — three
            // concentric, unlit, additive-blended spheres around each
            // node, hidden (opacity 0) until a pulse reveals them. Layered
            // soft falloff is the standard cheap approximation for a
            // volumetric glow in real-time engines; true marching-cubes
            // volumetric rendering would be far too expensive to run per-
            // node on a phone for a toggle-only view, and wouldn't look
            // meaningfully different from this at this object scale.
            // Hidden spheres are cheap for SceneKit to cull, so this is
            // fine even across all 246 nodes.
            let glow = SCNNode()
            for (layerScale, layerOpacity) in [(3.5, 0.5), (6.0, 0.24), (9.0, 0.1)] {
                let sphere = SCNSphere(radius: size * CGFloat(layerScale))
                sphere.segmentCount = 10
                let mat = SCNMaterial()
                mat.lightingModel = .constant
                mat.diffuse.contents = UIColor.clear
                mat.emission.contents = depthColor(node.depth)
                mat.blendMode = .add
                mat.writesToDepthBuffer = false
                mat.transparency = layerOpacity
                sphere.materials = [mat]
                glow.addChildNode(SCNNode(geometry: sphere))
            }
            glow.opacity = 0
            group.addChildNode(glow)
            glowMeshes[node.id] = glow

            rootGroup.addChildNode(group)
            nodeMeshes[node.id] = mesh
        }
    }

    /// TF146: one small line geometry per edge (was a single combined
    /// TF148: real, visible geometry instead of a hairline GL_LINES
    /// primitive. Confirmed directly from a screen recording (audio
    /// commentary + frame inspection) that thin .line-primitive edges are
    /// genuinely imperceptible against a bright camera background and 245
    /// other crossing white lines — a color change on one hairline strand
    /// is lost in the noise regardless of whether the underlying code
    /// fires correctly. A thin cylinder between the two points has real,
    /// visible width and — critically — a radius that can actually scale
    /// up during a pulse for a dramatic, unmistakable effect, which a GPU
    /// line primitive's fixed ~1px width never could.
    private func buildEdgeCylinder(from a: SCNVector3, to b: SCNVector3, radius: CGFloat, color: UIColor, opacity: CGFloat) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let length = CGFloat(sqrt(dx*dx + dy*dy + dz*dz))
        let cyl = SCNCylinder(radius: radius, height: max(length, 0.0001))
        cyl.radialSegmentCount = 6
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = color
        mat.emission.contents = UIColor.black
        mat.transparency = opacity
        cyl.materials = [mat]
        let node = SCNNode(geometry: cyl)
        // Cylinders are built along Y by default — orient and place at the midpoint.
        let mid = SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
        node.position = mid
        let len = Float(length)
        if len > 0.0001 {
            let dir = SCNVector3(dx/len, dy/len, dz/len)
            let dot = max(-1, min(1, dir.y))   // dot with (0,1,0)
            let angle = acos(dot)
            if angle > 0.0001 && angle < Float.pi - 0.0001 {
                // axis = (0,1,0) × dir
                let axis = SCNVector3(-dir.z, 0, dir.x)
                node.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
            } else if angle >= Float.pi - 0.0001 {
                node.rotation = SCNVector4(1, 0, 0, .pi)
            }
        }
        return node
    }

    private func billboardLabel(_ text: String, color: UIColor, scale: CGFloat) -> SCNNode {
        let textGeo = SCNText(string: text, extrusionDepth: 0.15)
        textGeo.font = UIFont.monospacedSystemFont(ofSize: 3.4, weight: .semibold)
        textGeo.flatness = 0.3
        textGeo.materials = [ThreeJSGeometry.basicMat(color, opacity: 0.95)]
        let node = SCNNode(geometry: textGeo)
        // SCNText's natural size is huge relative to the scene (font size
        // 3.4 in "points"), scaled way down to fit — cheaper than fighting
        // font metrics to get a tiny native size.
        let s = Float(0.0044 * scale)
        node.scale = SCNVector3(s, s, s)
        let (minB, maxB) = textGeo.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, minB.y, 0)
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    // MARK: — "Thinking" animation
    //
    // Explicitly NOT tied to any real data or live activity — this is meant
    // to read as Autumn's own internal reflexes turning over, a reflection
    // of the LEATR logic itself rather than anything happening in the
    // world. A signal starts at the root and randomly walks outward along
    // real edges, brightening each node it passes through and fading
    // behind it, then restarts. Multiple concurrent walkers to feel more
    // like ongoing internal activity than a single ping.

    public func startThinking() {
        guard pulseTimer == nil else { return }
        var walkers: [(current: Int, trail: [Int])] = (0..<3).map { _ in (0, []) }
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pulseFrame += 1
            for i in walkers.indices {
                var w = walkers[i]
                // Dim the trail node that's about to fall off.
                if w.trail.count > 4, let old = w.trail.first {
                    self.setEmphasis(old, on: false)
                    w.trail.removeFirst()
                }
                self.setEmphasis(w.current, on: true)
                w.trail.append(w.current)

                let children = self.edgeList.filter { $0.from == w.current }.map { $0.to }
                if let next = children.randomElement() {
                    w.current = next
                } else {
                    // Reached a leaf — fade the trail and restart from root.
                    for t in w.trail { self.setEmphasis(t, on: false) }
                    w.current = 0
                    w.trail = []
                }
                walkers[i] = w
            }
        }
    }

    public func stopThinking() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        for id in nodeMeshes.keys { setEmphasis(id, on: false) }
    }

    private func setEmphasis(_ id: Int, on: Bool) {
        guard let mesh = nodeMeshes[id], let node = nodeByID[id] else { return }
        let base = depthColor(node.depth)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.25
        mesh.geometry?.materials.first?.emission.contents = on ? UIColor.white : UIColor.black
        mesh.geometry?.materials.first?.diffuse.contents = base
        mesh.scale = on ? SCNVector3(1.6, 1.6, 1.6) : SCNVector3(1, 1, 1)
        SCNTransaction.commit()
    }
}
