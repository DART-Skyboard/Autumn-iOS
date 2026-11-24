import SwiftUI

/// Frosted palette editor: pick a preset, tap a saved palette, or build your own.
/// Every colour opens HighResColorPickerView (GRID / SPECTRUM / SLIDERS, hex, recents), same as the web app's picker.
/// UI SHADING (same controls as web): panel surface + 2nd stop, button fill + 2nd stop, glow, border,
/// UI opacity, backdrop blur, SOLID / GRADIENT style and gradient angle.
/// Saved palettes live in the profile settings (private vault) and reload on every launch.
struct PaletteEditorOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation

    /// Which colour the picker is editing.
    enum PickTarget: Hashable {
        case bg1, bg2, accent
        case surface, surface2, button, button2, glow, border
        var title: String {
            switch self {
            case .bg1: return "BG 1 COLOUR"
            case .bg2: return "BG 2 COLOUR"
            case .accent: return "ACCENT COLOUR"
            case .surface: return "SURFACE COLOUR"
            case .surface2: return "SURFACE 2 COLOUR"
            case .button: return "BUTTON COLOUR"
            case .button2: return "BUTTON 2 COLOUR"
            case .glow: return "GLOW COLOUR"
            case .border: return "BORDER COLOUR"
            }
        }
    }

    @State private var name = ""
    @State private var bg1 = "#05070d"
    @State private var bg2 = "#14203a"
    @State private var accent = "#7ecfff"
    @State private var ui = AutumnPaletteUI.defaults(bg1: "#05070d", bg2: "#14203a", accent: "#7ecfff")
    @State private var editingID: String?
    @State private var snapTheme: AutumnTheme = .void
    @State private var snapID: String?
    @State private var dirty = false
    @State private var loaded = false
    @State private var pickTarget: PickTarget?
    @State private var pickOriginal = ""
    @State private var pickWasOn = true

    private struct Direction: Hashable { let glyph: String; let degrees: Double }
    private static let directions: [Direction] = [("↑", 0.0), ("↗", 45.0), ("→", 90.0), ("↘", 135.0), ("↓", 180.0), ("↙", 225.0), ("←", 270.0), ("↖", 315.0)]
        .map { Direction(glyph: $0.0, degrees: $0.1) }

    var body: some View {
        GeometryReader { geo in
            // Sized from the space we actually have (window can be resized: iPhone Duo / Mirroring).
            let width = min(440, max(280, geo.size.width - 24))
            let height = min(720, max(320, geo.size.height - 24))
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { close() }
                card
                    .frame(width: width, height: height)
                    .modifier(EditorPanel(ui: AutumnPaletteRuntime.ui, accent: themeVM.chrome.accent))
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
                if let t = pickTarget {
                    HighResColorPickerView(
                        title: t.title,
                        hex: hex(for: t),
                        accent: themeVM.chrome.accent,
                        onLive: { h, _ in
                            set(t, h)
                            dirty = true
                            livePreview()
                        },
                        onDone: { h, _ in
                            if let h { set(t, h) } else {
                                set(t, pickOriginal)
                                if t.isUI { ui.on = pickWasOn }
                            }
                            if dirty { livePreview() }
                            pickTarget = nil
                        }
                    )
                    .id(t)
                    .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { if !loaded { loaded = true; start() } }
    }

    private var card: some View {
        let chrome = themeVM.chrome
        return VStack(spacing: 0) {
            HStack {
                Text("PALETTES")
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundColor(chrome.accent)
                Spacer()
                Button("✕") { close() }
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(14)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    preview
                    section("PRESETS")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AutumnTheme.presets) { t in
                                Button { choosePreset(t) } label: { swatch(AutumnPalette.from(t), label: t.rawValue, selected: themeVM.current == t) }
                                    .buttonStyle(.plain)
                            }
                            // Built-in palettes (with UI shading), e.g. NEON DUSK.
                            ForEach(AutumnPalette.builtIns) { p in
                                Button { chooseCustom(p) } label: {
                                    swatch(p, label: p.name, selected: themeVM.current == .custom && themeVM.activeCustomID == p.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !themeVM.customPalettes.isEmpty {
                        section("MY PALETTES")
                        VStack(spacing: 6) {
                            ForEach(themeVM.customPalettes) { p in
                                HStack(spacing: 10) {
                                    Button { chooseCustom(p) } label: {
                                        HStack(spacing: 10) {
                                            RoundedRectangle(cornerRadius: 6).fill(p.gradient).frame(width: 44, height: 28)
                                                .overlay(Circle().fill(p.ca).frame(width: 9, height: 9))
                                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.2), lineWidth: 1))
                                            if let u = p.activeUI {
                                                RoundedRectangle(cornerRadius: 4).fill(u.buttonFill).frame(width: 18, height: 18)
                                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(u.borderColor.opacity(0.6), lineWidth: 1))
                                                    .accessibilityLabel("Custom UI shading")
                                            }
                                            Text(p.name)
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.white.opacity(themeVM.current == .custom && themeVM.activeCustomID == p.id ? 1 : 0.8))
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    Button { themeVM.deleteCustom(id: p.id); if editingID == p.id { editingID = nil } } label: {
                                        Image(systemName: "trash").font(.system(size: 13)).foregroundColor(Color(hex: "#ff6680"))
                                    }
                                    .accessibilityLabel("Delete \(p.name)")
                                }
                                .padding(8)
                                .background(chrome.accent.opacity(themeVM.current == .custom && themeVM.activeCustomID == p.id ? 0.14 : 0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    section(editingID == nil ? "CREATE YOUR OWN" : "EDIT PALETTE")
                    TextField("Palette name", text: $name)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(9)
                        .background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    colorRow("Background · top", .bg1)
                    colorRow("Background · bottom", .bg2)
                    colorRow("Accent", .accent)

                    uiShadingSection(chrome: chrome)

                    HStack(spacing: 10) {
                        if editingID != nil {
                            Button("UPDATE") { save(asNew: false) }.buttonStyle(ActionStyle(accent: chrome.accent, filled: true))
                        }
                        Button(editingID == nil ? "SAVE PALETTE" : "SAVE AS NEW") { save(asNew: true) }
                            .buttonStyle(ActionStyle(accent: chrome.accent, filled: editingID == nil))
                    }
                    Text("Saved palettes are kept in your profile and load every time. Use ART to add your own video or image on top.")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                }
                .padding(.horizontal, 14).padding(.bottom, 16)
            }
        }
    }

    // MARK: UI shading

    @ViewBuilder
    private func uiShadingSection(chrome: AutumnTheme) -> some View {
        section("UI SHADING")
        HStack(spacing: 8) {
            chip("THEME DEFAULT", on: !ui.on, accent: chrome.accent) { ui.on = false; touchedToggle() }
            chip("CUSTOM", on: ui.on, accent: chrome.accent) { ui.on = true; touchedToggle() }
        }
        VStack(alignment: .leading, spacing: 10) {
            subsection("UI SURFACE · PANELS, CARDS, DRAWERS, CHAT")
            colorRow("Surface", .surface)
            colorRow("Surface · 2nd stop", .surface2).opacity(ui.isGradient ? 1 : 0.4).disabled(!ui.isGradient)

            subsection("BUTTON FILL & SHADING")
            colorRow("Button", .button)
            colorRow("Button · 2nd stop", .button2).opacity(ui.isGradient ? 1 : 0.4).disabled(!ui.isGradient)
            colorRow("Glow (pressed / active)", .glow)
            colorRow("Border tint", .border)

            subsection("UI GRADIENT STYLE")
            HStack(spacing: 8) {
                chip("SOLID", on: ui.style == .solid, accent: chrome.accent) { ui.style = .solid; touched() }
                chip("GRADIENT", on: ui.style == .gradient, accent: chrome.accent) { ui.style = .gradient; touched() }
            }
            Group {
                sliderRow("ANGLE", value: uiBinding(\.angle), range: 0...359, unit: "°", accent: chrome.accent)
                HStack(spacing: 4) {
                    ForEach(PaletteEditorOverlay.directions, id: \.self) { d in
                        chip(d.glyph, on: Int(ui.angle) == Int(d.degrees), accent: chrome.accent, compact: true) { ui.angle = d.degrees; touched() }
                            .accessibilityLabel("Gradient \(Int(d.degrees)) degrees")
                    }
                }
            }
            .opacity(ui.isGradient ? 1 : 0.4)
            .disabled(!ui.isGradient)

            subsection("UI TRANSPARENCY")
            sliderRow("OPACITY", value: uiBinding(\.opacity), range: 15...100, unit: "%", accent: chrome.accent)
            sliderRow("BLUR", value: uiBinding(\.blur), range: 0...40, unit: "", accent: chrome.accent)

            uiDemo
            Button("↺ RESET UI TO PALETTE") {
                ui = AutumnPaletteUI.defaults(bg1: bg1, bg2: bg2, accent: accent)
                dirty = true; livePreview()
            }
            .buttonStyle(ActionStyle(accent: chrome.accent, filled: false))
        }
        .opacity(ui.on ? 1 : 0.5)
    }

    /// Always shows the custom look (even while THEME DEFAULT is selected) so the controls have instant feedback.
    private var uiDemo: some View {
        HStack(spacing: 8) {
            Text("PANEL PREVIEW")
                .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            demoButton("BUTTON", active: false)
            demoButton("ACTIVE", active: true)
        }
        .padding(12)
        .modifier(AutumnUIPanel(ui: ui, corner: 12))
    }

    private func demoButton(_ label: String, active: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
            .foregroundColor(ui.buttonInk)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? ui.buttonFillActive : ui.buttonFill)
            .clipShape(shape)
            .overlay(shape.stroke(active ? ui.glowColor : ui.borderColor.opacity(0.55), lineWidth: 1))
            .shadow(color: active ? ui.glowColor.opacity(0.55) : .clear, radius: active ? 8 : 0)
    }

    private func uiBinding(_ kp: WritableKeyPath<AutumnPaletteUI, Double>) -> Binding<Double> {
        Binding(get: { ui[keyPath: kp] }, set: { ui[keyPath: kp] = $0.rounded(); ui.clamp(); touched() })
    }

    // MARK: pieces
    private var preview: some View {
        let p = AutumnPalette(name: name, bg1: bg1, bg2: bg2, accent: accent)
        return RoundedRectangle(cornerRadius: 12).fill(p.gradient)
            .frame(height: 70)
            .overlay(
                HStack {
                    Text(name.isEmpty ? "Preview" : name).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(p.ca)
                    Spacer()
                    Capsule().fill(p.ca.opacity(0.25)).overlay(Capsule().stroke(p.ca, lineWidth: 1)).frame(width: 46, height: 20)
                }.padding(.horizontal, 12)
            )
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.18), lineWidth: 1))
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.6).foregroundColor(.white.opacity(0.45))
    }

    private func subsection(_ t: String) -> some View {
        Text(t).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundColor(.white.opacity(0.4))
            .padding(.top, 4)
    }

    private func swatch(_ p: AutumnPalette, label: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8).fill(p.gradient).frame(width: 64, height: 40)
                .overlay(Circle().fill(p.ca).frame(width: 10, height: 10))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.white : Color.white.opacity(0.2), lineWidth: selected ? 2 : 1))
            Text(label).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.75)).lineLimit(1)
        }
        .frame(width: 70)
    }

    /// One tap opens the high-res picker for this colour.
    private func colorRow(_ title: String, _ target: PickTarget) -> some View {
        let h = hex(for: target)
        return Button { openPicker(target) } label: {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(h.uppercased()).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: h))
                    .frame(width: 30, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) colour \(h.uppercased())")
        .accessibilityHint("Opens the colour picker")
    }

    private func chip(_ label: String, on: Bool, accent: Color, compact: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: compact ? 12 : 10, weight: .bold, design: .monospaced)).tracking(compact ? 0 : 1)
                .padding(.horizontal, compact ? 0 : 12).padding(.vertical, 7)
                .frame(minWidth: compact ? CGFloat(30) : nil)
                .frame(maxWidth: compact ? CGFloat.infinity : nil)
        }
        .buttonStyle(AutumnUIButtonStyle(accent: accent, active: on, corner: 6))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, accent: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                .foregroundColor(.white.opacity(0.7)).frame(width: 58, alignment: .leading)
            Slider(value: value, in: range, step: 1).tint(accent)
                .accessibilityLabel(label)
            Text("\(Int(value.wrappedValue))\(unit)").font(.system(size: 10, design: .monospaced)).monospacedDigit()
                .foregroundColor(.white.opacity(0.85)).frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: picker plumbing
    private func hex(for t: PickTarget) -> String {
        switch t {
        case .bg1: return bg1
        case .bg2: return bg2
        case .accent: return accent
        case .surface: return ui.surface
        case .surface2: return ui.surface2
        case .button: return ui.button
        case .button2: return ui.button2
        case .glow: return ui.glow
        case .border: return ui.border
        }
    }

    private func set(_ t: PickTarget, _ h: String) {
        guard let v = HexColor.normalized(h) else { return }
        switch t {
        case .bg1: bg1 = v
        case .bg2: bg2 = v
        case .accent: accent = v
        case .surface: ui.surface = v; ui.on = true
        case .surface2: ui.surface2 = v; ui.on = true
        case .button: ui.button = v; ui.on = true
        case .button2: ui.button2 = v; ui.on = true
        case .glow: ui.glow = v; ui.on = true
        case .border: ui.border = v; ui.on = true
        }
    }

    private func openPicker(_ t: PickTarget) {
        pickOriginal = hex(for: t)
        pickWasOn = ui.on
        withAnimation(.easeOut(duration: 0.15)) { pickTarget = t }
    }

    // MARK: logic
    private func start() {
        snapTheme = themeVM.current
        snapID = themeVM.activeCustomID
        if themeVM.current == .custom, let p = themeVM.activePalette { load(p, editing: true) }
        else { load(AutumnPalette.from(themeVM.current), editing: false) }
    }

    private func load(_ p: AutumnPalette, editing: Bool) {
        name = editing ? p.name : ""
        bg1 = HexColor.normalized(p.bg1) ?? "#05070d"
        bg2 = HexColor.normalized(p.bg2) ?? "#14203a"
        accent = HexColor.normalized(p.accent) ?? "#7ecfff"
        if let saved = p.ui {
            ui = saved
        } else {
            // Palettes saved before UI shading keep the theme look until the user switches to CUSTOM.
            ui = AutumnPaletteUI.defaults(bg1: bg1, bg2: bg2, accent: accent)
            ui.on = !editing
        }
        editingID = (editing && !p.isBuiltIn) ? p.id : nil   // a built-in can't be overwritten; SAVE makes a copy
        dirty = false
    }

    private func touched() { ui.on = true; dirty = true; livePreview() }      // any UI edit switches to CUSTOM
    private func touchedToggle() { dirty = true; livePreview() }

    private func livePreview() {
        themeVM.previewPalette(AutumnPalette(id: editingID ?? "draft", name: name, bg1: bg1, bg2: bg2, accent: accent, ui: ui))
    }

    private func choosePreset(_ t: AutumnTheme) {
        themeVM.applyPreset(t)
        snapTheme = t; snapID = themeVM.activeCustomID
        load(AutumnPalette.from(t), editing: false)
    }

    private func chooseCustom(_ p: AutumnPalette) {
        themeVM.applyCustom(p)
        snapTheme = .custom; snapID = p.id
        load(p, editing: true)
    }

    private func save(asNew: Bool) {
        let p = themeVM.saveCustom(name: name, bg1: bg1, bg2: bg2, accent: accent, ui: ui, id: asNew ? nil : editingID)
        snapTheme = .custom; snapID = p.id
        load(p, editing: true)
    }

    private func close() {
        if dirty { themeVM.restore(theme: snapTheme, customID: snapID) }   // unsaved preview is discarded
        appNav.showPalette = false
    }
}

