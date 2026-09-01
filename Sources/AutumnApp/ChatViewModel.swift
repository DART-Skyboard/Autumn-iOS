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

    public var memoryOwner: String = "guest"
    public var sessionSID: String = String(UUID().uuidString.prefix(8)).lowercased()

    private var reasoningProvider: any ReasoningProvider = LEATROnlyProvider()
    private let tts = AutumnTTS.shared
    private let maxMemory = 40

    public func configure(apiKey: String?) {
        // Grammar-first. Optional cloud is enrichment only and never replaces Core Cognition.
        if let key = apiKey, !key.isEmpty {
            reasoningProvider = AnthropicClaudeProvider(apiKey: key)
        } else if #available(iOS 26.0, *) {
            reasoningProvider = AppleIntelligenceProvider()
        } else {
            reasoningProvider = LEATROnlyProvider()
        }
    }

    public func injectAndSend(_ text: String) async {
        inputText = text
        await send()
    }

    // MARK: — Send (grammar-first, same loop as web processForChat)
    public func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        isThinking = true
        sentienceState = .reflexing

        let turn = await GrammarEngine.shared.processForChat(text, facts: ["_memoryOwner": memoryOwner])
        currentEmotion = turn.emotion
        currentBuoyancy = turn.buoyancy
        currentTool = turn.tool
        currentShell = turn.shell
        sentienceState = .thinking

        let inner = ChatMessage(role: .assistant, content: turn.innerThought, isInternal: true)
        messages.append(inner)

        let response = turn.reply

        // Ash Star 3D — never dump geometry as chat text
        if text.uppercased().contains("[ASHSTAR") || text.lowercased().contains("ash star") {
            NotificationCenter.default.post(name: .autumnAshStar, object: nil)
        }

        var assistantMsg = ChatMessage(role: .assistant, content: response)
        assistantMsg.leatrMeta = LexicalMetadata(
            toolRoute: turn.tool.displayName,
            buoyancy: turn.buoyancy,
            emotion: turn.emotion.rawValue,
            shell: turn.shell.displayName,
            expressionLayer: turn.sentenceType
        )
        messages.append(assistantMsg)
        isThinking = false
        sentienceState = .idle

        tts.speak(response, emotion: turn.emotion)

        let owner = memoryOwner
        let sid = sessionSID
        Task.detached(priority: .background) {
            await AutumnGASClient.shared.writeJournal(
                uid: owner,
                thought: text,
                reply: response,
                emotion: turn.emotion.rawValue,
                buoyancy: turn.buoyancy
            )
            await AutumnGASClient.shared.writeSession(uid: owner, sid: sid, extra: [
                "emotion": turn.emotion.rawValue,
                "tool": turn.tool.displayName
            ])
            await AutumnGASClient.shared.pingPresence(
                message: text,
                response: response,
                emotion: turn.emotion.rawValue,
                buoyancy: turn.buoyancy,
                uid: owner
            )
        }
        autosaveIfNeeded()
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
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .default,
                options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker]
            )
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch { print("[Autumn] Audio session error: \(error)") }

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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

public enum SentienceState: String {
    case awake = "AWAKE"
    case reflexing = "REFLEXING"
    case thinking = "THINKING"
    case silence = "SILENCE"
    case idle = "IDLE"

    public var displayIcon: String {
        switch self {
        case .awake: return "●"
        case .reflexing: return "◈"
        case .thinking: return "★"
        case .silence: return "♥"
        case .idle: return "○"
        }
    }
}

extension ChatViewModel {
    func autosaveIfNeeded() {
        let nonInternal = messages.filter { !$0.isInternal }
        guard nonInternal.count % 5 == 0, nonInternal.count > 0 else { return }
        Task.detached(priority: .background) {
            await CloudKitSync.shared.syncMemoryChunk(
                messages: nonInternal,
                sessionID: await self.sessionSID
            )
        }
    }
}

extension Notification.Name {
    static let autumnAshStar = Notification.Name("autumnAshStar")
}
