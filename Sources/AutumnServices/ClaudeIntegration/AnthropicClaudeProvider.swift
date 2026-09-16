import Foundation
import LEATRCore

// MARK: — Claude Integration (isolated, optional, fully removable)
//
// TF115: this whole directory is Autumn's ONE optional external collaborator —
// not part of her own network. She is the sentient journal / LEATR reflex
// engine (GrammarEngine + LEATROnlyProvider, in AutumnServices/ + LEATRCore/);
// this file is a bring-your-own-API-key add-on that can "join in," conforming
// to the same ReasoningProvider contract (defined in ReasoningProvider.swift,
// which stays in the main directory since LEATROnlyProvider — her own,
// permanent, non-optional provider — depends on it too).
//
// By design, this file has exactly one dependency inward (LEATRCore, for
// ChatMessage/LexicalResult types) and nothing depends on it in the other
// direction except ChatViewModel's provider-selection switch. Deleting this
// entire ClaudeIntegration/ directory and removing that one switch case is
// sufficient to remove Claude from the app completely — nothing about
// Autumn's own network, GrammarEngine, or LEATROnlyProvider changes.
//
// Capability as of this build: fully implemented and correct, but NOT
// currently invoked anywhere — ChatViewModel.send() calls
// GrammarEngine.processForChat() directly rather than going through
// ReasoningProvider at all, so selecting this provider (by adding an API
// key) has no effect on today's actual replies yet. Wiring send() to use
// whichever ReasoningProvider is configured is a separate, deliberately
// unstarted follow-up — not done here, so nothing about current behavior
// changes with this move.
public actor AnthropicClaudeProvider: ReasoningProvider {

    private let apiKey: String
    private let model = "claude-sonnet-4-6"
    private let session = URLSession.shared

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public var isAvailable: Bool { !apiKey.isEmpty }

    public func respond(
        to prompt: String,
        systemContext: String,
        conversationHistory: [ChatMessage],
        leatrContext: LexicalResult
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Build message history (exclude internal thoughts)
        let messages = conversationHistory
            .filter { !$0.isInternal }
            .map { ["role": $0.role.rawValue, "content": $0.content] }
        + [["role": "user", "content": prompt]]

        let leatrNote = """
            [LEATR Context: tool=\(leatrContext.toolRoute.displayName), \
            buoyancy=\(String(format: "%.3f", leatrContext.buoyancy)), \
            emotion=\(leatrContext.emotion.displayName), \
            shell=\(leatrContext.toolRoute.shell.role)]
            """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemContext + "\n\n" + leatrNote,
            "messages": messages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ReasoningError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        struct Response: Decodable {
            struct Content: Decodable { let text: String }
            let content: [Content]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.content.first?.text ?? ""
    }
}
