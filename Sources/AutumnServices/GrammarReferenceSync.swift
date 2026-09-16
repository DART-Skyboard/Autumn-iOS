import Foundation
import LEATRCore

/// TF117: fetches ashtree/reference/grammar-en.json from leatr-ash (main branch,
/// via the existing no-token ashread GAS proxy) and feeds it into
/// GrammarEngine, so editing that file changes Autumn's actual conversational
/// range with zero app rebuild on either platform — the real version of the
/// "dynamically syncing with the training branch" idea, scoped to something
/// that's actually structured data today (see the file's own _meta.description
/// for why it's separate from Training/grammar's citation catalogs).
///
/// Lives here (AutumnServices), not in LEATRCore, because LEATRCore has no
/// network access by design — GrammarEngine only ever receives already-decoded
/// GrammarReference values, never reaches out itself.
public enum GrammarReferenceSync {
    private static let path = "ashtree/reference/grammar-en.json"

    /// Call once at app launch (and optionally periodically) — safe to call
    /// repeatedly; a failed fetch just leaves GrammarEngine on its existing
    /// reference (or its built-in fallback phrases if this never succeeds).
    public static func fetchAndApply() async {
        guard let raw = await AutumnGASClient.shared.ashread(path: path) else { return }
        guard let jsonText = extractJSONText(from: raw) else { return }
        guard let data = jsonText.data(using: .utf8) else { return }
        guard let ref = try? JSONDecoder().decode(GrammarReference.self, from: data) else { return }
        await GrammarEngine.shared.setReference(ref)
    }

    /// ashread's response shape varies (payload already-decoded vs content as
    /// a raw/base64 string) depending on which path GAS took to find the file
    /// — handle the reasonable variants rather than assuming one.
    private static func extractJSONText(from raw: Any) -> String? {
        if let dict = raw as? [String: Any] {
            if let payload = dict["payload"], !(payload is NSNull) {
                if let s = payload as? String { return s }
                if let d = try? JSONSerialization.data(withJSONObject: payload),
                   let s = String(data: d, encoding: .utf8) { return s }
            }
            if let content = dict["content"] as? String, !content.isEmpty {
                if let decoded = Data(base64Encoded: content.replacingOccurrences(of: "\n", with: "")),
                   let s = String(data: decoded, encoding: .utf8) {
                    return s
                }
                return content
            }
        }
        if let s = raw as? String, !s.isEmpty { return s }
        return nil
    }
}
