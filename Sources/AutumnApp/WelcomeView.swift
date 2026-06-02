
import SwiftUI
import AuthenticationServices
import LEATRCore

public struct WelcomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var showGitHubSheet = false
    @State private var patInput = ""
    @State private var patMode = false
    @State private var pulseAnim = false

    public var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Orb ──────────────────────────────────────────────
                ZStack {
                    // Outer pulse ring
                    Circle()
                        .stroke(themeVM.current.accent.opacity(0.15), lineWidth: 1)
                        .frame(width: pulseAnim ? 180 : 160, height: pulseAnim ? 180 : 160)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true),
                                   value: pulseAnim)
                    Circle()
                        .fill(themeVM.current.accent.opacity(0.08))
                        .frame(width: 140, height: 140)
                    Circle()
                        .stroke(themeVM.current.accent.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 140, height: 140)
                    Text(LEATRIdentity.displayName.prefix(1))
                        .font(.custom("Orbitron-Bold", size: 52))
                        .foregroundColor(themeVM.current.accent)
                }
                .onAppear { pulseAnim = true }

                Spacer().frame(height: 32)

                VStack(spacing: 6) {
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

                // ── Auth buttons ──────────────────────────────────────
                VStack(spacing: 14) {
                    // Sign in with Apple
                    SignInWithAppleButton(.signIn) { req in
                        req.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in
                        authVM.signInWithApple()
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .cornerRadius(10)

                    // GitHub device flow
                    Button {
                        showGitHubSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 18))
                            Text(authVM.githubConnected ? "GitHub Connected ✓" : "Connect GitHub")
                                .font(.custom("Exo2-SemiBold", size: 15))
                        }
                        .foregroundColor(authVM.githubConnected ? .green : themeVM.current.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(authVM.githubConnected ?
                                    Color.green.opacity(0.4) :
                                    themeVM.current.accent.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // PAT toggle
                    Button {
                        withAnimation { patMode.toggle() }
                    } label: {
                        Text("Use GitHub PAT instead")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(themeVM.current.textSecondary)
                    }

                    if patMode {
                        VStack(spacing: 8) {
                            SecureField("ghp_...", text: $patInput)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.07))
                                .cornerRadius(8)

                            Button {
                                authVM.signInWithPAT(pat: patInput)
                            } label: {
                                Text("Sign In with PAT")
                                    .font(.custom("Exo2-SemiBold", size: 14))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(themeVM.current.accent)
                                    .cornerRadius(8)
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if let err = authVM.error {
                        Text(err)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)

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
                    VStack(spacing: 16) {
                        Text("Enter this code at:")
                            .font(.custom("Exo2-Regular", size: 14))
                            .foregroundColor(themeVM.current.textSecondary)

                        Text(flow.verificationUrl)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(themeVM.current.accent)

                        Text(flow.userCode)
                            .font(.custom("Orbitron-Bold", size: 32))
                            .foregroundColor(.white)
                            .tracking(8)
                            .padding(16)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)

                        Button {
                            UIPasteboard.general.string = flow.userCode
                        } label: {
                            Label("Copy Code", systemImage: "doc.on.doc")
                                .font(.system(size: 13))
                                .foregroundColor(themeVM.current.accent)
                        }

                        ProgressView()
                            .tint(themeVM.current.accent)
                        Text("Waiting for authorization...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(themeVM.current.textSecondary)
                    }
                } else {
                    Button {
                        Task { await authVM.startGitHubAuth() }
                    } label: {
                        Text("Start GitHub Authorization")
                            .font(.custom("Exo2-SemiBold", size: 15))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(themeVM.current.accent)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 32)
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
