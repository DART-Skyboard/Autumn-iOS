import SceneKit
import UIKit
import simd
import AutumnServices

// MARK: — BRPN luminous FX (leatr.xyz parity)
// Ports of the live web scene's animated layers that the SceneKit port was missing:
//   · Metal fragment shader modifiers — Fresnel rim glow + travelling energy bands
//   · Plasma splines        index.html _makePlasmaSpline / _tickAshNodes
//   · Session rings         index.html _makeSessionGroup sigTorus + receiver
//   · Audio arc lines       index.html _ashNodes._arcLines (8 arcs)
//   · MIST geometry         js/mist-module.js _spawnOutgoing / _spawnIncoming / _tick
//   · Ash Shard crystal     js/ash-shard-module.js _spawnShardAt / _spawnArrivalBurst / _tick
// Everything here is animated from BRPNAnimator.tick() on the SceneKit render thread.

// MARK: — Shader modifiers
enum BRPNShaderFX {

    /// Fresnel rim + slow travelling energy band. Brightening rgb above alpha in
    /// SceneKit's premultiplied output gives an additive glow on top of the scene.
    static let luminousFragment = """
    #pragma arguments
    float fxRimPower;
    float fxRimGain;
    float fxEnergyGain;
    float fxEnergyFreq;
    #pragma body
    float3 fxN = normalize(_surface.normal);
    float3 fxV = normalize(_surface.view);
    float fxFacing = clamp(abs(dot(fxN, fxV)), 0.0, 1.0);
    float fxRim = pow(1.0 - fxFacing, max(fxRimPower, 0.5));
    float fxPhase = scn_frame.time * 2.4 + (_surface.position.x * 0.7 + _surface.position.y) * fxEnergyFreq;
    float fxBand = pow(0.5 + 0.5 * sin(fxPhase), 8.0);
    float fxBoost = 1.0 + fxRim * fxRimGain + fxBand * fxEnergyGain;
    _output.color.rgb = _output.color.rgb * fxBoost;
    """

    /// Lines have no normals: energy pulses travel along view depth instead.
    static let energyLineFragment = """
    #pragma arguments
    float fxLineGain;
    float fxLineFreq;
    #pragma body
    float fxP = scn_frame.time * 3.1 - length(_surface.position) * fxLineFreq;
    float fxB = pow(0.5 + 0.5 * sin(fxP), 10.0);
    _output.color.rgb = _output.color.rgb * (1.15 + fxB * fxLineGain);
    """

    static func makeLuminous(_ m: SCNMaterial?, rimPower: Float = 2.2, rimGain: Float = 1.6,
                             energyGain: Float = 0.9, energyFreq: Float = 6.0) {
        guard let m else { return }
        var mods = m.shaderModifiers ?? [:]
        mods[.fragment] = luminousFragment
        m.shaderModifiers = mods
        m.setValue(NSNumber(value: rimPower), forKey: "fxRimPower")
        m.setValue(NSNumber(value: rimGain), forKey: "fxRimGain")
        m.setValue(NSNumber(value: energyGain), forKey: "fxEnergyGain")
        m.setValue(NSNumber(value: energyFreq), forKey: "fxEnergyFreq")
    }

    static func makeEnergyLine(_ m: SCNMaterial?, gain: Float = 0.8, freq: Float = 5.0) {
        guard let m else { return }
        var mods = m.shaderModifiers ?? [:]
        mods[.fragment] = energyLineFragment
        m.shaderModifiers = mods
        m.setValue(NSNumber(value: gain), forKey: "fxLineGain")
        m.setValue(NSNumber(value: freq), forKey: "fxLineFreq")
    }

    /// Wireframe + luminous material for FX meshes (opacity driven by node.opacity).
    static func glowWire(_ color: UIColor, rimGain: Float = 1.4) -> SCNMaterial {
        let m = ThreeJSGeometry.wireMat(color, opacity: 1)
        makeLuminous(m, rimPower: 2.0, rimGain: rimGain, energyGain: 0.6, energyFreq: 9.0)
        return m
    }

