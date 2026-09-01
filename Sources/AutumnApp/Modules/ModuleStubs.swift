import SwiftUI
import AutumnServices
import LEATRCore
import SceneKit

/// Shared chrome for right-rail overlays (web mist/star/shard/sys drawers).
struct OverlayPanel<Content: View>: View {
    let title: String
    var onClose: () -> Void
    @EnvironmentObject var themeVM: ThemeViewModel
    let content: Content

    init(title: String, onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        let chrome = themeVM.chrome
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(chrome.accent)
                Spacer()
                Button("✕") { onClose() }
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(chrome.accent.opacity(0.06))
            content
        }
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(chrome.accent.opacity(0.28), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

/// Remaining-module map (honest). Surfaces exist; some are first native pass.
public enum RemainingWebModules {
    public static let map: [(name: String, web: String, note: String)] = [
        ("MIST", "js/mist-module.js", "Overlay + GAS presence + maze solve on BRPN"),
        ("Ash Star", "js/ash-star-archive.js", "3D spawn on orb + archive overlay"),
        ("Ash Shard", "js/ash-shard-module.js", "Textile + contacts overlay"),
        ("SYS", "index.html SYSTEM BROADCAST", "Read public JSON; compose via GAS"),
        ("ArcLake", "js/arclake_studio.js", "First-pass native studio, not a standalone app"),
        ("Arc Forge", "arc-forge.html", "Native first-pass studio"),
        ("Mantis NAV", "mn.html + MantisNavigationView", "Wired from HUD"),
        ("Mantis Radar", "mr.html", "First-pass MapKit + ADS-B HUD"),
        ("HUD tools", "js/hud-tools-module.js", "Wired"),
        ("World Studio", "worldstudio.html", "Native first-pass"),
        ("NATE", "nate.html", "Native first-pass"),
        ("Movement", "movement-conjecture.html", "Native first-pass"),
        ("Grammar engine", "js/autumn-grammar-engine.js", "processForChat in GrammarEngine.swift"),
        ("TTS", "js/autumn-tts.js", "AutumnTTS AVSpeech"),
        ("Theme videos", "assets/*.mp4", "Bundled loop muted AVPlayer"),
    ]
}
