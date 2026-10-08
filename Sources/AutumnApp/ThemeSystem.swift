import SwiftUI
import UIKit
import AutumnServices
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Theme engine matching web THEMES in index.html:
/// VOID DAY NIGHT STEALTH DEPARTURE ASH TREE ARIEL SKYBOARD LOUNGE SUMMIT AUTO
public enum AutumnTheme: String, CaseIterable, Identifiable {
    case void = "VOID"
    case day = "DAY"
    case night = "NIGHT"
    case stealth = "STEALTH"
    case departure = "DEPARTURE"
    case ashTree = "ASH TREE"
    case ariel = "ARIEL"
    case skyboard = "SKYBOARD"
    case lounge = "LOUNGE"
    case summit = "SUMMIT"
    case auto = "AUTO"
    case custom = "CUSTOM"

    public var id: String { rawValue }

    public var key: String {
        switch self {
        case .void: return "void"
        case .day: return "day"
        case .night: return "night"
        case .stealth: return "stealth"
        case .departure: return "departure"
        case .ashTree: return "ashtree"
        case .ariel: return "ariel"
        case .skyboard: return "skyboard"
        case .lounge: return "lounge"
        case .summit: return "summit"
        case .auto: return "system"
        case .custom: return "custom"
        }
    }

    public var dot: String {
        switch self {
        case .void: return "●"
        case .day: return "☀"
        case .night: return "🌙"
        case .stealth: return "◆"
        case .departure: return "🌅"
        case .ashTree: return "🌿"
        case .ariel: return "◇"
        case .skyboard: return "🛹"
        case .lounge: return "🛋"
        case .summit: return "🏔"
        case .auto: return "◈"
        case .custom: return "◐"
        }
    }

    public var accent: Color {
        switch self {
        case .void: return Color(hex: "#c5cad0")
        case .day: return Color(hex: "#7ecfff")
        case .night: return Color(hex: "#b48bff")
        case .stealth: return Color(hex: "#7aa8cc")
        case .departure: return Color(hex: "#ff9d4a")
        case .ashTree: return Color(hex: "#7ddc8e")
        case .ariel: return Color(hex: "#c4a36a")
        case .skyboard: return Color(hex: "#5fd4ff")
        case .lounge: return Color(hex: "#e8a86a")
        case .summit: return Color(hex: "#5fd4ff")
        case .auto: return Color(hex: "#ffb347")
        case .custom: return AutumnPaletteRuntime.accentColor
        }
    }

    /// Built-in palettes offered by the PALETTE button (the old named themes, now colour-only).
    public static var presets: [AutumnTheme] { allCases.filter { $0 != .auto && $0 != .custom } }

    public var resolved: AutumnTheme {
        if self == .auto {
            return UITraitCollection.current.userInterfaceStyle == .dark ? .night : .day
        }
        return self
    }

    public var base: Color {
        switch resolved {
        case .void: return Color(hex: "#000000")
        case .day: return Color(hex: "#020814")
        case .night: return Color(hex: "#05030c")
        case .stealth: return Color(hex: "#03050a")
        case .departure: return Color(hex: "#080400")
        case .ashTree: return Color(hex: "#010604")
        case .ariel: return Color(hex: "#050c14")
        case .skyboard: return Color(hex: "#040c16")
        case .lounge: return Color(hex: "#0a0604")
        case .summit: return Color(hex: "#050a10")
        case .auto: return Color(hex: "#020814")
        case .custom: return AutumnPaletteRuntime.bg1Color
        }
    }

    public var surface: Color {
        switch resolved {
        case .void: return Color(hex: "#0c0c0e").opacity(0.92)
        case .day: return Color(hex: "#0d1f3c").opacity(0.85)
        case .night: return Color(hex: "#0a0618").opacity(0.88)
        case .stealth: return Color(hex: "#0a0e14").opacity(0.88)
        case .departure: return Color(hex: "#120800").opacity(0.88)
        case .ashTree: return Color(hex: "#041208").opacity(0.88)
        case .ariel: return Color(hex: "#0a1624").opacity(0.88)
        case .skyboard: return Color(hex: "#0a1a2c").opacity(0.88)
        case .lounge: return Color(hex: "#1a1008").opacity(0.88)
        case .summit: return Color(hex: "#0f1620").opacity(0.88)
        case .auto: return Color(hex: "#0d1f3c").opacity(0.85)
        case .custom: return AutumnPaletteRuntime.bg2Color.opacity(0.88)
        }
    }

