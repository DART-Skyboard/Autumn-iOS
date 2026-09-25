import SwiftUI
import AutumnServices

/// Right tabs matching web: MIST, STAR, SHARD, SYS — overlays, not stub sheets.
public struct RightRailView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    var axis: Axis = .vertical

    public var body: some View {
        let tabs = Group {
            rail("MIST", color: Color(hex: "#5fd4ff"), selected: appNav.rightTab == .mist) { toggle(.mist) }
            rail("STAR", color: Color(hex: "#ffd25f"), selected: appNav.rightTab == .star) { toggle(.star) }
            rail("SHARD", color: Color(hex: "#c48bff"), selected: appNav.rightTab == .shard) { toggle(.shard) }
            rail("SYS", color: Color(hex: "#6dff9e"), selected: appNav.rightTab == .sys) { toggle(.sys) }
        }
        if axis == .horizontal {
            HStack(spacing: 4) { tabs }
        } else {
            // TF155: was VStack(spacing: 8) with no alignment (defaults to
            // .center) — same bug as the left HUD column before it was
            // fixed: different-width labels put each one's edge at a
            // different horizontal position. .trailing flushes them all to
            // the right edge, matching "align those right" directly.
            // Vertical padding cut 10->5 to match the left column's
            // thinner treatment.
            VStack(alignment: .trailing, spacing: 8) {
                tabs
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func toggle(_ t: AppNavigation.RightTab) {
        appNav.rightTab = appNav.rightTab == t ? .none : t
    }

    private func rail(_ title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(color.opacity(selected ? 1.0 : 0.75))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .moduleFrost(stroke: color.opacity(selected ? 0.6 : 0.3), fill: selected ? 0.16 : 0.09)
        }
    }
}

/// Hosts MIST/STAR/SHARD/SYS overlays on the BRPN scene (web right-edge drawers).
/// Portrait: 300pt card. Landscape: wider/taller so maze, shard canvas, SYS body show in full.
struct ModuleOverlayHost: View {
    @EnvironmentObject var appNav: AppNavigation
    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            ZStack(alignment: .topTrailing) {
                if appNav.rightTab != .none {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { appNav.rightTab = .none }
                }
                if appNav.rightTab != .none {
                    HStack {
                        Spacer()
                        Group {
                            switch appNav.rightTab {
                            case .mist: MISTOverlay()
                            case .star: StarOverlay()
                            case .shard: ShardOverlay()
                            case .sys: SYSOverlay()
                            case .none: EmptyView()
                            }
                        }
                        .frame(width: land ? min(geo.size.width - 24, 520) : min(300, geo.size.width - 52))
                        .frame(maxHeight: land ? geo.size.height - 16 : min(geo.size.height - 16, appNav.rightTab == .shard ? 780 : 640))
                        .padding(.trailing, land ? 10 : 46)
                        .padding(.leading, land ? 10 : 0)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .allowsHitTesting(appNav.rightTab != .none)
    }
}
