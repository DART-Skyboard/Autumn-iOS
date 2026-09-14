import SwiftUI
import AutumnServices
import LEATRCore

/// Arc Lake–style first-run Welcome (after Privacy Policy).
/// Primary SIWA surface — AppleSignInButton at root, not nested under Profile.
public struct WelcomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @AppStorage("autumn_welcome_done_v1") private var welcomeDone = false
    @State private var showGitHubSheet = false
    @State private var pulseAnim = false
    @State private var revealControls = false

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.04, blue: 0.07),
                    Color(red: 0.04, green: 0.06, blue: 0.09)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Pulse orb (ArcWelcomeView aesthetic, Autumn branding) ──
                ZStack {
                    Circle()
                        .stroke(themeVM.current.accent.opacity(0.10), lineWidth: 1)
                        .frame(
                            width: pulseAnim ? 200 : 162,
                            height: pulseAnim ? 200 : 162
                        )
                        .animation(
                            .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                            value: pulseAnim
                        )
                    Circle()
                        .stroke(themeVM.current.accent.opacity(0.18), lineWidth: 1)
                        .frame(
                            width: pulseAnim ? 170 : 148,
                            height: pulseAnim ? 170 : 148
                        )
                        .animation(
                            .easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(0.15),
                            value: pulseAnim
                        )
                    Circle()
                        .fill(themeVM.current.accent.opacity(0.06))
                        .frame(width: 140, height: 140)
                    Circle()
                        .stroke(themeVM.current.accent.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 140, height: 140)
                    AutumnLogoMark(size: 72)
                        .frame(width: 120, height: 120)
                }
                .onAppear { pulseAnim = true }

                Spacer().frame(height: 28)

                VStack(spacing: 6) {
                    Text("AUTUMN")
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .tracking(6)
                    Text("LEATR · BRPN · Radical Deepscale")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(themeVM.current.textSecondary)
                        .tracking(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                if revealControls {
                    authStack
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Text("LOADING")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(themeVM.current.accent.opacity(0.55))
                        .padding(.bottom, 48)
                }
            }
        }
        .onAppear {
            // Brief vector/pulse beat before revealing auth actions (Arc intro feel).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                withAnimation(.easeOut(duration: 0.45)) { revealControls = true }
            }
        }
        .sheet(isPresented: $showGitHubSheet) {
            GitHubDeviceFlowSheet()
                .environmentObject(authVM)
                .environmentObject(themeVM)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(false)
        }
        .onChange(of: authVM.githubConnected) { connected in
            if connected { enterApp() }
        }
    }

    private var authStack: some View {
        VStack(spacing: 12) {
            // ① Sign in with Apple — primary SIWA surface (Ashtree / Arc pattern)
            AppleSignInButton(
                onRequest: { authVM.prepareAppleRequest($0) },
                onCompletion: { result in
                    authVM.handleAppleCompletion(result)
                    if case .success = result {
                        enterApp()
                    }
                }
            )
            .frame(height: 52)
            .cornerRadius(12)

            // ② Connect GitHub
            Button { showGitHubSheet = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 17))
                    Text(authVM.githubConnected ? "GitHub Connected ✓" : "Connect GitHub")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(authVM.githubConnected ? .green : themeVM.current.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            authVM.githubConnected
                                ? Color.green.opacity(0.4)
                                : themeVM.current.accent.opacity(0.35),
                            lineWidth: 1.2
                        )
                )
            }

            // ③ Continue as Guest / Next into app
            Button {
                authVM.continueAsGuest()
                enterApp()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Continue as Guest")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }

            if let err = authVM.error {
                Text(err)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .accessibilityLabel("Sign in error")
                if authVM.appleErrorOffersSettings {
                    Button("Open Settings → Apple ID") {
                        authVM.openAppleIDSettings()
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: "#7ecfff"))
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 48)
    }

    private func enterApp() {
        welcomeDone = true
        appNav.showWelcome = false
        appNav.showAppleSignIn = false
    }
}
