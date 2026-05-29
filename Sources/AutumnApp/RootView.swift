import SwiftUI

public struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel

    public var body: some View {
        Group {
            if authVM.isSignedIn {
                MainTabView()
            } else {
                WelcomeView()
            }
        }
        .onAppear { authVM.restoreAppleSession() }
    }
}

// MARK: — Main Tab View
public struct MainTabView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var selected = 0

    public var body: some View {
        ZStack(alignment: .bottom) {
            themeVM.current.gradient.ignoresSafeArea()

            TabView(selection: $selected) {
                ChatView().tag(0)
                BRPNSceneView().tag(1)
                ToolsView().tag(2)
                JournalView().tag(3)
                SettingsView().tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom tab bar
            AutumnTabBar(selected: $selected)
        }
    }
}

// MARK: — Custom Tab Bar
struct AutumnTabBar: View {
    @Binding var selected: Int
    @EnvironmentObject var themeVM: ThemeViewModel

    private let tabs: [(icon: String, label: String)] = [
        ("bubble.left.and.bubble.right", "Chat"),
        ("circle.grid.3x3.fill", "BRPN"),
        ("wrench.and.screwdriver", "Tools"),
        ("book.closed", "Journal"),
        ("gearshape", "Settings")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3)) { selected = i }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[i].icon)
                            .font(.system(size: selected == i ? 22 : 18))
                            .foregroundColor(selected == i ? themeVM.current.accent : themeVM.current.textSecondary)
                        Text(tabs[i].label)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(selected == i ? themeVM.current.accent : themeVM.current.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(.ultraThinMaterial)
        .background(themeVM.current.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(themeVM.current.accent.opacity(0.3)),
            alignment: .top
        )
    }
}
