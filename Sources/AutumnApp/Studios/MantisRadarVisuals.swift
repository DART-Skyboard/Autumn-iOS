import SwiftUI
import SceneKit
import UIKit

// MARK: — Mantis Radar visual parity with leatr.xyz/mr.html
//
// Ports the web globe look (day/night Earth shader, atmosphere shell, 3,500-
// star field, lat/long grid, glowing point sprites) and the aerial HUD
// widgets (radar sweep, corner brackets, RANGE / CONTACTS / NEXT SCAN) to
// native SceneKit + SwiftUI. Everything here is self-contained so the
// renderer in MantisRadarView.swift only has to call into it.

enum MantisGlobeArt {
    /// mr.html glbRenderer.setClearColor(0x000508)
    static let spaceColor = UIColor(red: 0, green: 5.0 / 255.0, blue: 8.0 / 255.0, alpha: 1)
    static let cyan = UIColor(red: 0, green: 0.96, blue: 1, alpha: 1)
    static let amber = UIColor(red: 1, green: 0.72, blue: 0.2, alpha: 1)

    // MARK: Earth day/night shader

    /// Metal fragment modifier ported from mr.html's Earth ShaderMaterial.
    /// The normal is taken to world space (Earth-fixed: the globe never
    /// rotates, the camera orbits) so the terminator follows the real
    /// subsolar point as the camera moves — `sunDir` is Earth-fixed too.
    static let earthShaderModifier = """
    #pragma arguments
    float3 sunDir;
    #pragma body
    float3 vn = normalize(_surface.normal);
    float3 wn = normalize((scn_frame.inverseViewTransform * float4(vn, 0.0)).xyz);
    float d = dot(wn, normalize(sunDir));
    float t = smoothstep(-0.15, 0.18, d);
    float3 dayCol = float3(0.03, 0.14, 0.42);
    float3 nightCol = float3(0.005, 0.015, 0.048);
    float3 col = mix(nightCol, dayCol, t);
    float nc = pow(clamp(-d, 0.0, 1.0), 0.9) * 0.09;
    col += float3(0.9, 0.7, 0.3) * nc;
    float tg = clamp(1.0 - abs(d) * 6.0, 0.0, 1.0);
    col += float3(0.1, 0.4, 0.9) * tg * 0.15;
    float rim = 1.0 - abs(dot(vn, float3(0.0, 0.0, 1.0)));
    col += float3(0.0, 0.3, 0.8) * pow(rim, 5.0) * 0.3;
    _output.color = float4(col, 1.0);
    """