    static func glowLine(_ color: UIColor) -> SCNMaterial {
        let m = ThreeJSGeometry.wireMat(color, opacity: 1)
        makeEnergyLine(m, gain: 0.7, freq: 6.0)
        return m
    }

    /// Frosted crystal (Phong, translucent, specular) with a luminous rim.
    static func crystal(_ color: UIColor, emissive: CGFloat, shininess: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .phong
        m.diffuse.contents = color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        m.emission.contents = UIColor(red: r * emissive, green: g * emissive, blue: b * emissive, alpha: 1)
        m.specular.contents = UIColor.white
        m.shininess = shininess
        m.isDoubleSided = true
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        makeLuminous(m, rimPower: 1.8, rimGain: 1.2, energyGain: 0.35, energyFreq: 12.0)
        return m
    }
}

// MARK: — Curve (three.js CatmullRomCurve3, catmullrom tension 0.5)
struct BRPNCurve {
    let pts: [SIMD3<Float>]

    init(_ pts: [SIMD3<Float>]) { self.pts = pts }

    func point(_ tIn: Float) -> SIMD3<Float> {
        let l = pts.count
        guard l > 1 else { return pts.first ?? .zero }
        let t = max(0, min(1, tIn))
        let p = Float(l - 1) * t
        var i = Int(p.rounded(.down))
        var w = p - Float(i)
        if i >= l - 1 { i = l - 2; w = 1 }
        let p1 = pts[i], p2 = pts[i + 1]
        // Explicitly typed sub-expressions: Xcode's type checker times out on long
        // chained SIMD3<Float> arithmetic with mixed literals.
        let two: Float = 2, three: Float = 3
        let p1x2: SIMD3<Float> = p1 * two
        let p2x2: SIMD3<Float> = p2 * two
        let p0: SIMD3<Float> = i > 0 ? pts[i - 1] : (p1x2 - p2)
        let p3: SIMD3<Float> = i + 2 < l ? pts[i + 2] : (p2x2 - p1)
        let tension: Float = 0.5
        let t0: SIMD3<Float> = (p2 - p0) * tension
        let t1: SIMD3<Float> = (p3 - p1) * tension
        let c0: SIMD3<Float> = p1
        let c1: SIMD3<Float> = t0
        let p1x3: SIMD3<Float> = p1 * three
        let p2x3: SIMD3<Float> = p2 * three
        let t0x2: SIMD3<Float> = t0 * two
        var c2: SIMD3<Float> = p2x3 - p1x3
        c2 -= t0x2
        c2 -= t1
        var c3: SIMD3<Float> = p1x2 - p2x2
        c3 += t0
        c3 += t1
        let w2: Float = w * w
        let w3: Float = w2 * w
        var r: SIMD3<Float> = c0
        r += c1 * w
        r += c2 * w2
        r += c3 * w3
        return r
    }

    func sample(_ n: Int) -> [SIMD3<Float>] {
        (0...n).map { point(Float($0) / Float(n)) }
    }
}

extension SCNVector3 {
    /// Float SIMD copy (SceneKit's own `SCNVector3(_: SIMD3<Float>)` init covers the reverse).
    var brpnSIMD: SIMD3<Float> { SIMD3<Float>(Float(x), Float(y), Float(z)) }
}

enum BRPNFXGeometry {
    /// Line strip as SceneKit `.line` pairs.
    static func polyline(_ pts: [SIMD3<Float>]) -> SCNGeometry? {
        guard pts.count >= 2 else { return nil }
        let verts = pts.map { SCNVector3($0) }
        let src = SCNGeometrySource(vertices: verts)
        var idx: [Int32] = []
        idx.reserveCapacity((pts.count - 1) * 2)
        for i in 0..<(pts.count - 1) { idx.append(Int32(i)); idx.append(Int32(i + 1)) }
        let elem = SCNGeometryElement(indices: idx, primitiveType: .line)
        return SCNGeometry(sources: [src], elements: [elem])
    }