    public var accentSecondary: Color { accent }
    public var text: Color { .white }
    public var textSecondary: Color { Color.white.opacity(0.6) }

    public var gradient: LinearGradient {
        LinearGradient(colors: [base, surface], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Web WASH_RGB for scrim tint over the background.
    public var washRGB: (r: Double, g: Double, b: Double) {
        switch resolved {
        case .void: return (0, 0, 0)
        case .day, .auto: return (2/255.0, 10/255.0, 20/255.0)
        case .night: return (4/255.0, 2/255.0, 12/255.0)
        case .stealth: return (3/255.0, 5/255.0, 12/255.0)
        case .departure: return (12/255.0, 5/255.0, 0)
        case .ashTree: return (1/255.0, 10/255.0, 4/255.0)
        case .ariel: return (8/255.0, 20/255.0, 36/255.0)
        case .skyboard: return (4/255.0, 12/255.0, 22/255.0)
        case .lounge: return (10/255.0, 6/255.0, 2/255.0)
        case .summit: return (5/255.0, 10/255.0, 16/255.0)
        case .custom: return AutumnPaletteRuntime.washRGB
        }
    }

    public var washColor: Color {
        let w = washRGB
        return Color(red: w.r, green: w.g, blue: w.b)
    }

    /// Per-theme VOID overlay gradient (web VOID_GRAD).
    public var voidGradient: LinearGradient {
        switch resolved {
        case .ariel:
            return LinearGradient(colors: [Color(hex: "#050c14"), Color(hex: "#0a1624"), Color(hex: "#0c1210")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .skyboard:
            return LinearGradient(colors: [Color(hex: "#040c16"), Color(hex: "#0a1a2c"), Color(hex: "#081422")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lounge:
            return LinearGradient(colors: [Color(hex: "#0a0604"), Color(hex: "#1a1008"), Color(hex: "#120a06")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .summit:
            return LinearGradient(colors: [Color(hex: "#050a10"), Color(hex: "#0f1620"), Color(hex: "#0a1218")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .night:
            return LinearGradient(colors: [Color(hex: "#05030c"), Color(hex: "#0a0618")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .stealth:
            return LinearGradient(colors: [Color(hex: "#03050a"), Color(hex: "#070b12")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .departure:
            return LinearGradient(colors: [Color(hex: "#080400"), Color(hex: "#120800")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ashTree:
            return LinearGradient(colors: [Color(hex: "#010604"), Color(hex: "#041208")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .day, .auto:
            return LinearGradient(colors: [Color(hex: "#020814"), Color(hex: "#061018")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .void:
            return LinearGradient(colors: [Color(hex: "#000000"), Color(hex: "#0c0c0e")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .custom:
            return LinearGradient(colors: [AutumnPaletteRuntime.bg1Color, AutumnPaletteRuntime.bg2Color], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// A user colour palette: background gradient (top-left -> bottom-right) plus accent. Saved to the profile.
public struct AutumnPalette: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var bg1: String
    public var bg2: String
    public var accent: String
    public init(id: String = UUID().uuidString, name: String, bg1: String, bg2: String, accent: String) {
        self.id = id; self.name = name; self.bg1 = bg1; self.bg2 = bg2; self.accent = accent
    }
    public var c1: Color { Color(hex: bg1) }
    public var c2: Color { Color(hex: bg2) }
    public var ca: Color { Color(hex: accent) }
    public var gradient: LinearGradient { LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing) }
    /// Starting point for editing: the colours of a built-in preset.
    public static func from(_ t: AutumnTheme) -> AutumnPalette {
        let r = t.resolved
        return AutumnPalette(id: "draft", name: t.rawValue.capitalized, bg1: r.base.hexString, bg2: r.surface.hexString, accent: t.accent.hexString)
    }
}

/// Colours used when the current look is a saved/custom palette (AutumnTheme.custom reads these).
public enum AutumnPaletteRuntime {
    nonisolated(unsafe) static var active = AutumnPalette(id: "draft", name: "CUSTOM", bg1: "#05070d", bg2: "#14203a", accent: "#7ecfff")
    static var bg1Color: Color { active.c1 }
    static var bg2Color: Color { active.c2 }
    static var accentColor: Color { active.ca }
    static var washRGB: (r: Double, g: Double, b: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(active.c1).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r) * 0.6, Double(g) * 0.6, Double(b) * 0.6)
    }
}

/// The single piece of user art behind the UI: a video (MP4/MOV...) or a still image (PNG/JPEG/HEIC/TGA...).
public struct ArtSelection: Equatable {
    public enum Kind: String { case video, image }
    public var kind: Kind
    public var name: String
    public var fileName: String
    var defaultsString: String { "\(kind.rawValue)|\(name)|\(fileName)" }
    init?(defaultsString s: String) {
        let p = s.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard p.count == 3, let k = Kind(rawValue: p[0]) else { return nil }
        kind = k; name = p[1]; fileName = p[2]
    }
    init(kind: Kind, name: String, fileName: String) { self.kind = kind; self.name = name; self.fileName = fileName }
}

/// Overlay engine: FROST STEAM CLEAR HAZE DUSK DEEP VOID — matching web LEVELS.
public enum AutumnScrim: String, CaseIterable, Identifiable {
    case frost, steam, clear, haze, dusk, deep, voidOverlay
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .frost: return "FROST"
        case .steam: return "STEAM"
        case .clear: return "CLEAR"
        case .haze: return "HAZE"
        case .dusk: return "DUSK"
        case .deep: return "DEEP"
        case .voidOverlay: return "VOID"
        }
    }
    public var color: Color {
        switch self {
        case .frost: return Color(hex: "#7ecfff")
        case .steam: return Color(hex: "#a8ffc4")
        case .clear: return .white
        case .haze: return Color(hex: "#ffe040")
        case .dusk: return Color(hex: "#ff4aac")
        case .deep: return Color(hex: "#39ff6e")
        case .voidOverlay: return Color(hex: "#aeaeb2")
        }
    }
    public var alpha: Double {
        switch self {
        case .frost: return 0.20
        case .steam: return 0.55
        case .clear: return 0
        case .haze: return 0.50
        case .dusk: return 0.70
        case .deep: return 0.85
        case .voidOverlay: return 1.0
        }
    }
    public var blur: CGFloat {
        switch self {
        case .frost: return 6
        case .steam: return 8
        case .clear: return 0
        case .haze: return 10
        case .dusk: return 14
        case .deep: return 20
        case .voidOverlay: return 0
        }
    }
}

@MainActor
public final class ThemeViewModel: ObservableObject {
    private var suppressVaultNote = false

    @Published public var current: AutumnTheme {
        didSet {
            guard oldValue != current else { return }
            UserDefaults.standard.set(current.key, forKey: AutumnSettingsSync.themeKey)
            if !suppressVaultNote { AutumnSettingsSync.noteLocalChange() }
        }
    }
    @Published public var scrim: AutumnScrim {
        didSet {
            guard oldValue != scrim else { return }
            let all = AutumnScrim.allCases
            UserDefaults.standard.set(all.firstIndex(of: scrim) ?? 0, forKey: AutumnSettingsSync.scrimKey)
            if !suppressVaultNote { AutumnSettingsSync.noteLocalChange() }
        }
    }

    @Published public private(set) var customPalettes: [AutumnPalette] = []
    @Published public private(set) var activeCustomID: String?
    @Published public private(set) var art: ArtSelection?

    public init() {
        loadPaletteAndArt()
        if let k = UserDefaults.standard.string(forKey: AutumnSettingsSync.themeKey),
           let t = AutumnTheme.allCases.first(where: { $0.key == k }) {
            current = t
        } else {
            current = .void
        }
        if current == .custom && activePalette == nil { current = .void }
        let n = UserDefaults.standard.integer(forKey: AutumnSettingsSync.scrimKey)
        let all = AutumnScrim.allCases
        scrim = (n >= 0 && n < all.count) ? all[n] : .frost
    }

    // MARK: palettes
    public var activePalette: AutumnPalette? { customPalettes.first { $0.id == activeCustomID } }

    /// Name shown on the PALETTE button.
    public var paletteLabel: String {
        if current == .custom { return (activePalette?.name ?? "CUSTOM").uppercased() }
        return current.resolved.rawValue
    }

    private func loadPaletteAndArt() {
        let d = UserDefaults.standard
        if let json = d.string(forKey: AutumnSettingsSync.palettesKey), let data = json.data(using: .utf8),
           let list = try? JSONDecoder().decode([AutumnPalette].self, from: data) {
            customPalettes = list
        } else { customPalettes = [] }
        activeCustomID = d.string(forKey: AutumnSettingsSync.paletteKey)
        if let p = activePalette { AutumnPaletteRuntime.active = p }
        if let str = d.string(forKey: AutumnSettingsSync.artKey), let a = ArtSelection(defaultsString: str),
           FileManager.default.fileExists(atPath: Self.artDirectory.appendingPathComponent(a.fileName).path) {
            art = a
        } else { art = nil }
    }

    private func persistPalettes() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(customPalettes), let json = String(data: data, encoding: .utf8) {
            d.set(json, forKey: AutumnSettingsSync.palettesKey)
        }
        if let id = activeCustomID { d.set(id, forKey: AutumnSettingsSync.paletteKey) } else { d.removeObject(forKey: AutumnSettingsSync.paletteKey) }
        AutumnSettingsSync.noteLocalChange()
    }

    /// PALETTE button: presets first, then the user's saved palettes, then around again.
    public func cyclePalette() {
        enum E { case preset(AutumnTheme), custom(AutumnPalette) }
        let entries: [E] = AutumnTheme.presets.map { E.preset($0) } + customPalettes.map { E.custom($0) }
        var idx = -1
        for (i, e) in entries.enumerated() {
            switch e {
            case .preset(let t): if current == t { idx = i }
            case .custom(let p): if current == .custom && activeCustomID == p.id { idx = i }
            }
        }
        switch entries[(idx + 1) % entries.count] {
        case .preset(let t): current = t
        case .custom(let p): applyCustom(p)
        }
    }

    public func applyPreset(_ t: AutumnTheme) {
        activeCustomID = nil
        persistPalettes()
        current = t
    }

    public func applyCustom(_ p: AutumnPalette) {
        AutumnPaletteRuntime.active = p
        activeCustomID = p.id
        persistPalettes()
        objectWillChange.send()
        if current != .custom { current = .custom }
    }

    /// Live preview while editing (not saved to the list).
    public func previewPalette(_ p: AutumnPalette) {
        AutumnPaletteRuntime.active = p
        objectWillChange.send()
        if current != .custom { suppressVaultNote = true; current = .custom; suppressVaultNote = false }
    }

    /// Undo a preview.
    public func restore(theme: AutumnTheme, customID: String?) {
        activeCustomID = customID
        if let p = activePalette { AutumnPaletteRuntime.active = p }
        objectWillChange.send()
        suppressVaultNote = true
        current = (theme == .custom && activePalette == nil) ? .void : theme
        suppressVaultNote = false
    }

    @discardableResult
    public func saveCustom(name: String, bg1: String, bg2: String, accent: String, id: String?) -> AutumnPalette {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = clean.isEmpty ? "Custom \(customPalettes.count + 1)" : clean
        if let id, let i = customPalettes.firstIndex(where: { $0.id == id }) {
            customPalettes[i].name = label; customPalettes[i].bg1 = bg1; customPalettes[i].bg2 = bg2; customPalettes[i].accent = accent
            applyCustom(customPalettes[i])
            return customPalettes[i]
        }
        let p = AutumnPalette(name: label, bg1: bg1, bg2: bg2, accent: accent)
        customPalettes.append(p)
        applyCustom(p)
        return p
    }

    public func deleteCustom(id: String) {
        customPalettes.removeAll { $0.id == id }
        if activeCustomID == id {
            activeCustomID = nil
            if current == .custom { current = .void }
        }
        persistPalettes()
    }

    // MARK: art
    public static var artDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Art", isDirectory: true)
    }
    public var artURL: URL? { art.map { Self.artDirectory.appendingPathComponent($0.fileName) } }
    /// Art shows unless the VOID overlay is selected (then the palette background shows alone).
    public var showsArt: Bool { art != nil && scrim != .voidOverlay }

    /// Copy the picked file into the app's storage (so it is remembered and reloaded every launch), validate it, and use it.
    /// Returns an error message, or nil on success.
    public func importArt(from picked: URL) async -> String? {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let ext = picked.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        let isVideo = type?.conforms(to: .movie) == true || ["mp4", "m4v", "mov"].contains(ext)
        let kind: ArtSelection.Kind = isVideo ? .video : .image
        let dir = Self.artDirectory
        let fileName = "art-\(Int(Date().timeIntervalSince1970)).\(ext.isEmpty ? (isVideo ? "mp4" : "png") : ext)"
        let dest = dir.appendingPathComponent(fileName)
        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.copyItem(at: picked, to: dest)
            }.value
        } catch {
            return "Couldn't copy that file: \(error.localizedDescription)"
        }
        // Validate before replacing the current art.
        if kind == .video {
            let asset = AVURLAsset(url: dest)
            let ok = (try? await asset.load(.isPlayable)) ?? false
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            if !ok || tracks.isEmpty {
                try? FileManager.default.removeItem(at: dest)
                return "That video can't be played here. Use MP4 or MOV (H.264 / HEVC)."
            }
        } else {
            guard let src = CGImageSourceCreateWithURL(dest as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
                try? FileManager.default.removeItem(at: dest)
                return "That image format isn't supported. Use PNG, JPEG, HEIC, TGA, BMP, GIF or TIFF."
            }
        }
        if let old = art { try? FileManager.default.removeItem(at: dir.appendingPathComponent(old.fileName)) }
        let sel = ArtSelection(kind: kind, name: picked.lastPathComponent, fileName: fileName)
        art = sel
        UserDefaults.standard.set(sel.defaultsString, forKey: AutumnSettingsSync.artKey)
        AutumnSettingsSync.noteLocalChange()
        return nil
    }

    public func clearArt() {
        if let old = art { try? FileManager.default.removeItem(at: Self.artDirectory.appendingPathComponent(old.fileName)) }
        art = nil
        UserDefaults.standard.removeObject(forKey: AutumnSettingsSync.artKey)
        AutumnSettingsSync.noteLocalChange()
    }

    public func cycleTheme() {
        let all = AutumnTheme.allCases
        let i = all.firstIndex(of: current) ?? 0
        current = all[(i + 1) % all.count]
    }

    public func cycleScrim() {
        let all = AutumnScrim.allCases
        let i = all.firstIndex(of: scrim) ?? 0
        scrim = all[(i + 1) % all.count]
    }

    /// Apply theme/scrim from UserDefaults after vault restore (last saved wins).
    public func reloadFromDefaults() {
        let themeKey = UserDefaults.standard.string(forKey: AutumnSettingsSync.themeKey)
        let nextTheme = themeKey.flatMap { k in AutumnTheme.allCases.first(where: { $0.key == k }) } ?? current
        let n = UserDefaults.standard.integer(forKey: AutumnSettingsSync.scrimKey)
        let all = AutumnScrim.allCases
        let nextScrim = (n >= 0 && n < all.count) ? all[n] : scrim
        suppressVaultNote = true
        defer { suppressVaultNote = false }
        loadPaletteAndArt()
        objectWillChange.send()
        if nextTheme != current { current = (nextTheme == .custom && activePalette == nil) ? .void : nextTheme }
        if nextScrim != scrim { scrim = nextScrim }
    }

    public var chrome: AutumnTheme { current.resolved }
}

public struct GlassCard: ViewModifier {
    let theme: AutumnTheme
    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(theme.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(theme.accent.opacity(0.25), lineWidth: 1)
            )
    }
}

public extension View {
    func glassCard(theme: AutumnTheme) -> some View {
        modifier(GlassCard(theme: theme))
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64(0)
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}


extension UIColor {
    /// iOS 16-safe Color → UIColor (UIColor(Color) is iOS 17+).
    static func fromSwiftUI(_ color: Color) -> UIColor {
        if #available(iOS 17.0, *) {
            return UIColor(color)
        }
        return UIColor.cyan
    }
}