    static func earthMaterial(sunDir: SCNVector3) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: 0.03, green: 0.14, blue: 0.42, alpha: 1)
        m.shaderModifiers = [.fragment: earthShaderModifier]
        m.setValue(NSValue(scnVector3: sunDir), forKey: "sunDir")
        return m
    }

    static func setSun(_ dir: SCNVector3, on material: SCNMaterial?) {
        material?.setValue(NSValue(scnVector3: dir), forKey: "sunDir")
    }

    // MARK: Atmosphere shell

    /// Back-face blue halo (mr.html: SphereGeometry(1.025) BackSide, 0x0044bb,
    /// opacity .07) with a small Fresnel lift so the rim reads on a phone.
    static let atmosphereShaderModifier = """
    #pragma body
    float3 n = normalize(_surface.normal);
    float rim = 1.0 - abs(n.z);
    float a = 0.07 + 0.30 * pow(rim, 3.0);
    float3 c = float3(0.0, 0.267, 0.733);
    _output.color = float4(c * a, a);
    """

    static func atmosphereNode(radius: CGFloat) -> SCNNode {
        let s = SCNSphere(radius: radius)
        s.segmentCount = 48
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: 0, green: 0.267, blue: 0.733, alpha: 0.07)
        m.cullMode = .front
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        m.shaderModifiers = [.fragment: atmosphereShaderModifier]
        s.firstMaterial = m
        let n = SCNNode(geometry: s)
        n.name = "atmosphere"
        n.renderingOrder = 5
        return n
    }

    // MARK: Starfield

    /// mr.html buildStars(): 3,500 points on a shell r = 50…75.
    static func starfieldNode(count: Int = 3500) -> SCNNode {
        var verts = [Float](); verts.reserveCapacity(count * 3)
        var cols = [Float](); cols.reserveCapacity(count * 3)
        for _ in 0..<count {
            let phi = acos(2 * Float.random(in: 0...1) - 1)
            let theta = 2 * Float.pi * Float.random(in: 0...1)
            let r = 50 + Float.random(in: 0...25)
            verts += [r * sin(phi) * cos(theta), r * cos(phi), r * sin(phi) * sin(theta)]
            // PointsMaterial opacity .7 over black ≈ brightness .7; a little
            // spread keeps the field from looking like a uniform grid.
            let b = Float.random(in: 0.45...0.9)
            cols += [b, b, min(1, b * 1.04)]
        }
        let vData = verts.withUnsafeBufferPointer { Data(buffer: $0) }
        let cData = cols.withUnsafeBufferPointer { Data(buffer: $0) }
        let vSrc = SCNGeometrySource(data: vData, semantic: .vertex, vectorCount: count,
                                     usesFloatComponents: true, componentsPerVector: 3,
                                     bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let cSrc = SCNGeometrySource(data: cData, semantic: .color, vectorCount: count,
                                     usesFloatComponents: true, componentsPerVector: 3,
                                     bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let idx: [Int32] = (0..<Int32(count)).map { $0 }
        let elem = SCNGeometryElement(indices: idx, primitiveType: .point)
        elem.pointSize = 0.2
        elem.minimumPointScreenSpaceRadius = 0.6
        elem.maximumPointScreenSpaceRadius = 1.6
        let geo = SCNGeometry(sources: [vSrc, cSrc], elements: [elem])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.white
        m.writesToDepthBuffer = false
        geo.firstMaterial = m
        let n = SCNNode(geometry: geo)
        n.name = "stars"
        n.renderingOrder = -10
        return n
    }

    // MARK: Lat / long grid

    /// mr.html buildGridLines(): parallels every 30° (equator brighter),
    /// meridians every 30° (prime meridian brighter), plus the tropics
    /// (±23.44°) and polar circles (±66.56°).
    static func gridNode(radius r: Float = 1.002) -> SCNNode {
        let root = SCNNode()
        root.name = "latlon-grid"
        var faint: [Float] = [], med: [Float] = [], tropic: [Float] = []
        func parallel(_ lat: Double, into v: inout [Float]) {
            var prev: SCNVector3?
            var lo = 0.0
            while lo <= 360.0 {
                let p = latLon(lat: lat, lon: lo, r: r)
                if let q = prev { v += [q.x, q.y, q.z, p.x, p.y, p.z] }
                prev = p
                lo += 2
            }
        }
        func meridian(_ lon: Double, into v: inout [Float]) {
            var prev: SCNVector3?
            var la = -88.0
            while la <= 88.0 {
                let p = latLon(lat: la, lon: lon, r: r)
                if let q = prev { v += [q.x, q.y, q.z, p.x, p.y, p.z] }
                prev = p
                la += 2
            }
        }
        for lat in stride(from: -60.0, through: 60.0, by: 30.0) {
            if lat == 0 { parallel(lat, into: &med) } else { parallel(lat, into: &faint) }
        }
        for lat in [23.44, -23.44, 66.56, -66.56] { parallel(lat, into: &tropic) }
        for lon in stride(from: 0.0, to: 360.0, by: 30.0) {
            if lon == 0 { meridian(lon, into: &med) } else { meridian(lon, into: &faint) }
        }
        // Web opacities are .055 / .2 / .1 on a 1-px WebGL line; lifted a
        // touch so the hairlines survive Retina downsampling.
        if let n = ThreeJSGeometry.lineSegments(faint, color: cyan, opacity: 0.09) { root.addChildNode(n) }
        if let n = ThreeJSGeometry.lineSegments(tropic, color: cyan, opacity: 0.15) { root.addChildNode(n) }
        if let n = ThreeJSGeometry.lineSegments(med, color: cyan, opacity: 0.26) { root.addChildNode(n) }
        return root
    }

    static func latLon(lat: Double, lon: Double, r: Float) -> SCNVector3 {
        let la = Float(lat * .pi / 180)
        let lo = Float(lon * .pi / 180)
        return SCNVector3(r * cos(la) * cos(lo), r * sin(la), -r * cos(la) * sin(lo))
    }

    // MARK: Sun direction

    /// mr.html computeSunDir(): low-precision solar ephemeris → subsolar
    /// point (declination, RA − GMST) → unit vector in the globe frame.
    static func sunDirection(at date: Date = Date()) -> SCNVector3 {
        let jd = date.timeIntervalSince1970 / 86400.0 + 2440587.5
        let day = jd - 2451545.0
        func wrap360(_ x: Double) -> Double { let v = x.truncatingRemainder(dividingBy: 360); return v < 0 ? v + 360 : v }
        let L = wrap360(280.460 + 0.9856474 * day)
        let g = wrap360(357.528 + 0.9856003 * day) * .pi / 180
        let lam = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * .pi / 180
        let eps = 23.439 * Double.pi / 180
        let dec = asin(sin(eps) * sin(lam))
        let ra = atan2(cos(eps) * sin(lam), cos(lam))
        let gmst = TLEKepler.gmst(date)
        var subLon = (ra - gmst) * 180 / .pi
        subLon = wrap360(subLon + 180) - 180
        let v = latLon(lat: dec * 180 / .pi, lon: subLon, r: 1)
        let len = max(1e-6, sqrt(v.x * v.x + v.y * v.y + v.z * v.z))
        return SCNVector3(v.x / len, v.y / len, v.z / len)
    }

    // MARK: Glow point sprites

    private static var glowImages: [String: UIImage] = [:]
    private static var glowPlanes: [String: SCNPlane] = [:]

    /// mr.html sat/vessel CanvasTexture: white core → tint → transparent.
    static func glowImage(r: CGFloat, g: CGFloat, b: CGFloat, vessel: Bool) -> UIImage {
        let key = String(format: "%.3f-%.3f-%.3f-%d", r, g, b, vessel ? 1 : 0)
        if let img = glowImages[key] { return img }
        let size = CGSize(width: 64, height: 64)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors: [CGColor]
            let stops: [CGFloat]
            if vessel {
                colors = [
                    UIColor(white: 1, alpha: 1).cgColor,
                    UIColor(red: 1, green: 216.0 / 255, blue: 140.0 / 255, alpha: 0.95).cgColor,
                    UIColor(red: r, green: g, blue: b, alpha: 0.6).cgColor,
                    UIColor(red: r, green: g, blue: b, alpha: 0).cgColor
                ]
                stops = [0, 0.3, 0.65, 1]
            } else {
                colors = [
                    UIColor(white: 1, alpha: 1).cgColor,
                    UIColor(red: min(1, r * 0.35 + 0.65), green: min(1, g * 0.35 + 0.65), blue: min(1, b * 0.35 + 0.65), alpha: 0.9).cgColor,
                    UIColor(red: r, green: g, blue: b, alpha: 0.5).cgColor,
                    UIColor(red: r, green: g, blue: b, alpha: 0).cgColor
                ]
                stops = [0, 0.25, 0.6, 1]
            }
            guard let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: stops) else { return }
            let c = CGPoint(x: 32, y: 32)
            ctx.cgContext.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: 32, options: [])
        }
        glowImages[key] = img
        return img
    }

    /// Shared billboard quad per (color, size) so hundreds of markers reuse
    /// a handful of geometries/materials.
    static func glowPlane(r: CGFloat, g: CGFloat, b: CGFloat, size: CGFloat, vessel: Bool = false) -> SCNPlane {
        let key = String(format: "%.3f-%.3f-%.3f-%.4f-%d", r, g, b, size, vessel ? 1 : 0)
        if let p = glowPlanes[key] { return p }
        let p = SCNPlane(width: size, height: size)
        let m = SCNMaterial()
        let img = glowImage(r: r, g: g, b: b, vessel: vessel)
        m.diffuse.contents = img
        m.lightingModel = .constant
        m.blendMode = .add
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        p.firstMaterial = m
        glowPlanes[key] = p
        return p
    }

    static func makeSpriteNode(name: String, plane: SCNPlane) -> SCNNode {
        let n = SCNNode(geometry: plane)
        n.name = name
        n.renderingOrder = 20
        n.constraints = [SCNBillboardConstraint()]
        return n
    }
}