    /// three.js TorusGeometry lies in XY; SCNTorus lies in XZ — wrap so rotations match.
    static func torusNode(ringRadius: CGFloat, pipe: CGFloat, radialSegments: Int, tubular: Int,
                          material: SCNMaterial) -> (holder: SCNNode, torus: SCNNode) {
        let g = SCNTorus(ringRadius: ringRadius, pipeRadius: pipe)
        g.ringSegmentCount = max(3, tubular)
        g.pipeSegmentCount = max(3, radialSegments)
        g.materials = [material]
        let t = SCNNode(geometry: g)
        t.eulerAngles.x = .pi / 2
        let h = SCNNode()
        h.addChildNode(t)
        return (h, t)
    }

    static func uiColor(_ c: SIMD3<Float>, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: a)
    }

    static func rgb(_ color: UIColor) -> SIMD3<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }
}

/// Main-thread description of one plasma spline (web `_ashNodes._splines[key]`).
struct BRPNPlasmaSpec {
    let key: String
    /// nil = this device's own orb at the origin.
    let aSid: String?
    let bSid: String
    let curve: BRPNCurve
    let color: UIColor
    let resonance: Float
    let isLocal: Bool
}

// MARK: — FX system (render-thread animated)
final class BRPNFXSystem {

    private let lock = NSLock()

    let splineRoot: SCNNode = { let n = SCNNode(); n.name = "plasmaSplines"; return n }()
    let fxRoot: SCNNode = { let n = SCNNode(); n.name = "brpnFX"; return n }()
    let arcRoot: SCNNode = { let n = SCNNode(); n.name = "audioArcs"; return n }()
    private var installed = false

    /// Set from the main thread (BRPNSceneViewModel.setAudioPlayback) — also follows Autumn's TTS.
    var externalAudioActive = false

    // MARK: Plasma
    final class Plasma {
        let spec: BRPNPlasmaSpec
        let base: [SIMD3<Float>]
        let line: SCNNode
        let lineMat: SCNMaterial
        let pulse: SCNNode
        let inPulse: SCNNode
        let inMat: SCNMaterial
        let sigRing: SCNNode?
        var phase: Float
        var phaseIn: Float
        let speed: Float
        let baseOpacity: Float
        let color: SIMD3<Float>
        let retColor: SIMD3<Float>
        let wavePhase: Float
        var sigPhase: Float
        var wasFlashing = false

        init(spec: BRPNPlasmaSpec) {
            self.spec = spec
            let samples = spec.curve.sample(48)
            base = samples
            color = BRPNFXGeometry.rgb(spec.color)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            spec.color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let ret = UIColor(hue: (h + 0.16).truncatingRemainder(dividingBy: 1), saturation: s * 0.85,
                              brightness: min(1, b * 1.1), alpha: 1)
            retColor = BRPNFXGeometry.rgb(ret)
            let bOp: Float = 0.12 + spec.resonance * 0.35
            baseOpacity = bOp
            speed = 0.004 + spec.resonance * 0.012
            phase = Float.random(in: 0..<1)
            phaseIn = (Float.random(in: 0..<1) + 0.5).truncatingRemainder(dividingBy: 1)
            wavePhase = Float.random(in: 0..<(Float.pi * 2))
            sigPhase = Float.random(in: 0..<(Float.pi * 2))

            // Build via locals (no reads of self before phase-1 init completes).
            let lm = BRPNShaderFX.glowLine(spec.color)
            let ln = SCNNode(geometry: BRPNFXGeometry.polyline(samples))
            ln.geometry?.materials = [lm]
            ln.opacity = CGFloat(bOp)
            lineMat = lm
            line = ln

            let pSize = CGFloat(0.025 + spec.resonance * 0.018)
            let pg = SCNSphere(radius: pSize); pg.segmentCount = 6
            let pm = ThreeJSGeometry.basicMat(spec.color, opacity: 1)
            BRPNShaderFX.makeLuminous(pm, rimPower: 1.6, rimGain: 1.8, energyGain: 0.3, energyFreq: 4)
            pg.materials = [pm]
            pulse = SCNNode(geometry: pg)

            let ig = SCNSphere(radius: pSize * 0.78); ig.segmentCount = 5
            let im = ThreeJSGeometry.basicMat(ret, opacity: 1)
            BRPNShaderFX.makeLuminous(im, rimPower: 1.6, rimGain: 1.6, energyGain: 0.3, energyFreq: 4)
            ig.materials = [im]
            inMat = im
            inPulse = SCNNode(geometry: ig)

            if spec.isLocal {
                let col = ThreeJSGeometry.hex(spec.resonance > 0.6 ? 0xa78bfa : 0x00e5ff)
                let t = BRPNFXGeometry.torusNode(ringRadius: CGFloat(0.08 + spec.resonance * 0.04), pipe: 0.008,
                                                 radialSegments: 4, tubular: 12,
                                                 material: BRPNShaderFX.glowWire(col))
                t.holder.opacity = 0
                sigRing = t.holder
            } else {
                sigRing = nil
            }
        }
    }
    private var plasma: [Plasma] = []

