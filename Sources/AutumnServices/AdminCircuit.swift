import Foundation
import Combine

/// One admin gate used by UI and network.
/// Closed only when GitHub user is dartsolarpunk, the Enable Admin flag is on,
/// and `admin/circuit.json` is live:true with ts within ~90s (web tab heartbeat).
public enum AdminCircuitGate {
    public static let maxAge: TimeInterval = 90

    public static func allows(
        username: String,
        githubConnected: Bool,
        adminEnabled: Bool,
        live: Bool,
        ts: Date?,
        now: Date = Date()
    ) -> Bool {
        guard githubConnected else { return false }
        guard username.lowercased() == AutumnConfig.adminUsername else { return false }
        guard adminEnabled else { return false }
        guard live else { return false }
        guard let ts else { return false }
        return now.timeIntervalSince(ts) <= maxAge && now.timeIntervalSince(ts) >= -30
    }
}

/// Actor store so mailbox / ACL / SYS writes share the same gate as the UI.
public actor AdminCircuitStore {
    public static let shared = AdminCircuitStore()
    private var live = false
    private var ts: Date?

    public func ingest(live: Bool, ts: Date?) {
        self.live = live
        self.ts = ts
    }

    public func snapshot() -> (live: Bool, ts: Date?) { (live, ts) }

    public func allows(username: String, githubConnected: Bool, adminEnabled: Bool) -> Bool {
        AdminCircuitGate.allows(
            username: username,
            githubConnected: githubConnected,
            adminEnabled: adminEnabled,
            live: live,
            ts: ts
        )
    }
}

@MainActor
public final class AdminCircuitMonitor: ObservableObject {
    public static let shared = AdminCircuitMonitor()

    @Published public private(set) var live = false
    @Published public private(set) var ts: Date? = nil
    @Published public private(set) var status = "CIRCUIT OPEN"
    @Published public private(set) var lastPoll: Date? = nil

    private var task: Task<Void, Never>?

    public func allows(_ auth: AuthViewModel) -> Bool {
        AdminCircuitGate.allows(
            username: auth.githubUsername,
            githubConnected: auth.githubConnected,
            adminEnabled: auth.adminEnabled,
            live: live,
            ts: ts
        )
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func poll() async {
        let parsed = await Self.readCircuit()
        live = parsed.live
        ts = parsed.ts
        lastPoll = Date()
        await AdminCircuitStore.shared.ingest(live: live, ts: ts)
        if let ts {
            let age = Date().timeIntervalSince(ts)
            status = live && age <= AdminCircuitGate.maxAge
                ? String(format: "CIRCUIT CLOSED  %.0fs", age)
                : String(format: "CIRCUIT OPEN  stale %.0fs", age)
        } else {
            status = live ? "CIRCUIT LIVE (no ts)" : "CIRCUIT OPEN"
        }
    }

    static func readCircuit() async -> (live: Bool, ts: Date?) {
        if let any = await AutumnGASClient.shared.ashread(path: AutumnConfig.circuitPath) {
            let p = parse(any)
            if p.live || p.ts != nil { return p }
        }
        return (false, nil)
    }

    static func parse(_ any: Any) -> (live: Bool, ts: Date?) {
        var root: [String: Any]?
        if let d = any as? [String: Any] {
            if d["live"] != nil || d["ts"] != nil {
                root = d
            } else if let payload = d["payload"] as? [String: Any] {
                root = payload
            } else if let data = d["data"] as? [String: Any] {
                root = data
            } else if let content = d["content"] as? String {
                let cleaned = content.replacingOccurrences(of: "\n", with: "")
                if let decoded = Data(base64Encoded: cleaned),
                   let obj = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] {
                    root = obj
                } else if let data = content.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    root = obj
                }
            }
        }
        guard let obj = root else { return (false, nil) }
        var live = false
        if let b = obj["live"] as? Bool { live = b }
        else if let s = obj["live"] as? String { live = s == "true" || s == "1" }
        let ts = parseISO(obj["ts"] as? String)
        return (live, ts)
    }

    static func parseISO(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}
