import SwiftUI
import AutumnServices

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
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selected = 0
    @State private var showUserProfile = false

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

            // User profile button — top right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showUserProfile = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(themeVM.current.accent.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Text(authVM.username.prefix(1).uppercased())
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(themeVM.current.accent)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }

            // Custom tab bar
            AutumnTabBar(selected: $selected)

            // Privacy policy — shown once on first launch
            if !authVM.hasAcceptedPolicy {
                AutumnPolicyOverlay(onAccept: { authVM.acceptPolicy() },
                                    onDecline: { authVM.signOut() })
                    .zIndex(100)
            }
        }
        .sheet(isPresented: $showUserProfile) {
            UserProfileSheet()
        }
    }
}

// MARK: — User Profile Sheet
struct UserProfileSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()
            VStack(spacing: 0) {
                // Handle bar
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                // Avatar
                ZStack {
                    Circle()
                        .fill(themeVM.current.accent.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Circle()
                        .stroke(themeVM.current.accent.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 80, height: 80)
                    Text(authVM.username.prefix(1).uppercased())
                        .font(.custom("Orbitron-Bold", size: 32))
                        .foregroundColor(themeVM.current.accent)
                }

                Spacer().frame(height: 16)

                Text(authVM.username)
                    .font(.custom("Orbitron-Bold", size: 18))
                    .foregroundColor(.white)
                Text(authVM.githubConnected ? "GitHub Connected" : "GitHub Not Connected")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(authVM.githubConnected ? .green : themeVM.current.textSecondary)
                    .padding(.top, 4)

                Spacer().frame(height: 32)

                // Info rows
                VStack(spacing: 0) {
                    profileRow("Apple ID", value: authVM.isSignedIn ? "Connected ✓" : "—", color: .green)
                    Divider().background(Color.white.opacity(0.08))
                    profileRow("GitHub", value: authVM.githubConnected ? authVM.githubUsername : "Not connected",
                               color: authVM.githubConnected ? themeVM.current.accent : themeVM.current.textSecondary)
                    Divider().background(Color.white.opacity(0.08))
                    profileRow("LEATR", value: "v2 · Active", color: themeVM.current.accent)
                    Divider().background(Color.white.opacity(0.08))
                    profileRow("Build", value: "1.0.0 (31)", color: themeVM.current.textSecondary)
                }
                .background(themeVM.current.surface)
                .cornerRadius(12)
                .padding(.horizontal, 20)

                Spacer()

                // Sign out
                Button {
                    authVM.signOut()
                    dismiss()
                } label: {
                    Text("Sign Out")
                        .font(.custom("Exo2-SemiBold", size: 15))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func profileRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(themeVM.current.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
