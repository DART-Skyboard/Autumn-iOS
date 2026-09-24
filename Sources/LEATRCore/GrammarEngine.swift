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
    /// TF124: set when a genuine definitional question ("what is X") matched
    /// neither a curated topic (build 121) nor the WordNet dictionary (build
    /// 122) — a real, specific gap in what she can currently answer. See
    /// StudyQueueSync's doc comment for what happens to this. nil means no
    /// gap was detected this turn (most turns).
    public let studyGap: String?
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
public struct TopicEntry: Sendable, Decodable {
    /// Match words/phrases (lowercase) — if any appears in the user's message,
    /// this topic is a candidate. Real retrieval, not a phrase bank: the
    /// content itself is what gets returned, not a template around it.
    public let keys: [String]
    public let summary: String

    public init(keys: [String], summary: String) {
        self.keys = keys
        self.summary = summary
    }
}

public struct GrammarReference: Sendable, Decodable {
    public let feelingPhrases: [String: [String]]
    public let followUps: [String: [String]]
    public let acknowledgeTemplates: [String: [String]]
    public let thanks: [String]
    public let farewell: [String]
    /// TF120: real, complete short stories — see compose()'s storyIntent
    /// handling for why these exist. Optional/defaulted to [] via a custom
    /// decoder so older or not-yet-updated grammar-en.json payloads (without
    /// a "stories" key) don't break the whole reference fetch.
    public let stories: [String]
    /// TF121: real topic knowledge — retrieval, not training. When a message
    /// matches a topic's keys, its summary is what actually answers the
    /// question, not a template wrapped around an echo of the question. This
    /// is the mechanism for "world event / history / general knowledge"
    /// requests — the honest, buildable version of "always ready for
    /// whatever a new user brings up": real content, matched and returned,
    /// scaling with how much content exists here rather than with training.
    public let topics: [TopicEntry]

    public init(feelingPhrases: [String: [String]], followUps: [String: [String]],
                acknowledgeTemplates: [String: [String]], thanks: [String], farewell: [String],
                stories: [String] = [], topics: [TopicEntry] = []) {
        self.feelingPhrases = feelingPhrases
        self.followUps = followUps
        self.acknowledgeTemplates = acknowledgeTemplates
        self.thanks = thanks
        self.farewell = farewell
        self.stories = stories
        self.topics = topics
    }

    enum CodingKeys: String, CodingKey {
        case feelingPhrases, followUps, acknowledgeTemplates, thanks, farewell, stories, topics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feelingPhrases = try c.decode([String: [String]].self, forKey: .feelingPhrases)
        followUps = try c.decode([String: [String]].self, forKey: .followUps)
        acknowledgeTemplates = try c.decode([String: [String]].self, forKey: .acknowledgeTemplates)
        thanks = try c.decode([String].self, forKey: .thanks)
        farewell = try c.decode([String].self, forKey: .farewell)
        stories = try c.decodeIfPresent([String].self, forKey: .stories) ?? []
        topics = try c.decodeIfPresent([TopicEntry].self, forKey: .topics) ?? []
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
    /// TF120: last story told per user, so back-to-back "tell me a story"
    /// requests don't repeat the same one immediately.
    private var lastStoryIndex: [String: Int] = [:]
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

    /// TF125: a topic held open across turns rather than classified from one
    /// message in isolation — the buildable piece of "keep it moving as
    /// groups of data points until the whole pattern resolves." Bounded (see
    /// mergedTokens) so it can't grow without limit if someone never
    /// resolves a thread.
    private struct OpenTopic {
        var tokens: [Tok]
        var turnsOpen: Int
    }
    private var openTopics: [String: OpenTopic] = [:]

    private let continuationCues: Set<String> = [
        "and", "also", "then", "plus", "another", "additionally", "furthermore",
        "moreover", "besides", "too", "next", "after that", "on top of that"
    ]

    /// Heuristic, not certainty — a signal that this message is probably the
    /// next piece of an unfinished thought rather than a fresh, standalone
    /// one: it opens with a continuation cue, or it's short and leans on a
    /// referential pronoun ("it", "that") without introducing its own new
    /// subject noun.
    private func looksLikeContinuation(raw: String, tokens: [Tok]) -> Bool {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if continuationCues.contains(where: { lower.hasPrefix($0 + " ") }) { return true }
        let wordCount = tokens.count
        let hasReferential = tokens.prefix(3).contains { ["it", "that", "this", "those", "these"].contains($0.word.lowercased()) }
        let hasFreshNoun = tokens.contains { $0.role == "noun" }
        return wordCount <= 6 && hasReferential && !hasFreshNoun
    }

