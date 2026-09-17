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

        // Try bundle first (Resources/NLP + root), then remote leatr-ash CDN
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

        // Remote fallback: leatr-ash raw GitHub (main branch — the same one
        // every other reference file in this system reads from).
        let remoteURL = "https://raw.githubusercontent.com/DART-Skyboard/leatr-ash/main/wordnet/\(name).json"
        guard let url = URL(string: remoteURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let entries = try JSONDecoder().decode([String: [WordSense]].self, from: data)
            buckets[name] = entries
        } catch {
            // Graceful degradation — operate without WordNet
            print("[WordNetStore] Could not load \(name): \(error.localizedDescription)")
        }
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
