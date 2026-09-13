import Foundation

/// User algebra sheets — squares, cubes, fourth powers, a+b+c, conditionals.
/// Autumn expands / recognizes / evaluates these classes (not just arithmetic).
public struct AlgebraIdentity: Sendable {
    public let id: String
    public let name: String
    public let pattern: String
    public let expansion: String
    public let latex: String
    public let family: String
    public let note: String
}

public enum AlgebraIdentities {
    public static let catalog: [AlgebraIdentity] = [
        AlgebraIdentity(id: "sq_sum", name: "(a+b)^2", pattern: "(a+b)^2",
                        expansion: "a^2 + 2ab + b^2",
                        latex: "(a+b)^{2} = a^{2} + 2ab + b^{2}",
                        family: "squares", note: "Square of a sum."),
        AlgebraIdentity(id: "sq_diff", name: "(a-b)^2", pattern: "(a-b)^2",
                        expansion: "a^2 - 2ab + b^2",
                        latex: "(a-b)^{2} = a^{2} - 2ab + b^{2}",
                        family: "squares", note: "Square of a difference."),
        AlgebraIdentity(id: "diff_sq", name: "a^2-b^2", pattern: "a^2-b^2",
                        expansion: "(a+b)(a-b)",
                        latex: "a^{2}-b^{2} = (a+b)(a-b)",
                        family: "squares", note: "Difference of squares."),
        AlgebraIdentity(id: "sq_abc", name: "(a+b+c)^2", pattern: "(a+b+c)^2",
                        expansion: "a^2+b^2+c^2+2ab+2bc+2ca",
                        latex: "(a+b+c)^{2} = a^{2}+b^{2}+c^{2}+2ab+2bc+2ca",
                        family: "squares", note: "Square of a trinomial."),
        AlgebraIdentity(id: "cu_sum", name: "(a+b)^3", pattern: "(a+b)^3",
                        expansion: "a^3 + 3a^2b + 3ab^2 + b^3",
                        latex: "(a+b)^{3} = a^{3} + 3a^{2}b + 3ab^{2} + b^{3}",
                        family: "cubes", note: "Cube of a sum."),
        AlgebraIdentity(id: "cu_diff", name: "(a-b)^3", pattern: "(a-b)^3",
                        expansion: "a^3 - 3a^2b + 3ab^2 - b^3",
                        latex: "(a-b)^{3} = a^{3} - 3a^{2}b + 3ab^{2} - b^{3}",
                        family: "cubes", note: "Cube of a difference."),
        AlgebraIdentity(id: "sum_cu", name: "a^3+b^3", pattern: "a^3+b^3",
                        expansion: "(a+b)(a^2 - ab + b^2)",
                        latex: "a^{3}+b^{3} = (a+b)(a^{2}-ab+b^{2})",
                        family: "cubes", note: "Sum of cubes."),
        AlgebraIdentity(id: "diff_cu", name: "a^3-b^3", pattern: "a^3-b^3",
                        expansion: "(a-b)(a^2 + ab + b^2)",
                        latex: "a^{3}-b^{3} = (a-b)(a^{2}+ab+b^{2})",
                        family: "cubes", note: "Difference of cubes."),
        AlgebraIdentity(id: "cu_abc", name: "a^3+b^3+c^3-3abc", pattern: "a^3+b^3+c^3-3abc",
                        expansion: "(a+b+c)(a^2+b^2+c^2-ab-bc-ca)",
                        latex: "a^{3}+b^{3}+c^{3}-3abc = (a+b+c)(a^{2}+b^{2}+c^{2}-ab-bc-ca)",
                        family: "cubes", note: "Trinomial cubes identity."),
        AlgebraIdentity(id: "cu_cond", name: "a+b+c=0 => a^3+b^3+c^3=3abc",
                        pattern: "a+b+c=0",
                        expansion: "a^3+b^3+c^3 = 3abc",
                        latex: "a+b+c=0 \\Rightarrow a^{3}+b^{3}+c^{3}=3abc",
                        family: "conditionals", note: "If a+b+c=0 then cubes sum to 3abc."),
        AlgebraIdentity(id: "fo_sum", name: "(a+b)^4", pattern: "(a+b)^4",
                        expansion: "a^4 + 4a^3b + 6a^2b^2 + 4ab^3 + b^4",
                        latex: "(a+b)^{4} = a^{4} + 4a^{3}b + 6a^{2}b^{2} + 4ab^{3} + b^{4}",
                        family: "fourth", note: "Fourth power of a sum."),
        AlgebraIdentity(id: "fo_diff", name: "(a-b)^4", pattern: "(a-b)^4",
                        expansion: "a^4 - 4a^3b + 6a^2b^2 - 4ab^3 + b^4",
                        latex: "(a-b)^{4} = a^{4} - 4a^{3}b + 6a^{2}b^{2} - 4ab^{3} + b^{4}",
                        family: "fourth", note: "Fourth power of a difference."),
        AlgebraIdentity(id: "diff_fo", name: "a^4-b^4", pattern: "a^4-b^4",
                        expansion: "(a+b)(a-b)(a^2+b^2)",
                        latex: "a^{4}-b^{4} = (a+b)(a-b)(a^{2}+b^{2})",
                        family: "fourth", note: "Difference of fourth powers."),
        AlgebraIdentity(id: "force", name: "F=ma", pattern: "F=m*a",
                        expansion: "F = m * a",
                        latex: "F = m a",
                        family: "physics", note: "Newton II — force, mass, acceleration."),
        AlgebraIdentity(id: "emc2", name: "E=mc^2", pattern: "E=m*c^2",
                        expansion: "E = m * c^2",
                        latex: "E = m c^{2}",
                        family: "physics", note: "Mass–energy equivalence.")
    ]

