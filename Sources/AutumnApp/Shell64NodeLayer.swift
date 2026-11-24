import SceneKit
import UIKit
import simd
import QuartzCore
import AutumnServices

// MARK: — Shell 64 activity node (web parity: Autumn/js/shell64-node-module.js, FEED_CONTRACT v1)
// When anyone runs a calculation on shell64.dartmeadow.com, every Autumn viewer sees an x-ray
// group of four huddled figures seated on a glowing teal plasma curve outside the buoyancy
// shells. The nested Shell 64 sphere rises from the middle of their ring, hovers above their
// heads while calculations run, then eases back down and fades ~6–9 s after activity stops.
//
//  · Feed: `readnodes.shell64` (5 s scene poll, no extra request) → `feed(_:)` on the main thread.
//  · Animation: `tick()` from BRPNAnimator on the SceneKit render thread.
//  · Respects LIVE FEED (hidden at once when off). Up to 6 sessions, newest first.
//  · Asset: Resources/shell64-node.usdz — figures baked in the seat frame (scene units, Y up,
//    origin = curve centre at the seat, +Z = curve tangent). The emblem is rebuilt procedurally.
final class Shell64NodeLayer {

    // MARK: Constants (FEED_CONTRACT §3 / USDZ customData)
    static let outerShellR: Float = 1.9
    static let target: Float = (outerShellR * 2) / 6          // 0.633 — group's largest dimension
    static let maxSessions = 6
    static let idleFadeAfter: Double = 6.0                      // no `n` change for 6 s →
    static let fadeDuration: Double = 3.0                       // … fade over 3 s → removed (~9 s)
    static let curveR: CGFloat = 0.012
    /// GLB → scene scale the USDZ was baked with (H 3.608 GLB → 0.6147 scene units).
    static let glbScale: Float = 0.6147 / 3.608
    static let emblemRestY: Float = -0.11177
    static let emblemHoverY: Float = 0.56771
    static let emblemRestScale: Float = 0.35
    static let emblemR: Float = 0.6 * glbScale                  // web buildEmblem R = 0.6 (GLB units)

    let root: SCNNode = { let n = SCNNode(); n.name = "shell64Layer"; return n }()

    private let lock = NSLock()
    private var installed = false
    private var liveFeedOn = true

    // Feed state (web S.local)
    private struct Rec { var n: Int?; var lastActiveAt: Double; var calcTimes: [Double] }
    private var local: [String: Rec] = [:]
    private var rate: Float = 0
    private var rateTarget: Float = 0
    private var lastTick: Double = 0
    private let t0 = CACurrentMediaTime()

    // Template (loaded once, off the main thread)
    private var template: SCNNode?
    private var loading = false
    private var loadFailed = false

    private var nodes: [String: Group] = [:]

    // MARK: — Main-thread API

    func install(in scene: SCNNode) {
        if root.parent == nil { scene.addChildNode(root) }
        guard !installed else { return }
        installed = true
        loadTemplate()
    }

    func setLiveFeed(_ on: Bool) {
        lock.lock(); liveFeedOn = on; lock.unlock()
    }

    /// `summary` = readnodes.shell64 (nil when the backend doesn't send one — nothing changes).
    func feed(_ summary: Shell64Summary?, liveFeed: Bool) {
        let now = CACurrentMediaTime()
        lock.lock()
        defer { lock.unlock() }
        liveFeedOn = liveFeed
        guard let summary else { return }
        for s in summary.sessions { touch(sid: s.sid, n: s.n, now: now) }
        rateTarget = max(rateFromLocal(now), Float(summary.rate))
    }

    // MARK: — Feed helpers (lock held)

    private func touch(sid: String, n: Int?, now: Double) {
        guard !sid.isEmpty else { return }
        var rec = local[sid] ?? Rec(n: -1, lastActiveAt: 0, calcTimes: [])
        if n == nil || n != rec.n {
            rec.lastActiveAt = now
            rec.calcTimes.append(now)
            if rec.calcTimes.count > 60 { rec.calcTimes.removeFirst() }
        }
        if let n { rec.n = n }
        local[sid] = rec
    }

    private func rateFromLocal(_ now: Double) -> Float {
        var c = 0
        for r in local.values { c += r.calcTimes.filter { now - $0 < 60 }.count }
        return min(1, Float(log(1 + Double(c)) / log(121)))
    }

    // MARK: — Asset

