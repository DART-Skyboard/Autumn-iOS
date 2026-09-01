import SwiftUI
import AutumnServices
import LEATRCore

/// Peek tab matching js/hud-tools-module.js TOOLS rail.
struct HUDToolsTab: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    var body: some View {
        Button { appNav.showHUDTools.toggle() } label: {
            Text("TOOLS")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(Color(hex: "#00e5ff").opacity(0.75))
                .padding(.horizontal, 6).padding(.vertical, 10)
                .moduleFrost(stroke: Color(hex: "#00e5ff").opacity(0.25), corner: 6, fill: 0.05)
        }
    }
}

/// HUD tools: CALC / ARC EDGE / ARCLAKE / EMO MAP / FORGE / MANTIS / WORLD / NATE / HELP
struct HUDToolsPanel: View {
    var compact: Bool = false
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation

    var body: some View {
        let chrome = themeVM.chrome
        VStack(alignment: .leading, spacing: 6) {
            Text("TOOLS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(chrome.accent.opacity(0.45))
            tool("CALC", key: .calc)
            tool("ARC EDGE", key: .arcEdge)
            tool("ARCLAKE", key: .arcLake)
            tool("EMO MAP", key: .emoMap)
            tool("FORGE", key: .arcForge)
            tool("WORLD", key: .worldStudio)
            tool("N.A.T.E", key: .nate)
            Button { appNav.showMantis = true; appNav.showHUDTools = false } label: { row("MANTIS NAV") }
            Button { appNav.rightTab = .none; appNav.showMantis = false; appNav.studio = nil; appNav.showRadar = true; appNav.showHUDTools = false } label: { row("RADAR") }
            tool("ALC", key: .alc)
            tool("MOVEMENT", key: .movement)
            tool("HELP", key: .help)
            if !compact {
                Button { appNav.showHUDTools = false } label: { row("CLOSE") }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(chrome.accent.opacity(0.22), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tool(_ title: String, key: AppNavigation.StudioKind) -> some View {
        Button {
            appNav.studio = key
            appNav.showHUDTools = false
        } label: { row(title) }
    }

    private func row(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundColor(themeVM.chrome.accent.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(themeVM.chrome.accent.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(themeVM.chrome.accent.opacity(0.2), lineWidth: 1))
    }
}
