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

                // TF107: the username section (and everything else) added since
                // this was written pushed total content height well past the
                // screen, with no scroll anywhere — Admin toggle and everything
                // below it was simply unreachable. Everything below the header
                // now scrolls, capped to a sane fraction of screen height so the
                // card never tries to exceed the actual display.
                ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    GitHubAvatarView(
                        url: authVM.githubAvatarURL,
                        letter: authVM.username,
                        size: 52,
                        accent: chrome.accent
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(authVM.effectiveDisplayName).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        Text(authVM.githubConnected ? "GitHub Connected" : (authVM.isGuest ? "Guest" : "Signed in"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(authVM.githubConnected ? .green : chrome.textSecondary)
                    }
                }.padding(.horizontal, 14).padding(.bottom, 12)

                // TF105: custom profile username — independent of GitHub/Apple, the
                // one identity slot that's actually unique for Apple-only users.
                // Claiming here is what shows up for Apple ID/GitHub rows below and
                // in Admin Console's user list (ashtree/users/<name>/).
                usernameSection(chrome: chrome)

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
                        Text(authVM.appleUserId.isEmpty ? "Not signed in" : authVM.effectiveDisplayName)
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

                row("GitHub", authVM.githubConnected ? authVM.effectiveDisplayName : "Tap to connect") {
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
                    // TF111: dropped the redundant "OPEN ADMIN DRAWER" button — the left
                    // HUD ADMIN tab (visible whenever adminEnabled is true) already opens
                    // it, and having a second entry point here just added clutter.
                    if authVM.adminEnabled {
                        Text("Left HUD ADMIN tab opens the console")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color(hex: "#00ff88").opacity(0.75))
                            .padding(.horizontal, 14).padding(.bottom, 6)
                    } else {
                        Text("Enable Admin (dartsolarpunk) → OPEN ADMIN / left HUD")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                            .padding(.horizontal, 14).padding(.bottom, 6)
                    }
                }

                Button { showSignOutChoices = true } label: {
                    Text("Sign Out").font(.system(size: 13)).foregroundColor(.red)
                        .frame(maxWidth: .infinity).padding(14)
                }
                } // end inner VStack
                }
                .frame(maxHeight: min(560, UIScreen.main.bounds.height * 0.68))
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

    @State private var usernameDraft: String = ""
    @State private var showUsernameEditor: Bool = false

    private func usernameSection(chrome: AutumnTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("USERNAME").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundColor(chrome.accent.opacity(0.55))
                Spacer()
                if !authVM.customUsername.isEmpty && !showUsernameEditor {
                    Button("Change") { usernameDraft = authVM.customUsername; showUsernameEditor = true }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(chrome.accent)
                }
            }
            .padding(.horizontal, 14)

            if authVM.customUsername.isEmpty && !showUsernameEditor {
                Button {
                    usernameDraft = ""
                    showUsernameEditor = true
                    authVM.usernameClaimState = .idle
                } label: {
                    HStack {
                        Text("◇ Set a username").font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Spacer()
                    }
                    .foregroundColor(chrome.accent)
                }
                .padding(.horizontal, 14).padding(.bottom, 8)
            } else if !showUsernameEditor {
                HStack {
                    Text(authVM.customUsername)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Turn off") { authVM.clearCustomUsername() }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 14).padding(.bottom, 8)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("letters, numbers, _", text: $usernameDraft)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .onChange(of: usernameDraft) { _ in authVM.usernameClaimState = .idle }
                        Button {
                            Task { await authVM.claimUsername(usernameDraft) }
                        } label: {
                            if authVM.usernameClaimState == .checking {
                                ProgressView().tint(chrome.accent)
                            } else {
                                Text("Save")
                            }
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(chrome.accent)
                        .disabled(usernameDraft.trimmingCharacters(in: .whitespaces).isEmpty || authVM.usernameClaimState == .checking)
                        Button("Cancel") { showUsernameEditor = false }
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    usernameStatusText(chrome: chrome)
                }
                .padding(.horizontal, 14).padding(.bottom, 8)
            }
        }
        .onChange(of: authVM.usernameClaimState) { state in
            if state == .claimed { showUsernameEditor = false }
        }
    }

    @ViewBuilder
    private func usernameStatusText(chrome: AutumnTheme) -> some View {
        switch authVM.usernameClaimState {
        case .idle, .checking:
            EmptyView()
        case .available:
            Text("Available").font(.system(size: 10, design: .monospaced)).foregroundColor(.green)
        case .taken:
            Text("Already taken — try another").font(.system(size: 10, design: .monospaced)).foregroundColor(.orange)
        case .claimed:
            Text("Saved").font(.system(size: 10, design: .monospaced)).foregroundColor(.green)
        case .invalid(let msg):
            Text(msg).font(.system(size: 10, design: .monospaced)).foregroundColor(.orange)
        case .error(let msg):
            Text(msg).font(.system(size: 10, design: .monospaced)).foregroundColor(.red)
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
