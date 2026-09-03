import Foundation
import LEATRCore

// MARK: — ReasoningProvider Protocol
// Swappable: on-device Foundation Models (primary) or remote Claude (fallback)
public protocol ReasoningProvider: Actor {
    func respond(
        to prompt: String,
        systemContext: String,
        conversationHistory: [ChatMessage],
        leatrContext: LexicalResult
    ) async throws -> String

    var isAvailable: Bool { get async }
}

// MARK: — Chat attachment (web #img-file-input accept list + CAD/USDZ)
public struct ChatAttachment: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var fileName: String
    public var ext: String
    public var kind: Kind
    public var storedName: String

    public enum Kind: String, Sendable, Codable {
        case image, video, audio, model3d, cad, script, document, other
    }

    public init(fileName: String, ext: String, kind: Kind, storedName: String) {
        self.id = UUID()
        self.fileName = fileName
        self.ext = ext
        self.kind = kind
        self.storedName = storedName
    }

    public var fileURL: URL { ChatAttachment.directory.appendingPathComponent(storedName) }

    public static var directory: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat-attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    public static func kind(for ext: String) -> Kind {
        let e = ext.lowercased()
        if ["png","jpg","jpeg","gif","webp","bmp","heic","heif","tif","tiff","svg"].contains(e) { return .image }
        if ["mp4","mov","m4v","webm","avi","mkv"].contains(e) { return .video }
        if ["mp3","wav","ogg","flac","m4a","aac","opus","aiff","caf"].contains(e) { return .audio }
        if ["glb","gltf","obj","stl","fbx","dae","usdz","usda","usdc","ply","3ds","blend"].contains(e) { return .model3d }
        if ["step","stp","iges","igs","sat","dwg","dxf","3dm","sldprt","sldasm","ipt","iam","prt","catpart","catproduct","x_t","x_b"].contains(e) { return .cad }
        if ["html","htm","js","ts","json","css","xml","yaml","yml","py","java","c","cpp","h","hpp","rs","rb","go","php","sh","swift","sql","toml","ini","md","kt"].contains(e) { return .script }
        if ["pdf","txt","doc","docx","rtf","odt","csv","log","pages"].contains(e) { return .document }
        return .other
    }

    public var badge: String {
        switch kind {
        case .image: return "IMG"
        case .video: return "VIDEO"
        case .audio: return "AUDIO"
        case .model3d: return "3D"
        case .cad: return "CAD"
        case .script: return ext.uppercased()
        case .document: return ext.uppercased()
        case .other: return ext.uppercased()
        }
    }

    public var glyph: String {
        switch kind {
        case .image: return "🖼"
        case .video: return "▶"
        case .audio: return "🎵"
        case .model3d: return "◈"
        case .cad: return "⬡"
        case .script: return "</>"
        case .document: return "📄"
        case .other: return "📎"
        }
    }
}

// MARK: — Chat Message
public struct ChatMessage: Identifiable, Sendable, Codable {
    public let id: UUID
    public var role: Role
    public var content: String
    public var timestamp: Date
    public var leatrMeta: LexicalMetadata?
    public var isInternal: Bool   // _internal:true → private thoughts, never surfaced
    public var attachments: [ChatAttachment]

    public enum Role: String, Sendable, Codable {
        case user, assistant, system
    }

    public init(role: Role, content: String, isInternal: Bool = false, attachments: [ChatAttachment] = []) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isInternal = isInternal
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, leatrMeta, isInternal, attachments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        leatrMeta = try c.decodeIfPresent(LexicalMetadata.self, forKey: .leatrMeta)
        isInternal = try c.decodeIfPresent(Bool.self, forKey: .isInternal) ?? false
        attachments = try c.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
    }
}

public struct LexicalMetadata: Sendable, Codable {
    public let toolRoute: String
    public let buoyancy: Double
    public let emotion: String
    public let shell: String
    public let expressionLayer: String

    public init(toolRoute: String, buoyancy: Double, emotion: String, shell: String, expressionLayer: String) {
        self.toolRoute = toolRoute
        self.buoyancy = buoyancy
        self.emotion = emotion
        self.shell = shell
        self.expressionLayer = expressionLayer
    }
}

// MARK: — Apple Foundation Models Provider
// Requires iOS 26+ / Foundation Models framework
// Falls back gracefully when unavailable
public actor AppleIntelligenceProvider: ReasoningProvider {
    private let apiKey: String
    public init(apiKey: String = "") { self.apiKey = apiKey }

    public var isAvailable: Bool {
        get async {
            // Foundation Models availability check
            // FoundationModels.SystemLanguageModel.default.availability == .available
            // Compiled as runtime check for backward compat with iOS 17/18 targets
            if #available(iOS 26.0, *) {
                return true  // Will be gated by actual FM availability at runtime
            }
            return false
        }
    }

    public func respond(
        to prompt: String,
        systemContext: String,
        conversationHistory: [ChatMessage],
        leatrContext: LexicalResult
    ) async throws -> String {
        if #available(iOS 26.0, *) {
            return try await runFoundationModel(
                prompt: prompt,
                system: systemContext,
                history: conversationHistory,
                leatr: leatrContext
            )
        } else {
            throw ReasoningError.unavailable
        }
    }

    @available(iOS 26.0, *)
    private func runFoundationModel(
        prompt: String,
        system: String,
        history: [ChatMessage],
        leatr: LexicalResult
    ) async throws -> String {
        // FoundationModels API — dynamically linked to avoid compile error on iOS <26
        // At runtime on iOS 26+: import FoundationModels
        // let session = LanguageModelSession(instructions: system)
        // let response = try await session.respond(to: prompt)
        // return response.content

        // Placeholder until Foundation Models framework is available in toolchain
        // Replace this block with actual FM calls when building on Xcode 26+
        return "[Foundation Models response placeholder — build with Xcode 26+ to activate]"
    }
}

// MARK: — Anthropic Claude Provider (fallback / power users)
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

// MARK: — LEATR-only Provider (fully offline, no cloud)
public actor LEATROnlyProvider: ReasoningProvider {
    public init() {}
    public var isAvailable: Bool { true }

    public func respond(
        to prompt: String,
        systemContext: String,
        conversationHistory: [ChatMessage],
        leatrContext: LexicalResult
    ) async throws -> String {
        leatrContext.responseFragments.joined(separator: " ")
    }
}

// MARK: — Errors
public enum ReasoningError: LocalizedError {
    case unavailable
    case httpError(Int)
    case decodingError

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Reasoning provider unavailable on this device."
        case .httpError(let code): return "API error \(code)."
        case .decodingError: return "Response decoding failed."
        }
    }
}