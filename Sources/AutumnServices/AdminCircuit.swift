import Foundation
import Combine

/// One admin gate used by UI and network.
/// Granted from iOS sign-in as Justin's main account (dartsolarpunk) — no web
/// heartbeat, no leatr.xyz tab, no `admin/circuit.json` CIRCUIT OPEN/CLOSED poll.
public enum AdminCircuitGate {
    public static let appleLinkKey = "autumn_admin_apple_uid"

    public static func isAdminIdentity(
        githubUsername: String,
        displayName: String = "",
        appleUserId: String = "",
        isGuest: Bool = false
    ) -> Bool {
        guard !isGuest else { return false }
        let admin = AutumnConfig.adminUsername
        if githubUsername.lowercased() == admin { return true }
        if displayName.lowercased() == admin { return true }
        if !appleUserId.isEmpty,
           UserDefaults.standard.string(forKey: appleLinkKey) == appleUserId {
            return true
        }
        return false
    }

    public static func allows(
        username: String,
        githubConnected: Bool = true,
        adminEnabled: Bool = true,
        live: Bool = true,
        ts: Date? = Date(),
        isGuest: Bool = false,
        displayName: String = "",
        appleUserId: String = "",
        now: Date = Date()
    ) -> Bool {
        _ = (githubConnected, live, ts, now)
        guard isAdminIdentity(
            githubUsername: username,
            displayName: displayName,
            appleUserId: appleUserId,
            isGuest: isGuest
        ) else { return false }
        return adminEnabled
    }

    public static func linkAppleIdentity(_ appleUserId: String) {
        let id = appleUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        UserDefaults.standard.set(id, forKey: appleLinkKey)
    }
}

/// Actor store so mailbox / ACL / SYS writes share the same gate as the UI.
public actor AdminCircuitStore {
    public static let shared = AdminCircuitStore()

    public func ingest(live: Bool, ts: Date?) {
        _ = (live, ts)
    }

    public func snapshot() -> (live: Bool, ts: Date?) { (true, Date()) }

    public func allows(username: String, githubConnected: Bool, adminEnabled: Bool) -> Bool {
        _ = (githubConnected, adminEnabled)
        return AdminCircuitGate.isAdminIdentity(githubUsername: username)
    }
}

@MainActor
public final class AdminCircuitMonitor: ObservableObject {
    public static let shared = AdminCircuitMonitor()

    @Published public private(set) var live = true
    @Published public private(set) var ts: Date? = Date()
    @Published public private(set) var status = "iOS sign-in"
    @Published public private(set) var lastPoll: Date? = nil

    public func allows(_ auth: AuthViewModel) -> Bool {
        let ok = AdminCircuitGate.allows(
            username: auth.githubUsername,
            githubConnected: auth.githubConnected,
            adminEnabled: auth.adminEnabled,
            isGuest: auth.isGuest,
            displayName: auth.username,
            appleUserId: auth.appleUserId
        )
        if ok {
            status = "iOS ADMIN · \(AutumnConfig.adminUsername)"
        } else if auth.isGuest {
            status = "GUEST — sign in for admin"
        } else {
            status = "Not admin identity"
        }
        lastPoll = Date()
        return ok
    }

    /// No web heartbeat. Kept so existing `.onAppear { circuit.start() }` compiles.
    public func start() {}
    public func stop() {}
    public func poll() async {}
}
