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

    /// TF113: the web app's admin console tries these paths in order for the
    /// ANALYSIS folder (it's been renamed a couple of times over the app's
    /// history — `_admFbLegacyPaths` in index.html) and uses whichever actually
    /// has entries. iOS only ever checked the current name, so a user whose
    /// existing analysis messages are still under one of the earlier filenames
    /// saw "0 entries" here despite the data genuinely being there in leatr-ash.
    public var legacyPaths: [String] {
        switch self {
        case .analysis:
            return ["feedback/analysis.json", "feedback/archive.json",
                    "feedback/inbox-archive.json", "feedback/inbox_archive.json"]
        default:
            return [path]
        }
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
        // TF113: try the primary path first — if it already has entries, we're
        // done (matches web's behavior and avoids the extra round-trips on the
        // common case). Only fall through to the legacy paths when it's empty.
        let primaryEntries = await loadPath(folder.path)
        if !primaryEntries.isEmpty || folder.legacyPaths.count < 2 {
            return MailboxSnapshot(folder: folder, entries: primaryEntries)
        }
        var best = primaryEntries
        for path in folder.legacyPaths.dropFirst() {
            let entries = await loadPath(path)
            if entries.count > best.count { best = entries }
        }
        return MailboxSnapshot(folder: folder, entries: best)
    }

    /// Reads one exact path — GAS first, then a direct GitHub read as fallback.
    private func loadPath(_ path: String) async -> [FeedbackEntry] {
        // TF133: the real bug. readViaGAS returns non-nil whenever coerce
        // produces *any* array, including an empty one from a swallowed
        // JSONDecoder failure (decodeJSONArray uses `try?` internally,
        // turning a genuine decode mismatch into a silent []). Because this
        // was `if let parsed = ... { return parsed }`, a non-nil-but-empty
        // result was accepted as final and NEVER fell through to the
        // GitHub direct-read fallback — even though that fallback works
        // fine and the file genuinely has real entries. This is almost
        // certainly why analysis.json showed "0 entries" for real, present
        // data: GAS's response reached coerce in a shape that decoded to
        // [] rather than nil, and the working fallback path never ran.
        //
        // TF135: build 133's fix ran the two attempts sequentially — try
        // GAS (up to its own ~12s timeout), and only if that comes back
        // empty, then try GitHub (up to another ~12s). Two sequential ~12s
        // attempts can easily exceed the mailbox's overall 15s timeout
        // (AdminDrawerView's withTimeout), which would make the timeout
        // MORE likely after 133, not less — worth being upfront that my own
        // fix probably made this specific symptom worse before this build
        // made it better. Now genuinely concurrent: both attempts start at
        // once: total wait is whichever finishes first, roughly halving
        // worst-case latency, and GAS is still preferred when both succeed.
        async let gasResult = readViaGAS(path)
        async let githubResult: [FeedbackEntry] = {
            do {
                let file = try await GitHubClient.shared.readFile(
                    owner: AutumnConfig.ashOwner,
                    repo: AutumnConfig.ashRepo,
                    path: path
                )
                return Self.decodeEntries(file.decodedContent)
            } catch {
                return []
            }
        }()
        let gas = await gasResult
        if let gas, !gas.isEmpty { return gas }
        let github = await githubResult
        if github.isEmpty {
            Self.lastReadDiagnostic = "Both paths empty for \(path): GAS \(gas == nil ? "returned nil" : "coerced to []") (\(Self.lastReadDiagnostic ?? "?")); GitHub also decoded to 0"
        }
        return github
    }

    public func replaceFolder(_ folder: MailboxFolder, entries: [FeedbackEntry], uid: String, message: String) async throws {
        let intentional = message.range(of: "move|delete|unread|receive", options: [.regularExpression, .caseInsensitive]) != nil
        if entries.isEmpty && !intentional {
            throw FeedbackError.refusedEmpty
        }
        let payload = entries.map { ["id": $0.id, "ts": $0.ts, "cat": $0.cat, "msg": $0.msg, "user": $0.user] }
        let ok = await AutumnGASClient.shared.ashwriteReplace(path: folder.path, uid: uid, payload: payload, message: message)
        if !ok { throw FeedbackError.submitFailed }
    }

    public func move(entries: [FeedbackEntry], from: MailboxFolder, to: MailboxFolder, remaining: [FeedbackEntry], uid: String) async throws {
        guard await AdminCircuitStore.shared.allows(
            username: uid, githubConnected: true, adminEnabled: true
        ) else { throw FeedbackError.circuitOpen }
        var dest = try await loadFolder(to).entries
        dest.append(contentsOf: entries)
        try await replaceFolder(to, entries: dest, uid: uid, message: "feedback: receive entries in \(to.rawValue)")
        try await replaceFolder(from, entries: remaining, uid: uid, message: "feedback: move \(entries.count) entry to \(to.rawValue)")
    }

    /// Permanent delete only from trash. Other folders move to trash first.
    public func delete(remaining: [FeedbackEntry], folder: MailboxFolder, uid: String, count: Int) async throws {
        guard await AdminCircuitStore.shared.allows(
            username: uid, githubConnected: true, adminEnabled: true
        ) else { throw FeedbackError.circuitOpen }
        if folder != .trash {
            throw FeedbackError.trashLast
        }
        try await replaceFolder(folder, entries: remaining, uid: uid, message: "feedback: delete \(count) entry")
    }

    /// TF133: diagnostic breadcrumb for the "shows 0 entries despite real
    /// data existing" mystery from build 118 — never actually root-caused
    /// there, because the failure was silent: coerce() returning nil/empty
    /// looked identical whether GAS returned an error, an unrecognized
    /// shape, or genuinely nothing. This captures what actually came back
    /// so the next occurrence is diagnosable instead of another guess.
    public static var lastReadDiagnostic: String?

    private func readViaGAS(_ path: String) async -> [FeedbackEntry]? {
        guard let any = await AutumnGASClient.shared.ashread(path: path) else {
            Self.lastReadDiagnostic = "ashread(\(path)) returned nil — no response or request failed"
            return nil
        }
        let result = Self.coerce(any)
        if result?.isEmpty ?? true {
            Self.lastReadDiagnostic = "ashread(\(path)) returned \(Self.describeShape(any))"
        }
        return result
    }

    private static func describeShape(_ any: Any) -> String {
        if let dict = any as? [String: Any] {
            let keys = dict.keys.sorted().joined(separator: ",")
            if let err = dict["error"] { return "error dict: \(err)" }
            return "dict with keys [\(keys)]"
        }
        if let arr = any as? [Any] { return "array of \(arr.count) items, first: \(arr.first.map { "\($0)".prefix(80) } ?? "n/a")" }
        return "unrecognized type: \(type(of: any))"
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
    case empty, submitFailed, refusedEmpty, trashLast, circuitOpen
    public var errorDescription: String? {
        switch self {
        case .empty: return "Please enter a message"
        case .submitFailed: return "Submission failed — please try again"
        case .refusedEmpty: return "Refusing to PUT [] over a folder"
        case .trashLast: return "Permanent delete only from trash"
        case .circuitOpen: return "Admin circuit open — web must be live"
        }
    }
}