    public static func match(_ raw: String) -> AlgebraIdentity? {
        let n = normalize(raw)
        for id in catalog {
            if n.contains(normalize(id.pattern)) || n.contains(normalize(id.name))
                || n.contains(normalize(id.expansion)) {
                return id
            }
        }
        return recognizeTree(raw)
    }

    public static func expand(_ raw: String) -> String? {
        if let id = match(raw) { return "\(id.name) = \(id.expansion). \(id.note)" }
        return expandTree(raw)
    }

    public static func example(for query: String) -> AlgebraIdentity {
        let q = query.lowercased()
        if q.contains("cube") || q.contains("^3") { return catalog.first { $0.id == "cu_sum" }! }
        if q.contains("fourth") || q.contains("^4") { return catalog.first { $0.id == "fo_sum" }! }
        if q.contains("force") || q.contains("newton") || q.contains("f=m") {
            return catalog.first { $0.id == "force" }!
        }
        if q.contains("energy") || q.contains("mc") { return catalog.first { $0.id == "emc2" }! }
        if q.contains("conditional") || q.contains("a+b+c") {
            return catalog.first { $0.id == "cu_cond" }!
        }
        return catalog.first { $0.id == "sq_sum" }!
    }

    public static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "·", with: "*")
            .replacingOccurrences(of: "×", with: "*")
    }

    private static func recognizeTree(_ raw: String) -> AlgebraIdentity? {
        guard let stmt = MathParser.parse(nlPrepare(raw)) else { return nil }
        let node: MathNode
        switch stmt {
        case .expr(let n): node = n
        case .assign(_, let n): node = n
        case .equation(let l, let r):
            if let id = matchNode(l) { return id }
            return matchNode(r)
        case .text: return nil
        }
        return matchNode(node)
    }

    private static func matchNode(_ n: MathNode) -> AlgebraIdentity? {
        if case .binary("^", let base, .number(let e)) = n {
            if isSum2(base), abs(e - 2) < 1e-9 { return catalog.first { $0.id == "sq_sum" } }
            if isDiff2(base), abs(e - 2) < 1e-9 { return catalog.first { $0.id == "sq_diff" } }
            if isSum2(base), abs(e - 3) < 1e-9 { return catalog.first { $0.id == "cu_sum" } }
            if isDiff2(base), abs(e - 3) < 1e-9 { return catalog.first { $0.id == "cu_diff" } }
            if isSum2(base), abs(e - 4) < 1e-9 { return catalog.first { $0.id == "fo_sum" } }
            if isDiff2(base), abs(e - 4) < 1e-9 { return catalog.first { $0.id == "fo_diff" } }
            if isSum3(base), abs(e - 2) < 1e-9 { return catalog.first { $0.id == "sq_abc" } }
        }
        return nil
    }

    private static func isSum2(_ n: MathNode) -> Bool {
        if case .binary("+", .variable, .variable) = n { return true }
        return false
    }
    private static func isDiff2(_ n: MathNode) -> Bool {
        if case .binary("-", .variable, .variable) = n { return true }
        return false
    }
    private static func isSum3(_ n: MathNode) -> Bool {
        if case .binary("+", .binary("+", .variable, .variable), .variable) = n { return true }
        if case .binary("+", .variable, .binary("+", .variable, .variable)) = n { return true }
        return false
    }

    private static func expandTree(_ raw: String) -> String? {
        guard let id = recognizeTree(raw) else { return nil }
        return "\(id.name) = \(id.expansion). \(id.note)"
    }

    private static func nlPrepare(_ raw: String) -> String {
        MathNL.toExpr(raw) ?? raw
    }
}

/// Natural-language → math expression (web _nlToMathExpr).
public enum MathNL {
    public static func toExpr(_ raw: String) -> String? {
        var s = raw
        s = s.replacingOccurrences(of: #"[?!]+$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"^(please\s+)?((can|could|would) you\s+)?(tell me\s+)?(what(?:'s| is)|whats|calculate|compute|solve|evaluate|find|expand|show)\s+"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        s = s.replacingOccurrences(of: #"\bthe\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\bcube roots?\s+of\b"#, with: "cbrt ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\bsquare roots?\s+of\b"#, with: "sqrt ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\bnth roots?\s+of\b"#, with: "nthroot ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\broots?\s+of\b"#, with: "sqrt ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\bsquared\b"#, with: "^2", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\bcubed\b"#, with: "^3", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\bto the power of\b"#, with: "^", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\bplus\b"#, with: "+", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\bminus\b"#, with: "-", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\btimes\b"#, with: "*", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\bmultipl(?:ied|y)(?:\s+by)?\b"#, with: "*", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\bdivid(?:ed|e)(?:\s+by)?\b"#, with: "/", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "×", with: "*")
        s = s.replacingOccurrences(of: "÷", with: "/")
        s = s.replacingOccurrences(of: #"\b(cbrt|sqrt|sin|cos|tan|log|ln|abs|gamma|delta|zeta)\s+(-?\d+(?:\.\d+)?)"#,
                                   with: "$1($2)", options: .regularExpression)
        for (w, n) in GrammarIntegers.words.sorted(by: { $0.key.count > $1.key.count }) {
            s = s.replacingOccurrences(of: "\\b\(w)\\b", with: MathEval.format(n), options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
