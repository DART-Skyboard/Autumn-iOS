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
    @StateObject private var appNav    = AppNavigation()
    @StateObject private var circuit   = AdminCircuitMonitor.shared

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
                .environmentObject(appNav)
                .environmentObject(circuit)
                .preferredColorScheme(.dark)
                .environment(\.managedObjectContext, persistence.context)
                .onAppear {
                    chatVM.memoryOwner = authVM.sessionUID
                    Task {
                        await mistVM.authenticateLocalPlayer()
                        await journalVM.loadFromCoreData()
                        AutumnAutonomy.shared.scheduleAll()
                        await MISTModule.shared.refresh()
                    }
                }
                .onChange(of: authVM.githubUsername) { _ in
                    chatVM.memoryOwner = authVM.sessionUID
                }
                .onReceive(NotificationCenter.default.publisher(for: .autumnAshStar)) { _ in
                    _ = sceneVM.fireAshStar(thought: "", force: true)
                    MISTModule.shared.emitAshStarPacket(thought: "", toUids: sceneVM.connectedUids, uid: "autumn")
                }
                .onReceive(NotificationCenter.default.publisher(for: .autumnIncomingAshStar)) { note in
                    let thought = (note.userInfo?["thought"] as? String) ?? ""
                    let color = (note.userInfo?["color"] as? String) ?? "#00d4ff"
                    let uid = (note.userInfo?["uid"] as? String) ?? "autumn"
                    sceneVM.receiveIncomingStar(thought: thought, colorHex: color, uid: uid)
                }
        }
    }
}
