import Foundation
import SceneKit
import UIKit
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

/// Builds and animates the LEATR mind map as a 3D wireframe — a toggleable
/// alternate to the buoyancy shell scene, not a replacement. Everything this
/// type creates lives under one root group (`rootGroup`) that
/// BRPNSceneViewModel adds/removes/hides as a single unit, so none of the
/// existing shell/particle/mantis code needs to change to make room for it.
public final class LeatrMindMapScene {
    public let rootGroup = SCNNode()
    private var nodeMeshes: [Int: SCNNode] = [:]
    private var edgeList: [MindMapEdge] = []
    private var nodeByID: [Int: MindMapNode] = [:]
    private var pulseTimer: Timer?
    private var pulseFrame: Int = 0
    private var observers: [NSObjectProtocol] = []
    private var reflexPulseWorkItems: [Int: DispatchWorkItem] = [:]

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
            self?.pulsePath(matchingText: stage)
        })
        observers.append(nc.addObserver(forName: ReflexActivityBus.toolNotificationName, object: nil, queue: .main) { [weak self] note in
            guard let tool = note.userInfo?["tool"] as? String else { return }
            self?.pulsePath(matchingText: tool)
        })
        observers.append(nc.addObserver(forName: ReflexActivityBus.mathOpNotificationName, object: nil, queue: .main) { [weak self] note in
            guard let op = note.userInfo?["op"] as? String else { return }
            self?.pulsePath(matchingText: op)
        })
    }

    /// Finds the node whose own text best matches (case-insensitive,
    /// longest-match-wins so "Natural Order of Operations" doesn't get
    /// shadowed by a shorter incidental match), then walks its parent
    /// chain up to the root, lighting each one in sequence with a short
    /// stagger so it reads as a signal traveling down the tree rather than
    /// several nodes blinking at once.
    private func pulsePath(matchingText query: String) {
        let q = query.lowercased()
        let candidates = nodeByID.values.filter { $0.text.lowercased().contains(q) || q.contains($0.text.lowercased()) }
        guard let best = candidates.max(by: { $0.text.count < $1.text.count }) else { return }

        var chain: [MindMapNode] = [best]
        var cursor = best
        while let pid = cursor.parent, let p = nodeByID[pid] {
            chain.append(p)
            cursor = p
        }
        // Root-to-leaf order so the animation reads as traveling outward.
        for (i, node) in chain.reversed().enumerated() {
            reflexPulseWorkItems[node.id]?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.reflexPulse(node.id) }
            reflexPulseWorkItems[node.id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06, execute: work)
        }
    }

    private func reflexPulse(_ id: Int) {
        guard let mesh = nodeMeshes[id] else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.12
        mesh.geometry?.materials.first?.emission.contents = UIColor.white
        mesh.scale = SCNVector3(2.0, 2.0, 2.0)
        SCNTransaction.completionBlock = { [weak self] in
            guard let self, let node = self.nodeByID[id] else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.9
            mesh.geometry?.materials.first?.emission.contents = UIColor.black
            mesh.geometry?.materials.first?.diffuse.contents = self.depthColor(node.depth)
            mesh.scale = SCNVector3(1, 1, 1)
            SCNTransaction.commit()
        }
        SCNTransaction.commit()
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
        rootGroup.addChildNode(buildEdgeGeometry(data.edges, positions: positions))

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

            rootGroup.addChildNode(group)
            nodeMeshes[node.id] = mesh
        }
    }

    /// All 245 edges as ONE combined line-geometry (a single draw call)
    /// rather than 245 separate node/geometry pairs — the same performance
    /// reasoning as the vessel/satellite Points systems elsewhere in this
    /// app, just with SCNGeometryPrimitiveType.line instead of .point since
    /// these need to actually connect specific coordinate pairs, not just
    /// scatter.
    private func buildEdgeGeometry(_ edges: [MindMapEdge], positions: [Int: SCNVector3]) -> SCNNode {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        for edge in edges {
            guard let a = positions[edge.from], let b = positions[edge.to] else { continue }
            let base = Int32(vertices.count)
            vertices.append(a)
            vertices.append(b)
            indices.append(base)
            indices.append(base + 1)
        }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geo = SCNGeometry(sources: [source], elements: [element])
        geo.materials = [ThreeJSGeometry.basicMat(UIColor(white: 0.7, alpha: 0.28), opacity: 0.28)]
        let node = SCNNode(geometry: geo)
        node.name = "mindmap_edges"
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
