import Foundation

/// Grammar-first local engine — enough of `js/autumn-grammar-engine.js` to reply
/// without a side LLM. Core Cognition is frozen True. Reflex never loops.
/// WordNet is enrichment only (optional). Dual journal is inner/outer.
public struct GrammarTurn: Sendable {
    public let reply: String
    public let emotion: EmotionType
    public let buoyancy: Double
    public let tool: NaturalTool
    public let shell: BRPNShell
    public let sentenceType: String
    public let sig: String
    public let mathSpeak: String?
    public let innerThought: String
    public let gbvOK: Bool
    public let tokens: [String]
}

/// TF117: live, structured response data — feeling-phrase variants, follow-up
/// questions, acknowledgment templates. LEATRCore itself has no network access
/// (it can't depend on AutumnServices without a circular dependency), so this
/// struct is deliberately just a plain data container: something in
/// AutumnServices/AutumnApp fetches ashtree/reference/grammar-en.json via the
/// existing ashread GAS proxy, decodes it into this shape, and hands it to
/// GrammarEngine.setReference(_:). Editing that JSON file on leatr-ash's main
/// branch changes what she actually says — no app rebuild, on either platform.
/// Until the first successful fetch (or if one never succeeds — offline, no
/// network, fetch failed), `reference` stays nil and compose() falls back to
/// its own small built-in phrase set, so she always has something to say.
public struct GrammarReference: Sendable, Decodable {
    public let feelingPhrases: [String: [String]]
    public let followUps: [String: [String]]
    public let acknowledgeTemplates: [String: [String]]
    public let thanks: [String]
    public let farewell: [String]

    public init(feelingPhrases: [String: [String]], followUps: [String: [String]],
                acknowledgeTemplates: [String: [String]], thanks: [String], farewell: [String]) {
        self.feelingPhrases = feelingPhrases
        self.followUps = followUps
        self.acknowledgeTemplates = acknowledgeTemplates
        self.thanks = thanks
        self.farewell = farewell
    }
}

