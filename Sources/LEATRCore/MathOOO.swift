import Foundation

/// Builtin math in LEATR 25-order OOO (not a web lookup).
/// Order 8 Parentheses/Geometry first, then 9 exponents, 10-11 * /, 12-13 + -.
/// Extended: variables, identities, glossary, BRPN 3-pass batch, symbols.
public enum MathOOO {

    public static func isMathAsk(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return false }
        if s.range(of: #"\b(ash\s*star|ashstar|maze studio|how do you feel|how are you)\b"#, options: .regularExpression) != nil {
            return false
        }
        if AlgebraIdentities.match(s) != nil { return true }
        if s.range(of: #"\b(cube|square)\s+roots?\b"#, options: .regularExpression) != nil { return true }
        if s.range(of: #"\broots?\s+of\b"#, options: .regularExpression) != nil && s.range(of: #"\d"#, options: .regularExpression) != nil { return true }
        if s.range(of: #"\b(sqrt|cbrt|nthroot|sin|cos|tan|log|ln|gamma|zeta)\b"#, options: .regularExpression) != nil { return true }
        if s.range(of: #"[ΔδΓγζπθλαβ]"#, options: .regularExpression) != nil { return true }
        let hasDigit = s.range(of: #"\d"#, options: .regularExpression) != nil
        let hasWordInt = GrammarIntegers.words.keys.contains(where: { s.range(of: "\\b\($0)\\b", options: .regularExpression) != nil })
        let hasOp = s.range(of: #"[+\-*/x×÷^=()]"#, options: .regularExpression) != nil
            || s.range(of: #"\b(plus|minus|times|multipl|divid|squared|cubed|to the power|equals)\b"#, options: .regularExpression) != nil
        if (hasDigit || hasWordInt) && hasOp { return true }
        let verbs = ["what is", "what's", "calculate", "compute", "solve", "eval", "expand"]
        if verbs.contains(where: { s.contains($0) }) && (hasDigit || hasOp || hasWordInt) {
            return true
        }
        return s.range(of: #"^\s*[\d.(].*[+\-*/^]"#, options: .regularExpression) != nil
    }

    /// Grammar-integer talk without operators is language, not a calculation.
    public static func isGrammarIntegerTalk(_ raw: String) -> Bool {
        let s = raw.lowercased()
        let hasWord = GrammarIntegers.words.keys.contains(where: {
            s.range(of: "\\b\($0)\\b", options: .regularExpression) != nil
        })
        guard hasWord else { return false }
        return !isMathAsk(raw)
    }

    public static func evalSpeak(_ raw: String) -> String? {
        var ws = MathWorkspaceHolder.current
        let chunks = raw
            .split(whereSeparator: { $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let parts: [String]
        if chunks.count > 1 {
            let mathy = chunks.filter { isMathAsk($0) || $0.range(of: #"[0-9(]"#, options: .regularExpression) != nil || $0.contains("=") }
            parts = mathy.isEmpty ? chunks : mathy
        } else {
            parts = chunks
        }
        let result = BRPNMathBatch.process(parts, workspace: &ws)
        MathWorkspaceHolder.current = ws
        let spoken = result.lines.isEmpty ? result.report : result.lines.joined(separator: "\n\n")
        return spoken.isEmpty ? nil : spoken
    }

    static func nlToExpr(_ raw: String) -> String? { MathNL.toExpr(raw) }

    public static func evaluate(_ expr: String) -> Double? {
        guard let node = MathParser.parseNode(expr) else {
            // Fallback to legacy numeric-only parser
            var p = LegacyParser(expr)
            guard let v = p.parseExpr() else { return nil }
            p.skip()
            return p.i >= p.s.count ? v : nil
        }
        return MathEval.value(node, env: MathWorkspaceHolder.current.env)
    }

    public static func evaluate(_ expr: String, env: [String: Double]) -> Double? {
        guard let node = MathParser.parseNode(expr) else { return nil }
        return MathEval.value(node, env: env)
    }

    private struct LegacyParser {
        let chars: [Character]
        var i = 0
        var s: [Character] { chars }
        init(_ s: String) { chars = Array(s) }

        mutating func skip() {
            while i < chars.count && chars[i].isWhitespace { i += 1 }
        }

        mutating func parseExpr() -> Double? {
            guard var v = parseTerm() else { return nil }
            while true {
                skip()
                guard i < chars.count else { return v }
                let op = chars[i]
                if op == "+" { i += 1; guard let r = parseTerm() else { return nil }; v += r }
                else if op == "-" { i += 1; guard let r = parseTerm() else { return nil }; v -= r }
                else { return v }
            }
        }

        mutating func parseTerm() -> Double? {
            guard var v = parsePower() else { return nil }
            while true {
                skip()
                guard i < chars.count else { return v }
                let op = chars[i]
                if op == "*" { i += 1; guard let r = parsePower() else { return nil }; v *= r }
                else if op == "/" {
                    i += 1
                    guard let r = parsePower(), r != 0 else { return nil }
                    v /= r
                } else { return v }
            }
        }

        mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            skip()
            if i < chars.count && chars[i] == "^" {
                i += 1
                guard let exp = parsePower() else { return nil }
                return pow(base, exp)
            }
            return base
        }

        mutating func parseUnary() -> Double? {
            skip()
            if i < chars.count && chars[i] == "-" {
                i += 1
                guard let v = parseUnary() else { return nil }
                return -v
            }
            if i < chars.count && chars[i] == "+" {
                i += 1
                return parseUnary()
            }
            return parsePrimary()
        }

        mutating func parsePrimary() -> Double? {
            skip()
            guard i < chars.count else { return nil }
            if chars[i] == "(" {
                i += 1
                guard let v = parseExpr() else { return nil }
                skip()
                guard i < chars.count, chars[i] == ")" else { return nil }
                i += 1
                return v
            }
            return parseNumber()
        }

        mutating func parseNumber() -> Double? {
            skip()
            let start = i
            while i < chars.count && (chars[i].isNumber || chars[i] == ".") { i += 1 }
            guard i > start else { return nil }
            return Double(String(chars[start..<i]))
        }
    }

    static func format(_ v: Double) -> String { MathEval.format(v) }

    static func spoken(expr: String, result: String) -> String {
        "\(expr) = \(result). Geometry (parentheses) first, then exponents, multiply/divide, add/subtract — Natural Tool math orders, not the web."
    }
}

/// Process-wide math workspace so chat, solver, and Save Data share one project.
public enum MathWorkspaceHolder {
    public static var current = MathWorkspace()
}
