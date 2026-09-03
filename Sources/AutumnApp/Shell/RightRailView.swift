import SwiftUI
import AutumnServices

/// Right tabs matching web: MIST, STAR, SHARD, SYS — overlays, not stub sheets.
public struct RightRailView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    var axis: Axis = .vertical

    public var body: some View {
        let tabs = Group {
            rail("MIST", selected: appNav.rightTab == .mist) { toggle(.mist) }
            rail("STAR", selected: appNav.rightTab == .star) { toggle(.star) }
            rail("SHARD", selected: appNav.rightTab == .shard) { toggle(.shard) }
            rail("SYS", selected: appNav.rightTab == .sys) { toggle(.sys) }
        }
        if axis == .horizontal {
            HStack(spacing: 4) { tabs }
        } else {
            VStack(spacing: 8) {
                tabs
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func toggle(_ t: AppNavigation.RightTab) {
        appNav.rightTab = appNav.rightTab == t ? .none : t
    }

    private func rail(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let chrome = themeVM.chrome
        return Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(selected ? chrome.accent : chrome.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 10)
                .moduleFrost(stroke: chrome.accent.opacity(selected ? 0.55 : 0.22), fill: selected ? 0.14 : 0.08)
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
                        .frame(maxHeight: land ? geo.size.height - 16 : min(geo.size.height - 16, 520))
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
