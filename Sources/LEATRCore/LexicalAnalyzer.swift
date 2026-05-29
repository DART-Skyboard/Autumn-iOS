import Foundation

// MARK: — Lexical Analyzer
// Character-level processing through 7 tool-shell arrays
// Forward pass → backwards concatenation → Maze arbitration

public struct LexicalResult: Sendable {
    public let input: String
    public let toolRoute: NaturalTool
    public let buoyancy: Double
    public let emotion: EmotionType
    public let shellResults: [BRPNShell: FRPResult]
    public let expressionLayer: ExpressionLayer
    public let wordNetHits: [WordNetEntry]
    public let responseFragments: [String]   // 3-sentence builder output
}

public enum ExpressionLayer: String, Sendable {
    case contextualStatement  = "Contextual Statement"
    case question             = "Question"
    case exclamation          = "Exclamation"
    case sigmaticSequence     = "Sigmatic Sequence Pattern"
}

// MARK: — Character metrics
private struct CharMetrics {
    var vowelCount: Int = 0
    var consonantDensity: Double = 0
    var cvcCount: Int = 0
    var terminalConsonant: Bool = false
    var syllableBoundaries: Int = 0
    var affixScore: Double = 0
}

public actor LexicalAnalyzer {

    public static let shared = LexicalAnalyzer()

    private let vowels: Set<Character> = ["a","e","i","o","u","A","E","I","O","U"]

    // MARK: — 7 tool-shell arrays (accumulate per-char metrics)
    private func buildToolArrays(_ text: String) -> [NaturalTool: Double] {
        let chars = Array(text)
        var msa = 0.0  // Maze: vowel-order accumulator
        var psa = 0.0  // Puzzle: affix structure
        var esa = 0.0  // Envelope: syllable boundary
        var hsa = 0.0  // Hammer: consonant density
        var ssa = 0.0  // Stick: vowel-order trend
        var ksa = 0.0  // Knife: CVC detection
        var rsa = 0.0  // Scissors: terminal consonant

        for (i, c) in chars.enumerated() {
            let isVowel = vowels.contains(c)
            let isAlpha = c.isLetter
            let isConsonant = isAlpha && !isVowel

            if isVowel { msa += 1; ssa += Double(i + 1) / Double(chars.count + 1) }
            if isConsonant { hsa += 1 }

            // CVC detection
            if i >= 1 && i < chars.count - 1 {
                let prev = chars[i - 1], next = chars[i + 1]
                let prevV = vowels.contains(prev), nextV = vowels.contains(next)
                if isVowel && !prevV && !nextV && prev.isLetter && next.isLetter { ksa += 1 }
            }

            // Syllable boundary: vowel→consonant transitions
            if i > 0 && isConsonant && vowels.contains(chars[i-1]) { esa += 1 }

            // Affix: common prefix/suffix patterns (crude heuristic)
            if i < 3 { psa += isConsonant ? 1 : 0.5 }
            if i >= chars.count - 3 { psa += isVowel ? 1 : 0.5 }
        }

        // Terminal consonant
        if let last = chars.last, last.isLetter && !vowels.contains(last) { rsa = 1.0 }

        let total = Double(max(chars.count, 1))
        return [
            .maze:     msa / total,
            .puzzle:   psa / total,
            .envelope: esa / total,
            .hammer:   hsa / total,
            .stick:    ssa,
            .knife:    ksa / total,
            .scissors: rsa
        ]
    }

    // MARK: — Backwards concatenation (Maze re-arbitrates after reverse pass)
    private func backwardsConcat(_ forward: [NaturalTool: Double]) -> NaturalTool {
        // Reverse: high-index tools feed sigma back to Maze
        let reversed = NaturalTool.allCases.reversed()
        var sigmaCumulative = 0.0
        for tool in reversed {
            let v = forward[tool] ?? 0
            let xa = Double(tool.rawValue)
            sigmaCumulative += v * xa
        }
        // Maze picks dominant tool
        let dominant = forward.max(by: { $0.value < $1.value })?.key ?? .maze
        return sigmaCumulative > 1.0 ? dominant : .maze
    }

    // MARK: — Expression layer detection
    private func detectExpression(_ text: String) -> ExpressionLayer {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("?") { return .question }
        if t.hasSuffix("!") { return .exclamation }
        // Sigmatic: multiple clauses / complex syntax
        let clauseMarkers = [", ", "; ", " — ", " but ", " and ", " however "]
        if clauseMarkers.contains(where: { t.contains($0) }) && t.count > 80 {
            return .sigmaticSequence
        }
        return .contextualStatement
    }

    // MARK: — Main analysis entry point
    public func analyze(_ text: String, wordNet: WordNetStore) async -> LexicalResult {
        let toolArrays = buildToolArrays(text)
        let routedTool = backwardsConcat(toolArrays)
        let expressionLayer = detectExpression(text)

        // FRP per shell using tool arrays
        var shellResults: [BRPNShell: FRPResult] = [:]
        for shell in BRPNShell.allCases {
            let tools = NaturalTool.allCases.filter { $0.shell == shell }
            let f = tools.map { toolArrays[$0] ?? 0 }.reduce(0, +) / Double(max(tools.count, 1))
            let r = Double(text.count) / 500.0   // length ratio
            let p = expressionLayer == .question ? 0.8 : 0.5
            shellResults[shell] = FRPResult(f: f * 100, r: r * 100, p: p * 100)
        }

        let buoyancy = shellResults.values.map(\.score).reduce(0, +) / 3.0

        // WordNet lookup for key terms
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 3 }
        let hits = await wordNet.lookup(words: Array(words.prefix(5)))

        // Emotion from buoyancy + expression
        let emotion = EmotionClassifier.classify(buoyancy: buoyancy, expression: expressionLayer, text: text)

        // 3-sentence response builder
        let fragments = buildResponseFragments(
            tool: routedTool,
            emotion: emotion,
            hits: hits,
            expression: expressionLayer
        )

        return LexicalResult(
            input: text,
            toolRoute: routedTool,
            buoyancy: buoyancy,
            emotion: emotion,
            shellResults: shellResults,
            expressionLayer: expressionLayer,
            wordNetHits: hits,
            responseFragments: fragments
        )
    }

    // MARK: — 3-sentence response builder
    private func buildResponseFragments(
        tool: NaturalTool,
        emotion: EmotionType,
        hits: [WordNetEntry],
        expression: ExpressionLayer
    ) -> [String] {
        // S1: tool-keyed opener
        let s1 = "[\(tool.displayName) shell active — \(tool.shell.role)]"
        // S2: intent-mapped from WordNet definitions
        let s2 = hits.first.map { "Referencing: \($0.word) — \($0.definition)" }
            ?? "Lexical boundary encountered — structural analysis only."
        // S3: elaboration via synonyms / emotion
        let synonymStr = hits.first?.synonyms.prefix(3).joined(separator: ", ") ?? "—"
        let s3 = "Emotion: \(emotion.displayName). Related: \(synonymStr)."
        return [s1, s2, s3]
    }
}