// MARK: — HUD widgets (SwiftUI)

/// mr.html `.mc` corner brackets: 20×20, 2-pt cyan, 6 pt in from each corner.
struct MantisCornerBrackets: View {
    var color: Color = Color(hex: "#00f5ff")
    var body: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width, h = geo.size.height, i: CGFloat = 6, l: CGFloat = 20
                p.move(to: CGPoint(x: i, y: i + l)); p.addLine(to: CGPoint(x: i, y: i)); p.addLine(to: CGPoint(x: i + l, y: i))
                p.move(to: CGPoint(x: w - i - l, y: i)); p.addLine(to: CGPoint(x: w - i, y: i)); p.addLine(to: CGPoint(x: w - i, y: i + l))
                p.move(to: CGPoint(x: i, y: h - i - l)); p.addLine(to: CGPoint(x: i, y: h - i)); p.addLine(to: CGPoint(x: i + l, y: h - i))
                p.move(to: CGPoint(x: w - i - l, y: h - i)); p.addLine(to: CGPoint(x: w - i, y: h - i)); p.addLine(to: CGPoint(x: w - i, y: h - i - l))
            }
            .stroke(color, lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}

/// mr.html drawRadar(): rotating sweep with fading contact blips.
/// Blips are unit-disc offsets (x east, y south) of contacts inside the scan radius.
struct MantisRadarSweep: View {
    var blips: [CGPoint]
    var size: CGFloat = 116

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, sz in
                let t = tl.date.timeIntervalSinceReferenceDate
                // web: sweepAngle += .025 rad / frame @60 fps ≈ 1.5 rad/s
                let sweep = (t * 1.5).truncatingRemainder(dividingBy: 2 * .pi)
                let cx = sz.width / 2, cy = sz.height / 2, r = min(sz.width, sz.height) / 2 - 4
                let c = CGPoint(x: cx, y: cy)
                let cyan = Color(red: 0, green: 0.96, blue: 1)
                func circle(_ rad: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2)) }

                ctx.fill(circle(r), with: .color(Color(red: 0, green: 10.0 / 255, blue: 14.0 / 255).opacity(0.96)))
                for i in 1...4 {
                    ctx.stroke(circle(r * CGFloat(i) / 4), with: .color(cyan.opacity(i == 4 ? 0.2 : 0.07)), lineWidth: 1)
                }
                var cross = Path()
                cross.move(to: CGPoint(x: cx, y: cy - r)); cross.addLine(to: CGPoint(x: cx, y: cy + r))
                cross.move(to: CGPoint(x: cx - r, y: cy)); cross.addLine(to: CGPoint(x: cx + r, y: cy))
                ctx.stroke(cross, with: .color(cyan.opacity(0.07)), lineWidth: 1)

                // Trailing wedge (0.6π) behind the leading line; angles measured
                // clockwise from north like the canvas rotate() on the web.
                let lead = Angle(radians: sweep - .pi / 2)
                let tail = Angle(radians: sweep - .pi / 2 - .pi * 0.6)
                var wedge = Path()
                wedge.move(to: c)
                wedge.addArc(center: c, radius: r, startAngle: tail, endAngle: lead, clockwise: false)
                wedge.closeSubpath()
                ctx.fill(wedge, with: .radialGradient(
                    Gradient(stops: [
                        .init(color: cyan.opacity(0), location: 0),
                        .init(color: cyan.opacity(0.10), location: 0.6),
                        .init(color: cyan.opacity(0), location: 1)
                    ]),
                    center: c, startRadius: 0, endRadius: r))
                var line = Path()
                line.move(to: c)
                line.addLine(to: CGPoint(x: cx + r * CGFloat(cos(lead.radians)), y: cy + r * CGFloat(sin(lead.radians))))
                ctx.stroke(line, with: .color(cyan.opacity(0.55)), lineWidth: 1.5)

                // Blips light up as the beam passes and fade over one revolution.
                for b in blips {
                    let ang = atan2(Double(b.y), Double(b.x)) // screen angle, 0 = east, clockwise
                    var since = (lead.radians - ang).truncatingRemainder(dividingBy: 2 * .pi)
                    if since < 0 { since += 2 * .pi }
                    let fade = max(0, 1 - since / (2 * .pi) * 1.25)
                    guard fade > 0.02 else { continue }
                    let p = CGPoint(x: cx + b.x * (r - 6), y: cy + b.y * (r - 6))
                    let glow = Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
                    ctx.fill(glow, with: .color(cyan.opacity(0.25 * fade)))
                    let dot = Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
                    ctx.fill(dot, with: .color(cyan.opacity(fade)))
                }
                ctx.stroke(circle(r), with: .color(cyan.opacity(0.22)), lineWidth: 1.5)
                ctx.fill(circle(3), with: .color(cyan))
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    /// mr.html updateRadarBlips(): project contacts into the unit scan disc.
    static func blips(for aircraft: [RadarAircraft], userLat: Double, userLon: Double, radiusKm: Double) -> [CGPoint] {
        let kmPerDegLat = 111.32
        let cosLat = max(0.01, cos(userLat * .pi / 180))
        var out: [CGPoint] = []
        out.reserveCapacity(aircraft.count)
        for a in aircraft {
            let dx = (a.lon - userLon) / (radiusKm / kmPerDegLat / cosLat)
            let dy = -(a.lat - userLat) / (radiusKm / kmPerDegLat)
            if dx * dx + dy * dy <= 1 { out.append(CGPoint(x: dx, y: dy)) }
        }
        return out
    }
}

