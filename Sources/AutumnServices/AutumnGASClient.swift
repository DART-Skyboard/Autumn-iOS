import Foundation

/// AutumnGASClient — same GAS ashwrite proxy as live leatr.xyz.
/// Source of truth: Autumn/index.html AUTUMN_GAS_URL + `_ashFlushNow`.
/// Content-Type: text/plain (web avoids CORS preflight; iOS matches the body shape).
/// No client-side GitHub token is required for ashwrite.
public actor AutumnGASClient {
    public static let shared = AutumnGASClient()

    private let session: URLSession
    public let gasURL: String

    public init(gasURL: String = AutumnConfig.gasURL) {
        self.gasURL = gasURL
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    // MARK: — ashwrite (journal, sessions, feedback)
    /// Matches `_ashFlushNow`:
    /// `{ action: 'ashwrite', path, uid, append, payload }`
    @discardableResult
    public func ashwrite(path: String, uid: String, append: Bool, payload: Any) async -> Bool {
        let body: [String: Any] = [
            "action": "ashwrite",
            "path": path,
            "uid": uid,
            "append": append,
            "payload": payload
        ]
        return await postPlain(body)
    }

    public func writeJournal(uid: String, thought: String, reply: String, emotion: String, buoyancy: Double, platform: String = "ios") async {
        let entry: [String: Any] = [
            "id": hexId(),
            "ts": ISO8601DateFormatter().string(from: Date()),
            "thought": thought,
            "reply": reply,
            "emotion": emotion,
            "buoyancy": String(format: "%.3f", buoyancy),
            "platform": platform,
            "uid": uid
        ]
        _ = await ashwrite(path: AutumnConfig.journalPath, uid: uid, append: true, payload: [entry])
    }

    public func writeSession(uid: String, sid: String, extra: [String: Any] = [:]) async {
        var payload: [String: Any] = [
            "uid": uid,
            "sid": sid,
            "ts": Date().timeIntervalSince1970 * 1000,
            "platform": "ios"
        ]
        extra.forEach { payload[$0.key] = $0.value }
        let path = AutumnConfig.sessionsPrefix + sid + ".json"
        _ = await ashwrite(path: path, uid: uid, append: false, payload: payload)
    }

    /// Feedback inbox — OTHER APPS depend on this path. Do not change it.
    @discardableResult
    public func submitFeedback(id: String, ts: String, cat: String, msg: String, user: String, uid: String) async -> Bool {
        let entry: [String: Any] = [
            "id": id,
            "ts": ts,
            "cat": cat,
            "msg": msg,
            "user": user
        ]
        return await ashwrite(path: AutumnConfig.feedbackInboxPath, uid: uid, append: true, payload: [entry])
    }

    /// Admin mailbox read — web `_admFetchJson` via GAS `ashread`, GitHub fallback is in FeedbackService.
    public func ashread(path: String) async -> Any? {
        let body: [String: Any] = ["action": "ashread", "path": path]
        return await postPlainJSON(body)
    }

    /// Replace-write a JSON array (admin mailbox move/delete). Matches web `_admWriteJson` GAS path.
    @discardableResult
    public func ashwriteReplace(path: String, uid: String, payload: Any, message: String) async -> Bool {
        let body: [String: Any] = [
            "action": "ashwrite",
            "path": path,
            "uid": uid,
            "append": false,
            "payload": payload,
            "message": message
        ]
        return await postPlain(body)
    }

    // MARK: — OAuth helpers (same GAS as web)
    public func exchangeCode(_ code: String) async -> [String: Any]? {
        guard let url = URL(string: gasURL + "?action=exchange&code=" + code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) else { return nil }
        return await getJSON(url)
    }

    public func deviceCode() async -> [String: Any]? {
        guard let url = URL(string: gasURL + "?action=devicecode&scope=" + AutumnConfig.githubScopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) else { return nil }
        return await getJSON(url)
    }

    public func logPresence(token: String, dataJSON: String) async {
        let q = "action=logpresence&token=" + token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! + "&data=" + dataJSON.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        guard let url = URL(string: gasURL + "?" + q) else { return }
        _ = try? await session.data(from: url)
    }

    // MARK: — HTTP
    @discardableResult
    private func postPlain(_ payload: [String: Any]) async -> Bool {
        guard let url = URL(string: gasURL),
              let body = try? JSONSerialization.data(withJSONObject: payload)
        else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 12
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (200...299).contains(code)
        } catch {
            return false
        }
    }

    private func postPlainJSON(_ payload: [String: Any]) async -> Any? {
        guard let url = URL(string: gasURL),
              let body = try? JSONSerialization.data(withJSONObject: payload)
        else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 12
        do {
            let (data, _) = try await session.data(for: req)
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    private func getJSON(_ url: URL) async -> [String: Any]? {
        do {
            let (data, _) = try await session.data(from: url)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private func hexId() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000), radix: 16) + "-" + String(Int.random(in: 0x1000...0xffff), radix: 16)
    }
}

// MARK: — Models kept for callers
public struct GASJournalEntry: Codable, Identifiable {
    public let id: String
    public let thought: String
    public let emotion: String
    public let timestamp: String
    public let buoyancy: String?
    public let platform: String?
}

public struct MISTNode: Codable, Identifiable {
    public let id: String
    public let uid: String
    public let emotion: String
    public let buoyancy: String
    public let lastSeen: String
}
