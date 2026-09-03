import SwiftUI
import UIKit
import AutumnServices
import LEATRCore

/// Native shell matching live leatr.xyz:
/// Z-order: theme video/solid → scrim (hit-test off) → chrome/scene/chat/sheets.
/// Portrait: scene top, chat bottom, left GEO/MAR/AERO+ADMIN, right MIST/STAR/SHARD/SYS.
/// Landscape: header left, 3D scene over Ash Canvas in the middle, full chat right. Portrait restores the stacked chrome.
/// GEO/MAR/AERO live only as the left stack — never also as a top row.
public struct AppShellView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var circuit: AdminCircuitMonitor
    @EnvironmentObject var journalVM: JournalViewModel
    @State private var keyboardUp = false

    public var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                // 1. Theme video or solid (web #backdrop-video z-index:-2)
                themeVM.chrome.base.ignoresSafeArea()
                ThemeVideoBackground(
                    resourceName: themeVM.chrome.videoResourceName,
                    videoOn: themeVM.videoOn
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // 2. Scrim ON the video, BEHIND all UI (web #vid-scrim z-index:-1)
                scrimWash.allowsHitTesting(false)

                // 3. All chrome / scene HUD / chat / sheets
                Group {
                    if landscape {
                        landscapeChrome(size: geo.size)
                    } else {
                        portraitChrome(size: geo.size)
                    }
                }
                ModuleOverlayHost()

                if appNav.showProfile { ProfileSheet().transition(.move(edge: .trailing)) }
                if appNav.showFeedback { FeedbackSheet().transition(.opacity) }
                if appNav.showAdmin, circuit.allows(authVM) { AdminDrawerView().transition(.move(edge: .leading)) }
                if appNav.showMantis { studioWrap { MantisNavigationView() } }
                if appNav.showRadar { MantisRadarView() }
                if let studio = appNav.studio { StudioHostView(kind: studio) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // Chat/input stack must NOT ignore the keyboard. Removing this lets the
        // Ask Autumn bar rest directly above the system keyboard.
        .preferredColorScheme(themeVM.current == .day ? .light : .dark)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
        .animation(.easeInOut(duration: 0.25), value: appNav.showProfile)
        .animation(.easeInOut(duration: 0.25), value: appNav.showAdmin)
        .animation(.easeInOut(duration: 0.25), value: appNav.rightTab)
        .animation(.easeInOut(duration: 0.2), value: appNav.showHUDTools)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35), value: appNav.showAshCanvas)
        .onAppear { circuit.start() }
        .onChange(of: circuit.live) { _ in
            if !circuit.allows(authVM) { appNav.showAdmin = false }
        }
        .onChange(of: authVM.adminEnabled) { _ in
            if !circuit.allows(authVM) { appNav.showAdmin = false }
        }
    }

    // MARK: — Portrait: top bar / scene / EmoHUD / ash trigger / chat
    private func portraitChrome(size: CGSize) -> some View {
        VStack(spacing: 0) {
            topBar
            sceneStage
            belowSceneStack(chatMax: min(320, max(220, size.height * 0.34)))
        }
    }

    // MARK: — Landscape: header left, scene+canvas middle, full chat right.
    /// Portrait stack is restored by portraitChrome — do not change that layout.
    private func landscapeChrome(size: CGSize) -> some View {
        HStack(spacing: 0) {
            leftDrawer
                .frame(width: min(176, max(132, size.width * 0.18)))

            // Middle: HUD on the 3D scene (top); Ash Canvas (bottom) when open. Both stay in view.
            VStack(spacing: 0) {
                landscapeTopHUD
                sceneStage(includeSideHUD: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                AshCanvasTrigger()
                if appNav.showAshCanvas {
                    AshCanvasView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity)
            .background(themeVM.chrome.surface.opacity(0.35))

            // Right: entire pane is chat (messages + paperclip/send).
            VStack(spacing: 0) {
                EmoHUD()
                ChatView()
                    .frame(maxHeight: .infinity)
                    .background(themeVM.scrim == .clear ? Color.black.opacity(0.18) : themeVM.chrome.surface)
                if !keyboardUp {
                    footerBar
                }
            }
            .frame(width: min(400, max(280, size.width * 0.36)))
        }
    }

    /// HUD tabs sit on TOP of the chat/scene strip in landscape so they don't clip off the edge.
    private var landscapeTopHUD: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                LeftHUDView(axis: .horizontal)
                HUDToolsTab()
                RightRailView(axis: .horizontal)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .background(themeVM.chrome.surface.opacity(0.9))
    }

    /// Web order under #brpn-region: EmoHUD, ash-canvas-trigger, drawer (over chat).
    /// Drawer expands DOWN and overlays chat; it does not push the 3D scene up.
    private func belowSceneStack(chatMax: CGFloat) -> some View {
        VStack(spacing: 0) {
            EmoHUD()
            AshCanvasTrigger()
            ZStack(alignment: .top) {
                ChatView()
                    .frame(maxHeight: .infinity)
                    .background(themeVM.scrim == .clear ? Color.black.opacity(0.18) : themeVM.chrome.surface)
                if appNav.showAshCanvas {
                    AshCanvasView()
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .frame(maxHeight: appNav.showAshCanvas ? 520 : chatMax)
            if !keyboardUp {
                footerBar
            }
        }
    }

    /// BRPN + optional side HUD. Overlays live at the shell so landscape can squeeze them on-screen.
    private var sceneStage: some View { sceneStage(includeSideHUD: true) }

    private func sceneStage(includeSideHUD: Bool) -> some View {
        ZStack {
            BRPNSceneView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if includeSideHUD {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        LeftHUDView()
                        HUDToolsTab()
                        Spacer()
                    }
                    Spacer()
                    RightRailView()
                }
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }

            if appNav.showHUDTools {
                HUDToolsPanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, includeSideHUD ? 52 : 8)
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        let chrome = themeVM.chrome
        return HStack(spacing: 8) {
            AutumnLogoMark(size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Autumn")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(chrome.accent)
                Text("LEATR v2.1")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(chrome.textSecondary)
            }
            Spacer()
            scrimPill
            themePill
            livePill
            profileChip
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(chrome.surface.opacity(0.92))
        .overlay(Rectangle().frame(height: 1).foregroundColor(chrome.accent.opacity(0.2)), alignment: .bottom)
    }

    /// Web landscape: header becomes a left nav column.
    private var leftDrawer: some View {
        let chrome = themeVM.chrome
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                AutumnLogoMark(size: 22)
                Text("Autumn")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(chrome.accent)
            }
            .padding(.top, 10)
            scrimPill
            themePill
            livePill
            profileChip
            Divider().background(chrome.accent.opacity(0.2))
            ScrollView(.vertical, showsIndicators: false) {
                HUDToolsPanel(compact: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(chrome.surface.opacity(0.94))
        .overlay(Rectangle().frame(width: 1).foregroundColor(chrome.accent.opacity(0.2)), alignment: .trailing)
    }

    private var themePill: some View {
        let chrome = themeVM.chrome
        return Button { themeVM.cycleTheme() } label: {
            HStack(spacing: 6) {
                Text(chrome.dot)
                    .lineLimit(1)
                Text(themeVM.current.rawValue)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(chrome.accent)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(chrome.accent.opacity(0.10))
            .overlay(Capsule().stroke(chrome.accent.opacity(0.35), lineWidth: 1))
            .clipShape(Capsule())
        }
    }

    private var scrimPill: some View {
        Button { themeVM.cycleScrim() } label: {
            HStack(spacing: 6) {
                Text("\(Int((1.0 - themeVM.scrim.alpha) * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Text(themeVM.scrim.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(themeVM.scrim.color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(themeVM.scrim.color.opacity(0.10))
            .overlay(Capsule().stroke(themeVM.scrim.color.opacity(0.35), lineWidth: 1))
            .clipShape(Capsule())
        }
    }

    private var livePill: some View {
        Button {
            Task {
                await AutumnGASClient.shared.pingPresence(
                    message: "LIVE",
                    response: "ios shell",
                    emotion: "neutral",
                    buoyancy: 0.5,
                    uid: authVM.sessionUID
                )
            }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "#00ff88")).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
            }
            .foregroundColor(Color(hex: "#00ff88"))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(hex: "#00ff88").opacity(0.10))
            .overlay(Capsule().stroke(Color(hex: "#00ff88").opacity(0.35), lineWidth: 1))
            .clipShape(Capsule())
        }
    }

    private var footerBar: some View {
        let chrome = themeVM.chrome
        return HStack(spacing: 10) {
            HStack(spacing: 4) {
                Circle().fill(chrome.accent).frame(width: 5, height: 5)
                Text("LEATR")
            }
            Text("OPS: 25")
            Text("JOURNAL: \(journalVM.entries.count)")
            Text("SOURCES: 0")
            Spacer()
            Text("© 2026 DART MEADOW")
                .opacity(0.55)
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundColor(chrome.accent.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(chrome.surface.opacity(0.92))
        .overlay(Rectangle().frame(height: 1).foregroundColor(chrome.accent.opacity(0.15)), alignment: .top)
    }

    private var profileChip: some View {
        let chrome = themeVM.chrome
        return Button { appNav.showProfile = true } label: {
            GitHubAvatarView(
                url: authVM.githubAvatarURL,
                letter: authVM.username,
                size: 34,
                accent: chrome.accent
            )
        }
    }

    @ViewBuilder
    private var scrimWash: some View {
        let s = themeVM.scrim
        let chrome = themeVM.chrome
        switch s {
        case .clear:
            Color.clear.ignoresSafeArea()
        case .voidOverlay:
            chrome.voidGradient.ignoresSafeArea()
        case .steam:
            ZStack {
                VideoBlur(radius: s.blur).ignoresSafeArea()
                Color(red: 8/255.0, green: 20/255.0, blue: 12/255.0).opacity(s.alpha).ignoresSafeArea()
            }
        default:
            ZStack {
                if s.blur > 0 { VideoBlur(radius: s.blur).ignoresSafeArea() }
                chrome.washColor.opacity(s.alpha).ignoresSafeArea()
            }
        }
    }

    private func studioWrap<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        ZStack(alignment: .topTrailing) {
            content()
            Button { appNav.showMantis = false; appNav.showRadar = false } label: {
                Text("✕ CLOSE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
            }
            .padding(12)
        }
        .transition(.opacity)
    }
}

extension ThemeViewModel {
    /// Video plays unless VOID theme or VOID overlay (web setBackdropVideoOn).
    public var videoOn: Bool {
        guard chrome.videoResourceName != nil else { return false }
        return scrim != .voidOverlay
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
    @Published public var showHUDTools = false
    @Published public var showMantis = false
    @Published public var showRadar = false
    @Published public var showAshCanvas = false
    @Published public var ashApplied = false
    @Published public var ashStatusLabel = "NEURAL INFLUENCE"
    @Published public var studio: StudioKind? = nil

    public enum LeftTab { case none, geo, mar, aero }
    public enum RightTab { case none, mist, star, shard, sys }
    public enum AdminTab: String, CaseIterable { case data = "DATA", ash = "ASH", msg = "MESSAGES" }
    public enum StudioKind: String, Identifiable {
        case arcForge, worldStudio, nate, movement, help, privacy, arcLake, arcEdge, calc, emoMap, alc
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .arcForge: return "ARC FORGE"
            case .worldStudio: return "WORLD STUDIO"
            case .nate: return "N.A.T.E"
            case .movement: return "MOVEMENT CONJECTURE"
            case .help: return "HELP"
            case .privacy: return "PRIVACY"
            case .arcLake: return "ARCLAKE STUDIO"
            case .arcEdge: return "ARC EDGE"
            case .calc: return "CALC"
            case .emoMap: return "EMO MAP"
            case .alc: return "ALC · AFTERLIFE CROSSING"
            }
        }
    }
}
