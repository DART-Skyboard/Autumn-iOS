import SwiftUI

@main
struct AutumnApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(red: 0.02, green: 0.04, blue: 0.08)
                    .ignoresSafeArea()
                VStack(spacing: 24) {
                    Circle()
                        .stroke(Color.cyan.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 120, height: 120)
                        .overlay(
                            Text("A")
                                .font(.system(size: 48, weight: .thin, design: .rounded))
                                .foregroundColor(.cyan)
                        )
                    Text("AUTUMN")
                        .font(.system(size: 28, weight: .ultraLight, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(8)
                    Text("LEATR · BRPN · Radical Deepscale")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(2)
                    Spacer().frame(height: 40)
                    Text("Initializing...")
                        .font(.system(size: 11))
                        .foregroundColor(.cyan.opacity(0.6))
                }
            }
        }
    }
}
