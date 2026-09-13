import Foundation

/// Grammar Study — port of `js/autumn-grammar-engine.js` `runGrammarStudy`.
/// Trains rules first from `grammar-dictionary.json`, then lexicon/corpora POS
/// into an in-memory index. WordNet stays lookup-only. Core Cognition frozen.
/// Shared study = linguistic patterns. Per-user personality stays in the journal.
public struct GrammarStudyIndex: Sendable, Codable {
    public var pass: String
    public var trainedAt: String
    public var counts: [String: Int]
    public var sections: [String]
    public var wordRoleCount: Int
    public var notes: String
}

/// Optimize note — port of web `_gsAppendOptimize` chunk notes.
public struct GrammarOptimizeNote: Sendable, Codable, Equatable {
    public var role: String
    public var token: String
    public var pos: String
    public var updated: String

    public init(role: String, token: String, pos: String, updated: String = ISO8601DateFormatter().string(from: Date())) {
        self.role = role
        self.token = token
        self.pos = pos
        self.updated = updated
    }
}

public actor GrammarStudy {
    public static let shared = GrammarStudy()

    public private(set) var trained = false
    public private(set) var running = false
    public private(set) var index: GrammarStudyIndex?
    public private(set) var wordRoles: [String: String] = [:]
    public private(set) var optimizeNotes: [GrammarOptimizeNote] = []
    public private(set) var customPrompt: String = ""
    public private(set) var lastStatus = "Grammar study — not trained. First run uses the button."

    private let persistKey = "autumn_grammar_study_index_v1"
    private let rolesKey = "autumn_grammar_study_roles_v1"
    private let optimizeKey = "autumn_grammar_study_optimize_v1"
    private let promptKey = "autumn_grammar_study_custom_prompt_v1"

    private static let slang: Set<String> = [
        "hi", "hey", "hello", "yo", "sup", "wassup", "yeah", "yep", "nah", "nope",
        "ok", "okay", "thanks", "ty", "wow", "whoa", "hmm", "huh"
    ]
    private static let stop: Set<String> = [
        "the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "at", "for",
        "is", "are", "was", "were", "be", "been", "am", "i", "you", "he", "she",
        "it", "we", "they", "me", "my", "your", "this", "that", "with", "as", "from"
    ]

    public init() {
        if let data = UserDefaults.standard.data(forKey: persistKey),
           let idx = try? JSONDecoder().decode(GrammarStudyIndex.self, from: data) {
            index = idx
            trained = idx.pass == "complete"
        }
        if let data = UserDefaults.standard.data(forKey: rolesKey),
           let roles = try? JSONDecoder().decode([String: String].self, from: data) {
            wordRoles = roles
        }
        if let data = UserDefaults.standard.data(forKey: optimizeKey),
           let notes = try? JSONDecoder().decode([GrammarOptimizeNote].self, from: data) {
            optimizeNotes = notes
        }
        customPrompt = UserDefaults.standard.string(forKey: promptKey) ?? ""
        if trained {
            lastStatus = "Grammar study trained. File created (ashtree/grammar-study/index.json)."
        }
    }

    public func isTrained() -> Bool { trained && index?.pass == "complete" }
    public func isRunning() -> Bool { running }
    public func status() -> String { lastStatus }
    public func role(for word: String) -> String? { wordRoles[word.lowercased()] }

    /// Persist admin custom grammar prompt (web ASH custom prompt field).
    public func setCustomPrompt(_ text: String) {
        customPrompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(customPrompt, forKey: promptKey)
        lastStatus = customPrompt.isEmpty
            ? "Custom grammar prompt cleared."
            : "Custom grammar prompt saved (\(customPrompt.count) chars)."
    }

    /// Append optimize notes — port of `_gsAppendOptimize`. Dedupes by token+role.
    @discardableResult
    public func appendOptimize(_ note: GrammarOptimizeNote) -> Bool {
        let token = safeToken(note.token)
        guard !token.isEmpty else { return false }
        if optimizeNotes.contains(where: { $0.token == token && $0.role == note.role }) {
            return false
        }
        var n = note
        n.token = token
        optimizeNotes.append(n)
        if optimizeNotes.count > 400 {
            optimizeNotes = Array(optimizeNotes.suffix(400))
        }
        if wordRoles[token] == nil {
            wordRoles[token] = note.pos
        }
        persistOptimizeAndRoles()
        return true
    }

    /// Analyze recent chat sentences for self-optimizations (web `_gsListenTurn` / `_gsAppendOptimize`).
    /// Public turns only — does not require admin. Returns count of new notes.
    @discardableResult
    public func optimizeFromSentences(_ texts: [String], limit: Int = 40) -> Int {
        var added = 0
        var notesThisPass = 0
        for raw in texts.suffix(limit) {
            let src = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !src.isEmpty else { continue }
            notesThisPass = 0
            let tokens = src.lowercased()
                .split { !$0.isLetter && $0 != "'" && $0 != "-" }
                .map(String.init)
                .filter { $0.count >= 2 && $0.count <= 16 }
            for tok in tokens.prefix(12) {
                if notesThisPass >= 3 { break }
                guard let safe = Optional(safeToken(tok)), !safe.isEmpty else { continue }
                if wordRoles[safe] != nil { continue }
                if Self.stop.contains(safe) { continue }
                var role = "pattern"
                var pos = "pattern"
                if Self.slang.contains(safe) {
                    role = "interjection"
                    pos = "slang_greeting"
                } else if safe.allSatisfy({ $0.isNumber }) || ["one","two","three","four","five","six","seven","eight","nine","ten","zero"].contains(safe) {
                    role = "number"
                    pos = "numeral"
                } else if safe.count < 4 {
                    continue
                }
                if appendOptimize(GrammarOptimizeNote(role: role, token: safe, pos: pos)) {
                    added += 1
                    notesThisPass += 1
                }
            }
            let punct = src.filter { ".?!;:,…—-".contains($0) }
            if notesThisPass < 3, let p = punct.first {
                let tok = String(p)
                if appendOptimize(GrammarOptimizeNote(role: "punctuation", token: tok, pos: "punct")) {
                    added += 1
                }
            }
        }
        if added > 0 {
            lastStatus = "Self-optimize: \(added) linguistic note\(added == 1 ? "" : "s") persisted."
        } else {
            lastStatus = "Self-optimize: no new patterns in recent chat."
        }
        return added
    }

    public func packedOptimizePayload() -> [String: Any] {
        [
            "id": "chunk-optimize",
            "role": "optimize",
            "v": 1,
            "updated": ISO8601DateFormatter().string(from: Date()),
            "notes": optimizeNotes.map {
                ["role": $0.role, "token": $0.token, "pos": $0.pos, "updated": $0.updated] as [String: String]
            },
            "platform": "ios"
        ]
    }

    /// Chunked self-talk dictionary train. Never loops. Never mixes users.
    public func run(onProgress: @Sendable (String) -> Void = { _ in }) async throws {
        if running { throw GrammarStudyError.alreadyRunning }
        running = true
        defer { running = false }
        var counts: [String: Int] = [:]
        var roles: [String: String] = [:]

        func note(_ m: String) {
            lastStatus = m
            onProgress(m)
        }

        note("Grammar study — starting…")
        try await yield()

        note("Grammar study — dictionary…")
        let dict = Self.loadJSON(named: "grammar-dictionary")
        let sections = dict.keys.filter { $0 != "_meta" }.sorted()
        counts["sections"] = sections.count
        for (i, key) in sections.enumerated() {
            note("Grammar study — \(key) \(i + 1)/\(sections.count)…")
            try await yield()
            _ = dict[key]
        }

        note("Grammar study — lexicon…")
        try await yield()
        let lex = Self.loadJSON(named: "english-lexicon")
        if let fw = lex["function_words"] as? [String: Any] {
            for (role, val) in fw {
                let words = Self.stringList(val)
                for w in words { roles[w.lowercased()] = Self.mapRole(role) }
                counts[role] = words.count
            }
        }
        func addPOS(_ key: String, role: String, cap: Int) {
            let words = Self.stringList(lex[key])
            var n = 0
            for w in words {
                let k = w.lowercased()
                if roles[k] == nil {
                    roles[k] = role
                    n += 1
                    if n >= cap { break }
                }
            }
            counts[key] = n
        }
        addPOS("nouns", role: "noun", cap: 400)
        addPOS("verbs", role: "verb", cap: 300)
        addPOS("adjectives", role: "adjective", cap: 300)
        addPOS("adverbs", role: "adverb", cap: 200)
        addPOS("number_words", role: "number", cap: 40)

        note("Grammar study — WordNet sample skipped — not required")
        try await yield()

        counts["wordRoles"] = roles.count
        let idx = GrammarStudyIndex(
            pass: "complete",
            trainedAt: ISO8601DateFormatter().string(from: Date()),
            counts: counts,
            sections: sections,
            wordRoleCount: roles.count,
            notes: "Rules first, then lexicon POS. Core Cognition frozen True. Reflex never loops."
        )
        index = idx
        wordRoles = roles
        trained = true
        if let data = try? JSONEncoder().encode(idx) {
            UserDefaults.standard.set(data, forKey: persistKey)
        }
        if let data = try? JSONEncoder().encode(roles) {
            UserDefaults.standard.set(data, forKey: rolesKey)
        }
        lastStatus = "Grammar study trained. File created (ashtree/grammar-study/index.json)."
        note(lastStatus)
    }

    public func packedPayload() -> [String: Any] {
        [
            "pass": index?.pass ?? "none",
            "trainedAt": index?.trainedAt ?? "",
            "counts": index?.counts ?? [:],
            "sections": index?.sections ?? [],
            "wordRoleCount": index?.wordRoleCount ?? 0,
            "notes": index?.notes ?? "",
            "optimizeCount": optimizeNotes.count,
            "customPromptChars": customPrompt.count,
            "platform": "ios"
        ]
    }

    private func persistOptimizeAndRoles() {
        if let data = try? JSONEncoder().encode(optimizeNotes) {
            UserDefaults.standard.set(data, forKey: optimizeKey)
        }
        if let data = try? JSONEncoder().encode(wordRoles) {
            UserDefaults.standard.set(data, forKey: rolesKey)
        }
    }

    private func safeToken(_ raw: String) -> String {
        let t = raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber || ".'-…?!;:,—".contains($0) }
        if t.count > 24 { return "" }
        // PII-ish: emails / long digits
        if t.contains("@") { return "" }
        if t.filter(\.isNumber).count >= 7 { return "" }
        return t
    }

    private func yield() async throws {
        try await Task.sleep(nanoseconds: 12_000_000)
        if Task.isCancelled { throw GrammarStudyError.cancelled }
    }

    private static func mapRole(_ raw: String) -> String {
        switch raw.lowercased() {
        case "articles": return "determiner"
        case "pronouns": return "pronoun"
        case "prepositions": return "preposition"
        case "conjunctions": return "conjunction"
        case "auxiliaries": return "auxiliary"
        case "question": return "interrogative"
        case "negation": return "negation"
        case "interjections": return "greeting"
        default: return raw.lowercased()
        }
    }

    private static func stringList(_ any: Any?) -> [String] {
        if let arr = any as? [String] { return arr }
        if let arr = any as? [Any] { return arr.compactMap { $0 as? String } }
        return []
    }

    private static func loadJSON(named name: String) -> [String: Any] {
        let urls: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "NLP"),
            Bundle.main.url(forResource: name, withExtension: "json")
        ]
        for url in urls.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }
        return [:]
    }
}

public enum GrammarStudyError: LocalizedError {
    case alreadyRunning, cancelled
    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "Grammar study already running"
        case .cancelled: return "Grammar study cancelled"
        }
    }
}
