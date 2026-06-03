
import SwiftUI
import AuthenticationServices
import LEATRCore

public struct WelcomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var showGitHubSheet = false
    @State private var pulseAnim = false

    public var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Animated orb ─────────────────────────────────────
                ZStack {
                    Circle()
                        .stroke(themeVM.current.accent.opacity(0.10), lineWidth: 1)
                        .frame(
                            width: pulseAnim ? 195 : 160,
                            height: pulseAnim ? 195 : 160)
                        .animation(
                            .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                            value: pulseAnim)
                    Circle()
                        .fill(themeVM.current.accent.opacity(0.06))
                        .frame(width: 140, height: 140)
                    Circle()
                        .stroke(themeVM.current.accent.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 140, height: 140)
                    Text(LEATRIdentity.displayName.prefix(1))
                        .font(.custom("Orbitron-Bold", size: 52))
                        .foregroundColor(themeVM.current.accent)
                }
                .onAppear { pulseAnim = true }

                Spacer().frame(height: 30)

                VStack(spacing: 5) {
                    Text(LEATRIdentity.displayName.uppercased())
                        .font(.custom("Orbitron-Bold", size: 26))
                        .foregroundColor(.white)
                        .tracking(6)
                    Text("LEATR · BRPN · Radical Deepscale")
                        .font(.custom("Exo2-Regular", size: 12))
                        .foregroundColor(themeVM.current.textSecondary)
                        .tracking(2)
                }

                Spacer()

                // ── 3 auth buttons ────────────────────────────────────
                VStack(spacing: 12) {

                    // ① Sign in with Apple
                    SignInWithAppleButton(.signIn) { req in
                        req.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in
                        authVM.signInWithApple()
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .cornerRadius(12)

                    // ② Connect GitHub (device flow)
                    Button { showGitHubSheet = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 17))
                            Text(authVM.githubConnected
                                 ? "GitHub Connected ✓"
                                 : "Connect GitHub")
                                .font(.custom("Exo2-SemiBold", size: 15))
                        }
                        .foregroundColor(authVM.githubConnected
                                         ? .green
                                         : themeVM.current.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    authVM.githubConnected
                                        ? Color.green.opacity(0.4)
                                        : themeVM.current.accent.opacity(0.35),
                                    lineWidth: 1.2))
                    }

                    // ③ Continue as Guest
                    Button { authVM.continueAsGuest() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.5))
                            Text("Continue as Guest")
                                .font(.custom("Exo2-Regular", size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }

                    // Error display
                    if let err = authVM.error {
                        Text(err)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 48)
            }
        }
        .sheet(isPresented: $showGitHubSheet) {
            GitHubDeviceFlowSheet()
        }
    }
}

// MARK: — GitHub Device Flow Sheet
struct GitHubDeviceFlowSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()
            VStack(spacing: 24) {

                Text("Connect GitHub")
                    .font(.custom("Orbitron-Bold", size: 20))
                    .foregroundColor(themeVM.current.accent)
                    .padding(.top, 32)

                if let flow = authVM.deviceFlowCode {
                    // Show code + spinner
                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            Text("Visit this address:")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(themeVM.current.textSecondary)
                            Text(flow.verificationUrl)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(themeVM.current.accent)
                                .multilineTextAlignment(.center)
                        }

                        // Code — large and copyable
                        Button {
                            UIPasteboard.general.string = flow.userCode
                        } label: {
                            VStack(spacing: 6) {
                                Text(flow.userCode)
                                    .font(.custom("Orbitron-Bold", size: 30))
                                    .foregroundColor(.white)
                                    .tracking(8)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(12)
                                Label("Tap to copy", systemImage: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(themeVM.current.textSecondary)
                            }
                        }

                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(themeVM.current.accent)
                                .scaleEffect(0.9)
                            Text("Waiting for authorization…")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(themeVM.current.textSecondary)
                        }
                    }
                    .padding(.horizontal, 24)

                } else {
                    // Start button
                    VStack(spacing: 16) {
                        Text("Authorize Autumn to read/write your GitHub repositories.")
                            .font(.custom("Exo2-Regular", size: 13))
                            .foregroundColor(themeVM.current.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        Button {
                            Task { await authVM.startGitHubAuth() }
                        } label: {
                            Text("Start GitHub Authorization")
                                .font(.custom("Exo2-SemiBold", size: 15))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(themeVM.current.accent)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 28)
                    }
                }

                if let err = authVM.error {
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .foregroundColor(themeVM.current.textSecondary)
                    .padding(.bottom, 32)
            }
        }
        .onChange(of: authVM.githubConnected) { connected in
            if connected { dismiss() }
        }
    }
}
