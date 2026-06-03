
import SwiftUI

/// Privacy policy overlay shown once on first launch
struct AutumnPolicyOverlay: View {
    let onAccept: () -> Void
    let onDecline: () -> Void
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var scrolledToBottom = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("PRIVACY POLICY")
                        .font(.custom("Orbitron-Bold", size: 16))
                        .foregroundColor(themeVM.current.accent).tracking(4)
                    Text("Please read and accept to continue")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(themeVM.current.textSecondary)
                }
                .padding(.vertical, 16)

                Divider().background(themeVM.current.accent.opacity(0.3))

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        section("Data Collection",
                            "Autumn AI stores your conversations locally on your device. " +
                            "Journal entries and sentience records are kept private and only " +
                            "synced to repositories you authorize via GitHub PAT. " +
                            "DART Meadow Technologies does not collect or sell your data.")
                        section("AI Processing",
                            "Conversations use the LEATR/BRPN neural framework locally. " +
                            "If you provide an Anthropic API key, messages are sent to " +
                            "Anthropic's servers per their privacy policy. No data is " +
                            "stored on DART Meadow servers.")
                        section("Presence & BRPN",
                            "The BRPN world scene displays anonymized presence nodes for " +
                            "active users. No personally identifiable information is " +
                            "transmitted. Microphone access is only used when activated.")
                        section("GitHub",
                            "If you connect GitHub, Autumn may read/write authorized " +
                            "repositories. Your PAT is stored in the iOS Keychain and " +
                            "transmitted only to api.github.com.")
                        section("Contact",
                            "dartmeadow@gmail.com  ·  dartmeadow.com/privacy\n" +
                            "© 2026 DART Meadow Technologies / Radical Deepscale LLC")
                        Color.clear.frame(height: 1).onAppear { scrolledToBottom = true }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 340)

                Divider().background(themeVM.current.accent.opacity(0.3))

                VStack(spacing: 10) {
                    Button(action: onAccept) {
                        Text("Accept — Enter Autumn")
                            .font(.custom("Exo2-SemiBold", size: 15)).foregroundColor(.black)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(themeVM.current.accent).cornerRadius(10)
                    }
                    .opacity(scrolledToBottom ? 1.0 : 0.5)
                    .disabled(!scrolledToBottom)

                    Button("Decline & Sign Out", action: onDecline)
                        .font(.system(size: 12)).foregroundColor(themeVM.current.textSecondary)
                }
                .padding(16)
            }
            .background(Color(red:0.04, green:0.07, blue:0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(themeVM.current.accent.opacity(0.3), lineWidth: 0.5))
            .padding(20)
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.custom("Orbitron-Bold", size: 12))
                .foregroundColor(themeVM.current.accent)
            Text(body).font(.custom("Exo2-Regular", size: 12))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