    // MARK: Session rings (web _makeSessionGroup sigTorus / receiver)
    final class SessionFX {
        let sid: String
        let shells: [SCNNode]
        let sig: SCNNode
        let recv: SCNNode
        let h: Float
        let resonance: Float
        init(sid: String, shells: [SCNNode], sig: SCNNode, recv: SCNNode, h: Float, resonance: Float) {
            self.sid = sid; self.shells = shells; self.sig = sig; self.recv = recv; self.h = h; self.resonance = resonance
        }
    }
    private var sessions: [String: SessionFX] = [:]

    // MARK: Audio arcs
    final class Arc {
        let node: SCNNode
        let mat: SCNMaterial
        let phase: Float
        init(node: SCNNode, mat: SCNMaterial, phase: Float) { self.node = node; self.mat = mat; self.phase = phase }
    }
    private var arcs: [Arc] = []
    private var audioActive = false

    // MARK: MIST
    final class MistObj {
        let node: SCNNode
        let curve: BRPNCurve
        var t: Float
        let spd: Float
        let dir: Float
        let senderT: Float
        let rot: SIMD3<Float>
        init(node: SCNNode, curve: BRPNCurve, t: Float, spd: Float, dir: Float, senderT: Float, rot: SIMD3<Float>) {
            self.node = node; self.curve = curve; self.t = t; self.spd = spd; self.dir = dir; self.senderT = senderT; self.rot = rot
        }
    }
    final class MistGroup {
        let node: SCNNode
        let slot: Int
        let maxAge: Int
        let noLoop: Bool
        var age = 0
        var objs: [MistObj] = []
        var rings: [(node: SCNNode, expand: Float)] = []
        var routes: [SCNNode] = []
        init(node: SCNNode, slot: Int, maxAge: Int, noLoop: Bool) {
            self.node = node; self.slot = slot; self.maxAge = maxAge; self.noLoop = noLoop
        }
    }
    private var mist: [MistGroup] = []

    // MARK: Ash Shard
    final class ShardGroup {
        let node: SCNNode
        let body: SCNNode
        let shard: SCNNode
        let inner: SCNNode
        let shell: SCNNode
        let arc: SCNNode
        var trail: [(node: SCNNode, offset: Float, rot: SIMD3<Float>)] = []
        let curve: BRPNCurve
        let toPos: SIMD3<Float>
        let mainColor: UIColor
        let receive: Bool
        var t: Float = 0
        var age = 0
        let maxAge = 280
        var arrived = false
        init(node: SCNNode, body: SCNNode, shard: SCNNode, inner: SCNNode, shell: SCNNode, arc: SCNNode,
             curve: BRPNCurve, toPos: SIMD3<Float>, mainColor: UIColor, receive: Bool) {
            self.node = node; self.body = body; self.shard = shard; self.inner = inner; self.shell = shell
            self.arc = arc; self.curve = curve; self.toPos = toPos; self.mainColor = mainColor; self.receive = receive
        }
    }
    private var shards: [ShardGroup] = []

    final class Burst {
        let node: SCNNode
        var rings: [(node: SCNNode, expand: Float, op: Float)] = []
        var age = 0
        let maxAge: Int
        init(node: SCNNode, maxAge: Int) { self.node = node; self.maxAge = maxAge }
    }
    private var bursts: [Burst] = []

