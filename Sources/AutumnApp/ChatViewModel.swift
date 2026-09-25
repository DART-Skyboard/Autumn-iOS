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
    // TF154: real, reactive speaking state — AutumnTTS.isSpeaking is a
    // plain computed property (not @Published), so SwiftUI never redrew on
    // its own when speech started/stopped. Wired through TTS's existing
    // onSpeakingStart/onSpeakingFinish closures instead of polling.
    @Published public var isSpeaking = false
    private var currentSendTask: Task<Void, Never>?
    @Published public var currentEmotion: EmotionType = .neutral
    @Published public var currentBuoyancy: Double = 0.5
    @Published public var currentTool: NaturalTool = .maze
    @Published public var currentShell: BRPNShell = .maritime
    @Published public var sentienceState: SentienceState = .idle
    @Published public var isListening = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingAttachments: [ChatAttachment] = []

    public var memoryOwner: String = "guest"
    public var sessionSID: String = String(UUID().uuidString.prefix(8)).lowercased()

    private var reasoningProvider: any ReasoningProvider = LEATROnlyProvider()
    private let tts = AutumnTTS.shared
    private let maxMemory = 40

    public init() {
        // TF154: reflect TTS's real start/finish into a @Published property
        // so the stop/send button actually redraws when speech begins or
        // ends, rather than only when a new message is processed.
        tts.onSpeakingStart = { [weak self] in
            DispatchQueue.main.async { self?.isSpeaking = true }
        }
        tts.onSpeakingFinish = { [weak self] in
            DispatchQueue.main.async { self?.isSpeaking = false }
        }
    }

    // TF115: AnthropicClaudeProvider lives in AutumnServices/ClaudeIntegration/,
    // isolated so it can be deleted entirely (this switch case included) without
    // touching Autumn's own network (GrammarEngine/LEATROnlyProvider). Note: this
    // selection currently has no effect on actual replies — send() below calls
    // GrammarEngine.processForChat() directly rather than going through
    // reasoningProvider; wiring that up is a separate, not-yet-done follow-up.
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
    public func importFiles(from urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            let name = url.lastPathComponent
            let stored = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
            let dest = ChatAttachment.directory.appendingPathComponent(stored)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                pendingAttachments.append(ChatAttachment(
                    fileName: name,
                    ext: ext,
                    kind: ChatAttachment.kind(for: ext),
                    storedName: stored
                ))
            } catch {
                errorMessage = "Attach failed: \(name)"
            }
        }
    }

    public func removePending(_ id: UUID) {
        if let a = pendingAttachments.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: a.fileURL)
        }
        pendingAttachments.removeAll { $0.id == id }
    }

    public func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = pendingAttachments
        guard !text.isEmpty || !files.isEmpty else { return }
        inputText = ""
        pendingAttachments = []

        // TF154: was echoing raw filenames (autumn-pick-<uuid>...) both in
        // the chat bubble and into what GrammarEngine sees — ugly and,
        // worse, spoken back by TTS. The bubble now shows only the actual
        // message text (the thumbnail/stack already shows what's
        // attached, no text placeholder needed); GrammarEngine gets a
        // plain kind/count signal instead of names, e.g. "[2 images
        // attached]", so a reply can still reference that something was
        // attached without ever surfacing a filename.
        let display = text
        let kindCounts = Dictionary(grouping: files, by: { $0.kind }).mapValues(\.count)
        let kindSummary = kindCounts.map { kind, count in
            count == 1 ? "\(count) \(kind.rawValue)" : "\(count) \(kind.rawValue)s"
        }.joined(separator: ", ")
        let grammar = files.isEmpty ? display : (display.isEmpty ? "[\(kindSummary) attached]" : display + "\n\n[\(kindSummary) attached]")

        let userMsg = ChatMessage(role: .user, content: display, attachments: files)
        messages.append(userMsg)

        let lc = text.lowercased()
        let isSync = lc.range(of: #"\b(backup|back up|sync memory|sync memories|sync all|sync everything|sync my memory|sync the memory|memory sync|commit memory|archive memory|save memory|save data|save all|save to github|sync to github|force save|push memory|push to github)\b"#, options: .regularExpression) != nil
        if isSync {
            isThinking = true
            let save = await AutumnMemorySync.saveAllNow(
                username: memoryOwner,
                sessionUID: sessionSID,
                messages: messages,
                mathJSON: Self.mathSnapshotJSON()
            )
            switch save {
            case .success(let msg):
                messages.append(ChatMessage(role: .assistant, content: msg))
            case .failure(let err):
                messages.append(ChatMessage(role: .assistant, content: "Save failed: \(err.localizedDescription)"))
            }
            isThinking = false
            sentienceState = .idle
            return
        }

        if MathIntent.wantsLatexCanvas(text) {
            let seed = MathIntent.seed(for: text)
            NotificationCenter.default.post(name: .autumnLatexCanvas, object: seed)
        } else if MathIntent.wantsMathSolver(text) {
            NotificationCenter.default.post(name: .autumnMathSolver, object: text)
        }

        isThinking = true
        sentienceState = .reflexing

        // TF118: route to a real, computed answer for anything with an actual
        // capability behind it — see WeatherIntent's own doc comment for why
        // this matters more than it might look (a template can never be a
        // real answer to a factual question; only fetched data can).
        if WeatherIntent.wantsWeather(text) {
            let weatherReply = await WeatherIntent.answer()
            let turn = await GrammarEngine.shared.processForChat(grammar, facts: ["_memoryOwner": memoryOwner])
            guard !Task.isCancelled else { isThinking = false; sentienceState = .idle; return }
            currentEmotion = turn.emotion
            currentBuoyancy = turn.buoyancy
            currentTool = turn.tool
            currentShell = turn.shell
            sentienceState = .idle
            var assistantMsg = ChatMessage(role: .assistant, content: weatherReply)
            assistantMsg.leatrMeta = LexicalMetadata(
                toolRoute: turn.tool.displayName,
                buoyancy: turn.buoyancy,
                emotion: turn.emotion.rawValue,
                shell: turn.shell.displayName,
                expressionLayer: turn.sentenceType
            )
            messages.append(assistantMsg)
            isThinking = false
            tts.speak(weatherReply, emotion: turn.emotion)
            let owner = memoryOwner
            let sid = sessionSID
            Task.detached(priority: .background) {
                await AutumnGASClient.shared.writeJournal(uid: owner, thought: text, reply: weatherReply, emotion: turn.emotion.rawValue, buoyancy: turn.buoyancy)
                await AutumnGASClient.shared.writeSession(uid: owner, sid: sid, extra: ["emotion": turn.emotion.rawValue, "tool": turn.tool.displayName])
            }
            autosaveIfNeeded()
            return
        }

        let turn = await GrammarEngine.shared.processForChat(grammar, facts: ["_memoryOwner": memoryOwner])
        currentEmotion = turn.emotion
        currentBuoyancy = turn.buoyancy
        currentTool = turn.tool
        currentShell = turn.shell
        sentienceState = .thinking

        // TF154: stop button cancels the wrapping Task — checked here so a
        // reply that finished computing after the user hit stop never gets
        // displayed or spoken. The computation itself already ran (LEATR
        // processing isn't internally interruptible), but nothing from it
        // reaches the chat or TTS once cancelled.
        guard !Task.isCancelled else {
            isThinking = false
            sentienceState = .idle
            return
        }

        let inner = ChatMessage(role: .assistant, content: turn.innerThought, isInternal: true)
        messages.append(inner)

        let response = turn.reply

        // Ash Star 3D — never dump geometry or user chat as the star thought.
        let low = (text + " " + response).lowercased()
        if text.uppercased().contains("[ASHSTAR") || low.contains("ash star") || low.contains("send me a star") || low.contains("send a star") {
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
            if let gap = turn.studyGap {
                await AutumnGASClient.shared.writeStudyGap(uid: owner, word: gap, context: text)
            }
            await AutumnGASClient.shared.pingPresence(
                message: text,
                response: response,
                emotion: turn.emotion.rawValue,
                buoyancy: turn.buoyancy,
                uid: owner,
                sid: sid
            )
        }
        autosaveIfNeeded()
    }

    // MARK: — Stop / send toggle
    // TF154: the composer's button is a send button when idle, and a stop
    // button whenever there's something to interrupt — either Autumn is
    // still processing, or she's speaking the previous reply out loud
    // (someone who's heard enough of a long answer should be able to cut
    // it off, not just wait it out). Tapping stop cancels the in-flight
    // send() and halts speech; the button reverts to send immediately,
    // ready to take a new message to pick up from there.
    public var isBusyOrSpeaking: Bool { isThinking || isSpeaking }

    public func sendTapped() {
        currentSendTask = Task { await self.send() }
    }

    public func stopProcessingOrSpeaking() {
        currentSendTask?.cancel()
        currentSendTask = nil
        tts.stop()
        isThinking = false
        isSpeaking = false
        sentienceState = .idle
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

extension ChatViewModel {
    static func mathSnapshotJSON() -> String? {
        let snap = MathWorkspaceHolder.current.snapshot()
        guard let data = try? JSONEncoder().encode(snap) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension Notification.Name {
    static let autumnAshStar = Notification.Name("autumnAshStar")
    static let autumnLatexCanvas = Notification.Name("autumnLatexCanvas")
    static let autumnMathSolver = Notification.Name("autumnMathSolver")
}
