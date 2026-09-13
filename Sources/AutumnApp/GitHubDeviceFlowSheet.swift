import SwiftUI
import UIKit
import AutumnServices

// MARK: — GitHub Device Flow Sheet
// Shared by WelcomeView / ProfileSheet / Settings.
// When userCode is ready: copy clipboard + show large code. NEVER auto-open Safari
// (TF81: auto in-app Safari covered the code; close → cancel/restart → email trap).
// Primary "Open GitHub Authorization" uses UIApplication.shared.open (external Safari)
// with ?user_code= so closing Safari does not cancel the poll or burn the code.
struct GitHubDeviceFlowSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var didCopyOnAppear = false
    @State private var copiedBanner = false

    var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()
            VStack(spacing: 24) {

                HStack {
                    Spacer()
                    Button {
                        closeFlow()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(themeVM.current.textSecondary)
                    }
                    .accessibilityLabel("Close")
                    .padding(.trailing, 20)
                    .padding(.top, 12)
                }

                Text("Connect GitHub")
                    .font(.custom("Orbitron-Bold", size: 20))
                    .foregroundColor(themeVM.current.accent)

                if let flow = authVM.deviceFlowCode {
                    VStack(spacing: 16) {
                        Button {
                            copyCode(flow.userCode)
                        } label: {
                            VStack(spacing: 6) {
                                Text(flow.userCode)
                                    .font(.custom("Orbitron-Bold", size: 32))
                                    .foregroundColor(.white)
                                    .tracking(8)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(12)
                                Label(
                                    copiedBanner ? "Copied — open when ready" : "Tap to copy",
                                    systemImage: copiedBanner ? "checkmark.circle.fill" : "doc.on.doc"
                                )
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(copiedBanner ? themeVM.current.accent : themeVM.current.textSecondary)
                            }
                        }

                        Button {
                            copyCode(flow.userCode)
                            openExternalGitHub()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "safari.fill")
                                    .font(.system(size: 15))
                                Text("Open GitHub Authorization")
                                    .font(.custom("Exo2-SemiBold", size: 14))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(themeVM.current.accent)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 28)

                        Text("Code stays here while Safari is open — Close Safari anytime; tap Open again with the same code.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(themeVM.current.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

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
                    .onAppear { copyOnAppearIfNeeded(flow) }

                } else {
                    VStack(spacing: 16) {
                        Text("Authorize Autumn to read/write your GitHub repositories.")
                            .font(.custom("Exo2-Regular", size: 13))
                            .foregroundColor(themeVM.current.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if authVM.isAuthenticating {
                            ProgressView()
                                .tint(themeVM.current.accent)
                            Text("Starting device flow…")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(themeVM.current.textSecondary)
                        } else {
                            Button {
                                Task { await authVM.startGitHubAuth(openVerification: false) }
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
                }

                if let err = authVM.error {
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()
                Button("Cancel") { closeFlow() }
                    .foregroundColor(themeVM.current.textSecondary)
                    .padding(.bottom, 32)
            }
        }
        .interactiveDismissDisabled(false)
        .presentationDragIndicator(.visible)
        .onAppear {
            // Auto-start device flow once; do NOT auto-open Safari.
            if authVM.deviceFlowCode == nil && !authVM.isAuthenticating {
                Task { await authVM.startGitHubAuth(openVerification: false) }
            } else if let flow = authVM.deviceFlowCode {
                copyOnAppearIfNeeded(flow)
            }
        }
        .onChange(of: authVM.deviceFlowCode?.userCode) { _ in
            if let flow = authVM.deviceFlowCode {
                copyOnAppearIfNeeded(flow)
            }
        }
        .onChange(of: authVM.githubConnected) { connected in
            if connected {
                dismiss()
            }
        }
    }

    private func deviceURL(base: String, userCode: String) -> URL {
        // Prefer github.com/login/device?user_code= — GitHub 302s to login with
        // return_to preserving user_code so the code field is prefilled after sign-in.
        var components = URLComponents(string: "https://github.com/login/device")!
        if !userCode.isEmpty {
            components.queryItems = [URLQueryItem(name: "user_code", value: userCode)]
        } else if let baseURL = URL(string: base), let host = baseURL.host, host.contains("github.com") {
            return baseURL
        }
        return components.url ?? URL(string: "https://github.com/login/device")!
    }

    private func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        copiedBanner = true
    }

    /// External Safari — closing it must not cancel the device-flow poll.
    private func openExternalGitHub() {
        let code = authVM.deviceFlowCode?.userCode ?? ""
        let raw = authVM.deviceFlowCode?.verificationUrl ?? "https://github.com/login/device"
        let url = deviceURL(base: raw, userCode: code)
        UIApplication.shared.open(url)
    }

    private func copyOnAppearIfNeeded(_ flow: DeviceFlowDisplay) {
        guard !didCopyOnAppear else { return }
        didCopyOnAppear = true
        copyCode(flow.userCode)
        // Prefer NEVER auto-open — user taps "Open GitHub Authorization".
    }

    private func closeFlow() {
        authVM.cancelGitHubAuth()
        dismiss()
    }
}