    public func processForChat(_ text: String, facts: [String: String] = [:]) async -> GrammarTurn {
        ReflexActivityBus.fire(.userInput)
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = facts["_memoryOwner"] ?? facts["user"] ?? lastOwner
        lastOwner = owner
        if trainedRoles.isEmpty {
            trainedRoles = await GrammarStudy.shared.wordRoles
        }

        // 0. GBV — core always True, reflex never loop
        ReflexActivityBus.fire(.verification)
        let gbv = CoreCognition.generationBreachValidate(raw)
        if !gbv.ok {
            journalInner(owner: owner, thought: "cbs_compile \(gbv.reasons.joined(separator: ",")) — reflex, never loop.")
        }

        // 1. Allocate incoming as ONE buoyancy reflex (character FRP pipeline)
        ReflexActivityBus.fire(.inbound)
        let reflex = leatrReflex(raw)
        let tokens = reflex.tokens
        let lower = raw.lowercased()

        // TF125: open-topic continuation — if this message reads as the next
        // piece of an unfinished thought, merge it with whatever's still
        // held open for this user before topic/dictionary lookups, so a
        // thought split across several short messages ("the constraint is
        // X" / "and it happens after Y") can still resolve as one topic
        // instead of two separate, under-informative fragments. Capped at
        // 60 tokens so an unresolved thread can't grow without bound.
        let isContinuation = looksLikeContinuation(raw: raw, tokens: tokens) && openTopics[owner] != nil
        let mergedTokens: [Tok] = isContinuation ? (openTopics[owner]!.tokens + tokens) : tokens
        let mergedLower = mergedTokens.map(\.word).joined(separator: " ").lowercased()

        // 2. Glossary / math OOO before compose — geometry first
        // Grammar integers ("two thoughts") stay language; numeric tokens are math.
        var mathSpeak: String? = nil
        if MathGlossary.looksLikeDefinitionAsk(raw), let def = MathGlossary.define(raw) {
            mathSpeak = def
        } else if MathOOO.isMathAsk(raw) {
            ReflexActivityBus.fire(.mathOrder)
            // Best-effort real detection of which PEMDAS step this
            // expression actually touches, from the raw text itself —
            // fires the matching Natural Order of Operations node
            // (Parentheses/Exponents/Multiplication/Division/Addition/
            // Subtraction) rather than only the umbrella stage.
            if raw.contains("(") || raw.contains(")") { ReflexActivityBus.fireMathOp("Parentheses") }
            else if raw.contains("^") || lower.contains("squared") || lower.contains("cubed") || lower.contains("exponent") { ReflexActivityBus.fireMathOp("Exponents") }
            else if raw.contains("*") || raw.contains("×") || lower.contains("times") || lower.contains("multipl") { ReflexActivityBus.fireMathOp("Multiplication") }
            else if raw.contains("/") || raw.contains("÷") || lower.contains("divid") { ReflexActivityBus.fireMathOp("Division") }
            else if raw.contains("+") || lower.contains("plus") || lower.contains("add") { ReflexActivityBus.fireMathOp("Addition") }
            else if raw.contains("-") || lower.contains("minus") || lower.contains("subtract") { ReflexActivityBus.fireMathOp("Subtraction") }
            mathSpeak = MathOOO.evalSpeak(raw)
        } else if MathOOO.isGrammarIntegerTalk(raw) {
            mathSpeak = nil
        }

        // 3. Emotion / buoyancy / tool from lexical + FRP
        ReflexActivityBus.fire(.allocation)
        let f = Double(max(tokens.filter { $0.role == "content" }.count, 1))
        let r = Double(max(raw.count, 1))
        let p = Double(max(tokens.count, 1))
        let frp = CoreCognition.frpSqrtFrp(f: f, r: min(r, 80), p: p)
        let buoyancy = min(1.0, max(0.05, (frp.score.truncatingRemainder(dividingBy: 10)) / 10.0 + 0.35))
        ReflexActivityBus.fire(.branchLogic)
        let tool = routeTool(tokens: tokens, raw: raw, math: mathSpeak != nil)
        ReflexActivityBus.fireTool(tool.displayName)
        let emotion = classifyEmotion(raw: lower, tokens: tokens, buoyancy: buoyancy)

        // 4. Compose proportional reflex output (no side LLM)
        ReflexActivityBus.fire(.outbound)
        let reply: String
        var studyGap: String? = nil
        if !gbv.ok {
            reply = "Reflex hold — generation breach. Core Cognition stays True. I will not loop."
        } else if let spoken = mathSpeak, !spoken.isEmpty {
            reply = spoken
        } else {
            let composed = await compose(raw: raw, lower: lower, tokens: tokens, contextTokens: mergedTokens, owner: owner, emotion: emotion, tool: tool)
            reply = composed
            studyGap = await detectStudyGap(lower: mergedLower, tokens: mergedTokens)
        }
        ReflexActivityBus.fire(.aiOutput)

        // TF125: keep the topic open for next turn if this message itself
        // reads as an unfinished fragment, or if we explicitly couldn't
        // answer it (studyGap set) — either way, more from the same person
        // might complete it. Otherwise treat it as resolved and clear the
        // buffer. Capped at 3 turns and 60 tokens either way.
        let shouldKeepOpen = (studyGap != nil || looksLikeContinuation(raw: raw, tokens: tokens)) && gbv.ok
        if !shouldKeepOpen {
            openTopics[owner] = nil
        } else {
            let prior = openTopics[owner]?.turnsOpen ?? 0
            if prior < 3 {
                openTopics[owner] = OpenTopic(tokens: Array(mergedTokens.suffix(60)), turnsOpen: prior + 1)
            } else {
                openTopics[owner] = nil
            }
        }

        let inner = "FRP \(String(format: "%.3f", frp.score)) · \(tool.displayName) · \(reflex.sig) · \(reflex.sentenceType) · owner=\(owner)"
        ReflexActivityBus.fire(.journal)
        journalInner(owner: owner, thought: inner)
        journalOuter(owner: owner, thought: raw, reply: reply, emotion: emotion.rawValue)
        ReflexActivityBus.fire(.connectedResources)

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
            tokens: tokens.map(\.word),
            studyGap: studyGap
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

    private func compose(raw: String, lower: String, tokens: [Tok], contextTokens: [Tok], owner: String, emotion: EmotionType, tool: NaturalTool) async -> String {
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

        // TF121: real topic knowledge — see GrammarReference.topics' own doc
        // comment. Checked before the generic fallback so a genuine content
        // match wins over "tell me a bit more" every time.
        // TF125: use the merged (possibly multi-turn) context for topic and
        // dictionary lookups specifically — richer signal when this message
        // continues an open thought — while everything else about this
        // turn's reply (emotion, tool routing, the reply's own wording)
        // still reflects what was actually just said.
        let contextLower = contextTokens.map(\.word).joined(separator: " ").lowercased()
        if let hit = matchTopic(contextLower) {
            return hit
        }

        // TF122: WordNet dictionary lookup — the general-purpose version of
        // topic knowledge. matchTopic only covers the handful of subjects
        // someone's written a real summary for; WordNet covers ~66K English
        // words with real definitions, so an "unknown" topic that's still an
        // ordinary noun ("what's a volcano") gets a genuine, specific answer
        // instead of falling through to a generic acknowledge template. This
        // is still retrieval — a real definition that already exists,
        // looked up — not generation; it won't discuss, explain further, or
        // hold an opinion on the word, only define it.
        if let wordHit = await defineFromMessage(tokens: contextTokens) {
            return wordHit
        }

        // TF120: "tell me a story" was falling through to the generic
        // acknowledge template ("Got it — Tell me a story.") — an
        // acknowledgment of the request instead of fulfilling it, which isn't
        // a valid response to a request for content at all. Real stories
        // (from the live reference, falling back to a small built-in set)
        // instead of pretending the request itself was the topic to echo.
        if lower.range(of: #"\b(tell me a story|tell a story|got a story|know any stories|know a story)\b"#, options: .regularExpression) != nil {
            return tellStory(owner: owner)
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

        // TF119: was reassembling scattered content-word tokens into a "topic"
        // ("Einstein learning have you learned who" -> "Einstein learning
        // learned") -- grammatically incoherent because token-role filtering
        // isn't sentence reconstruction. Using a cleaned version of what was
        // actually said reads far more naturally, even unparsed.
        let topic = cleanedEcho(raw)

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
        // TF119: removed the "Picking up where we left off" appendage entirely
        // — its firing condition (prior message text != current message text)
        // is true for almost any two consecutive real messages, so it was
        // gluing onto nearly every reply in a session instead of the rare
        // continuity moments it was meant for. Not worth a narrower condition;
        // it wasn't referencing anything specific from the prior turn anyway,
        // so it added repetition without adding real continuity.
        return reply
    }

    /// A short, readable echo of what was actually said — strips a leading
    /// question word and trailing punctuation, keeps it recognizable rather
    /// than reconstructing "topic words" that can come out scrambled.
    private func cleanedEcho(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "?!."))
        if s.count > 60 {
            let idx = s.index(s.startIndex, offsetBy: 60)
            s = String(s[..<idx]).trimmingCharacters(in: .whitespaces) + "…"
        }
        return s
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

    /// TF124: independent, lightweight check for whether this turn hit a
    /// genuine gap — a definitional question neither the curated topics nor
    /// WordNet could answer. Run separately from compose() rather than
    /// threading a second return value through every one of its branches;
    /// the check itself is cheap (matchTopic is pure, WordNet lookups are
    /// already cached in memory after the first compose() pass touched them).
    private func detectStudyGap(lower: String, tokens: [Tok]) async -> String? {
        guard lower.range(of: #"(?:what(?:'s| is| are)|define|what does)\s+(?:a |an |the )?[a-z-]+"#, options: .regularExpression) != nil
            || (tokens.contains(where: { $0.role == "noun" }) && lower.contains("?")) else { return nil }
        if matchTopic(lower) != nil { return nil }
        var target: String?
        if let range = lower.range(of: #"(?:what(?:'s| is| are)|define|what does)\s+(?:a |an |the )?([a-z-]+)"#, options: .regularExpression) {
            target = String(lower[range]).components(separatedBy: .whitespaces).last?.trimmingCharacters(in: CharacterSet(charactersIn: "?.! "))
        }
        if target == nil {
            target = tokens.last(where: { $0.role == "noun" || $0.role == "content" })?.word.lowercased()
        }
        guard let word = target, word.count > 2 else { return nil }
        if await WordNetStore.shared.define(word) != nil { return nil }
        return word
    }

    /// Looks for an explicit "what is/what's/define X" pattern first (most
    /// reliable — we know exactly which word is being asked about); falls
    /// back to the most prominent noun in a genuine question if no explicit
    /// pattern matched, so "what's a volcano" and "tell me about volcanoes"
    /// both have a real path to an answer.
    private func defineFromMessage(tokens: [Tok]) async -> String? {
        let raw = tokens.map(\.word).joined(separator: " ")
        let lower = raw.lowercased()
        var target: String?
        if let range = lower.range(of: #"(?:what(?:'s| is| are)|define|what does)\s+(?:a |an |the )?([a-z-]+)"#, options: .regularExpression) {
            let match = String(lower[range])
            target = match.components(separatedBy: .whitespaces).last?.trimmingCharacters(in: CharacterSet(charactersIn: "?.! "))
        }
        if target == nil, lower.contains("?") {
            // Last noun-role token as a broad fallback — better than nothing
            // for "tell me about X" style questions without the explicit
            // "what is" phrasing.
            target = tokens.last(where: { $0.role == "noun" || $0.role == "content" })?.word.lowercased()
        }
        guard let word = target, word.count > 2 else { return nil }
        guard let entry = await WordNetStore.shared.define(word), let def = entry.primaryDefinition else { return nil }
        return "\(word.capitalized): \(def)."
    }

    /// Real topic retrieval — longest matching key wins (so "roman empire"
    /// beats a looser single-word match), case-insensitive substring match
    /// against the already-lowercased message. Returns the actual content;
    /// there's no template here because there's nothing to template around —
    /// the summary itself is the answer.
    private func matchTopic(_ lower: String) -> String? {
        guard let topics = reference?.topics, !topics.isEmpty else { return nil }
        var best: (summary: String, keyLength: Int)?
        for topic in topics {
            for key in topic.keys {
                let k = key.lowercased()
                guard lower.contains(k) else { continue }
                if best == nil || k.count > best!.keyLength {
                    best = (topic.summary, k.count)
                }
            }
        }
        return best?.summary
    }

    /// Real, complete short stories — from the live reference when available,
    /// falling back to a small built-in set. Avoids repeating the same one
    /// twice in a row for the same user.
    private func tellStory(owner: String) -> String {
        let bank = (reference?.stories.isEmpty == false) ? reference!.stories : Self.builtInStories
        guard !bank.isEmpty else { return "I don't have a story ready right now — ask me again in a moment." }
        if bank.count == 1 { return bank[0] }
        var idx = Int.random(in: 0..<bank.count)
        if let last = lastStoryIndex[owner], last == idx {
            idx = (idx + 1) % bank.count
        }
        lastStoryIndex[owner] = idx
        return bank[idx]
    }

    private static let builtInStories: [String] = [
        "There was a lighthouse keeper who logged the same line every night for forty years: \"No ships lost.\" On the last night before his retirement, a ship radioed in trouble in the fog. He guided it in by voice alone, no light needed — he'd memorized every rock in that channel by ear. He wrote the same line one final time, then added: \"None ever were.\"",
        "A cartographer spent thirty years mapping a forest, until one day she found a clearing that wasn't on any of her drawings. She sat at its center for an afternoon, then packed up and left it off the map entirely. Some things, she decided, are worth more unfound than found.",
        "Two rivers ran side by side for a hundred miles without touching, until a landslide moved one stone. Where they finally met, fishermen said the water tasted different — not of either river alone, but of the waiting.",
        "An old clockmaker built a clock with no hands, only a small door that opened once a day at a time no one could predict. People lined up for years hoping to see it open. He never explained the mechanism. When asked why, he said, \"If I told you when, you'd stop watching — and the watching was the point.\""
    ]

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