    private func loadTemplate() {
        guard template == nil, !loading, !loadFailed else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var built: SCNNode?
            if let url = Bundle.main.url(forResource: "shell64-node", withExtension: "usdz"),
               let scn = try? SCNScene(url: url, options: [.checkConsistency: false]) {
                let top = scn.rootNode.childNode(withName: "Shell64Node", recursively: true) ?? scn.rootNode
                // Figures only — the emblem is rebuilt procedurally (exact web buildEmblem).
                let figs = top.childNode(withName: "Figures", recursively: true)
                let holder = SCNNode()
                holder.name = "Shell64Figures"
                if let figs {
                    for c in figs.childNodes { holder.addChildNode(c.clone()) }
                } else {
                    for c in top.childNodes where c.name != "Emblem" && c.name != "Looks" {
                        holder.addChildNode(c.clone())
                    }
                }
                built = holder.childNodes.isEmpty ? nil : holder
            }
            guard let self else { return }
            self.lock.lock()
            self.template = built
            self.loadFailed = (built == nil)
            self.loading = false
            self.lock.unlock()
            if built == nil { print("[Shell64Node] shell64-node.usdz failed to load — emblem + curve only") }
        }
    }

    // MARK: — Shaders

    /// Web XRAY_FS as a SceneKit fragment modifier: Fresnel rim, travelling scanlines, static
    /// grain, sweeping band, additive (premultiplied) output, fade-driven alpha.
    static let xrayFragment = """
    #pragma arguments
    float s64Act;
    float s64Rate;
    float s64Fade;
    float s64Gain;
    float s64Scale;
    float3 s64ColA;
    float3 s64ColB;
    #pragma body
    float3 sN = normalize(_surface.normal);
    float3 sV = normalize(_surface.view);
    float sF = 1.0 - abs(dot(sN, sV));
    float sRim = pow(sF, 2.2);
    float4 sW = scn_frame.inverseViewTransform * float4(_surface.position, 1.0);
    float sY = sW.y / max(s64Scale, 0.0001);
    float sT = scn_frame.time;
    float sSpd = 6.0 + 10.0 * s64Rate;
    float sLines = smoothstep(0.86, 1.0, sin(sY * 420.0 - sT * sSpd) * 0.5 + 0.5);
    float2 sCell = floor(sW.xz / max(s64Scale, 0.0001) * 160.0 + sY * 97.0) + floor(sT * 24.0);
    float sH = fract(sin(dot(sCell, float2(127.1, 311.7))) * 43758.5453);
    float sGrain = step(0.985 - s64Act * 0.03 - s64Rate * 0.02, sH);
    float sBand = smoothstep(0.0, 0.08, abs(fract(sY * 0.9 - sT * (0.25 + 0.6 * s64Rate)) - 0.5) - 0.42);
    float3 sCol = mix(s64ColA, s64ColB, clamp(sF * 1.2 + 0.25 * sin(sT * 1.7 + sY * 6.0), 0.0, 1.0));
    float sA = 0.05 + sRim * 0.85 + sLines * (0.10 + 0.25 * s64Act) + sGrain * 0.35 * (0.4 + s64Act) + sBand * 0.35 * s64Act;
    sA = clamp(sA * 0.8 * s64Fade, 0.0, 1.0);
    _output.color = float4(sCol * (0.25 + sRim * 1.1 + sLines * 0.5) * s64Gain * sA, sA);
    """

    static func rgb(_ hex: UInt32) -> SCNVector3 {
        SCNVector3(Float((hex >> 16) & 0xff) / 255, Float((hex >> 8) & 0xff) / 255, Float(hex & 0xff) / 255)
    }

    static func xrayMat(_ colA: UInt32, _ colB: UInt32, gain: Float = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.black
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        m.isDoubleSided = true
        m.shaderModifiers = [.fragment: xrayFragment]
        m.setValue(NSValue(scnVector3: rgb(colA)), forKey: "s64ColA")
        m.setValue(NSValue(scnVector3: rgb(colB)), forKey: "s64ColB")
        m.setValue(NSNumber(value: gain), forKey: "s64Gain")
        m.setValue(NSNumber(value: glbScale), forKey: "s64Scale")
        m.setValue(NSNumber(value: Float(0)), forKey: "s64Act")
        m.setValue(NSNumber(value: Float(0)), forKey: "s64Rate")
        m.setValue(NSNumber(value: Float(0)), forKey: "s64Fade")
        return m
    }

    static func additive(_ hex: UInt32, image: UIImage? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image ?? ThreeJSGeometry.hex(hex)
        if image != nil { m.multiply.contents = ThreeJSGeometry.hex(hex) }
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    /// Web glareTexture() — soft cyan radial glow.
    static let glareImage: UIImage = {
        let size = CGSize(width: 128, height: 128)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(red: 200/255, green: 1, blue: 250/255, alpha: 0.9).cgColor,
                          UIColor(red: 80/255, green: 230/255, blue: 1, alpha: 0.25).cgColor,
                          UIColor(red: 0, green: 0, blue: 0, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.25, 1]) {
                ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                                 endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
            }
        }
    }()

    /// Web SPARK_FS — bright core + 4-point star cross.
    static let sparkImage: UIImage = {
        let n = 64
        let size = CGSize(width: n, height: n)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            for y in 0..<n {
                for x in 0..<n {
                    let cx = (Double(x) + 0.5) / Double(n) - 0.5, cy = (Double(y) + 0.5) / Double(n) - 0.5
                    let d = sqrt(cx * cx + cy * cy)
                    let core = exp(-d * d * 60)
                    let cross = exp(-abs(cx) * 40) * exp(-abs(cy) * 6) + exp(-abs(cy) * 40) * exp(-abs(cx) * 6)
                    let a = min(1, core + cross * 0.6)
                    if a < 0.01 { continue }
                    UIColor(white: 1, alpha: CGFloat(a)).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()

    // MARK: — Procedural geometry (three.js SphereGeometry / TorusGeometry ports)

    static func mesh(_ pos: [SIMD3<Float>], _ nrm: [SIMD3<Float>], _ idx: [Int32]) -> SCNGeometry {
        let src = SCNGeometrySource(vertices: pos.map { SCNVector3($0) })
        let nsrc = SCNGeometrySource(normals: nrm.map { SCNVector3($0) })
        let el = SCNGeometryElement(indices: idx, primitiveType: .triangles)
        return SCNGeometry(sources: [src, nsrc], elements: [el])
    }

    static func sphere(_ r: Float, ws: Int, hs: Int, phiStart: Float = 0, phiLen: Float = 2 * .pi,
                       thetaStart: Float = 0, thetaLen: Float = .pi, roughen: Bool = false) -> SCNGeometry {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [Int32] = []
        let thetaEnd = min(thetaStart + thetaLen, .pi)
        for iy in 0...hs {
            let v = Float(iy) / Float(hs)
            for ix in 0...ws {
                let u = Float(ix) / Float(ws)
                let ph = phiStart + u * phiLen, th = thetaStart + v * thetaLen
                var p = SIMD3<Float>(-r * cos(ph) * sin(th), r * cos(th), r * sin(ph) * sin(th))
                let n = simd_length(p) > 0 ? simd_normalize(p) : SIMD3<Float>(0, 1, 0)
                if roughen {   // weathered rock (web: v *= 1 + sin(37x)cos(29y)sin(41z)·0.035)
                    let q = sin(p.x / r * 0.6 * 37) * cos(p.y / r * 0.6 * 29) * sin(p.z / r * 0.6 * 41)
                    p *= 1 + q * 0.035
                }
                pos.append(p); nrm.append(n)
            }
        }
        let row = ws + 1
        for iy in 0..<hs {
            for ix in 0..<ws {
                let a = Int32(iy * row + ix + 1), b = Int32(iy * row + ix)
                let c = Int32((iy + 1) * row + ix), d = Int32((iy + 1) * row + ix + 1)
                if iy != 0 || thetaStart > 0 { idx += [a, b, d] }
                if iy != hs - 1 || thetaEnd < .pi { idx += [b, c, d] }
            }
        }
        return mesh(pos, nrm, idx)
    }

    /// three.js TorusGeometry — lies in the XY plane, arc around +Z.
    static func torus(_ R: Float, _ tube: Float, radial: Int, tubular: Int, arc: Float = 2 * .pi) -> SCNGeometry {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [Int32] = []
        for j in 0...radial {
            for i in 0...tubular {
                let u = Float(i) / Float(tubular) * arc
                let v = Float(j) / Float(radial) * 2 * .pi
                let p = SIMD3<Float>((R + tube * cos(v)) * cos(u), (R + tube * cos(v)) * sin(u), tube * sin(v))
                let c = SIMD3<Float>(R * cos(u), R * sin(u), 0)
                pos.append(p); nrm.append(simd_normalize(p - c))
            }
        }
        let row = tubular + 1
        for j in 1...radial {
            for i in 1...tubular {
                let a = Int32(row * j + i - 1), b = Int32(row * (j - 1) + i - 1)
                let c = Int32(row * (j - 1) + i), d = Int32(row * j + i)
                idx += [a, b, d, b, c, d]
            }
        }
        return mesh(pos, nrm, idx)
    }

    /// Tube along a sampled curve (three TubeGeometry, radialSegments 6).
    static func tube(_ pts: [SIMD3<Float>], radius: Float, radial: Int = 6) -> SCNGeometry {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [Int32] = []
        let n = pts.count
        var prevN = SIMD3<Float>(0, 1, 0)
        for i in 0..<n {
            let a = pts[max(0, i - 1)], b = pts[min(n - 1, i + 1)]
            var t = b - a
            t = simd_length(t) > 1e-6 ? simd_normalize(t) : SIMD3<Float>(0, 0, 1)
            var nn = prevN - t * simd_dot(prevN, t)
            if simd_length(nn) < 1e-4 { nn = simd_cross(t, SIMD3<Float>(1, 0, 0)) }
            nn = simd_normalize(nn); prevN = nn
            let bn = simd_normalize(simd_cross(t, nn))
            for j in 0...radial {
                let v = Float(j) / Float(radial) * 2 * .pi
                let d = nn * cos(v) + bn * sin(v)
                pos.append(pts[i] + d * radius); nrm.append(d)
            }
        }
        let row = radial + 1
        for i in 1..<n {
            for j in 1...radial {
                let a = Int32(row * (i - 1) + j - 1), b = Int32(row * i + j - 1)
                let c = Int32(row * i + j), d = Int32(row * (i - 1) + j)
                idx += [a, b, d, b, c, d]
            }
        }
        return mesh(pos, nrm, idx)
    }

    static func quat(_ x: Float, _ y: Float, _ z: Float) -> simd_quatf {
        // three.js Euler 'XYZ' → q = qx · qy · qz
        simd_quatf(angle: x, axis: SIMD3<Float>(1, 0, 0)) *
        simd_quatf(angle: y, axis: SIMD3<Float>(0, 1, 0)) *
        simd_quatf(angle: z, axis: SIMD3<Float>(0, 0, 1))
    }

    // MARK: — Emblem (web buildEmblem): cracked outer cutaway · bronze middle cutaway ·
    // teal core with equatorial seam + gold arc · glowing cyan octahedral gem.
    final class Emblem {
        let node: SCNNode
        let outer: SCNNode
        let middle: SCNNode
        let core: SCNNode
        let gem: SCNNode
        let gemGlow: SCNNode
        let gemGlowMat: SCNMaterial
        let crackMat: SCNMaterial
        let mats: [SCNMaterial]

        private static func add(_ parent: SCNNode, _ g: SCNGeometry, _ m: SCNMaterial,
                                _ mats: inout [SCNMaterial]) -> SCNNode {
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.renderingOrder = 6
            parent.addChildNode(n)
            mats.append(m)
            return n
        }

        init() {
            let R = Shell64NodeLayer.emblemR
            var ms: [SCNMaterial] = []
            let nodeL = SCNNode(); nodeL.name = "Shell64Emblem"
            let outerL = SCNNode(), middleL = SCNNode(), coreL = SCNNode()

            nodeL.addChildNode(outerL)
            _ = Emblem.add(outerL, Shell64NodeLayer.sphere(R, ws: 40, hs: 28, phiStart: .pi * 0.32, phiLen: .pi * 1.55,
                                                         thetaStart: 0.05, thetaLen: .pi * 0.95, roughen: true),
                         Shell64NodeLayer.xrayMat(0x7f93a8, 0xdfeeff, gain: 0.9), &ms)
            // Jagged crack rims along both cut edges.
            var crack: [SIMD3<Float>] = []
            for c in 0...26 {
                let a0: Float = .pi * 0.32
                let th: Float = 0.05 + Float(c) / 26 * .pi * 0.95
                let jag: Float = c % 2 == 1 ? 0.06 : -0.04
                crack.append(SIMD3<Float>(cos(a0 + jag) * sin(th) * -R, cos(th) * R, sin(a0 + jag) * sin(th) * R))
            }
            let crack2: [SIMD3<Float>] = crack.map { p in
                let a2: Float = .pi * (0.32 + 1.55)
                let rr = (p.x * p.x + p.z * p.z).squareRoot()
                let j: Float = Int((p.y * 97).rounded()) % 2 != 0 ? 0.05 : -0.05
                return SIMD3<Float>(-cos(a2 + j) * rr, p.y, sin(a2 + j) * rr)
            }
            let cm = Shell64NodeLayer.additive(0xbfe9ff)
            for pts in [crack, crack2] {
                if let g = BRPNFXGeometry.polyline(pts) {
                    g.materials = [cm]
                    let n = SCNNode(geometry: g); n.renderingOrder = 7; n.opacity = 0.7
                    outerL.addChildNode(n)
                }
            }

            nodeL.addChildNode(middleL)
            _ = Emblem.add(middleL, Shell64NodeLayer.sphere(R * 0.8, ws: 36, hs: 24, phiStart: .pi * 0.15, phiLen: .pi * 1.6,
                                                          thetaStart: 0.12, thetaLen: .pi * 0.8),
                         Shell64NodeLayer.xrayMat(0xc8923a, 0xfff0c8, gain: 1.0), &ms)
            let ring = Emblem.add(middleL, Shell64NodeLayer.torus(R * 0.8, R * 0.025, radial: 6, tubular: 64, arc: .pi * 1.6),
                                Shell64NodeLayer.xrayMat(0xe0a948, 0xfff6dc, gain: 1.2), &ms)
            ring.simdOrientation = Shell64NodeLayer.quat(.pi / 2, 0, 0)

            nodeL.addChildNode(coreL)
            _ = Emblem.add(coreL, Shell64NodeLayer.sphere(R * 0.58, ws: 32, hs: 22),
                         Shell64NodeLayer.xrayMat(0x1f9c98, 0xbffff4, gain: 1.1), &ms)
            let seam = Emblem.add(coreL, Shell64NodeLayer.torus(R * 0.585, R * 0.018, radial: 6, tubular: 64),
                                Shell64NodeLayer.xrayMat(0x9fe9e2, 0xffffff, gain: 1.3), &ms)
            seam.simdOrientation = Shell64NodeLayer.quat(.pi / 2, 0, 0)
            let arcN = Emblem.add(coreL, Shell64NodeLayer.torus(R * 0.6, R * 0.016, radial: 6, tubular: 48, arc: .pi * 0.85),
                                Shell64NodeLayer.xrayMat(0xe0b04f, 0xfff3cf, gain: 1.3), &ms)
            arcN.simdOrientation = Shell64NodeLayer.quat(0.35, 0.2, 1.05)

            let gemPivot = SCNNode()
            gemPivot.simdOrientation = Shell64NodeLayer.quat(-0.55, 0.65, 0)
            coreL.addChildNode(gemPivot)
            let gemL = Emblem.add(gemPivot, ThreeJSGeometry.octahedron(radius: R * 0.11, detail: 0),
                                Shell64NodeLayer.xrayMat(0x37e8ff, 0xffffff, gain: 2.2), &ms)
            gemL.simdPosition = SIMD3<Float>(0, R * 0.62, 0)
            let plane = SCNPlane(width: CGFloat(R * 0.55), height: CGFloat(R * 0.55))
            let gmat = Shell64NodeLayer.additive(0x5ff6ff, image: Shell64NodeLayer.glareImage)
            plane.materials = [gmat]
            let glow = SCNNode(geometry: plane)
            glow.constraints = [SCNBillboardConstraint()]
            glow.renderingOrder = 8
            glow.opacity = 0
            gemL.addChildNode(glow)

            node = nodeL; outer = outerL; middle = middleL; core = coreL
            gem = gemL; gemGlow = glow; gemGlowMat = gmat; crackMat = cm; mats = ms
        }
    }

    // MARK: — One visible session group (web makeNode)
    final class Group {
        let sid: String
        let slot: Int
        let wrap: SCNNode
        let root: SCNNode
        let emblem: Emblem
        let mats: [SCNMaterial]
        let curve: BRPNCurve
        let u: Float
        let base: [SIMD3<Float>]
        let line: SCNNode
        let lineMat: SCNMaterial
        let tube: SCNNode
        let pulse: SCNNode
        let glare: SCNNode
        let sparks: SCNParticleSystem
        var act: Float = 0
        var fade: Float = 0
        var rise: Float = 0
        var phase: Float = Float.random(in: 0..<1)
        var frame = 0

        init(sid: String, slot: Int, template: SCNNode?) {
            let T = Shell64NodeLayer.target
            let wrapL = SCNNode(); wrapL.name = "Shell64Wrap:\(sid)"
            let rootL = SCNNode(); rootL.name = "Shell64Node:\(sid)"
            var ms: [SCNMaterial] = []

            // Figures: x-ray material per figure (cyan / violet / green / pink, rim → white).
            let palette: [(UInt32, UInt32)] = [(0x7cf6ff, 0xffffff), (0x9b7bff, 0xd8f7ff),
                                               (0x39ff9c, 0xe8fff6), (0xff6ad5, 0xfff0fb)]
            if let template {
                let figs = template.clone()
                for (i, fig) in figs.childNodes.enumerated() {
                    let pal = palette[i % palette.count]
                    let m = Shell64NodeLayer.xrayMat(pal.0, pal.1)
                    ms.append(m)
                    fig.enumerateHierarchy { n, _ in
                        guard let g = n.geometry?.copy() as? SCNGeometry else { return }
                        g.materials = [m]       // copy() shares vertex data; materials are per-group
                        n.geometry = g
                        n.renderingOrder = 5
                    }
                }
                rootL.addChildNode(figs)
            }

            // Emblem rests low in the ring centre (campfire).
            let em = Emblem()
            em.node.simdPosition = SIMD3<Float>(0, Shell64NodeLayer.emblemRestY, 0)
            em.node.simdScale = SIMD3<Float>(repeating: Shell64NodeLayer.emblemRestScale)
            rootL.addChildNode(em.node)
            ms += em.mats

            // Sparkle cloud (scene units) — twinkle density follows activity × calc rate.
            let ps = SCNParticleSystem()
            ps.emitterShape = SCNSphere(radius: CGFloat(T * 0.85))
            ps.birthLocation = .volume
            ps.birthRate = 0
            ps.particleLifeSpan = 1.1
            ps.particleLifeSpanVariation = 0.7
            ps.particleSize = CGFloat(T * 0.022)
            ps.particleSizeVariation = CGFloat(T * 0.018)
            ps.particleVelocity = 0.01
            ps.particleVelocityVariation = 0.02
            ps.particleImage = Shell64NodeLayer.sparkImage
            ps.particleColor = ThreeJSGeometry.hex(0xbff8ff)
            ps.blendMode = .additive
            ps.isLightingEnabled = false
            ps.sortingMode = .none
            let twinkle = CAKeyframeAnimation()
            twinkle.values = [0.0, 1.0, 0.15, 0.9, 0.0]
            twinkle.keyTimes = [0, 0.2, 0.45, 0.65, 1]
            ps.propertyControllers = [.opacity: SCNParticlePropertyController(animation: twinkle)]
            let sparkNode = SCNNode()
            sparkNode.simdPosition = SIMD3<Float>(0, T * 0.18, 0)
            sparkNode.addParticleSystem(ps)
            rootL.addChildNode(sparkNode)

            let gp = SCNPlane(width: CGFloat(T * 1.7), height: CGFloat(T * 1.7))
            gp.materials = [Shell64NodeLayer.additive(0xffffff, image: Shell64NodeLayer.glareImage)]
            let gl = SCNNode(geometry: gp)
            gl.constraints = [SCNBillboardConstraint()]
            gl.simdPosition = SIMD3<Float>(0, T * 0.15, 0)
            gl.opacity = 0
            rootL.addChildNode(gl)

            // Seat curve (glowing teal rail through the ring centre) + travelling pulse.
            let sc = Shell64NodeLayer.buildSeatCurve(Shell64NodeLayer.anchorFor(slot))
            let pts = sc.curve.sample(96)
            let lm = Shell64NodeLayer.additive(0x39ffd2)
            let ln = SCNNode(geometry: BRPNFXGeometry.polyline(pts))
            ln.geometry?.materials = [lm]
            ln.opacity = 0
            let tg = Shell64NodeLayer.tube(sc.curve.sample(120), radius: Float(Shell64NodeLayer.curveR))
            tg.materials = [Shell64NodeLayer.additive(0x22e6ff)]
            let tb = SCNNode(geometry: tg)
            tb.opacity = 0
            let pg = SCNSphere(radius: 0.02); pg.segmentCount = 8
            pg.materials = [Shell64NodeLayer.additive(0xc9fff4)]
            let pn = SCNNode(geometry: pg)
            pn.opacity = 0
            wrapL.addChildNode(ln)
            wrapL.addChildNode(tb)
            wrapL.addChildNode(pn)
            wrapL.addChildNode(rootL)

            self.sid = sid; self.slot = slot
            wrap = wrapL; root = rootL; emblem = em; mats = ms
            curve = sc.curve; u = sc.u; base = pts
            line = ln; lineMat = lm; tube = tb; pulse = pn; glare = gl; sparks = ps
        }
    }

    // MARK: — Curve (web buildSeatCurve / anchorFor)

    static func anchorFor(_ k: Int) -> SIMD3<Float> {
        if k == 0 { return SIMD3<Float>(1.55, 1.30, 0.65) }
        let a: [Float] = [2.45, -0.7, 0.75, -2.3, 1.2]
        let y: [Float] = [1.0, 1.55, -1.25, 0.55, 1.75]
        let i = (k - 1) % 5
        return SIMD3<Float>(cos(a[i]) * 1.95, y[i], sin(a[i]) * 1.0 + 0.4)
    }

    static func buildSeatCurve(_ anchor: SIMD3<Float>) -> (curve: BRPNCurve, u: Float) {
        var d = simd_normalize(SIMD3<Float>(anchor.x, 0, anchor.z))
        d = simd_normalize(SIMD3<Float>(-d.z * 0.35 + d.x * 0.94, 0, d.x * 0.35 + d.z * 0.94))
        let up = SIMD3<Float>(0, 1, 0)
        let pts: [SIMD3<Float>] = [
            .zero,
            anchor * 0.45 - up * 0.05,
            anchor - d * 0.55 - up * 0.06,
            anchor - d * 0.2,
            anchor - up * 0.012,
            anchor + d * 0.2,
            anchor + d * 0.6 + up * 0.08,
            anchor + d * 1.1 + SIMD3<Float>(0.2, 0.35, -0.3),
        ]
        let curve = BRPNCurve(pts)
        var best: Float = 0, bd: Float = .greatestFiniteMagnitude
        for i in 0...400 {
            let t = Float(i) / 400
            let q = simd_distance_squared(curve.point(t), anchor)
            if q < bd { bd = q; best = t }
        }
        return (curve, best)
    }

    // MARK: — Render-thread tick (web tick + animateNode)

    func tick() {
        lock.lock()
        defer { lock.unlock() }
        let now = CACurrentMediaTime()
        let t = Float(now - t0)
        let dt = Float(min(0.25, max(0.001, lastTick == 0 ? 1.0 / 60 : now - lastTick)))
        lastTick = now
        func k(_ r: Float) -> Float { 1 - exp(-dt * r) }

        // Which sessions want to be visible (newest first, capped at 6).
        var want: [(sid: String, at: Double)] = local
            .map { (sid: $0.key, at: $0.value.lastActiveAt) }
            .filter { now - $0.at < Self.idleFadeAfter + Self.fadeDuration }
            .sorted { $0.at > $1.at }
        if want.count > Self.maxSessions { want = Array(want.prefix(Self.maxSessions)) }
        if !liveFeedOn { want = [] }
        let wantIds = Set(want.map(\.sid))
        for (sid, r) in local where now - r.lastActiveAt > 120 { local.removeValue(forKey: sid) }

        if !loading && (template != nil || loadFailed) {
            for w in want where nodes[w.sid] == nil {
                let used = Set(nodes.values.map(\.slot))
                var slot = 0
                while used.contains(slot) { slot += 1 }
                guard slot < Self.maxSessions else { continue }
                let g = Group(sid: w.sid, slot: slot, template: template)
                root.addChildNode(g.wrap)
                nodes[w.sid] = g
            }
        }
        rateTarget *= exp(-dt * 0.03)
        rate += (max(rateTarget, rateFromLocal(now)) - rate) * k(2.4)

        for (sid, g) in nodes {
            let wanted = wantIds.contains(sid)
            let idle = local[sid].map { now - $0.lastActiveAt } ?? 1e9
            let active = wanted && idle < Self.idleFadeAfter
            let fadeOut: Double = max(0, 1 - (idle - Self.idleFadeAfter) / Self.fadeDuration)
            let fadeTarget: Float = !wanted ? 0 : (idle < Self.idleFadeAfter ? 1 : Float(fadeOut))
            g.fade += (fadeTarget - g.fade) * k(fadeTarget > g.fade ? 3.5 : 6.0)
            g.act += ((active ? 1 : 0) - g.act) * k(3.0)
            g.rise += ((active ? 1 : 0) - g.rise) * k(active ? 1.6 : 1.1)
            if !liveFeedOn { g.fade = 0 }
            if g.fade < 0.01 && !wanted {
                g.wrap.removeFromParentNode()
                nodes.removeValue(forKey: sid)
                continue
            }
            animate(g, t: t, dt: dt)
        }
    }

    private static func ease(_ x: Float) -> Float {
        x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }

    private func animate(_ g: Group, t: Float, dt: Float) {
        let fr = dt * 60
        let a = g.act, f = g.fade, rt = rate
        g.frame += 1
        // Wave-displace the spline like the other buoyancy splines (rebuild every 2nd frame).
        if g.frame % 2 == 0 {
            let n = Float(max(1, g.base.count - 1))
            let pts: [SIMD3<Float>] = g.base.enumerated().map { i, p in
                let s = Float(i) / n, w = sin(s * .pi)
                return SIMD3<Float>(p.x, p.y + sin(t * 2.1 + s * 9.0) * 0.03 * w, p.z + cos(t * 1.7 + s * 7.0) * 0.025 * w)
            }
            if let geo = BRPNFXGeometry.polyline(pts) {
                geo.materials = [g.lineMat]
                g.line.geometry = geo
            }
        }
        g.line.opacity = CGFloat((0.45 + 0.5 * a) * f)
        g.tube.opacity = CGFloat((0.08 + 0.22 * a) * f)
        g.phase = (g.phase + (0.0025 + 0.008 * rt) * fr).truncatingRemainder(dividingBy: 1)
        g.pulse.simdPosition = g.curve.point(g.phase)
        g.pulse.opacity = CGFloat(0.95 * f)

        // Ride the curve: seat point at u with the same wave, so the rail never leaves the thighs.
        let p0 = g.curve.point(g.u), sw = sin(g.u * .pi)
        g.root.simdPosition = SIMD3<Float>(p0.x, p0.y + sin(t * 2.1 + g.u * 9.0) * 0.03 * sw,
                                           p0.z + cos(t * 1.7 + g.u * 7.0) * 0.025 * sw)
        var tan = g.curve.point(min(1, g.u + 0.002)) - g.curve.point(max(0, g.u - 0.002))
        tan.y = 0
        if simd_length(tan) > 1e-6 {
            g.root.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: simd_normalize(tan))
        }

        let aN = NSNumber(value: a), rN = NSNumber(value: rt), fN = NSNumber(value: f)
        for m in g.mats {
            m.setValue(aN, forKey: "s64Act")
            m.setValue(rN, forKey: "s64Rate")
            m.setValue(fN, forKey: "s64Fade")
        }
        // Sparkles ∝ calculation rate; faint while idle-fading.
        g.sparks.birthRate = CGFloat(f * (40 + 360 * a * (0.25 + rt)))
        g.sparks.particleColor = UIColor(red: 0.75, green: 0.97, blue: 1, alpha: CGFloat(min(1, 0.25 + 0.55 * a)))
        g.glare.opacity = CGFloat((0.12 + 0.35 * a * (0.7 + 0.3 * sin(t * (4.0 + 6.0 * rt)))) * f)

        // Emblem: rise from the ring centre, hover + bob above their heads, counter-rotate.
        let e = g.emblem
        let r = Self.ease(max(0, min(1, g.rise)))
        let span: Float = Self.emblemHoverY - Self.emblemRestY
        let bob: Float = sin(t * 1.6) * 0.06 * Self.glbScale * r
        let y: Float = Self.emblemRestY + span * r + bob
        e.node.simdPosition = SIMD3<Float>(0, y, 0)
        e.node.simdScale = SIMD3<Float>(repeating: Self.emblemRestScale + (1 - Self.emblemRestScale) * r)
        let spin = (0.004 + 0.02 * a * (0.4 + rt)) * fr
        e.outer.eulerAngles.y += spin
        e.outer.eulerAngles.x = sin(t * 0.3) * 0.15
        e.middle.eulerAngles.y -= spin * 1.4
        e.middle.eulerAngles.z += spin * 0.6
        e.core.eulerAngles.x += spin * 0.8
        e.core.eulerAngles.y += spin * 0.5
        let beat = 0.5 + 0.5 * sin(t * (3.0 + 7.0 * rt))
        e.gem.eulerAngles.y += (0.03 + 0.05 * rt) * fr
        e.gem.simdScale = SIMD3<Float>(repeating: 1 + 0.25 * beat * a)
        e.gemGlow.opacity = CGFloat((0.35 + 0.5 * beat * a) * f)
        let crackOp = CGFloat((0.3 + 0.4 * a) * f)
        for c in e.outer.childNodes where c.geometry?.firstMaterial === e.crackMat { c.opacity = crackOp }
    }
}
