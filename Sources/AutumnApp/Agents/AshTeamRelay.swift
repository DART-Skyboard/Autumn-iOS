import Foundation

/// Public users reach Autumn's PRIVATE knowledge base only through the read-only Shell 64 relay (leatr-ash services/shell64-relay).
/// The relay never writes and never learns from user prompts/data; the team state stays on this device and is sent back each time.
/// Empty `url` = relay not deployed yet: agents stay admin-only.
enum AutumnTeamRelay {
    static let url = ""   // e.g. "https://leatr-shell64-relay.onrender.com"

    struct Reply { let text: String; let program: String; let team: Data }

    static func ask(_ text: String, team: Data?) async throws -> Reply {
        guard let endpoint = URL(string: url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/team") else { throw URLError(.badURL) }
        var req = URLRequest(url: endpoint); req.httpMethod = "POST"; req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["text": text]
        if let team, let obj = try? JSONSerialization.jsonObject(with: team) { body["team"] = obj }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = o["text"] as? String, let p = o["program"] as? String, let tm = o["team"],
              let td = try? JSONSerialization.data(withJSONObject: tm) else { throw URLError(.badServerResponse) }
        return Reply(text: t, program: p, team: td)
    }
}
