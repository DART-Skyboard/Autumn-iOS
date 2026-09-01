import SwiftUI
import AuthenticationServices
import AutumnServices

/// Profile: GitHub login, Enable/Disable Admin (dartsolarpunk only). Matches web gh-user-menu.
public struct ProfileSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var circuit: AdminCircuitMonitor

    public var body: some View {
        let chrome = themeVM.chrome
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { appNav.showProfile = false }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("PROFILE").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(chrome.accent)
                    Spacer()
                    Button("✕") { appNav.showProfile = false }.foregroundColor(.white.opacity(0.5))
                }.padding(14)

                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(chrome.accent.opacity(0.12)).frame(width: 52, height: 52)
                        Text(authVM.username.prefix(1).uppercased())
                            .font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundColor(chrome.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(authVM.username).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        Text(authVM.githubConnected ? "GitHub Connected" : (authVM.isGuest ? "Guest" : "Signed in"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(authVM.githubConnected ? .green : chrome.textSecondary)
                    }
                }.padding(.horizontal, 14).padding(.bottom, 12)

                row("Apple ID", authVM.appleUserId.isEmpty ? "Not signed in" : authVM.username) { authVM.signInWithApple() }
                row("GitHub", authVM.githubConnected ? authVM.githubUsername : "Tap to connect") {
                    Task { await authVM.startGitHubAuth() }
                }
                if authVM.deviceFlowCode != nil {
                    Text("Device code: \(authVM.deviceFlowCode!.userCode)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(chrome.accent)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                    Text("Enter this code at github.com/login/device (opened in-app).")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 14)
                }
                if let err = authVM.error {
                    Text(err).font(.system(size: 10)).foregroundColor(.red).padding(.horizontal, 14)
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
                    if circuit.allows(authVM) {
                        Button { appNav.showAdmin = true; appNav.showProfile = false } label: {
                            labelRow("⚙ OPEN ADMIN")
                        }
                    } else if authVM.adminEnabled {
                        Text("Admin waits for web circuit (leatr.xyz live)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.horizontal, 14).padding(.bottom, 6)
                    }
                }

                Button { authVM.signOut(); appNav.showProfile = false } label: {
                    Text("Sign Out").font(.system(size: 13)).foregroundColor(.red)
                        .frame(maxWidth: .infinity).padding(14)
                }
            }
            .frame(width: 300)
            .background(Color(hex: "#040c16").opacity(0.97))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(chrome.accent.opacity(0.25), lineWidth: 1))
            .cornerRadius(10)
            .padding(.top, 56)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
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
