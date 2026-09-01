import SwiftUI
import AutumnServices

/// Honest stubs for modules not ported in this pass. Each names the web file it maps to.
public struct ModuleStubSheet: View {
    let tab: AppNavigation.RightTab
    @EnvironmentObject var themeVM: ThemeViewModel
    @Environment(\.dismiss) var dismiss

    public var body: some View {
        let spec = Self.spec(tab)
        NavigationStack {
            ZStack {
                themeVM.chrome.gradient.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("TODO").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(themeVM.chrome.accent)
                    Text(spec.title).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(.white)
                    Text(spec.blurb).font(.system(size: 14)).foregroundColor(.white.opacity(0.75))
                    Text("Web source: \(spec.web)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(themeVM.chrome.accent.opacity(0.8))
                    Spacer()
                }.padding(24)
            }
            .navigationTitle(spec.title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    struct Spec { let title: String; let blurb: String; let web: String }
    static func spec(_ tab: AppNavigation.RightTab) -> Spec {
        switch tab {
        case .mist:
            return Spec(title: "MIST",
                        blurb: "Multiplayer presence maze on the BRPN orb. iOS has a GameKit scaffold in MISTMultiplayer.swift; live GAS presence + maze overlay is not wired in this pass.",
                        web: "js/mist-module.js + index.html MIST overlay")
        case .star:
            return Spec(title: "ASH STAR",
                        blurb: "Ash Star is a 3D wireframe on the live BRPN scene — never a chat card. SceneKit spawn is stubbed on BRPNSceneViewModel.spawnAshStar. Full plasma-curve animation is next pass.",
                        web: "js/ash-star-archive.js + index.html ASHSTAR tags")
        case .shard:
            return Spec(title: "SHARD",
                        blurb: "Ash Shard module: fragment archive / shard HUD. Not ported.",
                        web: "js/ash-shard-module.js")
        case .sys:
            return Spec(title: "SYS",
                        blurb: "System broadcast (system-broadcast.json). Admin compose lives on web SYS tab. This pass shows the stub only.",
                        web: "index.html SYSTEM BROADCAST MODULE + system-broadcast.json")
        case .none:
            return Spec(title: "—", blurb: "", web: "")
        }
    }
}

/// Additional remaining-module map for the PR / README. Not a view.
public enum RemainingWebModules {
    public static let map: [(name: String, web: String, note: String)] = [
        ("MIST multiplayer", "js/mist-module.js", "GameKit scaffold exists; GAS presence + overlay TODO"),
        ("Ash Star 3D", "js/ash-star-archive.js", "SceneKit spawn stub; plasma curves TODO"),
        ("Ash Shard", "js/ash-shard-module.js", "Not ported"),
        ("SYS broadcast", "index.html SYSTEM BROADCAST + system-broadcast.json", "Stub sheet only"),
        ("ArcLake", "js/arclake_studio.js", "ToolsView ArcLakePanel is legacy; not in new shell"),
        ("Arc Forge", "arc-forge.html", "Not ported"),
        ("Mantis / Radar", "index.html MANTIS NAV + MantisNavigationView.swift", "Existing view unused in new shell"),
        ("HUD tools", "js/hud-tools-module.js", "Not ported"),
        ("Grammar Study train", "js/autumn-grammar-engine.js Grammar Study", "Admin ASH tab stub + live admin chat"),
        ("WordNet buckets", "js/wordnet_loader.js", "WordNetStore.swift exists; no bundled JSON in this pass"),
        ("Theme video backdrops", "assets/*.mp4", "Native chrome only; no video bundle (236MB)"),
        ("World Studio", "worldstudio.html", "Not ported"),
        ("Nate / MR / MN", "nate.html mr.html mn.html", "Not ported"),
        ("Desktop layout", "js/desktop-layout.js", "iOS uses AppShellView instead"),
    ]
}
