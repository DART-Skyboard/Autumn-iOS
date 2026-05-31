import SwiftUI
import LEATRCore
import BackgroundTasks

// MARK: — Identity is derived from LEATR constants, never hardcoded
// See LEATRIdentity.swift

@main
struct AutumnApp: App {

    @StateObject private var authVM    = AuthViewModel()
    @StateObject private var chatVM    = ChatViewModel()
    @StateObject private var sceneVM   = BRPNSceneViewModel()
    @StateObject private var journalVM = JournalViewModel()
    @StateObject private var themeVM   = ThemeViewModel()
    @StateObject private var mistVM    = MISTSession.shared

    // Persistence
    let persistence = PersistenceController.shared

    init() {
        // Register background tasks before app finishes launching
        AutumnAutonomy.shared.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authVM)
                .environmentObject(chatVM)
                .environmentObject(sceneVM)
                .environmentObject(journalVM)
                .environmentObject(themeVM)
                .environmentObject(mistVM)
                .preferredColorScheme(.dark)
                .environment(\.managedObjectContext, persistence.context)
                .onAppear {
                    // Authenticate GameKit for MIST
                    Task { await mistVM.authenticateLocalPlayer() }
                    // Load journal from Core Data
                    Task { await journalVM.loadFromCoreData() }
                    // Schedule background tasks
                    AutumnAutonomy.shared.scheduleAll()
                }
        }
    }
}