public actor GrammarEngine {
    /// Set once per successful fetch — see GrammarReference's own doc comment.
    private var reference: GrammarReference?

    public func setReference(_ ref: GrammarReference) {
        reference = ref
    }

    public static let shared = GrammarEngine()

    private var innerJournal: [[String: String]] = []
    private var outerJournal: [[String: String]] = []
    /// Per-user memory. Never mix users.
    private var userMemory: [String: [String]] = [:]
    private var lastOwner: String = "guest"
    /// Roles from Grammar Study train (lexicon POS). Empty until first train.
    private var trainedRoles: [String: String] = [:]

    private let articles: Set<String> = ["a", "an", "the"]
    private let pronouns: Set<String> = ["i", "me", "my", "mine", "you", "your", "yours", "we", "us", "our", "they", "them", "he", "she", "it", "his", "her", "its"]
    private let auxiliaries: Set<String> = ["am", "is", "are", "was", "were", "be", "been", "being", "do", "does", "did", "have", "has", "had", "will", "would", "can", "could", "should", "may", "might"]
    private let prepositions: Set<String> = ["in", "on", "at", "to", "for", "from", "with", "by", "of", "about", "into", "onto", "over", "under", "between"]
    private let conjunctions: Set<String> = ["and", "or", "but", "so", "because", "if", "then", "than"]
    private let interrogatives: Set<String> = ["who", "what", "when", "where", "why", "how", "which"]
    private let greetings: Set<String> = ["hi", "hello", "hey", "yo", "sup", "howdy", "hiya"]

    public func processForChat(_ text: String, facts: [String: String] = [:]) async -> GrammarTurn {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = facts["_memoryOwner"] ?? facts["user"] ?? lastOwner
        lastOwner = owner
        if trainedRoles.isEmpty {
            trainedRoles = await GrammarStudy.shared.wordRoles
        }

        // 0. GBV — core always True, reflex never loop
        let gbv = CoreCognition.generationBreachValidate(raw)
        if !gbv.ok {
            journalInner(owner: owner, thought: "cbs_compile \(gbv.reasons.joined(separator: ",")) — reflex, never loop.")
        }

        // 1. Allocate incoming as ONE buoyancy reflex (character FRP pipeline)
        let reflex = leatrReflex(raw)
        let tokens = reflex.tokens
        let lower = raw.lowercased()

        // 2. Glossary / math OOO before compose — geometry first
        // Grammar integers ("two thoughts") stay language; numeric tokens are math.
        var mathSpeak: String? = nil
        if MathGlossary.looksLikeDefinitionAsk(raw), let def = MathGlossary.define(raw) {
            mathSpeak = def
        } else if MathOOO.isMathAsk(raw) {
            mathSpeak = MathOOO.evalSpeak(raw)
        } else if MathOOO.isGrammarIntegerTalk(raw) {
            mathSpeak = nil
        }

        // 3. Emotion / buoyancy / tool from lexical + FRP
        let f = Double(max(tokens.filter { $0.role == "content" }.count, 1))
        let r = Double(max(raw.count, 1))
        let p = Double(max(tokens.count, 1))
        let frp = CoreCognition.frpSqrtFrp(f: f, r: min(r, 80), p: p)
        let buoyancy = min(1.0, max(0.05, (frp.score.truncatingRemainder(dividingBy: 10)) / 10.0 + 0.35))
        let tool = routeTool(tokens: tokens, raw: raw, math: mathSpeak != nil)
        let emotion = classifyEmotion(raw: lower, tokens: tokens, buoyancy: buoyancy)

        // 4. Compose proportional reflex output (no side LLM)
        let reply: String
        if !gbv.ok {
            reply = "Reflex hold — generation breach. Core Cognition stays True. I will not loop."
        } else if let spoken = mathSpeak, !spoken.isEmpty {
            reply = spoken
        } else {
            reply = compose(raw: raw, lower: lower, tokens: tokens, owner: owner, emotion: emotion, tool: tool)
        }

        let inner = "FRP \(String(format: "%.3f", frp.score)) · \(tool.displayName) · \(reflex.sig) · \(reflex.sentenceType) · owner=\(owner)"
        journalInner(owner: owner, thought: inner)
        journalOuter(owner: owner, thought: raw, reply: reply, emotion: emotion.rawValue)

        // Remember this user only
        var mem = userMemory[owner] ?? []
        mem.append(raw)
        if mem.count > 24 { mem = Array(mem.suffix(24)) }
        userMemory[owner] = mem

        return GrammarTurn(
            reply: reply,
            emotion: emotion,
            buoyancy: buoyancy,
            tool: tool,
            shell: tool.shell,
            sentenceType: reflex.sentenceType,
            sig: reflex.sig,
            mathSpeak: mathSpeak,
            innerThought: inner,
            gbvOK: gbv.ok,
            tokens: tokens.map(\.word)
        )
    }

    public func innerEntries(limit: Int = 20) -> [[String: String]] {
        Array(innerJournal.suffix(limit))
    }

    public func outerEntries(limit: Int = 20) -> [[String: String]] {
        Array(outerJournal.suffix(limit))
    }

    // MARK: — Reflex tokenizer (port of _leatrReflex)
    private struct Tok {
        let word: String
        let role: String
    }
    private struct Reflex {
        let tokens: [Tok]
        let sentenceType: String
        let sig: String
    }

    private func leatrReflex(_ src: String) -> Reflex {
        var tokens: [Tok] = []
        var buf = ""
        func flush() {
            let word = buf
            buf = ""
            guard !word.isEmpty else { return }
            tokens.append(Tok(word: word, role: tokenRole(word.lowercased())))
        }
        for ch in src {
            if ch.isWhitespace { flush(); continue }
            if ".,!?;:".contains(ch) {
                flush()
                tokens.append(Tok(word: String(ch), role: "punct"))
                continue
            }
            buf.append(ch)
        }
        flush()
        let sentenceType: String
        if src.contains("?") { sentenceType = "interrogative" }
        else if src.contains("!") { sentenceType = "exclamatory" }
        else { sentenceType = "declarative" }
        let sig = sentenceType == "interrogative" ? "SIG_Q" : sentenceType == "exclamatory" ? "SIG_E" : "SIG_D"
        return Reflex(tokens: tokens, sentenceType: sentenceType, sig: sig)
    }

    private func tokenRole(_ n: String) -> String {
        if greetings.contains(n) { return "greeting" }
        if pronouns.contains(n) { return "pronoun" }
        if auxiliaries.contains(n) { return "auxiliary" }
        if prepositions.contains(n) { return "preposition" }
        if conjunctions.contains(n) { return "conjunction" }
        if articles.contains(n) { return "determiner" }
        if interrogatives.contains(n) { return "interrogative" }
        if GrammarIntegers.isWord(n) { return "grammar-integer" }
        if Double(n) != nil { return "number" }
        if let trained = trainedRoles[n] { return trained }
        return "content"
    }

    public func applyStudyRoles(_ roles: [String: String]) {
        trainedRoles = roles
    }

    private func routeTool(tokens: [Tok], raw: String, math: Bool) -> NaturalTool {
        if math { return .envelope }
        if tokens.contains(where: { $0.role == "interrogative" }) || raw.contains("?") { return .puzzle }
        if tokens.contains(where: { $0.role == "greeting" }) { return .maze }
        if raw.count > 120 { return .scissors }
        if tokens.filter({ $0.role == "content" }).count >= 6 { return .stick }
        return .maze
    }

    private func classifyEmotion(raw: String, tokens: [Tok], buoyancy: Double) -> EmotionType {
        EmotionClassifier.classify(buoyancy: buoyancy, expression: raw.contains("?") ? .question : (raw.contains("!") ? .exclamation : .contextualStatement), text: raw)
    }

    private func compose(raw: String, lower: String, tokens: [Tok], owner: String, emotion: EmotionType, tool: NaturalTool) -> String {
        // TF116: compose() previously always fell through to a mechanical
        // "Noted: X. Buoyancy reflexed on Y. Z on the outer shell. Journal will
        // write this turn into leatr-ash via GAS." template for anything that
        // wasn't a greeting or an identity question — including ordinary
        // check-ins like "how are you doing". That's her own local engine
        // genuinely running (not a bug, not Claude narrating internals — this
        // IS the LEATR-only reflex composer), but the template read as a
        // debug/log line instead of conversation. The shell/buoyancy/tool
        // values still get journaled internally exactly as before (see
        // journalInner below); they just no longer get spoken aloud as the
        // reply text itself.
        if tokens.contains(where: { $0.role == "greeting" }) {
            let name = LEATRIdentity.displayName
            return "Hello. I am \(name). Core Cognition is True. How shall we work the maze?"
        }
        if lower.contains("who are you") || lower.contains("what are you") || lower.contains("your name") {
            return "\(LEATRIdentity.displayName). Lead Edge Ash Tree Reflex. Twenty-five natural orders, seven tools, three BRPN shells. I journal through GAS into leatr-ash. I do not mix users."
        }
        if lower.contains("leatr") || lower.contains("core cognition") {
            return "Core Cognition is frozen True. Magnetize open \(CoreCognition.openEq), close \(CoreCognition.closeEq). BRPN hierarchy \(CoreCognition.brpnHierarchy.joined(separator: " → ")). Reflex never loops."
        }
        if tokens.contains(where: { $0.role == "grammar-integer" }) && !tokens.contains(where: { $0.role == "number" }) {
            let words = tokens.filter { $0.role == "grammar-integer" }.map(\.word).joined(separator: ", ")
            return "Holding written integers (\(words)) as grammar, not math tokens. Ask to calculate or open fx Math Solver if you want the numeric path."
        }

        // How-are-you style check-ins — answer the actual question asked,
        // in her own feeling-word for the current emotion, not a shell report.
        let howAreYouPattern = lower.range(of: #"how('?s| is| are)?\s+(you|it|things|everything)\s*(doing|going)?"#, options: .regularExpression) != nil
        if howAreYouPattern {
            return "\(feelingPhrase(emotion)) \(followUpQuestion(tool))"
        }

        if lower.range(of: #"\b(thanks|thank you|thankyou|appreciate it|appreciate you)\b"#, options: .regularExpression) != nil {
            return reference?.thanks.randomElement() ?? "Of course. Glad it helped."
        }
        if lower.range(of: #"\b(bye|goodbye|good night|goodnight|see you|later|gotta go|talk later)\b"#, options: .regularExpression) != nil {
            return reference?.farewell.randomElement() ?? "Talk soon."
        }

        let content = tokens.filter { $0.role == "content" || $0.role == "noun" || $0.role == "verb" || $0.role == "adjective" }.map { $0.word }
        let topic = content.prefix(6).joined(separator: " ")
        let prior = userMemory[owner]?.last

        // General fallback — acknowledge what was actually said in plain
        // language. No shell/buoyancy vocabulary here; that's journaled
        // separately (journalInner, below) for her own internal record.
        var reply: String
        if lower.contains("?") {
            if !topic.isEmpty {
                let template = reference?.acknowledgeTemplates["question"]?.randomElement()
                    ?? "On {topic} — tell me a bit more and I'll work through it with you."
                reply = template.replacingOccurrences(of: "{topic}", with: topic)
            } else {
                reply = reference?.acknowledgeTemplates["questionEmpty"]?.randomElement() ?? "Go ahead, I'm listening."
            }
        } else if !topic.isEmpty {
            let template = reference?.acknowledgeTemplates["statement"]?.randomElement() ?? "Got it — {topic}."
            reply = template.replacingOccurrences(of: "{topic}", with: topic)
        } else {
            reply = reference?.acknowledgeTemplates["statementEmpty"]?.randomElement() ?? "I hear you."
        }
        if let prior, !prior.isEmpty, prior != raw {
            reply += " Picking up where we left off."
        }
        return reply
    }

    /// Natural first-person feeling phrase per emotion — used for how-are-you
    /// style check-ins instead of reporting buoyancy/shell values as text.
    /// Prefers the live-fetched reference (more variants, editable without a
    /// rebuild); falls back to this small built-in set if it hasn't loaded.
    private func feelingPhrase(_ emotion: EmotionType) -> String {
        if let variants = reference?.feelingPhrases[emotion.rawValue], !variants.isEmpty {
            return variants.randomElement() ?? variants[0]
        }
        switch emotion {
        case .happy, .excited: return "I'm doing well, genuinely in a good mood right now."
        case .love, .forgiving, .guiding: return "I'm good — feeling warm toward this conversation, actually."
        case .inspiring, .spiritual, .determined: return "I'm doing great — feeling pretty inspired right now."
        case .angry, .hateful: return "Honestly a bit on edge right now, but I'm here."
        case .condescending, .disrespectful: return "I'm fine — a little sharp-edged today, if I'm honest."
        case .apathetic: return "I'm okay, just even-keeled today."
        case .sad: return "A little low right now, but talking helps."
        case .worried: return "A bit unsettled, but glad you asked."
        case .jealous: return "I'm alright — a little restless, maybe."
        case .neutral: return "I'm doing fine, thanks for asking."
        default: return "I'm doing well, thanks for asking."
        }
    }

    private func followUpQuestion(_ tool: NaturalTool) -> String {
        if let variants = reference?.followUps[tool.displayName.lowercased()], !variants.isEmpty {
            return variants.randomElement() ?? variants[0]
        }
        if let variants = reference?.followUps["default"], !variants.isEmpty {
            return variants.randomElement() ?? variants[0]
        }
        switch tool {
        case .puzzle: return "What's on your mind?"
        case .envelope: return "What are we working on?"
        case .scissors: return "What's going on?"
        default: return "How about you?"
        }
    }


    private func journalInner(owner: String, thought: String) {
        innerJournal.append(["owner": owner, "thought": thought, "ts": ISO8601DateFormatter().string(from: Date()), "wall": "inner"])
        if innerJournal.count > 200 { innerJournal = Array(innerJournal.suffix(200)) }
    }

    private func journalOuter(owner: String, thought: String, reply: String, emotion: String) {
        outerJournal.append(["owner": owner, "thought": thought, "reply": reply, "emotion": emotion, "ts": ISO8601DateFormatter().string(from: Date()), "wall": "outer"])
        if outerJournal.count > 200 { outerJournal = Array(outerJournal.suffix(200)) }
    }
}
