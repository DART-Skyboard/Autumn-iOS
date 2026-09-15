import SwiftUI
import AutumnServices
import LEATRCore

/// Full-screen native studios mapped from standalone web HTML/JS — not WKWebView of the site.
struct StudioHostView: View {
    let kind: AppNavigation.StudioKind
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var chatVM: ChatViewModel

    var body: some View {
        if kind == .alc {
            ALCStudioView()
        } else if kind == .mathSolver {
            Color.clear.onAppear {
                appNav.studio = nil
                appNav.showMathSolver = true
            }
        } else if kind == .latexCanvas {
            Color.clear.onAppear {
                appNav.studio = nil
                appNav.showLatexCanvas = true
            }
        } else {
        ZStack(alignment: .topTrailing) {
            themeVM.chrome.base.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(kind.title)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(themeVM.chrome.accent)
                    Spacer()
                    Button("✕ CLOSE") { appNav.studio = nil }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(themeVM.chrome.surface.opacity(0.95))
                Group {
                    switch kind {
                    case .arcForge: ArcForgeStudioView()
                    case .worldStudio: WorldStudioView()
                    case .nate: NateStudioView()
                    case .movement: MovementConjectureView()
                    case .help: HelpStudioView()
                    case .privacy: PrivacyStudioView()
                    case .arcLake: ArcLakePanel()
                    case .arcEdge: ArcEdgePanel()
                    case .calc: CalcPanel()
                    case .emoMap: EmoMapPanel()
                    case .alc: ALCStudioView()
                    case .mathSolver: MathSolverOverlay()
                    case .latexCanvas: LatexCanvasOverlay()
                    case .music: MusicPanel()
                    }
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct HelpStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                help("CHAT", "Talk to Autumn. Grammar engine runs locally. Core Cognition frozen True. Reflex never loops.")
                help("THEME / SCRIM", "Cycle VOID DAY NIGHT STEALTH DEPARTURE ASH TREE ARIEL AUTO. Scrim FROST to VOID sits on the video, behind UI.")
                help("MIST", "Right rail. Solve the maze on the BRPN orb. Signals ride plasma splines to peers via GAS.")
                help("STAR", "Right rail. Spawns 3D Ash Star geometry on the orb and archives the thought.")
                help("SHARD", "Right rail. Design a textile, pick GitHub following, send along splines.")
                help("SYS", "Right rail. System broadcast. dartsolarpunk can compose; writes go through GAS ashwrite.")
                help("MANTIS / RADAR", "HUD tools. Flight sim (mn.html) and radar (mr.html) native views.")
                help("ARCLAKE", "HUD tools. Chemistry studio first pass — not a standalone App Store app.")
                help("MATH SOLVER", "fx on Ask Autumn, or TOOLS → MATH SOLVER. Assign special operator / physics field / math op per variable. Multi-prompt batch uses BRPN Foundation → Reflex → Performance.")
                help("LATEX CANVAS", "Ask “show me an example of advanced LaTeX” to auto-open. Export TeX, MathML, transparent PNG, CSV, ODT.")
                help("ADMIN", "dartsolarpunk only. Independent of the web app — no browser session required. DATA / ASH / MESSAGES mailbox.")
                help("MUSIC", "HUD tools. Search and play Apple Music inside Autumn. Requires an Apple Music subscription for full playback.")
            }.padding(16)
        }
    }
    private func help(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(themeVM.chrome.accent)
            Text(b).font(.system(size: 13)).foregroundColor(.white.opacity(0.75))
        }
    }
}

struct PrivacyStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Autumn stores conversation history locally. Journal writes go to leatr-ash through the GAS ashwrite proxy. No PAT is stored in the client. GitHub OAuth tokens live in Keychain only. Presence nodes are anonymized. Microphone is on only when you tap voice. Feedback is reviewed by Radical Deepscale LLC and is not public.")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                Text("Full policy: leatr.xyz/autumn-privacy.html")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent)
            }.padding(16)
        }
    }
}
