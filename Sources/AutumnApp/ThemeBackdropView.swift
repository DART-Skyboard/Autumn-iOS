import SwiftUI

// MARK: — Theme default atmospheres (leatr.xyz css/theme-backdrops.css, Autumn PR #44)
// Layered gradients replace the old low-quality bundled background videos.
// Sits at the bottom of the shell ZStack; the user's own ART image/video still
// draws on top of it exactly as before (ThemeVideoBackground / ArtImageBackground).

/// One CSS `radial-gradient(ellipse RX RY at CX CY, rgba(c,a) 0%, [mid,] transparent END)`.
struct BackdropRadial {
    let rgb: UInt32
    let alpha: Double
    let rx: Double, ry: Double   // radii as fractions of width / height
    let cx: Double, cy: Double   // centre as fractions of width / height
    let end: Double              // stop where it reaches transparent (0…1 of the radius)
    var midAlpha: Double? = nil  // optional second colour stop
    var midLoc: Double = 0
}

/// One CSS `linear-gradient(DEG, …)` with explicit colour stops.
struct BackdropLinear {
    let degrees: Double
    let stops: [(rgb: UInt32, alpha: Double, loc: Double)]
}

struct ThemeBackdropSpec {
    let base: UInt32
    /// Bottom-most linear gradient first, then translucent streaks / radials in paint order.
    let linear: BackdropLinear
    let streaks: [BackdropLinear]
    /// CSS order (first = top-most). Drawn reversed.
    let radials: [BackdropRadial]
}

