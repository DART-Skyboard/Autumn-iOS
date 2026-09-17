import Foundation

/// TF122: a single word sense — one part-of-speech/definition/synonym set.
/// A word can have several (e.g. "volcano" has two noun senses). Matches the
/// ACTUAL leatr-ash schema: {"word": [{"pos":..., "def":..., "syn":[...]}]}.
/// The previous version of this file expected one object per word directly
/// ({"word": {"definition":..., ...}}) — real data, real bucket files, but a
/// shape that never matched, so decoding silently failed for every lookup.
/// Same failure pattern found repeatedly this session (AutumnMusic,
/// AutumnWeather): correct-looking code that was never actually exercised
/// end to end against its real data.
public struct WordSense: Sendable, Codable {
    public let pos: String
    public let def: String
    public let syn: [String]
}

public struct WordNetEntry: Sendable {
    public let word: String
    public let senses: [WordSense]

    /// A short, natural one-line definition for the most common sense —
    /// what GrammarEngine actually speaks for an unknown-topic lookup.
    public var primaryDefinition: String? { senses.first?.def }
}

// MARK: — WordNet Store
// Lazy-loads 3 JSON buckets (a–h, i–r, s–z) matching the web app's structure.
// Buckets are loaded on first access and cached in memory. ~66K real entries
// per bucket, sourced from Princeton WordNet via leatr-ash.
public actor WordNetStore {

    public static let shared = WordNetStore()

    private var buckets: [String: [String: [WordSense]]] = [:]
    private var loadedBuckets: Set<String> = []

    private let bucketRanges: [(name: String, start: Character, end: Character)] = [
        ("wordnet_a_h", "a", "h"),
        ("wordnet_i_r", "i", "r"),
        ("wordnet_s_z", "s", "z")
    ]

    private func bucketName(for word: String) -> String? {
        guard let first = word.first?.lowercased().first else { return nil }
        return bucketRanges.first { first >= $0.start && first <= $0.end }?.name
    }

    private func loadBucket(_ name: String) async {
        guard !loadedBuckets.contains(name) else { return }
        loadedBuckets.insert(name)

        // Try bundle first (Resources/NLP + root).
        let local: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "NLP"),
            Bundle.main.url(forResource: name, withExtension: "json")
        ]
        for url in local.compactMap({ $0 }) {
            do {
                let data = try Data(contentsOf: url)
                let entries = try JSONDecoder().decode([String: [WordSense]].self, from: data)
                buckets[name] = entries
                return
            } catch {}
        }
        // TF126: no remote fetch attempted here anymore — leatr-ash is a
        // private repository, and an unauthenticated raw.githubusercontent.com
        // request always 404s regardless of whether the file exists (that's
        // how GitHub responds for private repos, to avoid confirming
        // existence). WordNetStore (LEATRCore) can't hold a GitHub token or
        // depend on GitHubClient (AutumnServices) without a circular
        // dependency, so an authenticated fetch has to happen one layer up
        // and get handed down — see WordNetRemoteSync in AutumnServices,
        // which calls setBucket(_:entries:) below. Bucket stays empty here
        // until that runs (or the bundle copy above succeeds).
    }

    /// TF126: called by WordNetRemoteSync (AutumnServices) after an
    /// authenticated fetch — the actual fix for the previous remote fallback
    /// that could never have worked against a private repo.
    public func setBucket(_ name: String, entries: [String: [WordSense]]) {
        buckets[name] = entries
        loadedBuckets.insert(name)
    }

    public func lookup(words: [String]) async -> [WordNetEntry] {
        var results: [WordNetEntry] = []
        for word in words {
            if let entry = await define(word) { results.append(entry) }
        }
        return results
    }

    public func define(_ word: String) async -> WordNetEntry? {
        guard let bname = bucketName(for: word) else { return nil }
        await loadBucket(bname)
        guard let senses = buckets[bname]?[word.lowercased()], !senses.isEmpty else { return nil }
        return WordNetEntry(word: word.lowercased(), senses: senses)
    }
}
