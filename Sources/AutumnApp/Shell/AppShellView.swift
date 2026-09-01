import SwiftUI
import AutumnServices
import LEATRCore

/// Native shell matching live leatr.xyz layout:
/// BRPN scene on top, chat on the bottom, left HUD + ADMIN, right MIST/STAR/SHARD/SYS.
public struct AppShellView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var appNav: AppNavigation

    public var body: some View {
        let chrome = themeVM.chrome
        ZStack {
            chrome.base.ignoresSafeArea()
            chrome.gradient.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                GeometryReader { geo in
                    ZStack {
                        BRPNSceneView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        GEOMarAeroHUD()
                            .padding(.top, 8)
                            .padding(.horizontal, 52)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        HStack {
                            LeftHUDView()
                            Spacer()
                            RightRailView()
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                    }
                    .frame(height: geo.size.height)
                }
                .frame(maxHeight: .infinity)

                ChatView()
                    .frame(maxHeight: 320)
                    .background(chrome.surface)
            }

            scrimWash.allowsHitTesting(false)

            if appNav.showProfile { ProfileSheet().transition(.move(edge: .trailing)) }
            if appNav.showFeedback { FeedbackSheet().transition(.opacity) }
            if appNav.showAdmin, authVM.adminEnabled { AdminDrawerView().transition(.move(edge: .leading)) }
        }
        .preferredColorScheme(themeVM.current == .day ? .light : .dark)
        .animation(.easeInOut(duration: 0.25), value: appNav.showProfile)
        .animation(.easeInOut(duration: 0.25), value: appNav.showAdmin)
    }

    private var topBar: some View {
        let chrome = themeVM.chrome
        return HStack(spacing: 8) {
            Button { themeVM.cycleTheme() } label: {
                HStack(spacing: 6) {
                    Text(chrome.dot)
                    Text(themeVM.current.rawValue)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                }
                .foregroundColor(chrome.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(chrome.accent.opacity(0.10))
                .overlay(Capsule().stroke(chrome.accent.opacity(0.35), lineWidth: 1))
                .clipShape(Capsule())
            }
            Button { themeVM.cycleScrim() } label: {
                HStack(spacing: 6) {
                    Text("◐")
                    Text(themeVM.scrim.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                }
                .foregroundColor(themeVM.scrim.color)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(themeVM.scrim.color.opacity(0.10))
                .overlay(Capsule().stroke(themeVM.scrim.color.opacity(0.35), lineWidth: 1))
                .clipShape(Capsule())
            }
            Spacer()
            Text(LEATRIdentity.displayName.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundColor(chrome.accent.opacity(0.7))
            Button { appNav.showProfile = true } label: {
                ZStack {
                    Circle().fill(chrome.accent.opacity(0.15)).frame(width: 34, height: 34)
                    Circle().stroke(chrome.accent.opacity(0.4), lineWidth: 1).frame(width: 34, height: 34)
                    if let url = authVM.githubAvatarURL {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill().frame(width: 34, height: 34).clipShape(Circle())
                        } placeholder: {
                            Text(authVM.username.prefix(1).uppercased())
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(chrome.accent)
                        }
                    } else {
                        Text(authVM.username.prefix(1).uppercased())
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(chrome.accent)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(chrome.surface.opacity(0.92))
        .overlay(Rectangle().frame(height: 1).foregroundColor(chrome.accent.opacity(0.2)), alignment: .bottom)
    }

    @ViewBuilder
    private var scrimWash: some View {
        let s = themeVM.scrim
        if s == .voidOverlay {
            themeVM.chrome.gradient.opacity(0.92).ignoresSafeArea()
        } else if s != .clear {
            themeVM.chrome.base.opacity(s.alpha)
                .background(.ultraThinMaterial.opacity(s.blur > 0 ? 0.6 : 0))
                .ignoresSafeArea()
        }
    }
}

@MainActor
public final class AppNavigation: ObservableObject {
    @Published public var showProfile = false
    @Published public var showFeedback = false
    @Published public var showAdmin = false
    @Published public var leftTab: LeftTab = .none
    @Published public var rightTab: RightTab = .none
    @Published public var adminTab: AdminTab = .data

    public enum LeftTab { case none, geo, mar, aero }
    public enum RightTab { case none, mist, star, shard, sys }
    public enum AdminTab: String, CaseIterable { case data = "DATA", ash = "ASH", msg = "MSG" }
}
