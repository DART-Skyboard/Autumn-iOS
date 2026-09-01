import Foundation

/// Builtin math in LEATR 25-order OOO (not a web lookup).
/// Order 8 Parentheses/Geometry first, then 9 exponents, 10-11 * /, 12-13 + -.
/// Port of autumn-grammar-engine.js _evalMathSpeak / math parser intent.
public enum MathOOO {

    public static func isMathAsk(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return false }
        if s.range(of: #"^\s*[-+]?\d"#, options: .regularExpression) != nil,
           s.range(of: #"[+\-*/^x/()]|plus|minus|times|divided"#, options: .regularExpression) != nil {
            return true
        }
        let verbs = ["what is", "what's", "calculate", "compute", "solve", "eval"]
        if verbs.contains(where: { s.contains($0) }) &&
            s.range(of: #"[0-9+\-*/^()]"#, options: .regularExpression) != nil {
            return true
        }
        return s.range(of: #"^\s*[\d.(].*[+\-*/^]"#, options: .regularExpression) != nil
    }

    public static func evalSpeak(_ raw: String) -> String? {
        let chunks = raw
            .split(whereSeparator: { $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let parts: [String]
        if chunks.count > 1 {
            let mathy = chunks.filter { isMathAsk($0) || $0.range(of: #"[0-9(]"#, options: .regularExpression) != nil }
            parts = mathy.isEmpty ? chunks : mathy
        } else {
            parts = chunks
        }
        var lines: [String] = []
        for part in parts {
            guard let expr = nlToExpr(part) else { continue }
            guard let val = evaluate(expr) else { continue }
            lines.append(spoken(expr: expr, result: format(val)))
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    static func nlToExpr(_ raw: String) -> String? {
        var s = raw.lowercased()
        let replacements = [
            "what is": "", "what's": "", "calculate": "", "compute": "",
            "solve": "", "equals": "", "equal to": "",
            "plus": "+", "minus": "-", "times": "*",
            "multiplied by": "*", "divided by": "/", "over": "/",
            "to the power of": "^", "squared": "^2", "cubed": "^3"
        ]
        for (a, b) in replacements { s = s.replacingOccurrences(of: a, with: b) }
        s = s.filter { $0.isNumber || "+-*/^().".contains($0) || $0.isWhitespace }
        s = s.replacingOccurrences(of: " ", with: "")
        guard s.contains(where: { $0.isNumber }) else { return nil }
        guard s.contains(where: { "+-*/^".contains($0) }) || s.contains("(") else { return nil }
        return s.isEmpty ? nil : s
    }

    public static func evaluate(_ expr: String) -> Double? {
        var p = Parser(expr)
        guard let v = p.parseExpr() else { return nil }
        p.skip()
        return p.i >= p.s.count ? v : nil
    }

    private struct Parser {
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

    static func format(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "undefined" }
        if abs(v - v.rounded()) < 1e-10 { return String(Int(v.rounded())) }
        var s = String(format: "%.10g", v)
        if s.hasSuffix(".0") { s = String(s.dropLast(2)) }
        return s
    }

    static func spoken(expr: String, result: String) -> String {
        "\(expr) = \(result). Geometry (parentheses) first, then exponents, multiply/divide, add/subtract — Natural Tool math orders, not the web."
    }
}
