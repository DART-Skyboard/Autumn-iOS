import SwiftUI

/// Frosted palette editor: pick a preset, tap a saved palette, or build your own with colour pickers.
/// Saved palettes live in the profile settings (private vault) and reload on every launch.
struct PaletteEditorOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation

    @State private var name = ""
    @State private var bg1 = Color(hex: "#05070d")
    @State private var bg2 = Color(hex: "#14203a")
    @State private var accent = Color(hex: "#7ecfff")
    @State private var editingID: String?
    @State private var snapTheme: AutumnTheme = .void
    @State private var snapID: String?
    @State private var dirty = false
    @State private var loaded = false

    var body: some View {
        GeometryReader { geo in
            // Sized from the space we actually have (window can be resized: iPhone Duo / Mirroring).
            let width = min(440, max(280, geo.size.width - 24))
            let height = min(680, max(320, geo.size.height - 24))
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { close() }
                card
                    .frame(width: width, height: height)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.40))
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeVM.chrome.accent.opacity(0.35), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
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
                    picker("Background · top", binding($bg1))
                    picker("Background · bottom", binding($bg2))
                    picker("Accent", binding($accent))

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

    // MARK: pieces
    private var preview: some View {
        let p = AutumnPalette(name: name, bg1: bg1.hexString, bg2: bg2.hexString, accent: accent.hexString)
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

    private func swatch(_ p: AutumnPalette, label: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8).fill(p.gradient).frame(width: 64, height: 40)
                .overlay(Circle().fill(p.ca).frame(width: 10, height: 10))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.white : Color.white.opacity(0.2), lineWidth: selected ? 2 : 1))
            Text(label).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.75)).lineLimit(1)
        }
        .frame(width: 70)
    }

    private func picker(_ title: String, _ b: Binding<Color>) -> some View {
        HStack {
            Text(title).font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            Spacer()
            ColorPicker("", selection: b, supportsOpacity: false).labelsHidden()
        }
    }

    private func binding(_ c: Binding<Color>) -> Binding<Color> {
        Binding(get: { c.wrappedValue }, set: { c.wrappedValue = $0; dirty = true; livePreview() })
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
        bg1 = p.c1; bg2 = p.c2; accent = p.ca
        editingID = editing ? p.id : nil
        dirty = false
    }

    private func livePreview() {
        themeVM.previewPalette(AutumnPalette(id: editingID ?? "draft", name: name, bg1: bg1.hexString, bg2: bg2.hexString, accent: accent.hexString))
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
        let p = themeVM.saveCustom(name: name, bg1: bg1.hexString, bg2: bg2.hexString, accent: accent.hexString, id: asNew ? nil : editingID)
        snapTheme = .custom; snapID = p.id
        load(p, editing: true)
    }

    private func close() {
        if dirty { themeVM.restore(theme: snapTheme, customID: snapID) }   // unsaved preview is discarded
        appNav.showPalette = false
    }
}

private struct ActionStyle: ButtonStyle {
    let accent: Color
    let filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
            .foregroundColor(filled ? .black : accent)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(filled ? accent : accent.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.6), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
