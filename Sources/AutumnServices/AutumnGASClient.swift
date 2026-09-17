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

    /// TF124: the actual "she educates herself" mechanism — not generating
    /// new knowledge (nothing rule-based can), but recording exactly what she
    /// was asked and couldn't answer from her curated topics or WordNet, so
    /// there's a real, growing, reviewable record of specific gaps to fill —
    /// by adding real content to ashtree/reference/, the same place every
    /// other piece of her knowledge already lives. This is the honest version
    /// of self-directed learning available without training an actual model.
    public func writeStudyGap(uid: String, word: String, context: String, platform: String = "ios") async {
        let entry: [String: Any] = [
            "id": hexId(),
            "ts": ISO8601DateFormatter().string(from: Date()),
            "word": word,
            "context": String(context.prefix(200)),
            "platform": platform,
            "uid": uid
        ]
        _ = await ashwrite(path: AutumnConfig.studyQueuePath, uid: uid, append: true, payload: [entry])
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

    /// Web `_pollAshNodes` PRIMARY write — CacheService `writenode` (not a new sid per ping).
    public func writeNode(sid: String, uid: String, label: String) async {
        let body: [String: Any] = [
            "action": "writenode",
            "sid": sid,
            "uid": uid,
            "node": [
                "x": 0, "y": 0, "z": 0,
                "shell": "Geological",
                "color": "#00e5ff",
                "label": String(label.prefix(10)),
                "ts": Date().timeIntervalSince1970 * 1000
            ]
        ]
        _ = await postPlain(body)
    }

    /// Web `?action=readnodes` — live buoyancy-node listing (CacheService, sub-100ms).
    public func readNodes() async -> [[String: Any]] {
        guard let url = URL(string: gasURL + "?action=readnodes") else { return [] }
        guard let json = await getJSON(url) else { return [] }
        return json["nodes"] as? [[String: Any]] ?? []
    }

    /// Web `?action=sessions` — GitHub-backed sessions + mist/ashstar heartbeat.
    public func readSessions() async -> [[String: Any]] {
        guard let url = URL(string: gasURL + "?action=sessions") else { return [] }
        guard let json = await getJSON(url) else { return [] }
        return json["sessions"] as? [[String: Any]] ?? []
    }

    /// Canvas / presence ping. Same GAS as web: stable sid + writenode (never mint presence-* ghosts).
    public func pingPresence(message: String, response: String, emotion: String, buoyancy: Double, uid: String = "ios-guest", sid: String? = nil) async {
        let useSid = (sid?.isEmpty == false) ? sid! : uid
        await writeNode(sid: useSid, uid: uid, label: uid)
        await writeSession(uid: uid, sid: useSid, extra: [
            "type": "presence",
            "message": message,
            "response": response,
            "emotion": emotion,
            "buoyancy": String(format: "%.3f", buoyancy)
        ])
        let data: [String: Any] = [
            "platform": "ios",
            "message": message,
            "response": response,
            "emotion": emotion,
            "buoyancy": String(format: "%.3f", buoyancy),
            "ts": ISO8601DateFormatter().string(from: Date()),
            "uid": uid,
            "sid": useSid
        ]
        if let raw = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: raw, encoding: .utf8) {
            await logPresence(token: "", dataJSON: json)
        }
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
    /// TF120: was only checking the HTTP status code (200-299 = "success"),
    /// but GAS webapps almost always return HTTP 200 even when the operation
    /// failed internally — the script catches its own errors and still
    /// responds normally at the HTTP level. Confirmed by reading the web
    /// app's own equivalent (`viaGas` in index.html): it parses the response
    /// BODY and looks for a real success indicator (`ok`/`commit`/`sha`) or an
    /// explicit `error` field, never trusting the status code alone. This is
    /// exactly why feedback submission could show "SUBMITTED" in the UI while
    /// silently never writing anything — postPlain reported success on any
    /// 200 response regardless of what GAS actually did with the write.
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
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let httpOK = (200...299).contains(code)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // No parseable body — fall back to the HTTP-level signal, same
                // as before, rather than failing writes for endpoints that
                // genuinely don't return a body.
                return httpOK
            }
            let hasError = json["error"] != nil
            let hasSuccessField = (json["ok"] as? Bool) == true || json["commit"] != nil || json["sha"] != nil
            if hasError && !hasSuccessField { return false }
            if !httpOK && !hasSuccessField { return false }
            return true
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
