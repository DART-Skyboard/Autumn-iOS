import Foundation

// MARK: — 21 Emotion Types
public enum EmotionType: String, CaseIterable, Sendable {
    // Positive (8)
    case happy        = "happy"
    case love         = "love"
    case inspiring    = "inspiring"
    case determined   = "determined"
    case spiritual    = "spiritual"
    case guiding      = "guiding"
    case forgiving    = "forgiving"
    case excited      = "excited"
    // Negative (5)
    case angry        = "angry"
    case hateful      = "hateful"
    case condescending = "condescending"
    case disrespectful = "disrespectful"
    case apathetic    = "apathetic"
    // Neutral/Complex (8)
    case neutral      = "neutral"
    case sad          = "sad"
    case worried      = "worried"
    case jealous      = "jealous"
    case lucrative    = "lucrative"
    case concerned    = "concerned"
    case judgemental  = "judgemental"
    case confused     = "confused"

    public var displayName: String { rawValue.capitalized }

    public var isPositive: Bool {
        [.happy, .love, .inspiring, .determined, .spiritual, .guiding, .forgiving, .excited].contains(self)
    }
    public var isNegative: Bool {
        [.angry, .hateful, .condescending, .disrespectful, .apathetic].contains(self)
    }

    public var accentHex: String {
        switch self {
        case .happy:         return "#FFD700"
        case .love:          return "#FF69B4"
        case .inspiring:     return "#00E5FF"
        case .determined:    return "#FF8C00"
        case .spiritual:     return "#9B59B6"
        case .guiding:       return "#2ECC71"
        case .forgiving:     return "#87CEEB"
        case .excited:       return "#FF4500"
        case .angry:         return "#FF0000"
        case .hateful:       return "#8B0000"
        case .condescending: return "#A0522D"
        case .disrespectful: return "#DC143C"
        case .apathetic:     return "#808080"
        case .neutral:       return "#00E5FF"
        case .sad:           return "#4169E1"
        case .worried:       return "#DAA520"
        case .jealous:       return "#228B22"
        case .lucrative:     return "#FFD700"
        case .concerned:     return "#FF8C00"
        case .judgemental:   return "#8B4513"
        case .confused:      return "#9370DB"
        }
    }
}

// MARK: — Emotion Classifier
public enum EmotionClassifier {

    private static let positiveKeywords: Set<String> = [
        "love","happy","great","amazing","wonderful","excited","thanks","beautiful",
        "inspire","joy","hope","help","guide","proud","grateful","awesome","fantastic"
    ]
    private static let negativeKeywords: Set<String> = [
        "hate","angry","terrible","awful","stupid","wrong","broken","fail","never",
        "worst","bad","horrible","disgusting","pathetic","useless"
    ]
    private static let worriedKeywords: Set<String> = [
        "worry","worried","anxious","nervous","scared","afraid","concern","uncertain"
    ]
    private static let confusedKeywords: Set<String> = [
        "confused","unclear","don't understand","what do","how does","why is","huh","what"
    ]

    public static func classify(
        buoyancy: Double,
        expression: ExpressionLayer,
        text: String
    ) -> EmotionType {
        let lower = text.lowercased()
        let words = Set(lower.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)))

        let posScore = words.intersection(positiveKeywords).count
        let negScore = words.intersection(negativeKeywords).count
        let worriedScore = words.intersection(worriedKeywords).count
        let confusedScore = expression == .question ? 1 : 0

        if worriedScore > 0 { return .worried }
        if confusedScore > 0 && buoyancy < 0.4 { return .confused }
        if negScore > posScore && negScore > 0 {
            return negScore > 2 ? .angry : .apathetic
        }
        if posScore > negScore && posScore > 0 {
            return posScore > 2 ? .excited : .happy
        }
        if buoyancy > 0.7 { return .inspiring }
        if buoyancy > 0.5 { return .neutral }
        return .concerned
    }
}
