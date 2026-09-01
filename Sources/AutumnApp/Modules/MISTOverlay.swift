import SwiftUI
import AutumnServices
import LEATRCore

/// MIST overlay on the BRPN scene — maze draw/solve + presence (js/mist-module.js).
public struct MISTOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @ObservedObject private var mist = MISTModule.shared
    @State private var difficulty = 1
    @State private var status = "READY"

    public var body: some View {
        OverlayPanel(title: "MIST · LEAD EDGE MAZE", onClose: { appNav.rightTab = .none }) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Solve on the BRPN orb. Signals ride plasma splines to session peers.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))

                HStack(spacing: 6) {
                    ForEach([1, 2, 3], id: \.self) { d in
                        Button(d == 1 ? "★ STAR" : d == 2 ? "♥ HEART" : "◈ MIST") {
                            difficulty = d
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .foregroundColor(difficulty == d ? Color(hex: "#00e5ff") : .white.opacity(0.45))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#00e5ff").opacity(difficulty == d ? 0.6 : 0.2), lineWidth: 1))
                    }
                }

                HStack(spacing: 8) {
                    Button("⬡ SIGMA SOLVE") {
                        sceneVM.autumnSolveMaze()
                        mist.emitSolve(uid: authVM.sessionUID, slot: difficulty)
                        sceneVM.emitMist(fromLocal: true)
                        status = "SOLVE SIGNAL SENT"
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.cyan.opacity(0.1))
                    .clipShape(Capsule())

                    Button("NEW MAZE") {
                        sceneVM.generateNewMaze()
                        status = "NEW ITERATION"
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }

                Text("PRESENCE · \(mist.activeSignals.count) LIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.7))
                if mist.activeSignals.isEmpty {
                    Text("Polling GAS / presence.json — no live peers yet.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                } else {
                    ForEach(mist.activeSignals.prefix(6)) { sig in
                        HStack {
                            Circle().fill(sig.isAsh ? Color.yellow : Color.cyan).frame(width: 6, height: 6)
                            Text(sig.isAsh ? "AUTUMN ASH" : "PEER")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Text(String(format: "%.0f%%", sig.intensity * 100))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                Text(status)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.5))
            }
            .padding(12)
        }
        .task {
            await mist.refresh()
            sceneVM.rebuildSplines()
        }
    }
}