    /// Called on the main thread when an arriving shard should pulse the shells.
    var onShardArrived: ((Bool) -> Void)?

    // MARK: — Install (main thread, once)
    func install(in root: SCNNode) {
        guard !installed else {
            if splineRoot.parent == nil { root.addChildNode(splineRoot) }
            if fxRoot.parent == nil { root.addChildNode(fxRoot) }
            if arcRoot.parent == nil { root.addChildNode(arcRoot) }
            return
        }
        installed = true
        root.addChildNode(splineRoot)
        root.addChildNode(fxRoot)
        root.addChildNode(arcRoot)
        var built: [Arc] = []
        for i in 0..<8 {
            let mat = BRPNShaderFX.glowLine(ThreeJSGeometry.hex(0x00aaff))
            let n = SCNNode(geometry: BRPNFXGeometry.polyline([.zero, SIMD3<Float>(0, 0.01, 0)]))
            n.geometry?.materials = [mat]
            n.opacity = 0
            n.name = "audioArc_\(i)"
            arcRoot.addChildNode(n)
            built.append(Arc(node: n, mat: mat, phase: Float(i) * (Float.pi * 2 / 8)))
        }
        lock.lock(); arcs = built; lock.unlock()
    }

    // MARK: — Main-thread mutators
    func setPlasma(_ specs: [BRPNPlasmaSpec]) {
        let built = specs.map { Plasma(spec: $0) }
        lock.lock()
        let old = plasma
        plasma = built
        lock.unlock()
        for p in old {
            p.line.removeFromParentNode(); p.pulse.removeFromParentNode()
            p.inPulse.removeFromParentNode(); p.sigRing?.removeFromParentNode()
        }
        for p in built {
            splineRoot.addChildNode(p.line)
            splineRoot.addChildNode(p.pulse)
            splineRoot.addChildNode(p.inPulse)
            if let s = p.sigRing { splineRoot.addChildNode(s) }
        }
    }

    func registerSession(_ s: SessionFX) {
        lock.lock(); sessions[s.sid] = s; lock.unlock()
    }

    func unregisterSession(_ sid: String) {
        lock.lock(); sessions.removeValue(forKey: sid); lock.unlock()
    }

    func addMist(_ g: MistGroup) {
        fxRoot.addChildNode(g.node)
        lock.lock(); mist.append(g); lock.unlock()
    }

    func addShard(_ g: ShardGroup) {
        fxRoot.addChildNode(g.node)
        lock.lock(); shards.append(g); lock.unlock()
    }

    /// Web `_spawnArrivalBurst` — 3 expanding wireframe rings.
    func spawnArrivalBurst(at pos: SIMD3<Float>, color: UIColor) {
        let b = makeBurst(at: pos, color: color)
        fxRoot.addChildNode(b.node)
        lock.lock(); bursts.append(b); lock.unlock()
    }

    private func makeBurst(at pos: SIMD3<Float>, color: UIColor) -> Burst {
        let b = Burst(node: SCNNode(), maxAge: 80)
        b.node.name = "shardBurst"
        for i in 0..<3 {
            let t = BRPNFXGeometry.torusNode(ringRadius: CGFloat(0.08 + Float(i) * 0.07), pipe: 0.01,
                                             radialSegments: 4, tubular: 18, material: BRPNShaderFX.glowWire(color))
            t.holder.position = SCNVector3(pos)
            t.holder.eulerAngles = SCNVector3(Float.random(in: 0..<Float.pi), Float.random(in: 0..<Float.pi), 0)
            let op = 0.7 - Float(i) * 0.15
            t.holder.opacity = CGFloat(op)
            b.node.addChildNode(t.holder)
            b.rings.append((t.holder, 0.008 + Float(i) * 0.003, op))
        }
        return b
    }

