import SwiftUI
import AuthenticationServices

public struct WelcomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var showGitHubSheet = false
    @State private var patInput = ""

    public var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Identity orb
                ZStack {
                    Circle()
                        .fill(themeVM.current.accent.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Circle()
                        .stroke(themeVM.current.accent.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 120, height: 120)
                    Text(LEATRIdentity.displayName.prefix(1))
                        .font(.custom("Orbitron-Bold", size: 48))
                        .foregroundColor(themeVM.current.accent)
                }

                VStack(spacing: 8) {
                    Text(LEATRIdentity.displayName.uppercased())
                        .font(.custom("Orbitron-Bold", size: 28))
                        .foregroundColor(.white)
                        .tracking(6)
                    Text("LEATR · BRPN · Radical Deepscale")
                        .font(.custom("Exo2-Regular", size: 13))
                        .foregroundColor(themeVM.current.textSecondary)
                        .tracking(2)
                }

                Spacer()

                VStack(spacing: 16) {
                    // Sign in with Apple
                    SignInWithAppleButton(.signIn) { req in
                        req.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        authVM.signInWithApple()
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .cornerRadius(10)

                    // GitHub connect
                    Button {
                        showGitHubSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "link")
                            Text("Connect GitHub")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(themeVM.current.surface)
                        .foregroundColor(themeVM.current.accent)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(themeVM.current.accent.opacity(0.4), lineWidth: 1)
                        )
                    }

                    // Guest / LEATR-only
                    Button {
                        authVM.isSignedIn = true
                    } label: {
                        Text("Continue offline (LEATR only)")
                            .font(.custom("Exo2-Regular", size: 13))
                            .foregroundColor(themeVM.current.textSecondary)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showGitHubSheet) {
            GitHubConnectSheet()
        }
    }
}

// MARK: — GitHub Connect Sheet
struct GitHubConnectSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var patInput = ""
    @State private var useDeviceFlow = false

    var body: some View {
        NavigationStack {
            ZStack {
                themeVM.current.gradient.ignoresSafeArea()
                VStack(spacing: 24) {
                    if let code = authVM.deviceFlowCode {
                        // Device flow — show code to enter at github.com/login/device
                        VStack(spacing: 16) {
                            Text("Visit github.com/login/device")
                                .foregroundColor(.white)
                            Text(code.userCode)
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundColor(themeVM.current.accent)
                                .padding()
                                .glassCard(theme: themeVM.current)
                            Text("Waiting for authorization…")
                                .foregroundColor(themeVM.current.textSecondary)
                            ProgressView().tint(themeVM.current.accent)
                            Link("Open GitHub", destination: URL(string: code.verificationUrl)!)
                                .foregroundColor(themeVM.current.accent)
                        }
                    } else {
                        // PAT or device flow choice
                        VStack(alignment: .leading, spacing: 12) {
                            Text("GitHub Personal Access Token")
                                .font(.custom("Exo2-Regular", size: 14))
                                .foregroundColor(themeVM.current.textSecondary)
                            SecureField("ghp_…", text: $patInput)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Button("Connect with PAT") {
                                Task {
                                    await authVM.connectGitHubPAT(patInput)
                                    dismiss()
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(themeVM.current.accent)
                            .foregroundColor(.black)
                            .cornerRadius(10)

                            Divider().background(themeVM.current.accent.opacity(0.3))

                            Button("Use Device Flow (no token needed)") {
                                Task { await authVM.startGitHubAuth() }
                            }
                            .foregroundColor(themeVM.current.accent)
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Connect GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(themeVM.current.accent)
                }
            }
        }
    }
}
