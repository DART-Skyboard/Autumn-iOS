import Foundation

/// One mailbox for all types (feedback, user mail, other apps).
/// Folders: inbox / analysis / read / trash.
/// Paths: `feedback/inbox.json` or `feedback/{folder}.json` — OTHER APPS depend on inbox.json.
/// Submit still GAS-ashwrites inbox.json append `{id,ts,cat,msg,user}`.
public struct FeedbackEntry: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var ts: String
    public var cat: String
    public var msg: String
    public var user: String

    public init(id: String, ts: String, cat: String, msg: String, user: String) {
        self.id = id; self.ts = ts; self.cat = cat; self.msg = msg; self.user = user
    }

    enum CodingKeys: String, CodingKey {
        case id, ts, cat, msg, user, type, kind, from, app, source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        ts = try c.decodeIfPresent(String.self, forKey: .ts) ?? ""
        cat = try c.decodeIfPresent(String.self, forKey: .cat)
            ?? c.decodeIfPresent(String.self, forKey: .type)
            ?? c.decodeIfPresent(String.self, forKey: .kind)
            ?? "MESSAGE"
        msg = try c.decodeIfPresent(String.self, forKey: .msg) ?? ""
        user = try c.decodeIfPresent(String.self, forKey: .user)
            ?? c.decodeIfPresent(String.self, forKey: .from)
            ?? c.decodeIfPresent(String.self, forKey: .app)
            ?? c.decodeIfPresent(String.self, forKey: .source)
            ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ts, forKey: .ts)
        try c.encode(cat, forKey: .cat)
        try c.encode(msg, forKey: .msg)
        try c.encode(user, forKey: .user)
    }
}

public enum MailboxFolder: String, CaseIterable, Sendable {
    case inbox, analysis, read, trash
    public var path: String {
        self == .inbox ? AutumnConfig.feedbackInboxPath : "feedback/\(rawValue).json"
    }
}

public struct MailboxSnapshot: Sendable {
    public var folder: MailboxFolder
    public var entries: [FeedbackEntry]
    public init(folder: MailboxFolder, entries: [FeedbackEntry]) {
        self.folder = folder; self.entries = entries
    }
}

public actor FeedbackService {
    public static let shared = FeedbackService()
    public static let categories = ["BUG REPORT", "FEATURE REQUEST", "GENERAL", "OTHER"]

    public func submit(msg: String, cat: String, user: String, uid: String) async throws {
        let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FeedbackError.empty }
        let entry = FeedbackEntry(
            id: String(Int(Date().timeIntervalSince1970 * 1000), radix: 16) + "-" + String(Int.random(in: 0x1000...0xffff), radix: 16),
            ts: ISO8601DateFormatter().string(from: Date()),
            cat: cat,
            msg: String(trimmed.prefix(1000)),
            user: user.isEmpty ? "guest" : user
        )
        let ok = await AutumnGASClient.shared.submitFeedback(
            id: entry.id, ts: entry.ts, cat: entry.cat, msg: entry.msg, user: entry.user, uid: uid.isEmpty ? "guest" : uid
        )
        if !ok { throw FeedbackError.submitFailed }
    }

    public func loadInbox() async throws -> [FeedbackEntry] {
        try await loadFolder(.inbox).entries
    }

    public func loadFolder(_ folder: MailboxFolder) async throws -> MailboxSnapshot {
        if let parsed = await readViaGAS(folder.path) {
            return MailboxSnapshot(folder: folder, entries: parsed)
        }
        do {
            let file = try await GitHubClient.shared.readFile(
                owner: AutumnConfig.ashOwner,
                repo: AutumnConfig.ashRepo,
                path: folder.path
            )
            return MailboxSnapshot(folder: folder, entries: Self.decodeEntries(file.decodedContent))
        } catch {
            return MailboxSnapshot(folder: folder, entries: [])
        }
    }

    public func replaceFolder(_ folder: MailboxFolder, entries: [FeedbackEntry], uid: String, message: String) async throws {
        let payload = entries.map { ["id": $0.id, "ts": $0.ts, "cat": $0.cat, "msg": $0.msg, "user": $0.user] }
        let ok = await AutumnGASClient.shared.ashwriteReplace(path: folder.path, uid: uid, payload: payload, message: message)
        if !ok { throw FeedbackError.submitFailed }
    }

    public func move(entries: [FeedbackEntry], from: MailboxFolder, to: MailboxFolder, remaining: [FeedbackEntry], uid: String) async throws {
        var dest = try await loadFolder(to).entries
        dest.append(contentsOf: entries)
        try await replaceFolder(to, entries: dest, uid: uid, message: "feedback: receive entries in \(to.rawValue)")
        try await replaceFolder(from, entries: remaining, uid: uid, message: "feedback: move \(entries.count) entry to \(to.rawValue)")
    }

    public func delete(remaining: [FeedbackEntry], folder: MailboxFolder, uid: String, count: Int) async throws {
        try await replaceFolder(folder, entries: remaining, uid: uid, message: "feedback: delete \(count) entry")
    }

    private func readViaGAS(_ path: String) async -> [FeedbackEntry]? {
        guard let any = await AutumnGASClient.shared.ashread(path: path) else { return nil }
        return Self.coerce(any)
    }

    static func coerce(_ any: Any) -> [FeedbackEntry]? {
        if let arr = any as? [Any] { return decodeJSONArray(arr) }
        guard let dict = any as? [String: Any] else { return nil }
        if let arr = dict["data"] as? [Any] { return decodeJSONArray(arr) }
        if let arr = dict["payload"] as? [Any] { return decodeJSONArray(arr) }
        if let arr = dict["entries"] as? [Any] { return decodeJSONArray(arr) }
        if let content = dict["content"] as? String {
            return decodeEntries(base64Loose(content))
        }
        if dict["error"] != nil || dict["message"] != nil { return nil }
        return nil
    }

    static func decodeJSONArray(_ arr: [Any]) -> [FeedbackEntry] {
        guard let data = try? JSONSerialization.data(withJSONObject: arr) else { return [] }
        return (try? JSONDecoder().decode([FeedbackEntry].self, from: data)) ?? []
    }

    static func decodeEntries(_ raw: String?) -> [FeedbackEntry] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        if let arr = try? JSONDecoder().decode([FeedbackEntry].self, from: data) { return arr }
        struct Wrap: Decodable { let entries: [FeedbackEntry]? }
        return (try? JSONDecoder().decode(Wrap.self, from: data))?.entries ?? []
    }

    static func base64Loose(_ c: String) -> String? {
        let cleaned = c.replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: cleaned) else { return c }
        return String(data: data, encoding: .utf8)
    }
}

public enum FeedbackError: LocalizedError {
    case empty, submitFailed
    public var errorDescription: String? {
        switch self {
        case .empty: return "Please enter a message"
        case .submitFailed: return "Submission failed — please try again"
        }
    }
}
