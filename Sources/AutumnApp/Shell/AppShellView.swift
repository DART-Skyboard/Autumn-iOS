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
    @State private var keyboardHeight: CGFloat = 0

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

                if appNav.showProfile { ProfileSheet().transition(.move(edge: .trailing)) }
                if appNav.showFeedback { FeedbackSheet().transition(.opacity) }
                if appNav.showAdmin, authVM.adminAllowed, authVM.adminEnabled { AdminDrawerView().transition(.move(edge: .leading)) }
                if appNav.showMantis { studioWrap { MantisNavigationView() } }
                if appNav.showRadar { MantisRadarView() }
                if let studio = appNav.studio { StudioHostView(kind: studio) }
                if appNav.showMathSolver { MathSolverOverlay() }
                if appNav.showLatexCanvas { LatexCanvasOverlay() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // GeometryReader must ignore the keyboard so its size (and ChatView identity)
        // stay stable while Ask Autumn becomes first responder. Pad chat by keyboardHeight.
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(themeVM.current == .day ? .light : .dark)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            let screenH = UIScreen.main.bounds.height
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
            // Ignore zero/off-screen frames (launch can post CGRect.zero → overlap≈screenH → black shell).
            guard frame.height > 1, frame.width > 1 else {
                keyboardUp = false
                keyboardHeight = 0
                return
            }
            let overlap = max(0, screenH - frame.origin.y)
            let safe = min(overlap, screenH * 0.7)
            if safe > 40 {
                keyboardUp = true
                keyboardHeight = safe
            } else {
                keyboardUp = false
                keyboardHeight = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
            keyboardHeight = 0
        }
        .animation(.easeInOut(duration: 0.25), value: appNav.showProfile)
        .animation(.easeInOut(duration: 0.25), value: appNav.showAdmin)
        .animation(.easeInOut(duration: 0.25), value: appNav.rightTab)
        .animation(.easeInOut(duration: 0.2), value: appNav.showHUDTools)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35), value: appNav.showAshCanvas)
        .onReceive(NotificationCenter.default.publisher(for: .autumnLatexCanvas)) { note in
            if let seed = note.object as? String { appNav.latexSeed = seed }
            appNav.showLatexCanvas = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .autumnMathSolver)) { note in
            if let seed = note.object as? String { appNav.mathSeed = seed }
            appNav.showMathSolver = true
        }
        .onChange(of: authVM.isGuest) { _ in
            if authVM.isGuest || !authVM.adminAllowed || !authVM.adminEnabled {
                appNav.showAdmin = false
            }
        }
        .onChange(of: authVM.githubUsername) { _ in
            if !authVM.adminAllowed || !authVM.adminEnabled { appNav.showAdmin = false }
        }
        .onChange(of: authVM.adminEnabled) { _ in
            if !authVM.adminEnabled { appNav.showAdmin = false }
        }
        // SIWA at root window (Ashtree/Welcome pattern) — not nested under Profile overlay.
        .fullScreenCover(isPresented: $appNav.showAppleSignIn) {
            RootAppleSignInCover()
                .environmentObject(authVM)
                .environmentObject(themeVM)
                .environmentObject(appNav)
        }
    }

    // MARK: — Portrait: top bar / scene / EmoHUD / ash trigger / chat
    private func portraitChrome(size: CGSize) -> some View {
        VStack(spacing: 0) {
            topBar
            sceneStage
            belowSceneStack(chatMax: min(320, max(220, size.height * 0.34)))
        }
        .padding(.bottom, keyboardUp ? keyboardHeight : 0)
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
                ChatView(compact: true)
                    .frame(maxHeight: .infinity)
                    .background(themeVM.scrim == .clear ? Color.black.opacity(0.18) : themeVM.chrome.surface)
                if !keyboardUp {
                    footerBar
                }
            }
            .frame(width: min(400, max(280, size.width * 0.36)))
            .padding(.bottom, keyboardUp ? keyboardHeight : 0)
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

            // Drawers sit on the 3D scene only — never cover Ask Autumn / the keyboard.
            ModuleOverlayHost()

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
        return HStack(spacing: 6) {
            AutumnLogoMark(size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("Autumn")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(chrome.accent)
                    .lineLimit(1)
                Text("LEATR v2.1")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(chrome.textSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(0)
            Spacer(minLength: 4)
            scrimPill
            themePill
            livePill
            profileChip
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
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

    /// One-line capsule. Never a circle, never wraps letters inside a word.
    private func headerChip(text: String, color: Color, dot: Bool = false) -> some View {
        HStack(spacing: 4) {
            if dot { Circle().fill(color).frame(width: 5, height: 5) }
            Text(text)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(color.opacity(0.10))
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    private var themePill: some View {
        let chrome = themeVM.chrome
        return Button { themeVM.cycleTheme() } label: {
            headerChip(text: themeVM.current.rawValue, color: chrome.accent)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    private var scrimPill: some View {
        let pct = Int((1.0 - themeVM.scrim.alpha) * 100)
        let label = "\(pct)% \(themeVM.scrim.label)"
        return Button { themeVM.cycleScrim() } label: {
            headerChip(text: label, color: themeVM.scrim.color)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    private var livePill: some View {
        Button {
            sceneVM.liveFeedEnabled.toggle()
        } label: {
            headerChip(
                text: sceneVM.liveFeedEnabled ? "LIVE FEED" : "FEED OFF",
                color: sceneVM.liveFeedEnabled ? Color(hex: "#00ff88") : Color.white.opacity(0.45),
                dot: sceneVM.liveFeedEnabled
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
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
                size: 26,
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


/// Dark root SIWA host — AppleSignInButton tap starts auth (same gesture). Profile only opens this cover.
struct RootAppleSignInCover: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @State private var reopenProfileOnSuccess = true

    var body: some View {
        let chrome = themeVM.chrome
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Text("SIGN IN WITH APPLE")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(chrome.accent)
                    Spacer()
                    Button("Cancel") {
                        authVM.error = nil
                        appNav.showAppleSignIn = false
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                Text("Use the Apple button below. Auth starts from this root cover — same as Welcome.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                AppleSignInButton(
                    onRequest: { req in
                        authVM.error = nil
                        authVM.prepareAppleRequest(req)
                    },
                    onCompletion: { result in
                        authVM.handleAppleCompletion(result)
                        switch result {
                        case .success:
                            appNav.showAppleSignIn = false
                            authVM.error = nil
                            if reopenProfileOnSuccess {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    appNav.showProfile = true
                                }
                            }
                        case .failure:
                            // Canceled → applyAppleError leaves error nil → dismiss. Failure keeps cover + banner.
                            if authVM.error == nil {
                                appNav.showAppleSignIn = false
                            }
                        }
                    }
                )
                .frame(maxWidth: 360)
                .frame(height: 52)
                .cornerRadius(12)
                .padding(.horizontal, 28)
                .accessibilityLabel("Sign in with Apple")

                if let err = authVM.error {
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "#ff6688"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .accessibilityLabel("Sign in error")
                    if authVM.appleErrorOffersSettings {
                        Button("Open Settings → Apple ID") {
                            authVM.openAppleIDSettings()
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "#7ecfff"))
                        .padding(.top, 4)
                    }
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

@MainActor
public final class AppNavigation: ObservableObject {
    @Published public var showProfile = false
    @Published public var showFeedback = false
    @Published public var showAdmin = false
    /// Root fullScreenCover for SIWA — Profile must not host AppleSignInButton nested.
    @Published public var showAppleSignIn = false
    /// When true, RootView shows WelcomeView (fresh Apple/GitHub/Guest) instead of shell.
    @Published public var showWelcome = false
    @Published public var leftTab: LeftTab = .none
    @Published public var rightTab: RightTab = .none
    @Published public var adminTab: AdminTab = .data
    @Published public var showHUDTools = false
    @Published public var showMantis = false
    @Published public var showRadar = false
    @Published public var showAshCanvas = false
    @Published public var showMathSolver = false
    @Published public var showLatexCanvas = false
    @Published public var latexSeed = ""
    @Published public var mathSeed = ""
    @Published public var ashApplied = false
    @Published public var ashStatusLabel = "NEURAL INFLUENCE"
    @Published public var studio: StudioKind? = nil

    public enum LeftTab { case none, geo, mar, aero }
    public enum RightTab { case none, mist, star, shard, sys }
    /// Web-parity admin chrome: DATA / ASH / MESSAGES (roles + users live on DATA).
    public enum AdminTab: String, CaseIterable { case data = "DATA", ash = "ASH", messages = "MESSAGES" }
    public enum StudioKind: String, Identifiable {
        case arcForge, worldStudio, nate, movement, help, privacy, arcLake, arcEdge, calc, emoMap, alc, mathSolver, latexCanvas
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
            case .mathSolver: return "MATH SOLVER"
            case .latexCanvas: return "LATEX CANVAS"
            }
        }
    }
}
