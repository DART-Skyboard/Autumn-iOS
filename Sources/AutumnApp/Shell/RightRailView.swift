import SwiftUI
import AutumnServices

/// Right tabs matching web: MIST, STAR, SHARD, SYS — overlays, not stub sheets.
public struct RightRailView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation

    public var body: some View {
        VStack(spacing: 8) {
            rail("MIST", selected: appNav.rightTab == .mist) { toggle(.mist) }
            rail("STAR", selected: appNav.rightTab == .star) { toggle(.star) }
            rail("SHARD", selected: appNav.rightTab == .shard) { toggle(.shard) }
            rail("SYS", selected: appNav.rightTab == .sys) { toggle(.sys) }
            Spacer()
        }
        .padding(.top, 4)
    }

    private func toggle(_ t: AppNavigation.RightTab) {
        appNav.rightTab = appNav.rightTab == t ? .none : t
    }

    private func rail(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let chrome = themeVM.chrome
        return Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(selected ? chrome.accent : chrome.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 10)
                .background(selected ? chrome.accent.opacity(0.15) : chrome.surface.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(chrome.accent.opacity(selected ? 0.5 : 0.2), lineWidth: 1))
        }
    }
}

/// Hosts MIST/STAR/SHARD/SYS overlays on the BRPN scene (web right-edge drawers).
struct ModuleOverlayHost: View {
    @EnvironmentObject var appNav: AppNavigation
    var body: some View {
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
            .frame(width: 300)
            .padding(.trailing, 46)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .allowsHitTesting(appNav.rightTab != .none)
    }
}
