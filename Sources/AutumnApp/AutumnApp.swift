import SwiftUI
import LEATRCore
import BackgroundTasks
import AutumnServices

@main
struct AutumnApp: App {
    @AppStorage("policy_accepted_v1") private var policyAccepted = false

    @StateObject private var themeVM   = ThemeViewModel()
    @StateObject private var authVM    = AuthViewModel()
    @StateObject private var chatVM    = ChatViewModel()
    @StateObject private var sceneVM   = BRPNSceneViewModel()
    @StateObject private var journalVM = JournalViewModel()
    @StateObject private var mistVM    = MISTSession.shared

    let persistence = PersistenceController.shared

    init() {
        AutumnAutonomy.shared.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .fullScreenCover(isPresented: .init(
                    get: { !policyAccepted },
                    set: { _ in }
                )) {
                    PolicyGateView(onAccept: { policyAccepted = true },
                                   onDecline: { policyAccepted = false })
                        .environmentObject(themeVM)
                }
                .environmentObject(authVM)
                .environmentObject(chatVM)
                .environmentObject(sceneVM)
                .environmentObject(journalVM)
                .environmentObject(themeVM)
                .environmentObject(mistVM)
                .preferredColorScheme(.dark)
                .environment(\.managedObjectContext, persistence.context)
                .onAppear {
                    Task {
                        await mistVM.authenticateLocalPlayer()
                        await journalVM.loadFromCoreData()
                        AutumnAutonomy.shared.scheduleAll()
                    }
                }
        }
    }
}
