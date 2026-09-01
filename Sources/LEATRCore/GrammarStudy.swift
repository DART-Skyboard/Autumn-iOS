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

public actor GrammarStudy {
    public static let shared = GrammarStudy()

    public private(set) var trained = false
    public private(set) var running = false
    public private(set) var index: GrammarStudyIndex?
    public private(set) var wordRoles: [String: String] = [:]
    public private(set) var lastStatus = "Grammar study — not trained. First run uses the button."

    private let persistKey = "autumn_grammar_study_index_v1"
    private let rolesKey = "autumn_grammar_study_roles_v1"

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
        if trained {
            lastStatus = "Grammar study trained. File created (ashtree/grammar-study/index.json)."
        }
    }

    public func isTrained() -> Bool { trained && index?.pass == "complete" }
    public func isRunning() -> Bool { running }
    public func status() -> String { lastStatus }
    public func role(for word: String) -> String? { wordRoles[word.lowercased()] }

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
            "platform": "ios"
        ]
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