/// mr.html #map-hud: RANGE (km) · CONTACTS · NEXT SCAN.
struct MantisAerialHUD: View {
    @ObservedObject var feed: RadarFeed

    var body: some View {
        let cyan = Color(hex: "#00f5ff")
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("RANGE").foregroundColor(cyan.opacity(0.55))
                    Text("\(Int(feed.rangeKm.rounded()))").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(cyan)
                    Text("km").foregroundColor(cyan.opacity(0.55))
                }
                HStack(spacing: 4) {
                    Text("CONTACTS").foregroundColor(cyan.opacity(0.55))
                    Text("\(feed.aircraft.count)").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(cyan)
                }
                Text("NEXT SCAN: \(feed.secondsToNextScan(now: tl.date))s")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(cyan.opacity(0.4))
            }
            .font(.system(size: 10, design: .monospaced))
            .tracking(1)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(red: 3.0 / 255, green: 10.0 / 255, blue: 14.0 / 255).opacity(0.88))
            .overlay(Rectangle().stroke(cyan.opacity(0.25), lineWidth: 1))
        }
    }
}

/// mr.html #globe-time-hud: UTC, local time, date, time zone.
struct MantisGlobeTimeHUD: View {
    var body: some View {
        let cyan = Color(hex: "#00f5ff")
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            VStack(alignment: .trailing, spacing: 3) {
                Text(Self.utc.string(from: tl.date) + " UTC")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(cyan)
                Text("LOCAL " + Self.local.string(from: tl.date))
                Text(Self.day.string(from: tl.date))
                Text("TZ: " + TimeZone.current.identifier)
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(cyan.opacity(0.6))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(red: 3.0 / 255, green: 10.0 / 255, blue: 14.0 / 255).opacity(0.85))
            .overlay(Rectangle().stroke(cyan.opacity(0.25), lineWidth: 1))
        }
        .allowsHitTesting(false)
    }

    private static let utc: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    private static let local: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d, yyyy"
        return f
    }()
}
