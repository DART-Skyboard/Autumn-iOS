import SwiftUI
import UIKit
import AutumnServices

/// Profile: GitHub login, Enable/Disable Admin (dartsolarpunk only). Matches web gh-user-menu.
/// Frosted card only — NO full-screen dim. Tap outside the card still dismisses.
public struct ProfileSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var circuit: AdminCircuitMonitor
    @EnvironmentObject var chatVM: ChatViewModel
    @StateObject private var tint = AvatarTintSampler()
    @State private var saveBusy = false
    @State private var saveBanner: SaveBanner?
    @State private var showGitHubSheet = false
    @State private var showSignOutChoices = false
    @AppStorage("autumn_welcome_done_v1") private var welcomeDone = false

    private struct SaveBanner: Equatable {
        let text: String
        let ok: Bool
    }

    public var body: some View {
        let chrome = themeVM.chrome
        ZStack(alignment: .topTrailing) {
            // Transparent hit target only — never a black dim wash.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { appNav.showProfile = false }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("PROFILE").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(chrome.accent)
                    Spacer()
                    Button("✕") { appNav.showProfile = false }.foregroundColor(.white.opacity(0.5))
                }.padding(14)

                HStack(spacing: 12) {
                    GitHubAvatarView(
                        url: authVM.githubAvatarURL,
                        letter: authVM.username,
                        size: 52,
                        accent: chrome.accent
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(authVM.username).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        Text(authVM.githubConnected ? "GitHub Connected" : (authVM.isGuest ? "Guest" : "Signed in"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(authVM.githubConnected ? .green : chrome.textSecondary)
                    }
                }.padding(.horizontal, 14).padding(.bottom, 12)

                if !authVM.savedGitHubAccounts.isEmpty {
                    Text("ACCOUNTS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(chrome.accent.opacity(0.55))
                        .padding(.horizontal, 14).padding(.bottom, 4)
                    ForEach(authVM.savedGitHubAccounts) { acct in
                        Button { authVM.switchGitHubAccount(to: acct) } label: {
                            HStack(spacing: 10) {
                                GitHubAvatarView(
                                    url: acct.avatarURL.flatMap { URL(string: $0) },
                                    letter: acct.displayName,
                                    size: 28,
                                    accent: chrome.accent
                                )
                                Text(acct.displayName)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                if acct.id == authVM.githubUsername {
                                    Text("LIVE")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color(hex: "#00ff88"))
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                        }
                    }
                }

                // Apple ID — open root fullScreenCover (Welcome/Ashtree pattern). Nested
                // AppleSignInButton inside Profile overlay still fails with .unknown.
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Apple ID").font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                        Spacer()
                        Text(authVM.appleUserId.isEmpty ? "Not signed in" : authVM.username)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 14).padding(.top, 10)
                    if authVM.appleUserId.isEmpty {
                        Button {
                            authVM.error = nil
                            appNav.showProfile = false
                            appNav.showAppleSignIn = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Sign in with Apple")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                        .accessibilityLabel("Sign in with Apple")
                    }
                }

                row("GitHub", authVM.githubConnected ? authVM.githubUsername : "Tap to connect") {
                    showGitHubSheet = true
                }
                if let err = authVM.error {
                    Text(err).font(.system(size: 10)).foregroundColor(.red).padding(.horizontal, 14)
                }

                Button {
                    Task { await runSaveData() }
                } label: {
                    labelRow(saveBusy
                             ? "⬡ SAVING…"
                             : (authVM.githubConnected ? "⬡ SAVE DATA" : "⬡ SAVE DATA (CONNECT GITHUB)"))
                }
                .disabled(saveBusy)
                .opacity(saveBusy ? 0.55 : 1)

                if let banner = saveBanner {
                    Text(banner.text)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(banner.ok ? Color(hex: "#00ff88") : Color(hex: "#ff6688"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background((banner.ok ? Color.green : Color.red).opacity(0.12))
                        .accessibilityLabel(banner.ok ? "Save success" : "Save error")
                }

                Button { appNav.showFeedback = true; appNav.showProfile = false } label: {
                    labelRow("◇ SUBMIT FEEDBACK")
                }
                Button { appNav.studio = .help; appNav.showProfile = false } label: {
                    labelRow("? HELP")
                }
                Button { appNav.studio = .privacy; appNav.showProfile = false } label: {
                    labelRow("PRIVACY")
                }
                Button { appNav.studio = .worldStudio; appNav.showProfile = false } label: {
                    labelRow("WORLD STUDIO")
                }
                Button { appNav.studio = .arcForge; appNav.showProfile = false } label: {
                    labelRow("ARC FORGE")
                }

                if authVM.adminAllowed {
                    Button { authVM.toggleAdminFlag() } label: {
                        labelRow(authVM.adminEnabled ? "⚙ DISABLE ADMIN" : "⚙ ENABLE ADMIN")
                    }
                    if authVM.adminEnabled {
                        Button { appNav.showAdmin = true; appNav.showProfile = false } label: {
                            labelRow("⚙ OPEN ADMIN DRAWER")
                        }
                        Text("Admin is live from this iOS sign-in. TOOLS → Administration Console, or left HUD ADMIN.")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color(hex: "#00ff88").opacity(0.75))
                            .padding(.horizontal, 14).padding(.bottom, 6)
                    } else {
                        Text("Enable Admin to open DATA / ASH / MESSAGES, roles, and users.")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.horizontal, 14).padding(.bottom, 6)
                    }
                }

                Button { showSignOutChoices = true } label: {
                    Text("Sign Out").font(.system(size: 13)).foregroundColor(.red)
                        .frame(maxWidth: .infinity).padding(14)
                }
            }
            .frame(width: min(320, UIScreen.main.bounds.width - 32))
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 14).fill(tint.tint.opacity(0.82))
                    RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.28))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(chrome.accent.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .padding(.top, 56)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .onAppear { tint.sample(url: authVM.githubAvatarURL) }
        .onChange(of: authVM.githubAvatarURL) { u in tint.sample(url: u) }
        // Do not cancelGitHubAuth on dismiss — Cancel/✕ owns cancel. Keep polling so
        // closing/reopening the sheet (or Safari) does not burn the user_code.
        .sheet(isPresented: $showGitHubSheet) {
            GitHubDeviceFlowSheet()
                .environmentObject(authVM)
                .environmentObject(themeVM)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(false)
        }
        .confirmationDialog("Sign Out", isPresented: $showSignOutChoices, titleVisibility: .visible) {
            Button("Sign Out") {
                authVM.signOut()
                appNav.showProfile = false
                appNav.showAdmin = false
                appNav.showAppleSignIn = false
            }
            Button("Sign Out & return to Welcome") {
                authVM.signOut()
                appNav.showProfile = false
                appNav.showAdmin = false
                appNav.showAppleSignIn = false
                appNav.showFeedback = false
                welcomeDone = false
                appNav.showWelcome = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sign Out stays in the app as Guest. Sign Out & Welcome returns to the fresh Apple / GitHub / Guest screen.")
        }
    }

    private func runSaveData() async {
        guard !saveBusy else { return }
        saveBusy = true
        saveBanner = SaveBanner(text: "Saving… vault + Autumn backup + optimize", ok: true)
        let result = await AutumnMemorySync.saveAllNow(
            username: authVM.githubUsername,
            sessionUID: authVM.sessionUID,
            messages: chatVM.messages,
            mathJSON: ChatViewModel.mathSnapshotJSON()
        )
        switch result {
        case .success(let msg):
            saveBanner = SaveBanner(text: msg, ok: true)
        case .failure(let err):
            saveBanner = SaveBanner(text: err.localizedDescription, ok: false)
        }
        saveBusy = false
    }

    private func row(_ k: String, _ v: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(k).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                Spacer()
                Text(v).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.85))
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private func labelRow(_ t: String) -> some View {
        Text(t).font(.system(size: 11, design: .monospaced)).tracking(1)
            .foregroundColor(themeVM.chrome.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// Shared GitHub avatar. Letter fallback only when unsigned or the image fetch failed.
struct GitHubAvatarView: View {
    let url: URL?
    let letter: String
    var size: CGFloat = 34
    let accent: Color

    var body: some View {
        ZStack {
            Circle().fill(accent.opacity(0.15)).frame(width: size, height: size)
            Circle().stroke(accent.opacity(0.4), lineWidth: 1).frame(width: size, height: size)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    default:
                        letterGlyph
                    }
                }
            } else {
                letterGlyph
            }
        }
        .frame(width: size, height: size)
    }

    private var letterGlyph: some View {
        Text(letter.prefix(1).uppercased())
            .font(.system(size: max(11, size * 0.38), weight: .bold, design: .monospaced))
            .foregroundColor(accent)
    }
}