    // MARK: — Render-thread tick
    func tick(frame: Int, thinking: Bool, activity: Float) {
        lock.lock()
        defer { lock.unlock() }
        let f = Float(frame)
        // Web _tickAshNodes runs every 3rd frame with t = frame * 0.005.
        let t = f * 0.005
        if frame % 10 == 0 { audioActive = externalAudioActive || AutumnTTS.shared.isSpeaking }
        tickSessions(t: t)
        tickPlasma(frame: frame, t: t, thinking: thinking, activity: activity)
        tickArcs(f: f, frame: frame)
        tickMist()
        tickShards()
        tickBursts()
    }

    private func tickSessions(t: Float) {
        for s in sessions.values {
            for (i, m) in s.shells.enumerated() {
                m.eulerAngles.y = t * (0.3 + Float(i) * 0.15)
                m.eulerAngles.x = t * (0.1 + Float(i) * 0.08)
            }
            // Sigmatic ring — visible + rotating with pattern resonance.
            let sigVis = s.resonance * 0.65
            let sigOp = max(0, min(0.75, sigVis * (0.5 + 0.5 * sin(t * 1.8 + s.h * 6))))
            s.sig.opacity = CGFloat(sigOp)
            s.sig.eulerAngles.z = t * (0.4 + s.resonance * 0.6)
            s.sig.eulerAngles.x = t * 0.15
            // Receiver — flashes when the local→node incoming pulse arrives.
            var flash: Float = 0
            if let sp = plasma.first(where: { $0.spec.isLocal && $0.spec.bSid == s.sid }) {
                flash = max(0, 1 - sp.phaseIn * 8) * 0.9
            }
            s.recv.opacity = CGFloat(max(0, min(0.92, flash)))
            s.recv.eulerAngles.z = t * 1.2
            let sc = 1 + flash * 0.4
            s.recv.scale = SCNVector3(sc, sc, sc)
        }
    }

