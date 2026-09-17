import Foundation
import LEATRCore

/// TF126: authenticated fetch for WordNet's three bucket files, replacing
/// build 122's anonymous raw.githubusercontent.com attempt — leatr-ash is a
/// private repository, so that request always 404'd regardless of whether
/// the file existed (GitHub's deliberate behavior for private repos, to
/// avoid confirming existence to an unauthenticated caller). This uses
/// GitHubClient's already-stored token (from GitHub sign-in) via the
/// Contents API instead.
///
/// Lives here, not in LEATRCore, for the same reason GrammarReferenceSync
/// does: WordNetStore has no network access by design.
public enum WordNetRemoteSync {
    private static let buckets = ["wordnet_a_h", "wordnet_i_r", "wordnet_s_z"]

    /// Call once at app launch, alongside GrammarReferenceSync. Safe to call
    /// repeatedly — buckets already loaded (bundle or a prior successful
    /// fetch) are skipped by WordNetStore internally via loadedBuckets.
    public static func fetchAndApply() async {
        // Only attempt this if signed in — an unauthenticated attempt would
        // 404 identically to before, so there's nothing to gain from trying.
        guard await GitHubClient.shared.hasToken() else { return }
        for name in buckets {
            do {
                let obj = try await GitHubClient.shared.readJSON(
                    owner: "DART-Skyboard", repo: "leatr-ash",
                    path: "wordnet/\(name).json"
                )
                guard let data = try? JSONSerialization.data(withJSONObject: obj) else { continue }
                let entries = try JSONDecoder().decode([String: [WordSense]].self, from: data)
                await WordNetStore.shared.setBucket(name, entries: entries)
            } catch {
                // Graceful degradation — that bucket just stays unavailable;
                // GrammarEngine's definition lookups already handle a miss.
            }
        }
    }
}
