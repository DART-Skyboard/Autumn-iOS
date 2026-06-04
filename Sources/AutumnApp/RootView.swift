import SwiftUI
import AutumnServices
import AuthenticationServices
import LEATRCore

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
        .onAppear { authVM.restoreSession() }
    }
}

// MARK: — Main Tab View
public struct MainTabView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selected = 0
    @State private var showUserProfile = false

    // Per-tab header leading content (title / badges)
    private var tabTitle: String {
        switch selected {
        case 0: return "CHAT"
        case 1: return "BRPN"
        case 2: return "TOOLS"
        case 3: return "JOURNAL"
        case 4: return "SETTINGS"
        default: return ""
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Persistent top header ─────────────────────────────
            AutumnHeader(
                selected: selected,
                showUserProfile: $showUserProfile
            )

            // ── Tab content ───────────────────────────────────────
            ZStack {
                themeVM.current.gradient.ignoresSafeArea()
                TabView(selection: $selected) {
                    ChatView().tag(0)
                    BRPNSceneView().tag(1)
                    ToolsView().tag(2)
                    JournalView().tag(3)
                    SettingsView().tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            // ── Custom tab bar ────────────────────────────────────
            AutumnTabBar(selected: $selected)
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showUserProfile) { UserProfileSheet() }
    }
}

// MARK: — Persistent Top Header
struct AutumnHeader: View {
    let selected: Int
    @Binding var showUserProfile: Bool
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var sceneVM: BRPNSceneViewModel

    var body: some View {
        ZStack {
            // Background
            themeVM.current.surface
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(themeVM.current.accent.opacity(0.25)),
                    alignment: .bottom
                )

            HStack(spacing: 8) {
                // ── Left: per-tab content ─────────────────────────
                Group {
                    switch selected {
                    case 1: // BRPN — shell badges
                        BRPNHeaderBadges()
                    default:
                        Text(tabTitle(for: selected))
                            .font(.custom("Orbitron-Bold", size: 13))
                            .foregroundColor(themeVM.current.accent)
                            .tracking(3)
                    }
                }

                Spacer()

                // ── Right: avatar button ──────────────────────────
                Button { showUserProfile = true } label: {
                    ZStack {
                        Circle()
                            .fill(themeVM.current.accent.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(themeVM.current.accent.opacity(0.35), lineWidth: 1)
                            .frame(width: 36, height: 36)
                        if let avatarURL = authVM.githubAvatarURL {
                            AsyncImage(url: avatarURL) { img in
                                img.resizable().scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                            } placeholder: {
                                Text(authVM.username.prefix(1).uppercased())
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(themeVM.current.accent)
                            }
                        } else {
                            Text(authVM.username.prefix(1).uppercased())
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(themeVM.current.accent)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 56)
    }

    private func tabTitle(for index: Int) -> String {
        switch index {
        case 0: return "CHAT"
        case 2: return "TOOLS"
        case 3: return "JOURNAL"
        case 4: return "SETTINGS"
        default: return ""
        }
    }
}

// MARK: — BRPN header badges (shell pills + node count)
struct BRPNHeaderBadges: View {
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var themeVM: ThemeViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(BRPNShell.allCases, id: \.rawValue) { shell in
                VStack(spacing: 1) {
                    Text(shell.displayName.uppercased())
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(themeVM.current.textSecondary)
                    Text(shell.role)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(themeVM.current.accent)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(themeVM.current.accent.opacity(0.08))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(themeVM.current.accent.opacity(0.2), lineWidth: 1))
            }
            HStack(spacing: 4) {
                Image(systemName: "circle.grid.3x3")
                    .font(.system(size: 9))
                    .foregroundColor(themeVM.current.textSecondary)
                Text("\(sceneVM.activeNodes) nodes")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.current.textSecondary)
            }
            .padding(.leading, 4)
        }
    }
}

// MARK: — User Profile Sheet
struct UserProfileSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showAppleAccountPicker = false
    @State private var showGitHubAccountPicker = false
    @State private var showSupport = false

    var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Capsule().fill(Color.white.opacity(0.2))
                        .frame(width: 40, height: 4).padding(.top, 12).padding(.bottom, 20)

                    // Avatar
                    ZStack {
                        Circle().fill(themeVM.current.accent.opacity(0.12)).frame(width: 80, height: 80)
                        Circle().stroke(themeVM.current.accent.opacity(0.4), lineWidth: 1.5).frame(width: 80, height: 80)
                        Text(authVM.username.prefix(1).uppercased())
                            .font(.custom("Orbitron-Bold", size: 32)).foregroundColor(themeVM.current.accent)
                    }
                    Spacer().frame(height: 16)
                    Text(authVM.username)
                        .font(.custom("Orbitron-Bold", size: 18)).foregroundColor(.white)
                    Text(authVM.githubConnected ? "GitHub Connected" : "GitHub Not Connected")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(authVM.githubConnected ? .green : themeVM.current.textSecondary)
                        .padding(.top, 4)
                    Spacer().frame(height: 24)

                    // ── Status rows ──────────────────────────────────
                    VStack(spacing: 0) {
                        // Apple ID row — tap to switch if multiple saved
                        accountRow(
                            label: "Apple ID",
                            value: authVM.appleUserId.isEmpty ? "—" : authVM.username,
                            status: authVM.appleUserId.isEmpty ? "Not signed in" : "Connected ✓",
                            statusColor: authVM.appleUserId.isEmpty ? themeVM.current.textSecondary : .green,
                            canSwitch: authVM.savedAppleAccounts.count > 1
                        ) { showAppleAccountPicker = true }

                        Divider().background(Color.white.opacity(0.08))

                        // GitHub row — tap to switch or connect
                        accountRow(
                            label: "GitHub",
                            value: authVM.githubConnected ? authVM.githubUsername : "Not connected",
                            status: authVM.githubConnected ? "Connected ✓" : "Tap to connect",
                            statusColor: authVM.githubConnected ? themeVM.current.accent : themeVM.current.textSecondary,
                            canSwitch: true
                        ) { showGitHubAccountPicker = true }

                        Divider().background(Color.white.opacity(0.08))
                        profileRow("Vault", value: "Autumn-Ash ✓", color: themeVM.current.accent)
                        Divider().background(Color.white.opacity(0.08))
                        profileRow("LEATR", value: "v2 · Active", color: themeVM.current.accent)
                        Divider().background(Color.white.opacity(0.08))
                        profileRow("Build", value: "1.0.0 (43)", color: themeVM.current.textSecondary)
                    }
                    .background(themeVM.current.surface).cornerRadius(12).padding(.horizontal, 20)

                    Spacer().frame(height: 24)

                    // Sign out
                    Button {
                        authVM.signOut(); dismiss()
                    } label: {
                        Text("Sign Out").font(.custom("Exo2-SemiBold", size: 15)).foregroundColor(.red)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color.red.opacity(0.1)).cornerRadius(10)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showSupport) {
            SupportSheet(accentColor: themeVM.current.accent, appName: "Autumn")
        }
        // Apple account picker
        .confirmationDialog("Switch Apple Account", isPresented: $showAppleAccountPicker) {
            ForEach(authVM.savedAppleAccounts) { acct in
                Button(acct.displayName) {
                    authVM.switchAppleAccount(to: acct)
                }
            }
            Button("Add New Apple ID") { authVM.signInWithApple() }
            Button("Cancel", role: .cancel) {}
        }
        // GitHub account picker
        .confirmationDialog("Switch GitHub Account", isPresented: $showGitHubAccountPicker) {
            ForEach(authVM.savedGitHubAccounts) { acct in
                Button(acct.displayName) {
                    authVM.switchGitHubAccount(to: acct)
                    dismiss()
                }
            }
            Button("Connect New GitHub Account") {
                Task { await authVM.startGitHubAuth() }
                dismiss()
            }
            if authVM.githubConnected {
                Button("Disconnect GitHub", role: .destructive) {
                    authVM.disconnectGitHub()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func accountRow(
        label: String, value: String, status: String,
        statusColor: Color, canSwitch: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13, design: .monospaced))
                        .foregroundColor(themeVM.current.textSecondary)
                    Text(value).font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                HStack(spacing: 6) {
                    Text(status).font(.system(size: 13, design: .monospaced))
                        .foregroundColor(statusColor)
                    if canSwitch {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(themeVM.current.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private func profileRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 13, design: .monospaced))
                .foregroundColor(themeVM.current.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, design: .monospaced)).foregroundColor(color)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: — Custom Tab Bar
struct AutumnTabBar: View {
    @Binding var selected: Int
    @EnvironmentObject var themeVM: ThemeViewModel

    private let tabs: [(icon: String, label: String)] = [
        ("bubble.left.and.bubble.right", "Chat"),
        ("circle.grid.3x3.fill",         "BRPN"),
        ("wrench.and.screwdriver",        "Tools"),
        ("book.closed",                   "Journal"),
        ("gearshape",                     "Settings")
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
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
            }
        }
        .background(.ultraThinMaterial)
        .background(themeVM.current.surface)
        .overlay(Rectangle().frame(height: 1)
            .foregroundColor(themeVM.current.accent.opacity(0.3)), alignment: .top)
        .padding(.bottom, 0)
    }
}
