import Foundation
import AutumnServices

/// Everyone (not just the admin) reaches Autumn's PRIVATE knowledge base through the existing Apps Script web app (`shell64team`
/// action in presence.gs). It is read-only and one-way: it never writes, never stores user prompts or data, never learns from them,
/// and returns only the derived team plan (record keys). The team state stays on this device and is sent back with the next message.
enum AutumnTeamRelay {
    struct Reply { let text: String; let program: String; let team: Data }

    static func ask(_ text: String, team: Data?) async throws -> Reply {
        guard let endpoint = URL(string: AutumnConfig.gasURL) else { throw URLError(.badURL) }
        var req = URLRequest(url: endpoint); req.httpMethod = "POST"; req.timeoutInterval = 25
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")      // same simple-request shape the other GAS calls use
        var body: [String: Any] = ["action": "shell64team", "text": text]
        if let team, let obj = try? JSONSerialization.jsonObject(with: team) { body["team"] = obj }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any], (o["ok"] as? Bool) == true,
              let t = o["text"] as? String, let p = o["program"] as? String, let tm = o["team"],
              let td = try? JSONSerialization.data(withJSONObject: tm) else { throw URLError(.badServerResponse) }
        return Reply(text: t, program: p, team: td)
    }
}
