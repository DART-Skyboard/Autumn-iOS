import Foundation
import GameKit
import BackgroundTasks
import LEATRCore
import AutumnServices

// MARK: — Phase 4: GameKit MIST Multiplayer + BGTaskScheduler Autonomy

// MARK: — MIST Session (GameKit peer-to-peer)
// MIST = cross-session maze-solve signaling
// Each solved maze emits a MIST event to connected peers via GameKit

@MainActor
public final class MISTSession: NSObject, ObservableObject {
    public static let shared = MISTSession()

    @Published public var connectedPeers: [GKPlayer] = []
    @Published public var mistEvents: [MISTEvent] = []
    @Published public var isMatchmaking = false

    private var match: GKMatch?
    private var request: GKMatchRequest?

    // MARK: — Authentication
    public func authenticateLocalPlayer() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard error == nil else {
                print("GameKit auth error: \(error!.localizedDescription)")
                return
            }
            if GKLocalPlayer.local.isAuthenticated {
                self?.setupMatchmaking()
            }
        }
    }

    // MARK: — Matchmaking
    private func setupMatchmaking() {
        request = GKMatchRequest()
        request?.minPlayers = 2
        request?.maxPlayers = 8
        request?.inviteMessage = "Join Autumn MIST — BRPN multiplayer session"
    }

    public func startMatchmaking() async {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        isMatchmaking = true
        do {
            let newMatch = try await GKMatchmaker.shared().findMatch(for: request ?? GKMatchRequest())
            self.match = newMatch
            newMatch.delegate = self
            self.connectedPeers = newMatch.players
            isMatchmaking = false
        } catch {
            isMatchmaking = false
            print("Matchmaking error: \(error.localizedDescription)")
        }
    }

    public func disconnect() {
        match?.disconnect()
        match = nil
        connectedPeers = []
    }

    // MARK: — Send MIST Event
    public func sendMISTEvent(_ event: MISTEvent) async {
        guard let match, let data = try? JSONEncoder().encode(event) else { return }
        try? match.sendData(toAllPlayers: data, with: .reliable)
        mistEvents.append(event)

        // Also save to leatr-ash mist events
        Task.detached(priority: .background) {
            await self.persistMISTEvent(event)
        }
    }

    private func persistMISTEvent(_ event: MISTEvent) async {
        let github = GitHubClient.shared
        let path = "ashtree/mist/events/\(event.id).json"
        if let data = try? JSONEncoder().encode(event),
           let content = String(data: data, encoding: .utf8) {
            try? await github.writeFile(
                owner: "DART-Skyboard", repo: "leatr-ash",
                path: path, content: content,
                message: "mist event \(event.id)"
            )
        }
    }

    // MARK: — Broadcast BRPN node to peers
    public func broadcastBRPNNode(sessionID: String, shell: BRPNShell, buoyancy: Double) async {
        let event = MISTEvent(
            type: .brpnNode,
            senderID: GKLocalPlayer.local.gamePlayerID,
            payload: ["sessionID": sessionID, "shell": String(shell.rawValue),
                      "buoyancy": String(buoyancy)]
        )
        await sendMISTEvent(event)
    }
}

// MARK: — GKMatchDelegate
extension MISTSession: GKMatchDelegate {
    public func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let event = try? JSONDecoder().decode(MISTEvent.self, from: data) else { return }
        Task { @MainActor in
            mistEvents.append(event)
            handleIncomingEvent(event, from: player)
        }
    }

    @MainActor
    private func handleIncomingEvent(_ event: MISTEvent, from player: GKPlayer) {
        switch event.type {
        case .mazeComplete:
            // Peer solved a maze — add their node to BRPN scene
            if let sessionID = event.payload["sessionID"] {
                BRPNSceneViewModel.shared?.addRemoteNode(
                    uid: sessionID,
                    color: .cyan
                )
            }
        case .brpnNode:
            if let sid = event.payload["sessionID"],
               let shellRaw = event.payload["shell"],
               let shellInt = Int(shellRaw),
               let shell = BRPNShell(rawValue: shellInt) {
                _ = shell // shell routing for future node coloring
                BRPNSceneViewModel.shared?.addRemoteNode(uid: sid, color: .cyan)
            }
        case .signal:
            break
        }
    }

    public func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        Task { @MainActor in
            connectedPeers = match.players
        }
    }
}

// MARK: — MIST Event Model
public struct MISTEvent: Codable, Identifiable, Sendable {
    public let id: String
    public let type: MISTEventType
    public let senderID: String
    public let timestamp: Date
    public let payload: [String: String]

