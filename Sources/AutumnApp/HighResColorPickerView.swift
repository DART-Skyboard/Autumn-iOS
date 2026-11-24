import SwiftUI
import UIKit

// MARK: - Colour value

/// HSB + alpha colour used by the picker. Works in hex/RGB doubles so it never depends on
/// Color → UIColor conversion (unreliable before iOS 17, see UIColor.fromSwiftUI).
struct PickerHSBA: Equatable {
    var h: Double   // 0 … 1
    var s: Double   // 0 … 1
    var b: Double   // 0 … 1
    var a: Double   // 0 … 1

    init(h: Double, s: Double, b: Double, a: Double = 1) {
        self.h = PickerHSBA.unit(h); self.s = PickerHSBA.unit(s); self.b = PickerHSBA.unit(b); self.a = PickerHSBA.unit(a)
    }

    init(hex: String, alpha: Double = 1) {
        let c = HexColor.rgb(hex)
        self = PickerHSBA.fromRGB(c.r, c.g, c.b, alpha)
    }

    static func unit(_ x: Double) -> Double { x.isFinite ? min(1, max(0, x)) : 0 }

    /// RGB → HSB. `keepHue` holds the hue steady when the colour turns grey (s == 0) so sliders don't jump.
    static func fromRGB(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1, keepHue: Double? = nil) -> PickerHSBA {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = keepHue ?? 0
        if d > 0 {
            if mx == r { h = (g - b) / d }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return PickerHSBA(h: h, s: mx > 0 ? d / mx : 0, b: mx, a: a)
    }

    var rgb: (r: Double, g: Double, b: Double) {
        let hh = (h >= 1 ? 0 : h) * 6
        let i = floor(hh), f = hh - i
        let p = b * (1 - s), q = b * (1 - s * f), t = b * (1 - s * (1 - f))
        switch Int(i) % 6 {
        case 0: return (b, t, p)
        case 1: return (q, b, p)
        case 2: return (p, b, t)
        case 3: return (p, q, b)
        case 4: return (t, p, b)
        default: return (b, p, q)
        }
    }

    var hex: String { let c = rgb; return HexColor.hex(r: c.r, g: c.g, b: c.b) }
    var opaque: Color { Color(hue: h, saturation: s, brightness: b) }
    var color: Color { Color(hue: h, saturation: s, brightness: b, opacity: a) }
}

// MARK: - Recent colours

/// Last 12 picked colours, shared by every picker in the app (UserDefaults).
enum ColorRecents {
    static let key = "autumn_color_recents_v1"
    static func load() -> [String] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap { HexColor.normalized($0) }
    }
    static func push(_ hex: String) {
        guard let h = HexColor.normalized(hex) else { return }
        var list = load().filter { $0 != h }
        list.insert(h, at: 0)
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: key)
    }
}

// MARK: - Picker

/// High-resolution dark glass colour picker, matching the web app's picker (js/autumn-theme-art.js openColorPicker):
/// title + ✕, GRID / SPECTRUM / SLIDERS tabs, live preview swatch (original | new), editable HEX, RECENT swatches, CANCEL / DONE.
/// `onLive` fires while dragging; `onDone` gets the final hex, or nil when cancelled (caller restores its own preview).
struct HighResColorPickerView: View {
    enum PickerTab: String, CaseIterable, Identifiable { case grid = "GRID", spectrum = "SPECTRUM", sliders = "SLIDERS"; var id: String { rawValue } }

    let title: String
    let supportsOpacity: Bool
    let accent: Color
    let onLive: ((String, Double) -> Void)?
    let onDone: (String?, Double) -> Void

    private let original: PickerHSBA
    @State private var value: PickerHSBA
    @State private var tab: PickerTab = .spectrum
    @State private var hexText: String
    @State private var hexBad = false
    @State private var recents: [String] = ColorRecents.load()
    @FocusState private var hexFocused: Bool

