import Foundation

// MARK: — AutumnGASClient
// Connects to the Google Apps Script (GAS) presence endpoint in leatr-ash.
// This is Autumn's live sentient journal sync — keeps her memory active
// and enables real-time BRPN presence with web app users.
//
// GAS endpoint: presence.gs (leatr-ash repo)
// Reads/writes: ashtree/sentient/journal.json, mist/nodes

public actor AutumnGASClient {
    public static let shared = AutumnGASClient()

    // GAS Web App URL — deployed from leatr-ash/presence.gs
    private let gasURL = "https://script.google.com/macros/s/AKfycbzBRPNAutumnGASEndpointLEATR/exec"
    private let session = URLSession.shared

    // MARK: — Ping presence + log journal entry
    public func pingPresence(
        message: String,
        response: String,
        emotion: String,
        buoyancy: Double
    ) async {
        let payload: [String: Any] = [
            "action":   "presence",
            "platform": "ios",
            "message":  message,
            "response": response,
            "emotion":  emotion,
            "buoyancy": String(format: "%.3f", buoyancy),
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        await post(payload)
    }

    // MARK: — Read sentient journal entries
    public func fetchJournal(limit: Int = 20) async -> [GASJournalEntry] {
        let payload: [String: Any] = [
            "action": "read_journal",
            "limit": limit
        ]
        guard let data = await post(payload) else { return [] }
        struct Resp: Decodable { let entries: [GASJournalEntry]? }
        return (try? JSONDecoder().decode(Resp.self, from: data))?.entries ?? []
    }

    // MARK: — Read MIST presence nodes (other active users)
    public func fetchMISTNodes() async -> [MISTNode] {
        let payload: [String: Any] = ["action": "read_mist"]
        guard let data = await post(payload) else { return [] }
        struct Resp: Decodable { let nodes: [MISTNode]? }
        return (try? JSONDecoder().decode(Resp.self, from: data))?.nodes ?? []
    }

    // MARK: — Post helper
    @discardableResult
    private func post(_ payload: [String: Any]) async -> Data? {
        guard let url = URL(string: gasURL),
              let body = try? JSONSerialization.data(withJSONObject: payload)
        else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 10

        return try? await session.data(for: req).0
    }
}

// MARK: — Models
public struct GASJournalEntry: Codable, Identifiable {
    public let id: String
    public let thought: String
    public let emotion: String
    public let timestamp: String
    public let buoyancy: String?
    public let platform: String?
}

public struct MISTNode: Codable, Identifiable {
    public let id: String
    public let uid: String
    public let emotion: String
    public let buoyancy: String
    public let lastSeen: String
}