    public init(type: MISTEventType, senderID: String, payload: [String: String] = [:]) {
        self.id = UUID().uuidString
        self.type = type
        self.senderID = senderID
        self.timestamp = Date()
        self.payload = payload
    }
}

public enum MISTEventType: String, Codable, Sendable {
    case mazeComplete = "MAZE_COMPLETE"
    case brpnNode     = "BRPN_NODE"
    case signal       = "SIGNAL"
}

// MARK: — BGTaskScheduler Autonomy
// Registers background tasks for autonomous cognition
// Mirrors Autumn web app's autonomousThink() GAS time-driven trigger

public final class AutumnAutonomy {
    public static let shared = AutumnAutonomy()

    // Task identifiers — must match Info.plist BGTaskSchedulerPermittedIdentifiers
    private let reflexTaskID  = "DART-Meadow-LLC.Autumn.reflex"
    private let journalTaskID = "DART-Meadow-LLC.Autumn.journal"
    private let memoryTaskID  = "DART-Meadow-LLC.Autumn.memory"

    public func registerTasks() {
        // Reflex task — autonomous LEATR processing every 15 min
        BGTaskScheduler.shared.register(forTaskWithIdentifier: reflexTaskID, using: nil) { task in
            self.handleReflexTask(task as! BGAppRefreshTask)
        }

        // Journal task — sync journal to CloudKit + GitHub nightly
        BGTaskScheduler.shared.register(forTaskWithIdentifier: journalTaskID, using: nil) { task in
            self.handleJournalTask(task as! BGProcessingTask)
        }

        // Memory task — consolidate rolling memory chunks
        BGTaskScheduler.shared.register(forTaskWithIdentifier: memoryTaskID, using: nil) { task in
            self.handleMemoryTask(task as! BGProcessingTask)
        }
    }

    public func scheduleAll() {
        scheduleReflex()
        scheduleJournal()
        scheduleMemory()
    }

    // MARK: — Schedule
    private func scheduleReflex() {
        let request = BGAppRefreshTaskRequest(identifier: reflexTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func scheduleJournal() {
        let request = BGProcessingTaskRequest(identifier: journalTaskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(hour: 2, minute: 0),
            matchingPolicy: .nextTime
        )
        try? BGTaskScheduler.shared.submit(request)
    }

    private func scheduleMemory() {
        let request = BGProcessingTaskRequest(identifier: memoryTaskID)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: — Handlers
    private func handleReflexTask(_ task: BGAppRefreshTask) {
        let taskWork = Task {
            // Autonomous LEATR reflex — process any pending thoughts
            let engine = LEATREngine.shared
            let panels = await engine.runPipeline(f: 50, r: 10, p: 60)
            let _ = await engine.pipelineClears(panels: panels)

            // Journal the autonomous thought
            let entry = CloudJournalEntry(
                thought: "[autonomous reflex] pipeline check at \(Date())",
                emotion: "neutral"
            )
            try? await AutumnCloud.shared.saveCloudJournalEntry(entry)
        }

        task.expirationHandler = { taskWork.cancel() }
        Task {
            await taskWork.value
            task.setTaskCompleted(success: true)
            scheduleReflex() // Reschedule
        }
    }

    private func handleJournalTask(_ task: BGProcessingTask) {
        let taskWork = Task {
            // Full journal sync — CloudKit → GitHub
            let entries = (try? await AutumnCloud.shared.fetchJournalEntries(limit: 500)) ?? []
            if !entries.isEmpty {
                let parity = await CloudKitSync.shared.parityCheck()
                if !parity.inSync {
                    // Re-sync all entries to GitHub
                    for entry in entries.suffix(10) {
                        try? await GitHubClient.shared.syncJournalEntry(entry, username: "")
                    }
                }
            }
        }

        task.expirationHandler = { taskWork.cancel() }
        Task {
            await taskWork.value
            task.setTaskCompleted(success: true)
            scheduleJournal()
        }
    }

    private func handleMemoryTask(_ task: BGProcessingTask) {
        let taskWork = Task {
            // Consolidate memory chunks older than 24h into single archive
            // Placeholder — full implementation requires CoreData integration
        }

        task.expirationHandler = { taskWork.cancel() }
        Task {
            await taskWork.value
            task.setTaskCompleted(success: true)
            scheduleMemory()
        }
    }
}

// MARK: — BRPNSceneViewModel shared accessor for GameKit callbacks
private extension BRPNSceneViewModel {
    static weak var shared: BRPNSceneViewModel?
}