private extension PaletteEditorOverlay.PickTarget {
    var isUI: Bool {
        switch self {
        case .bg1, .bg2, .accent: return false
        default: return true
        }
    }
}

/// Editor card background: follows UI SHADING live when it's on, else the classic frosted black glass.
private struct EditorPanel: ViewModifier {
    let ui: AutumnPaletteUI?
    let accent: Color
    @ViewBuilder
    func body(content: Content) -> some View {
        if let ui {
            content.modifier(AutumnUIPanel(ui: ui, corner: 16))
        } else {
            content
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.40))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.35), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct ActionStyle: ButtonStyle {
    let accent: Color
    let filled: Bool
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        if !filled, let u = AutumnPaletteRuntime.ui {
            // UI SHADING button look for the secondary actions.
            configuration.label
                .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
                .foregroundColor(u.buttonInk)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(configuration.isPressed ? u.buttonFillActive : u.buttonFill)
                .overlay(shape.stroke(configuration.isPressed ? u.glowColor : u.borderColor.opacity(0.55), lineWidth: 1))
                .clipShape(shape)
                .shadow(color: configuration.isPressed ? u.glowColor.opacity(0.5) : .clear, radius: 8)
        } else {
            configuration.label
                .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
                .foregroundColor(filled ? .black : accent)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(filled ? accent : accent.opacity(0.10))
                .overlay(shape.stroke(accent.opacity(0.6), lineWidth: 1))
                .clipShape(shape)
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}
