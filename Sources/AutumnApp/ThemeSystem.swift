import SwiftUI
import UIKit

/// Theme engine matching web THEMES in index.html:
/// VOID DAY NIGHT STEALTH DEPARTURE ASH TREE ARIEL AUTO
public enum AutumnTheme: String, CaseIterable, Identifiable {
    case void = "VOID"
    case day = "DAY"
    case night = "NIGHT"
    case stealth = "STEALTH"
    case departure = "DEPARTURE"
    case ashTree = "ASH TREE"
    case ariel = "ARIEL"
    case auto = "AUTO"

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
        case .auto: return "system"
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
        case .auto: return "◈"
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
        case .auto: return Color(hex: "#ffb347")
        }
    }

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
        case .auto: return Color(hex: "#020814")
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
        case .auto: return Color(hex: "#0d1f3c").opacity(0.85)
        }
    }

    public var accentSecondary: Color { accent }
    public var text: Color { .white }
    public var textSecondary: Color { Color.white.opacity(0.6) }

    public var gradient: LinearGradient {
        LinearGradient(colors: [base, surface], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Bundle resource name (no extension). VOID and unresolved AUTO have none.
    public var videoResourceName: String? {
        switch resolved {
        case .void: return nil
        case .day: return "autumnanimation"
        case .night: return "autumnnight"
        case .stealth: return "dartalley"
        case .departure: return "autumndeparture"
        case .ashTree: return "ashtree"
        case .ariel: return "ariel"
        case .auto: return "autumnanimation"
        }
    }

    /// Web WASH_RGB for scrim tint on video.
    public var washRGB: (r: Double, g: Double, b: Double) {
        switch resolved {
        case .void: return (0, 0, 0)
        case .day, .auto: return (2/255.0, 10/255.0, 20/255.0)
        case .night: return (4/255.0, 2/255.0, 12/255.0)
        case .stealth: return (3/255.0, 5/255.0, 12/255.0)
        case .departure: return (12/255.0, 5/255.0, 0)
        case .ashTree: return (1/255.0, 10/255.0, 4/255.0)
        case .ariel: return (8/255.0, 20/255.0, 36/255.0)
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
        }
    }
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
    @Published public var current: AutumnTheme
    @Published public var scrim: AutumnScrim

    public init() {
        if let k = UserDefaults.standard.string(forKey: "_aut_theme"),
           let t = AutumnTheme.allCases.first(where: { $0.key == k }) {
            current = t
        } else {
            current = .void
        }
        let n = UserDefaults.standard.integer(forKey: "_aut_scrim")
        let all = AutumnScrim.allCases
        scrim = (n >= 0 && n < all.count) ? all[n] : .frost
    }

    public func cycleTheme() {
        let all = AutumnTheme.allCases
        let i = all.firstIndex(of: current) ?? 0
        let next = all[(i + 1) % all.count]
        current = next
        UserDefaults.standard.set(next.key, forKey: "_aut_theme")
    }

    public func cycleScrim() {
        let all = AutumnScrim.allCases
        let i = (all.firstIndex(of: scrim) ?? 0)
        scrim = all[(i + 1) % all.count]
        UserDefaults.standard.set(all.firstIndex(of: scrim) ?? 0, forKey: "_aut_scrim")
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