    private func tickPlasma(frame: Int, t: Float, thinking: Bool, activity: Float) {
        guard !plasma.isEmpty else { return }
        let speedMult: Float = thinking ? 3.2 : 1.0
        let boost = 1 + activity * 2.5
        let rebuildLines = frame % 3 == 0
        func wave(_ frac: Float, _ wp: Float, _ extra: Float = 0, _ extra2: Float = 0) -> SIMD3<Float> {
            let env = sin(frac * .pi)
            let w1 = sin(frac * 6 + t * 3.5 + wp + extra) * 0.045 * env
            let w2 = sin(frac * 11 - t * 5.0 + wp * 1.7 + extra2) * 0.022 * env
            return SIMD3<Float>(w1 * boost, w2 * boost, (w1 * 0.5 + w2 * 0.5) * boost)
        }
        for sp in plasma {
            // 1. Plasma wave — dual sine ripple, zero at the anchored ends.
            if rebuildLines {
                var pts = sp.base
                let n = Float(max(1, pts.count - 1))
                for i in 0..<pts.count { pts[i] += wave(Float(i) / n, sp.wavePhase) }
                if let g = BRPNFXGeometry.polyline(pts) {
                    g.materials = [sp.lineMat]
                    sp.line.geometry = g
                }
            }
            // 2/3. Bidirectional travelling pulses (web steps speed per 3 frames).
            sp.phase = (sp.phase + sp.speed * speedMult / 3).truncatingRemainder(dividingBy: 1)
            sp.pulse.position = SCNVector3(sp.spec.curve.point(sp.phase) + wave(sp.phase, sp.wavePhase))
            sp.phaseIn = (sp.phaseIn - sp.speed * speedMult * 0.85 / 3 + 1).truncatingRemainder(dividingBy: 1)
            sp.inPulse.position = SCNVector3(sp.spec.curve.point(sp.phaseIn) + wave(sp.phaseIn, sp.wavePhase, 1.2, 0.8))
            // 4. Breathing opacity.
            let breathe = 0.5 + 0.5 * sin(t * 2.2 + sp.wavePhase)
            let activeBoost = activity * 0.4
            sp.line.opacity = CGFloat(min(0.85, sp.baseOpacity * (0.55 + 0.45 * breathe) + activeBoost))
            sp.pulse.opacity = CGFloat(min(0.95, 0.5 + 0.45 * breathe + activeBoost))
            sp.inPulse.opacity = CGFloat(min(0.80, 0.38 + 0.36 * breathe + activeBoost * 0.8))
            // 5. Pulse throb.
            let throb = 0.9 + 0.25 * sin(t * 8 + sp.wavePhase * 3)
            let sizeBoost = 1 + activity * 1.5
            let s1 = throb * sizeBoost, s2 = throb * 0.78 * sizeBoost
            sp.pulse.scale = SCNVector3(s1, s1, s1)
            sp.inPulse.scale = SCNVector3(s2, s2, s2)
            // 6. Sigmatic ring at the midpoint of local splines.
            if let ring = sp.sigRing {
                ring.position = SCNVector3(sp.spec.curve.point(0.5))
                sp.sigPhase += 0.05 / 3
                ring.eulerAngles.z += 0.022 / 3
                let sigOp = (activity * 0.35 + (thinking ? 0.25 : 0)) * (0.4 + 0.6 * sin(sp.sigPhase))
                ring.opacity = CGFloat(max(0, min(0.9, sigOp)))
                let sc = 1 + activity * 0.5
                ring.scale = SCNVector3(sc, sc, sc)
            }
            // 7. Discharge flash while Autumn is thinking.
            if thinking {
                let flash = 0.7 + 0.3 * sin(t * 18 + sp.wavePhase)
                let c = SIMD3<Float>(sp.color.x * flash + (1 - flash), sp.color.y * flash + (1 - flash) * 0.85,
                                     sp.color.z * flash + (1 - flash) * 0.7)
                let rc = SIMD3<Float>(sp.retColor.x * flash + (1 - flash) * 0.8, sp.retColor.y * flash + (1 - flash) * 0.9,
                                      sp.retColor.z * flash + (1 - flash))
                sp.lineMat.diffuse.contents = BRPNFXGeometry.uiColor(c)
                sp.lineMat.emission.contents = BRPNFXGeometry.uiColor(c)
                sp.inMat.diffuse.contents = BRPNFXGeometry.uiColor(rc)
                sp.inMat.emission.contents = BRPNFXGeometry.uiColor(rc)
                sp.wasFlashing = true
            } else if sp.wasFlashing {
                sp.lineMat.diffuse.contents = BRPNFXGeometry.uiColor(sp.color)
                sp.lineMat.emission.contents = BRPNFXGeometry.uiColor(sp.color)
                sp.inMat.diffuse.contents = BRPNFXGeometry.uiColor(sp.retColor)
                sp.inMat.emission.contents = BRPNFXGeometry.uiColor(sp.retColor)
                sp.wasFlashing = false
            }
        }
    }

    private func tickArcs(f: Float, frame: Int) {
        for (ai, arc) in arcs.enumerated() {
            if !audioActive {
                if arc.node.opacity > 0 { arc.node.opacity = max(0, arc.node.opacity - 0.06) }
                continue
            }
            // Electrical arc: zigzag from the core out to shell level.
            let r = 0.22 + sin(f * 0.08 + arc.phase) * 0.08
            let R = 1.8 + sin(f * 0.05 + arc.phase * 1.3) * 0.4
            let baseAngle = arc.phase + f * 0.04 * (ai % 2 == 0 ? 1 : -1)
            var pts: [SIMD3<Float>] = []
            for pi in 0..<6 {
                let tt = Float(pi) / 5
                let r2 = r + (R - r) * tt
                let jitter: Float = (pi > 0 && pi < 5) ? Float.random(in: -0.275...0.275) : 0
                let a = baseAngle + jitter + sin(f * 0.2 + Float(pi)) * 0.3
                let elev = sin(f * 0.06 + arc.phase + Float(pi) * 0.5) * 0.6
                pts.append(SIMD3<Float>(cos(a) * r2 * cos(elev), sin(elev) * r2 * 0.7, sin(a) * r2 * cos(elev)))
            }
            if let g = BRPNFXGeometry.polyline(pts) {
                g.materials = [arc.mat]
                arc.node.geometry = g
            }
            arc.node.opacity = CGFloat(0.7 + Float.random(in: 0...0.3))
            let col = ThreeJSGeometry.hex(frame % 4 < 2 ? 0x00aaff : 0x44ddff)
            arc.mat.diffuse.contents = col
            arc.mat.emission.contents = col
        }
    }

