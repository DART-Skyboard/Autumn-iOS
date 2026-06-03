
import SwiftUI

/// Full-screen policy gate shown once on first launch
/// Uses callbacks instead of @EnvironmentObject to avoid Swift 5.9 closure binding issues
struct PolicyGateView: View {
    let onAccept:  () -> Void
    let onDecline: () -> Void
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var scrolledToBottom = false

    var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Text("AUTUMN AI")
                        .font(.custom("Orbitron-Bold", size: 20))
                        .foregroundColor(themeVM.current.accent)
                        .tracking(6)
                    Text("Privacy Policy & Terms")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(themeVM.current.textSecondary)
                }
                .padding(.vertical, 24)

                Divider().background(themeVM.current.accent.opacity(0.3))

                // Scrollable policy
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        policySection("Data Collection",
                            "Autumn AI stores your conversations locally on your device. " +
                            "Journal entries are kept private and only synced to GitHub " +
                            "repositories you explicitly authorize via PAT. " +
                            "DART Meadow Technologies does not collect or sell your data.")

                        policySection("AI Processing",
                            "Conversations use the LEATR/BRPN neural framework locally. " +
                            "If you provide an Anthropic API key, messages are processed " +
                            "by Anthropic per their privacy policy. No data is stored " +
                            "on DART Meadow servers without your authorization.")

                        policySection("Presence & BRPN World Scene",
                            "The BRPN world scene shows anonymized presence nodes for " +
                            "active users. No personally identifiable information is " +
                            "transmitted. Microphone access is only used when you " +
                            "explicitly activate it.")

                        policySection("GitHub Integration (Optional)",
                            "If you connect GitHub via device flow or PAT, Autumn may " +
                            "read and write to repositories you authorize. Your credentials " +
                            "are stored only in the iOS Keychain and transmitted only to " +
                            "api.github.com.")

                        policySection("Your Rights",
                            "You may delete your local data at any time via Settings. " +
                            "Signing out removes all stored credentials. " +
                            "You may continue as a Guest without any account.")

                        policySection("Contact",
                            "Privacy questions: dartmeadow@gmail.com\n" +
                            "Full policy: dartmeadow.com/privacy\n" +
                            "© 2026 DART Meadow Technologies / Radical Deepscale LLC")

                        // Scroll sentinel
                        Color.clear.frame(height: 1)
                            .onAppear { scrolledToBottom = true }
                    }
                    .padding(20)
                }

                Divider().background(themeVM.current.accent.opacity(0.3))

                // Buttons
                VStack(spacing: 12) {
                    if !scrolledToBottom {
                        Text("Scroll to read the full policy")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(themeVM.current.textSecondary)
                    }

                    Button(action: onAccept) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                            Text("Accept & Continue")
                        }
                        .font(.custom("Exo2-SemiBold", size: 16))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(scrolledToBottom ? themeVM.current.accent : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(!scrolledToBottom)

                    Button(action: onDecline) {
                        Text("Decline — Exit")
                            .font(.system(size: 13))
                            .foregroundColor(themeVM.current.textSecondary)
                    }
                }
                .padding(20)
            }
        }
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(themeVM.current.accent)
                    .frame(width: 3, height: 16)
                Text(title)
                    .font(.custom("Orbitron-Bold", size: 13))
                    .foregroundColor(themeVM.current.accent)
            }
            Text(body)
                .font(.custom("Exo2-Regular", size: 13))
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }
}
