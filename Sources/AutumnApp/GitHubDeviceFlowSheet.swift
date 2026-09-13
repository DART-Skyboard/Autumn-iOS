import SwiftUI
import AutumnServices
import SafariServices

// MARK: — GitHub Device Flow Sheet
// Shared by WelcomeView and ProfileSheet so the user code is visible,
// copyable, with “Open GitHub Authorization” — matches web clarity.
// Opens github.com/login/device in-app via SFSafariViewController when code is ready.
struct GitHubDeviceFlowSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showSafari = false
    @State private var didAutoOpen = false

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
                        // Code — tap to copy
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

                        // Open GitHub in-app button
                        Button {
                            UIPasteboard.general.string = flow.userCode
                            showSafari = true
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

                        Text("Code copied to clipboard — paste it on the GitHub page.")
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
                    // Auto-open safari the first time the code appears
                    .onAppear {
                        if !didAutoOpen {
                            didAutoOpen = true
                            UIPasteboard.general.string = flow.userCode
                            showSafari = true
                        }
                    }

                } else {
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
        .sheet(isPresented: $showSafari) {
            if let url = URL(string: "https://github.com/login/device") {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .onChange(of: authVM.githubConnected) { connected in
            if connected { dismiss() }
        }
    }
}

// MARK: — SFSafariViewController wrapper
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: cfg)
        vc.preferredControlTintColor = UIColor(red: 0, green: 0.9, blue: 1.0, alpha: 1)
        vc.preferredBarTintColor = UIColor(red: 0.02, green: 0.05, blue: 0.08, alpha: 1)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
