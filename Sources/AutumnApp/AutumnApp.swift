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
    // TF157: referencing .shared once is enough to trigger AnalyticsEventLogger's
    // init() and register its ReflexActivityBus observers for the whole app session.
    private let analyticsLogger = AnalyticsEventLogger.shared
    // TF161: same pattern — activates LiveFeedController's remote-config
    // polling and event subscription for the whole app session.
    private let liveFeedController = LiveFeedController.shared

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
                    chatVM.sessionSID = authVM.sessionSID
                    sceneVM.bindIdentity(uid: authVM.sessionUID, sid: authVM.sessionSID)
                    Task {
                        await mistVM.authenticateLocalPlayer()
                        await journalVM.loadFromCoreData()
                        AutumnAutonomy.shared.scheduleAll()
                        await MISTModule.shared.refresh()
                    }
                }
                .onChange(of: authVM.githubUsername) { _ in
                    chatVM.memoryOwner = authVM.sessionUID
                    chatVM.sessionSID = authVM.sessionSID
                    sceneVM.bindIdentity(uid: authVM.sessionUID, sid: authVM.sessionSID)
                }
                .onReceive(NotificationCenter.default.publisher(for: AutumnSettingsSync.localChangeNotification)) { _ in
                    AutumnSettingsSync.scheduleDebouncedVaultWrite(
                        username: authVM.githubConnected ? authVM.githubUsername : nil
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: AutumnSettingsSync.didRestoreNotification)) { _ in
                    themeVM.reloadFromDefaults()
                    authVM.restoreAdminFlag()
                    if UserDefaults.standard.object(forKey: AutumnSettingsSync.liveFeedKey) != nil {
                        sceneVM.liveFeedEnabled = UserDefaults.standard.bool(forKey: AutumnSettingsSync.liveFeedKey)
                    }
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