    private func tickMist() {
        guard !mist.isEmpty else { return }
        var keep: [MistGroup] = []
        for g in mist {
            g.age += 1
            let fade = 1 - Float(g.age) / Float(g.maxAge)
            if fade <= 0 { g.node.removeFromParentNode(); continue }
            for r in g.rings {
                let s = r.node.scale.x * (1 + r.expand)
                r.node.scale = SCNVector3(s, s, s)
                r.node.opacity = CGFloat(0.7 * fade * min(1, Float(g.age) / 8))
            }
            for route in g.routes { route.opacity = CGFloat(0.18 * fade) }
            for o in g.objs {
                o.t += o.dir * o.spd
                if g.noLoop {
                    o.t = max(0, min(1, o.t))
                } else {
                    if o.t > 1 { o.t = o.senderT + Float.random(in: 0..<0.08) }
                    if o.t < 0 { o.t = (o.senderT == 0 ? 1 : o.senderT) - Float.random(in: 0..<0.08) }
                }
                let tt = max(0, min(1, o.t))
                var p = o.curve.point(tt)
                if g.slot == 2 { p.x += sin(Float(g.age) * 0.05 + tt * 4) * 0.06 }
                o.node.position = SCNVector3(p)
                o.node.eulerAngles.x += o.rot.x
                o.node.eulerAngles.y += o.rot.y
                o.node.eulerAngles.z += o.rot.z
                // Brightest at the leading edge, transparent near the sender.
                let tFade = abs(o.t - o.senderT)
                o.node.opacity = CGFloat(max(0, 0.9 * fade * pow(tFade + 0.08, 0.35)))
            }
            keep.append(g)
        }
        mist = keep
    }

    private func tickShards() {
        guard !shards.isEmpty else { return }
        var keep: [ShardGroup] = []
        for g in shards {
            g.age += 1
            let fade = 1 - Float(g.age) / Float(g.maxAge)
            if fade <= 0 { g.node.removeFromParentNode(); continue }
            g.t = min(1, g.t + 0.006)
            let pos = g.curve.point(g.t)
            g.body.position = SCNVector3(pos)
            if g.t >= 0.95 && !g.arrived {
                g.arrived = true
                let b = makeBurst(at: g.toPos, color: g.mainColor)
                fxRoot.addChildNode(b.node)
                bursts.append(b)
                let receive = g.receive
                DispatchQueue.main.async { [weak self] in self?.onShardArrived?(receive) }
            }
            g.shard.eulerAngles.y += 0.04
            g.inner.eulerAngles.x += 0.06
            g.inner.eulerAngles.z += 0.04
            g.shell.eulerAngles.y -= 0.02
            g.shell.eulerAngles.x += 0.015
            g.shard.opacity = CGFloat(0.52 * fade)
            g.inner.opacity = CGFloat(0.8 * fade)
            g.shell.opacity = CGFloat(0.12 * fade)
            for tr in g.trail {
                let tp = g.curve.point(max(0, g.t - tr.offset))
                tr.node.position = SCNVector3(tp)
                tr.node.eulerAngles.x += tr.rot.x
                tr.node.eulerAngles.y += tr.rot.y
                tr.node.opacity = CGFloat(0.5 * fade)
            }
            g.arc.opacity = CGFloat(0.22 * fade)
            keep.append(g)
        }
        shards = keep
    }

    private func tickBursts() {
        guard !bursts.isEmpty else { return }
        var keep: [Burst] = []
        for b in bursts {
            b.age += 1
            let fade = 1 - Float(b.age) / Float(b.maxAge)
            if fade <= 0 { b.node.removeFromParentNode(); continue }
            for r in b.rings {
                let s = r.node.scale.x * (1 + r.expand)
                r.node.scale = SCNVector3(s, s, s)
                r.node.opacity = CGFloat(0.65 * fade * (r.op / 0.7))
            }
            keep.append(b)
        }
        bursts = keep
    }
}
