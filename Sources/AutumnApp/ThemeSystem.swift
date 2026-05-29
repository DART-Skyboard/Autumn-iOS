import SwiftUI

// MARK: — Autumn Theme System
// 5 themes matching the web app's CSS variable system

public enum AutumnTheme: String, CaseIterable, Identifiable {
    case day       = "Day"
    case night     = "Night"
    case stealth   = "Stealth"
    case departure = "Departure"
    case ashTree   = "Ash Tree"

    public var id: String { rawValue }

    public var base: Color {
        switch self {
        case .day:       return Color(hex: "#0a1628")
        case .night:     return Color(hex: "#020a14")
        case .stealth:   return Color(hex: "#060a10")
        case .departure: return Color(hex: "#0d0a1a")
        case .ashTree:   return Color(hex: "#0a140a")
        }
    }

    public var surface: Color {
        switch self {
        case .day:       return Color(hex: "#0d1f3c").opacity(0.85)
        case .night:     return Color(hex: "#060f1e").opacity(0.85)
        case .stealth:   return Color(hex: "#0a0e14").opacity(0.85)
        case .departure: return Color(hex: "#120d24").opacity(0.85)
        case .ashTree:   return Color(hex: "#0d190d").opacity(0.85)
        }
    }

    public var accent: Color { Color(hex: "#00e5ff") }

    public var accentSecondary: Color {
        switch self {
        case .day:       return Color(hex: "#00ffcc")
        case .night:     return Color(hex: "#00ccff")
        case .stealth:   return Color(hex: "#888888")
        case .departure: return Color(hex: "#aa88ff")
        case .ashTree:   return Color(hex: "#44ff88")
        }
    }

    public var text: Color { .white }
    public var textSecondary: Color { Color.white.opacity(0.6) }

    public var gradient: LinearGradient {
        LinearGradient(
            colors: [base, surface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: — Theme ViewModel
@MainActor
public final class ThemeViewModel: ObservableObject {
    @Published public var current: AutumnTheme = .night
}

// MARK: — Glass modifier
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

// MARK: — Color from hex
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
