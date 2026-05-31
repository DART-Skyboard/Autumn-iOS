import SwiftUI
import LEATRCore

// MARK: — Identity is derived from LEATR constants, never hardcoded
// See LEATRIdentity.swift

@main
struct AutumnApp: App {

    @StateObject private var authVM    = AuthViewModel()
    @StateObject private var chatVM    = ChatViewModel()
    @StateObject private var sceneVM   = BRPNSceneViewModel()
    @StateObject private var journalVM = JournalViewModel()
    @StateObject private var themeVM   = ThemeViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authVM)
                .environmentObject(chatVM)
                .environmentObject(sceneVM)
                .environmentObject(journalVM)
                .environmentObject(themeVM)
                .preferredColorScheme(.dark)
        }
    }
}