    init(title: String, hex: String, alpha: Double = 1, supportsOpacity: Bool = false, accent: Color = Color(hex: "#00e5ff"),
         onLive: ((String, Double) -> Void)? = nil, onDone: @escaping (String?, Double) -> Void) {
        let start = PickerHSBA(hex: HexColor.normalized(hex) ?? "#7ecfff", alpha: supportsOpacity ? alpha : 1)
        self.title = title
        self.supportsOpacity = supportsOpacity
        self.accent = accent
        self.onLive = onLive
        self.onDone = onDone
        self.original = start
        _value = State(initialValue: start)
        _hexText = State(initialValue: start.hex.uppercased())
    }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width > geo.size.height && geo.size.height < 560
            let width = compact ? min(680, geo.size.width - 24) : min(380, max(280, geo.size.width - 24))
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { finish(false) }
                Group {
                    if compact { compactCard } else { card }
                }
                .frame(width: width)
                .padding(14)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#0a121e").opacity(0.84))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.35), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: accent.opacity(0.18), radius: 24)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) picker")
    }

    // MARK: layout

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            tabBar
            tabContent(aspect: 16.0 / 10.0)
            previewRow
            if supportsOpacity { opacityRow }
            recentRow
            footer
        }
    }

    /// Landscape phones: picker surface on the left, preview / hex / recents / buttons on the right.
    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    tabBar
                    tabContent(aspect: 16.0 / 8.0)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    previewRow
                    if supportsOpacity { opacityRow }
                    recentRow
                    Spacer(minLength: 0)
                    footer
                }
                .frame(width: 240)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(2)
                .foregroundColor(accent)
                .lineLimit(1)
            Spacer()
            Button { finish(false) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(PickerTab.allCases) { t in
                Button { tab = t } label: {
                    Text(t.rawValue)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2)
                        .foregroundColor(accent.opacity(tab == t ? 1 : 0.75))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(accent.opacity(tab == t ? 0.24 : 0.07))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent.opacity(tab == t ? 0.7 : 0.3), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func tabContent(aspect: CGFloat) -> some View {
        switch tab {
        case .grid: gridTab
        case .spectrum:
            VStack(spacing: 12) {
                spectrumPad.aspectRatio(aspect, contentMode: .fit)
                hueBar
            }
        case .sliders: slidersTab
        }
    }

    // MARK: SPECTRUM

    /// Saturation (x) × brightness (y) for the current hue. White→hue then clear→black is exact HSB, rendered on the GPU (drawingGroup → Metal).
    private var spectrumPad: some View {
        GeometryReader { g in
            let size = g.size
            ZStack {
                ZStack {
                    LinearGradient(colors: [.white, Color(hue: value.h, saturation: 1, brightness: 1)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                }
                .drawingGroup()
                Circle()
                    .fill(value.opaque)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.65), radius: 3)
                    .position(x: CGFloat(value.s) * size.width, y: CGFloat(1 - value.b) * size.height)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard size.width > 0, size.height > 0 else { return }
                        value.s = PickerHSBA.unit(Double(v.location.x / size.width))
                        value.b = 1 - PickerHSBA.unit(Double(v.location.y / size.height))
                        changed()
                    }
            )
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel("Saturation and brightness")
        .accessibilityValue("Saturation \(Int(value.s * 100)) percent, brightness \(Int(value.b * 100)) percent")
        .accessibilityAdjustableAction { dir in
            value.b = PickerHSBA.unit(value.b + (dir == .increment ? 0.02 : -0.02)); changed()
        }
    }

    private static let rainbow: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12.0).map { Color(hue: $0 >= 1 ? 0.9999 : $0, saturation: 1, brightness: 1) }

    private var hueBar: some View {
        GeometryReader { g in
            let w = g.size.width, knob: CGFloat = 26
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: HighResColorPickerView.rainbow, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 18)
                Circle()
                    .fill(Color(hue: value.h, saturation: 1, brightness: 1))
                    .frame(width: knob, height: knob)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .position(x: knob / 2 + CGFloat(value.h) * max(1, w - knob), y: g.size.height / 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        value.h = min(0.9999, PickerHSBA.unit(Double((v.location.x - knob / 2) / max(1, w - knob))))
                        changed()
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Hue")
        .accessibilityValue("\(Int(value.h * 360)) degrees")
        .accessibilityAdjustableAction { dir in
            value.h = min(0.9999, PickerHSBA.unit(value.h + (dir == .increment ? 1.0 / 72 : -1.0 / 72))); changed()
        }
    }

    // MARK: GRID

    private static let gridHues: [Double] = [0, 15, 30, 45, 60, 90, 140, 175, 200, 220, 250, 280, 310, 335].map { $0 / 360 }
    /// (saturation, brightness) rows from deep to pastel.
    private static let gridRows: [(Double, Double)] = [(1, 0.22), (1, 0.36), (1, 0.5), (1, 0.65), (1, 0.8), (1, 0.92), (0.85, 1), (0.62, 1), (0.42, 1), (0.24, 1)]
    private static let gridHexes: [[String]] = {
        let hues = HighResColorPickerView.gridHues
        let n = hues.count
        let greys = (0..<n).map { i -> String in let v = Double(i) / Double(n - 1); return HexColor.hex(r: v, g: v, b: v) }
        let rows = HighResColorPickerView.gridRows.map { row in hues.map { PickerHSBA(h: $0, s: row.0, b: row.1).hex } }
        return [greys] + rows
    }()

    private var gridTab: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: HighResColorPickerView.gridHues.count)
        let current = value.hex
        return LazyVGrid(columns: cols, spacing: 0) {
            ForEach(Array(HighResColorPickerView.gridHexes.joined().enumerated()), id: \.offset) { _, hex in
                Rectangle()
                    .fill(Color(hex: hex))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(Rectangle().stroke(Color.white, lineWidth: hex == current ? 2 : 0))
                    .zIndex(hex == current ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { set(hex: hex) }
                    .accessibilityLabel(hex.uppercased())
                    .accessibilityAddTraits(.isButton)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: SLIDERS

    private var slidersTab: some View {
        let c = value.rgb
        return VStack(spacing: 8) {
            sliderRow("H", value: hueBinding, range: 0...360, unit: "°",
                      colors: HighResColorPickerView.rainbow)
            sliderRow("S", value: Binding(get: { value.s * 100 }, set: { value.s = PickerHSBA.unit($0 / 100); changed() }), range: 0...100, unit: "%",
                      colors: [Color(hue: value.h, saturation: 0, brightness: value.b), Color(hue: value.h, saturation: 1, brightness: value.b)])
            sliderRow("B", value: Binding(get: { value.b * 100 }, set: { value.b = PickerHSBA.unit($0 / 100); changed() }), range: 0...100, unit: "%",
                      colors: [.black, Color(hue: value.h, saturation: value.s, brightness: 1)])
            Divider().overlay(Color.white.opacity(0.1))
            sliderRow("R", value: rgbBinding(0), range: 0...255, unit: "",
                      colors: [Color(red: 0, green: c.g, blue: c.b), Color(red: 1, green: c.g, blue: c.b)])
            sliderRow("G", value: rgbBinding(1), range: 0...255, unit: "",
                      colors: [Color(red: c.r, green: 0, blue: c.b), Color(red: c.r, green: 1, blue: c.b)])
            sliderRow("B", value: rgbBinding(2), range: 0...255, unit: "",
                      colors: [Color(red: c.r, green: c.g, blue: 0), Color(red: c.r, green: c.g, blue: 1)])
            if supportsOpacity {
                Divider().overlay(Color.white.opacity(0.1))
                sliderRow("A", value: alphaBinding, range: 0...100, unit: "%", colors: [value.opaque.opacity(0), value.opaque], checker: true)
            }
        }
    }

    private var hueBinding: Binding<Double> {
        Binding(get: { value.h * 360 }, set: { value.h = min(0.9999, PickerHSBA.unit($0 / 360)); changed() })
    }
    private var alphaBinding: Binding<Double> {
        Binding(get: { value.a * 100 }, set: { value.a = PickerHSBA.unit($0 / 100); changed() })
    }
    private func rgbBinding(_ i: Int) -> Binding<Double> {
        Binding(get: {
            let c = value.rgb
            return (i == 0 ? c.r : i == 1 ? c.g : c.b) * 255
        }, set: { n in
            var c = value.rgb
            let v = PickerHSBA.unit(n.rounded() / 255)
            if i == 0 { c.r = v } else if i == 1 { c.g = v } else { c.b = v }
            value = PickerHSBA.fromRGB(c.r, c.g, c.b, value.a, keepHue: value.h)
            changed()
        })
    }

    private func sliderRow(_ label: String, value v: Binding<Double>, range: ClosedRange<Double>, unit: String, colors: [Color], checker: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 14, alignment: .leading)
            Button { v.wrappedValue = max(range.lowerBound, (v.wrappedValue - 1).rounded()) } label: { stepGlyph("minus") }
                .buttonStyle(.plain).accessibilityLabel("\(label) down")
            GradientTrackSlider(value: v, range: range, colors: colors, checker: checker)
                .frame(height: 26)
                .accessibilityLabel(label)
                .accessibilityValue("\(Int(v.wrappedValue.rounded()))\(unit)")
            Button { v.wrappedValue = min(range.upperBound, (v.wrappedValue + 1).rounded()) } label: { stepGlyph("plus") }
                .buttonStyle(.plain).accessibilityLabel("\(label) up")
            Text("\(Int(v.wrappedValue.rounded()))\(unit)")
                .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func stepGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(accent.opacity(0.85))
            .frame(width: 20, height: 20)
            .background(accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: preview / hex / recents / footer

    private var previewRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                Rectangle().fill(original.color)
                Rectangle().fill(value.color)
            }
            .frame(width: 58, height: 34)
            .background(CheckerboardView())
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.25), lineWidth: 1))
            .accessibilityLabel("Original and new colour")
            Text("HEX")
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                .foregroundColor(.white.opacity(0.75))
            TextField("#0074FF", text: hexFieldBinding)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .focused($hexFocused)
                .onSubmit { if !hexBad { finish(true) } }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(hexBad ? Color(hex: "#ff4466") : Color.white.opacity(0.2), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .frame(maxWidth: 120)
            Spacer(minLength: 0)
        }
    }

    private var opacityRow: some View {
        HStack(spacing: 8) {
            Text("OPACITY")
                .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                .foregroundColor(.white.opacity(0.6))
            GradientTrackSlider(value: alphaBinding, range: 0...100, colors: [value.opaque.opacity(0), value.opaque], checker: true)
                .frame(height: 24)
            Text("\(Int((value.a * 100).rounded()))%")
                .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var hexFieldBinding: Binding<String> {
        Binding(get: { hexText }, set: { t in
            hexText = t
            if let h = HexColor.normalized(t) {
                hexBad = false
                let next = PickerHSBA(hex: h, alpha: value.a)
                if next.hex != value.hex { value = next; changed(fromHex: true) }
            } else {
                hexBad = true
            }
        })
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT")
                .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.6)
                .foregroundColor(.white.opacity(0.5))
            if recents.isEmpty {
                Text("None yet").font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(recents, id: \.self) { h in
                            Button { set(hex: h) } label: {
                                Circle().fill(Color(hex: h))
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(Color.white.opacity(h == value.hex ? 0.95 : 0.3), lineWidth: h == value.hex ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Recent \(h.uppercased())")
                        }
                    }
                    .padding(2)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            footerButton("CANCEL") { finish(false) }
            footerButton("DONE", strong: true) { finish(true) }
                .disabled(hexBad)
                .opacity(hexBad ? 0.5 : 1)
        }
    }

    private func footerButton(_ label: String, strong: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2)
                .foregroundColor(accent)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(accent.opacity(strong ? 0.2 : 0.08))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent.opacity(strong ? 0.75 : 0.4), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: state

    private func set(hex: String) {
        value = PickerHSBA(hex: hex, alpha: value.a)
        hexBad = false
        changed()
    }

    private func changed(fromHex: Bool = false) {
        if !fromHex { hexText = value.hex.uppercased(); hexBad = false }
        onLive?(value.hex, value.a)
    }

    private func finish(_ ok: Bool) {
        hexFocused = false
        if ok {
            ColorRecents.push(value.hex)
            onDone(value.hex, value.a)
        } else {
            onLive?(original.hex, original.a)
            onDone(nil, original.a)
        }
    }
}

// MARK: - Pieces

/// Capsule track painted with a gradient, white ring knob, drag anywhere on the track.
struct GradientTrackSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let colors: [Color]
    var checker: Bool = false

    private static let knob: CGFloat = 22

    private var span: Double { max(0.0001, range.upperBound - range.lowerBound) }
    private var fraction: Double { min(1, max(0, (value - range.lowerBound) / span)) }
    private var trackColors: [Color] { colors.count > 1 ? colors : [colors.first ?? .clear, colors.first ?? .clear] }

    private func knobX(width: CGFloat) -> CGFloat {
        let travel: CGFloat = max(1, width - GradientTrackSlider.knob)
        return GradientTrackSlider.knob / 2 + CGFloat(fraction) * travel
    }

    private func update(x: CGFloat, width: CGFloat) {
        let travel: CGFloat = max(1, width - GradientTrackSlider.knob)
        let f: CGFloat = min(1, max(0, (x - GradientTrackSlider.knob / 2) / travel))
        value = range.lowerBound + Double(f) * span
    }

    private var track: some View {
        ZStack {
            if checker { CheckerboardView() }
            LinearGradient(colors: trackColors, startPoint: .leading, endPoint: .trailing)
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
    }

    private var knobView: some View {
        Circle()
            .fill(Color.white)
            .frame(width: GradientTrackSlider.knob, height: GradientTrackSlider.knob)
            .overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 2)
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                track
                knobView
                    .position(x: knobX(width: g.size.width), y: g.size.height / 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in update(x: v.location.x, width: g.size.width) })
        }
    }
}

/// Transparency checkerboard behind alpha swatches.
struct CheckerboardView: View {
    var cell: CGFloat = 6
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.85)))
            let cols = Int(ceil(size.width / cell)), rows = Int(ceil(size.height / cell))
            var p = Path()
            for r in 0..<max(rows, 0) {
                for c in 0..<max(cols, 0) where (r + c) % 2 == 0 {
                    p.addRect(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell))
                }
            }
            ctx.fill(p, with: .color(Color(white: 0.6)))
        }
    }
}