extension AutumnTheme {
    /// nil = no atmosphere (VOID solid black, CUSTOM uses the saved palette gradient).
    var backdropSpec: ThemeBackdropSpec? {
        func lin(_ deg: Double, _ s: [(UInt32, Double)]) -> BackdropLinear {
            BackdropLinear(degrees: deg, stops: s.map { (rgb: $0.0, alpha: 1.0, loc: $0.1) })
        }
        switch resolved {
        case .void, .custom:
            return nil
        case .day, .auto:
            // DAY — frosted cyan / violet over deep navy
            return ThemeBackdropSpec(base: 0x020a14,
                linear: lin(165, [(0x07182c, 0), (0x020a14, 0.40), (0x0a1628, 0.72), (0x041018, 1)]),
                streaks: [],
                radials: [
                    BackdropRadial(rgb: 0x7ecfff, alpha: 0.28, rx: 0.90, ry: 0.60, cx: 0.16, cy: 0.08, end: 0.58),
                    BackdropRadial(rgb: 0xbf50ff, alpha: 0.18, rx: 0.70, ry: 0.50, cx: 0.88, cy: 0.10, end: 0.55),
                    BackdropRadial(rgb: 0x00ffcc, alpha: 0.14, rx: 0.80, ry: 0.40, cx: 0.50, cy: 1.00, end: 0.60),
                    BackdropRadial(rgb: 0x0088ff, alpha: 0.10, rx: 0.50, ry: 0.30, cx: 0.70, cy: 0.70, end: 0.70),
                ])
        case .night:
            // NIGHT — near-black indigo with neon violet bloom
            return ThemeBackdropSpec(base: 0x06040f,
                linear: lin(168, [(0x0b0618, 0), (0x06040f, 0.45), (0x0d0820, 1)]),
                streaks: [],
                radials: [
                    BackdropRadial(rgb: 0xb48bff, alpha: 0.32, rx: 0.70, ry: 0.55, cx: 0.78, cy: 0.12, end: 0.58),
                    BackdropRadial(rgb: 0x7b4fff, alpha: 0.20, rx: 0.50, ry: 0.40, cx: 0.12, cy: 0.80, end: 0.60),
                    BackdropRadial(rgb: 0xff2d78, alpha: 0.10, rx: 0.40, ry: 0.30, cx: 0.40, cy: 0.30, end: 0.65),
                    BackdropRadial(rgb: 0x140828, alpha: 0.85, rx: 1.00, ry: 0.45, cx: 0.50, cy: 1.00, end: 0.70),
                ])
        case .stealth:
            // STEALTH — dark alley, cold steel-blue shafts
            return ThemeBackdropSpec(base: 0x03040a,
                linear: lin(180, [(0x07090f, 0), (0x03040a, 0.48), (0x050814, 1)]),
                streaks: [BackdropLinear(degrees: 105, stops: [
                    (0x4a88cc, 0, 0), (0x4a88cc, 0.07, 0.36), (0x4a88cc, 0, 0.38),
                    (0x2a5090, 0, 0.62), (0x2a5090, 0.10, 0.64), (0x2a5090, 0, 0.78)])],
                radials: [
                    BackdropRadial(rgb: 0x4a88cc, alpha: 0.16, rx: 0.50, ry: 0.80, cx: 0.08, cy: 0.50, end: 0.60),
                    BackdropRadial(rgb: 0x6aacee, alpha: 0.10, rx: 0.40, ry: 0.50, cx: 0.92, cy: 0.20, end: 0.55),
                    BackdropRadial(rgb: 0x080c18, alpha: 0.90, rx: 0.80, ry: 0.40, cx: 0.50, cy: 1.00, end: 0.65),
                ])
        case .departure:
            // DEPARTURE — amber dusk, warm horizon
            return ThemeBackdropSpec(base: 0x0a0500,
                linear: lin(180, [(0x1a0a02, 0), (0x120800, 0.38), (0x2a1004, 0.72), (0x3a1606, 1)]),
                streaks: [],
                radials: [
                    BackdropRadial(rgb: 0xff9d4a, alpha: 0.36, rx: 0.90, ry: 0.45, cx: 0.50, cy: 1.00, end: 0.70, midAlpha: 0.12, midLoc: 0.42),
                    BackdropRadial(rgb: 0xff3c3c, alpha: 0.18, rx: 0.50, ry: 0.30, cx: 0.78, cy: 0.78, end: 0.70),
                    BackdropRadial(rgb: 0xffb450, alpha: 0.12, rx: 0.40, ry: 0.25, cx: 0.18, cy: 0.70, end: 0.70),
                ])
        case .ashTree:
            // ASH TREE — forest floor, bioluminescent green bloom
            return ThemeBackdropSpec(base: 0x010a04,
                linear: lin(168, [(0x04150a, 0), (0x010a04, 0.42), (0x040f06, 1)]),
                streaks: [],
                radials: [
                    BackdropRadial(rgb: 0x7ddc8e, alpha: 0.26, rx: 0.40, ry: 0.40, cx: 0.22, cy: 0.78, end: 0.60),
                    BackdropRadial(rgb: 0xa8e63d, alpha: 0.12, rx: 0.35, ry: 0.30, cx: 0.78, cy: 0.30, end: 0.60),
                    BackdropRadial(rgb: 0x3a9e55, alpha: 0.22, rx: 0.60, ry: 0.35, cx: 0.50, cy: 1.00, end: 0.65),
                    BackdropRadial(rgb: 0x50dc64, alpha: 0.10, rx: 0.20, ry: 0.50, cx: 0.48, cy: 0.60, end: 0.70),
                ])
        case .ariel:
            // ARIEL — desert night sky, sand-gold ground wash
            return ThemeBackdropSpec(base: 0x081420,
                linear: lin(180, [(0x0c1a28, 0), (0x081420, 0.48), (0x1a1610, 1)]),
                streaks: [],
                radials: [
                    BackdropRadial(rgb: 0x7ec8e8, alpha: 0.20, rx: 0.70, ry: 0.40, cx: 0.50, cy: 0.00, end: 0.60),
                    BackdropRadial(rgb: 0xc4a36a, alpha: 0.28, rx: 0.90, ry: 0.40, cx: 0.50, cy: 1.00, end: 0.75, midAlpha: 0.06, midLoc: 0.50),
                    BackdropRadial(rgb: 0xe8eef4, alpha: 0.10, rx: 0.30, ry: 0.25, cx: 0.82, cy: 0.18, end: 0.70),
                ])
        case .skyboard:
            // SKYBOARD — holographic HUD, icy cyan depth
            return ThemeBackdropSpec(base: 0x040c16,
                linear: lin(165, [(0x071422, 0), (0x040c16, 0.40), (0x0a1a2c, 1)]),
                streaks: [BackdropLinear(degrees: 115, stops: [
                    (0x5fd4ff, 0, 0), (0x5fd4ff, 0.06, 0.46), (0x5fd4ff, 0, 0.48),
                    (0x5fd4ff, 0, 0.70), (0x5fd4ff, 0.05, 0.72), (0x5fd4ff, 0, 1)])],
                radials: [
                    BackdropRadial(rgb: 0x5fd4ff, alpha: 0.26, rx: 0.60, ry: 0.50, cx: 0.70, cy: 0.18, end: 0.58),
                    BackdropRadial(rgb: 0x2a5a78, alpha: 0.28, rx: 0.45, ry: 0.40, cx: 0.16, cy: 0.70, end: 0.60),
                    BackdropRadial(rgb: 0x0a1a2c, alpha: 0.90, rx: 0.80, ry: 0.35, cx: 0.50, cy: 1.00, end: 0.70),
                ])
        case .lounge:
            // LOUNGE — low-lit warm amber pools
            return ThemeBackdropSpec(base: 0x0a0604,
                linear: lin(180, [(0x140c08, 0), (0x0a0604, 0.45), (0x1a1008, 1)]),
                streaks: [],
                radials: [
                    BackdropRadial(rgb: 0xe8a86a, alpha: 0.28, rx: 0.55, ry: 0.40, cx: 0.20, cy: 0.82, end: 0.62),
                    BackdropRadial(rgb: 0xe8a86a, alpha: 0.14, rx: 0.40, ry: 0.30, cx: 0.84, cy: 0.30, end: 0.65),
                    BackdropRadial(rgb: 0x8a5a30, alpha: 0.12, rx: 0.30, ry: 0.20, cx: 0.50, cy: 0.50, end: 0.70),
                ])
        case .summit:
            // SUMMIT — icy alpine night, misted cyan peaks
            return ThemeBackdropSpec(base: 0x050a10,
                linear: lin(180, [(0x0a141c, 0), (0x050a10, 0.40), (0x0f1620, 1)]),
                streaks: [],
                radials: [
                    BackdropRadial(rgb: 0xeefbff, alpha: 0.10, rx: 0.80, ry: 0.35, cx: 0.50, cy: 0.00, end: 0.60),
                    BackdropRadial(rgb: 0x5fd4ff, alpha: 0.22, rx: 0.50, ry: 0.45, cx: 0.28, cy: 1.00, end: 0.60),
                    BackdropRadial(rgb: 0x3a8fc4, alpha: 0.20, rx: 0.45, ry: 0.40, cx: 0.78, cy: 0.88, end: 0.60),
                    BackdropRadial(rgb: 0xdff3ff, alpha: 0.08, rx: 0.20, ry: 0.15, cx: 0.60, cy: 0.42, end: 0.70),
                ])
        }
    }
}

