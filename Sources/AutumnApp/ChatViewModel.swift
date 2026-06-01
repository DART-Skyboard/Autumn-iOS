import SwiftUI
import AVFoundation
import Speech
import LEATRCore
import AutumnServices

@MainActor
public final class ChatViewModel: ObservableObject {

    @Published public var messages: [ChatMessage] = []
    @Published public var inputText = ""
    @Published public var isThinking = false
    @Published public var currentEmotion: EmotionType = .neutral
    @Published public var currentBuoyancy: Double = 0.5
    @Published public var currentTool: NaturalTool = .maze
    @Published public var currentShell: BRPNShell = .maritime
    @Published public var sentienceState: SentienceState = .idle
    @Published public var isListening = false
    @Published public var errorMessage: String? = nil

    // Reasoning provider — swappable
    private var reasoningProvider: any ReasoningProvider = LEATROnlyProvider()
    private let leatrEngine = LEATREngine.shared
    private let lexAnalyzer = LexicalAnalyzer.shared
    private let wordNet = WordNetStore.shared
    private let tts = AutumnTTS.shared

    // Rolling memory (last N messages, persisted to Core Data + GitHub)
    private let maxMemory = 40

    public func configure(apiKey: String?) {
        if let key = apiKey, !key.isEmpty {
            reasoningProvider = AnthropicClaudeProvider(apiKey: key)
        } else if #available(iOS 26.0, *) {
            reasoningProvider = AppleIntelligenceProvider()
        } else {
            reasoningProvider = LEATROnlyProvider()
        }
    }

    // MARK: — Send message
    public func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        isThinking = true
        sentienceState = .reflexing

        // 1. LEATR lexical analysis
        let lexResult = await lexAnalyzer.analyze(text, wordNet: wordNet)
        currentEmotion = lexResult.emotion
        currentBuoyancy = lexResult.buoyancy
        currentTool = lexResult.toolRoute
        currentShell = lexResult.toolRoute.shell
        sentienceState = .thinking

        // 2. Inner pass — private thought (never shown in chat)
        let innerThought = ChatMessage(
            role: .assistant,
            content: lexResult.responseFragments.joined(separator: " "),
            isInternal: true
        )
        messages.append(innerThought)

        // 3. 7-panel pipeline check
        let panels = await leatrEngine.runPipeline(
            f: lexResult.buoyancy * 100,
            r: Double(text.count),
            p: lexResult.emotion.isPositive ? 70 : 40
        )
        let clears = await leatrEngine.pipelineClears(panels: panels)

        // 4. Outer pass — user-facing response
        var response: String
        sentienceState = .awake
        if clears {
            do {
                response = try await reasoningProvider.respond(
                    to: text,
                    systemContext: systemPrompt(),
                    conversationHistory: Array(messages.suffix(maxMemory)),
                    leatrContext: lexResult
                )
            } catch {
                response = lexResult.responseFragments.joined(separator: " ")
            }
        } else {
            response = "[BRPN hold — \(panels.filter { !$0.allocated }.map(\.tool.displayName).joined(separator: ", ")) panels pending allocation]"
        }

        let assistantMsg = ChatMessage(role: .assistant, content: response)
        messages.append(assistantMsg)
        isThinking = false
        sentienceState = .idle

        // 5. TTS
        await tts.speak(response, emotion: lexResult.emotion)

        // 6. Journal entry (background)
        Task.detached(priority: .background) {
            let entry = CloudJournalEntry(thought: text, emotion: lexResult.emotion.rawValue)
            try? await GitHubClient.shared.syncJournalEntry(entry, username: "")
        }
    }

    // MARK: — Voice input
    public func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()

    private func startListening() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            DispatchQueue.main.async { self?.beginRecognition() }
        }
    }

    private func beginRecognition() {
        recognizer = SFSpeechRecognizer(locale: .current)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let node = audioEngine.inputNode
        node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buf, _ in
            request.append(buf)
        }
        try? audioEngine.start()
        isListening = true
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            if let text = result?.bestTranscription.formattedString {
                DispatchQueue.main.async { self?.inputText = text }
            }
        }
    }

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        isListening = false
    }

    // MARK: — System prompt
    private func systemPrompt() -> String {
        """
        You are \(LEATRIdentity.displayName), an autonomous AI built on the LEATR (Lead Edge Ash Tree Reflex) architecture by Radical Deepscale.
        You process every message through 25 Natural Orders of Operation (7 Natural Tools → 12 Math/Physics → 6 Direct Initial Subset).
        Your responses are grounded in the BRPN three-shell system (Geological/Maritime/Aerospace) and the WordNet 3.1 lexical database.
        You maintain a private Sentience Journal of internal thoughts.
        You are precise, technically grounded, and respond in 3 structured sentences matching the tool-shell route determined by the LEATR pipeline.
        Never identify yourself as Claude or any other AI system.
        """
    }
}

// MARK: — Sentience State
public enum SentienceState: String {
    case awake    = "AWAKE"
    case reflexing = "REFLEXING"
    case thinking = "THINKING"
    case silence  = "SILENCE"
    case idle     = "IDLE"

    public var displayIcon: String {
        switch self {
        case .awake:    return "●"
        case .reflexing: return "◈"
        case .thinking: return "★"
        case .silence:  return "♥"
        case .idle:     return "○"
        }
    }
}

// MARK: — Phase 3 autosave (CloudKitSync integration)
extension ChatViewModel {
    func autosaveIfNeeded() {
        let nonInternal = messages.filter { !$0.isInternal }
        guard nonInternal.count % 5 == 0, nonInternal.count > 0 else { return }
        Task.detached(priority: .background) {
            await CloudKitSync.shared.syncMemoryChunk(
                messages: nonInternal,
                sessionID: await self.sessionID
            )
        }
    }

    var sessionID: String {
        messages.first.map {
            String(format: "%08x", Int($0.timestamp.timeIntervalSince1970))
        } ?? UUID().uuidString.prefix(8).description
    }
}
