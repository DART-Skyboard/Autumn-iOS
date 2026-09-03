import SwiftUI
import AutumnServices
import LEATRCore

/// Left HUD: GEO / MAR / AERO pills + ADMIN tab when dartsolarpunk has enabled it.
public struct LeftHUDView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var circuit: AdminCircuitMonitor
    var axis: Axis = .vertical

    public var body: some View {
        let pills = Group {
            pill("GEO", sub: sceneVM.shellStates[.geological] ?? "FOUNDATION", color: Color(hex: "#00ffcc")) {
                appNav.leftTab = appNav.leftTab == .geo ? .none : .geo
            }
            pill("MAR", sub: sceneVM.shellStates[.maritime] ?? "REFLEX", color: Color(hex: "#0088ff")) {
                appNav.leftTab = appNav.leftTab == .mar ? .none : .mar
            }
            pill("AERO", sub: sceneVM.shellStates[.aerospace] ?? "PERFORMANCE", color: Color(hex: "#ff4466")) {
                appNav.leftTab = appNav.leftTab == .aero ? .none : .aero
            }
            Button {
                appNav.rightTab = .none
                appNav.showMantis = false
                appNav.studio = nil
                appNav.showHUDTools = false
                appNav.showRadar = true
            } label: {
                VStack(spacing: 2) {
                    Text("📡").font(.system(size: 11))
                    Text("RADAR")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundColor(Color(hex: "#00ff88"))
                .padding(.horizontal, 8).padding(.vertical, 8)
                .moduleFrost(stroke: Color(hex: "#00ff88").opacity(appNav.showRadar ? 0.7 : 0.35), fill: appNav.showRadar ? 0.14 : 0.08)
            }
            Button {
                appNav.showRadar = false
                appNav.studio = .alc
            } label: {
                VStack(spacing: 2) {
                    Text("✦").font(.system(size: 11))
                    Text("ALC")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundColor(Color(hex: "#a050ff"))
                .padding(.horizontal, 8).padding(.vertical, 8)
                .moduleFrost(stroke: Color(hex: "#a050ff").opacity(appNav.studio == .alc ? 0.7 : 0.35), fill: appNav.studio == .alc ? 0.14 : 0.08)
            }
            if circuit.allows(authVM) {
                Button {
                    appNav.showAdmin.toggle()
                } label: {
                    VStack(spacing: 2) {
                        Text("⚙").font(.system(size: 12))
                        Text("ADMIN")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(Color(hex: "#ffb347"))
                    .padding(.horizontal, 8).padding(.vertical, 8)
                    .moduleFrost(stroke: Color(hex: "#ffb347").opacity(0.4), fill: 0.10)
                }
            }
        }
        if axis == .horizontal {
            HStack(spacing: 4) { pills }
                .padding(.vertical, 2)
        } else {
            VStack(spacing: 8) {
                pills
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func pill(_ title: String, sub: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                Text(sub.prefix(4).uppercased())
                    .font(.system(size: 7, design: .monospaced))
                    .opacity(0.7)
            }
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .moduleFrost(stroke: color.opacity(0.35), fill: 0.08)
        }
    }
}

public struct GEOMarAeroHUD: View {
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var chatVM: ChatViewModel

    public var body: some View {
        HStack(spacing: 8) {
            badge("GEO", sceneVM.shellStates[.geological] ?? "FOUNDATION", Color(hex: "#00ffcc"))
            badge("MAR", sceneVM.shellStates[.maritime] ?? "REFLEX", Color(hex: "#0088ff"))
            badge("AERO", sceneVM.shellStates[.aerospace] ?? "PERFORMANCE", Color(hex: "#ff4466"))
            Spacer()
            Text(chatVM.sentienceState.rawValue)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeVM.chrome.accent)
            Text(String(format: "QS %.3f", sceneVM.quantumSocket))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeVM.chrome.textSecondary)
        }
    }

    private func badge(_ k: String, _ v: String, _ c: Color) -> some View {
        HStack(spacing: 4) {
            Text(k).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(c)
            Text(v).font(.system(size: 8, design: .monospaced)).foregroundColor(c.opacity(0.8))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(c.opacity(0.10))
        .overlay(Capsule().stroke(c.opacity(0.3), lineWidth: 1))
    }
}