/// Renders a theme's default atmosphere. VOID = solid black; CUSTOM = saved palette gradient.
struct ThemeBackdropView: View {
    let theme: AutumnTheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                if theme.resolved == .void {
                    Color.black
                } else if let spec = theme.backdropSpec {
                    Color(hex: Self.hexString(spec.base))
                    Self.linearView(spec.linear)
                    ForEach(Array(spec.streaks.enumerated()), id: \.offset) { _, s in
                        Self.linearView(s)
                    }
                    ForEach(Array(spec.radials.reversed().enumerated()), id: \.offset) { _, r in
                        Self.radialView(r)
                            .frame(width: max(CGFloat(1), CGFloat(2 * r.rx) * w),
                                   height: max(CGFloat(1), CGFloat(2 * r.ry) * h))
                            .position(x: CGFloat(r.cx) * w, y: CGFloat(r.cy) * h)
                    }
                } else {
                    theme.voidGradient
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func hexString(_ v: UInt32) -> String { String(format: "#%06x", v) }

    static func color(_ rgb: UInt32, _ a: Double) -> Color {
        Color(hex: hexString(rgb)).opacity(a)
    }

    /// CSS angle → unit points (0deg = to top, 90deg = to right).
    static func linearView(_ l: BackdropLinear) -> some View {
        let rad = l.degrees * .pi / 180
        let dx = CGFloat(sin(rad)), dy = CGFloat(-cos(rad))
        let start = UnitPoint(x: 0.5 - dx * 0.5, y: 0.5 - dy * 0.5)
        let end = UnitPoint(x: 0.5 + dx * 0.5, y: 0.5 + dy * 0.5)
        let stops = l.stops.map { Gradient.Stop(color: color($0.rgb, $0.alpha), location: CGFloat($0.loc)) }
        return LinearGradient(gradient: Gradient(stops: stops), startPoint: start, endPoint: end)
    }

    static func radialView(_ r: BackdropRadial) -> some View {
        var stops = [Gradient.Stop(color: color(r.rgb, r.alpha), location: 0)]
        if let m = r.midAlpha { stops.append(Gradient.Stop(color: color(r.rgb, m), location: CGFloat(r.midLoc))) }
        stops.append(Gradient.Stop(color: color(r.rgb, 0), location: CGFloat(r.end)))
        return Rectangle().fill(EllipticalGradient(gradient: Gradient(stops: stops), center: .center,
                                                   startRadiusFraction: 0, endRadiusFraction: 0.5))
    }
}
