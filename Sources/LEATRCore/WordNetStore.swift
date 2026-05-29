import Foundation

public struct WordNetEntry: Sendable, Codable {
    public let word: String
    public let definition: String
    public let synonyms: [String]
    public let partOfSpeech: String
}

// MARK: — WordNet Store
// Lazy-loads 3 JSON buckets (a–h, i–r, s–z) matching the web app's structure.
// Buckets are loaded on first access and cached in memory.
public actor WordNetStore {

    public static let shared = WordNetStore()

    private var buckets: [String: [String: WordNetEntry]] = [:]
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

        // Try bundle first, then remote leatr-ash CDN
        if let url = Bundle.main.url(forResource: name, withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let entries = try JSONDecoder().decode([String: WordNetEntry].self, from: data)
                buckets[name] = entries
                return
            } catch {}
        }

        // Remote fallback: leatr-ash raw GitHub
        let remoteURL = "https://raw.githubusercontent.com/DART-Skyboard/leatr-ash/main/wordnet/\(name).json"
        guard let url = URL(string: remoteURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let entries = try JSONDecoder().decode([String: WordNetEntry].self, from: data)
            buckets[name] = entries
        } catch {
            // Graceful degradation — operate without WordNet
            print("[WordNetStore] Could not load \(name): \(error.localizedDescription)")
        }
    }

    public func lookup(words: [String]) async -> [WordNetEntry] {
        var results: [WordNetEntry] = []
        for word in words {
            guard let bname = bucketName(for: word) else { continue }
            await loadBucket(bname)
            if let entry = buckets[bname]?[word.lowercased()] {
                results.append(entry)
            }
        }
        return results
    }

    public func define(_ word: String) async -> WordNetEntry? {
        guard let bname = bucketName(for: word) else { return nil }
        await loadBucket(bname)
        return buckets[bname]?[word.lowercased()]
    }
}
