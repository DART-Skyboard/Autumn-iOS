import Foundation

/// Expression tree for LEATR math — nested parens, OOO, symbols, algebra.
/// Geometry (parentheses) first, then exponents, multiply/divide, add/subtract.
public indirect enum MathNode: Equatable, Sendable {
    case number(Double)
    case variable(String)
    case unary(String, MathNode)
    case binary(String, MathNode, MathNode)
    case call(String, [MathNode])

    public var latex: String { MathLatex.emit(self) }
    public var mathML: String { MathML.emit(self) }
    public var infix: String { MathInfix.emit(self) }

    public func variables() -> Set<String> {
        switch self {
        case .number: return []
        case .variable(let n):
            return MathRuntime.isConst(n) ? [] : [n]
        case .unary(_, let x): return x.variables()
        case .binary(_, let a, let b): return a.variables().union(b.variables())
        case .call(let f, let args):
            var s = Set<String>()
            if !MathRuntime.isFunction(f) && !MathRuntime.isConst(f) { s.insert(f) }
            for a in args { s.formUnion(a.variables()) }
            return s
        }
    }
}

public enum MathStmt: Equatable, Sendable {
    case expr(MathNode)
    case assign(String, MathNode)
    case equation(MathNode, MathNode)
    case text(String)

    public var latex: String {
        switch self {
        case .expr(let n): return n.latex
        case .assign(let v, let n): return "\(MathLatex.ident(v)) = \(n.latex)"
        case .equation(let l, let r): return "\(l.latex) = \(r.latex)"
        case .text(let t): return t
        }
    }
}

public enum MathRuntime {
    public static let functions: Set<String> = [
        "sqrt", "cbrt", "nthroot", "sin", "cos", "tan", "asin", "acos", "atan",
        "log", "ln", "log10", "abs", "exp", "gamma", "delta", "zeta", "fact"
    ]
    public static let consts: [String: Double] = [
        "pi": Double.pi, "π": Double.pi,
        "e": 2.718281828459045,
        "c": 299_792_458,
        "g_earth": 9.80665,
        "G": 6.67430e-11,
        "h": 6.62607015e-34,
        "kB": 1.380649e-23,
        "qe": 1.602176634e-19
    ]
    public static func isFunction(_ n: String) -> Bool { functions.contains(n.lowercased()) }
    public static func isConst(_ n: String) -> Bool { consts[n] != nil || consts[n.lowercased()] != nil }

    public static func call(_ name: String, _ args: [Double]) -> Double? {
        let n = name.lowercased()
        guard let x = args.first else { return nil }
        switch n {
        case "sqrt": return x < 0 ? nil : sqrt(x)
        case "cbrt": return cbrt(x)
        case "nthroot":
            guard args.count >= 2 else { return nil }
            return pow(args[1], 1.0 / args[0])
        case "sin": return sin(x)
        case "cos": return cos(x)
        case "tan": return tan(x)
        case "asin": return asin(x)
        case "acos": return acos(x)
        case "atan": return atan(x)
        case "log", "log10": return x <= 0 ? nil : log10(x)
        case "ln": return x <= 0 ? nil : log(x)
        case "abs": return abs(x)
        case "exp": return exp(x)
        case "gamma": return lanczosGamma(x)
        case "delta": return abs(x) < 1e-12 ? 1 : 0
        case "zeta": return zetaApprox(x)
        case "fact":
            guard x >= 0, abs(x - x.rounded()) < 1e-9, x <= 170 else { return nil }
            var a = 1.0
            if x >= 1 { for i in 1...Int(x.rounded()) { a *= Double(i) } }
            return a
        default: return nil
        }
    }

    /// Lanczos approximation for Γ(x), x > 0.
    public static func lanczosGamma(_ x: Double) -> Double? {
        if x <= 0 { return nil }
        if abs(x - x.rounded()) < 1e-12 && x <= 170 {
            var a = 1.0
            if x >= 2 { for i in 1..<Int(x.rounded()) { a *= Double(i) } }
            return a
        }
        let p = [0.99999999999980993, 676.5203681218851, -1259.1392167224028,
                 771.32342877765313, -176.61502916214059, 12.507343278686905,
                 -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7]
        var z = x
        if z < 0.5 {
            guard let g = lanczosGamma(1 - z) else { return nil }
            return Double.pi / (sin(Double.pi * z) * g)
        }
        z -= 1
        var a = p[0]
        for i in 1..<p.count { a += p[i] / (z + Double(i)) }
        let t = z + 7.5
        return sqrt(2 * Double.pi) * pow(t, z + 0.5) * exp(-t) * a
    }

    public static func zetaApprox(_ s: Double) -> Double? {
        if abs(s - 2) < 1e-12 { return pow(Double.pi, 2) / 6 }
        if abs(s - 0) < 1e-12 { return -0.5 }
        if s <= 1 { return nil }
        var sum = 0.0
        for n in 1...400 { sum += pow(Double(n), -s) }
        return sum
    }
}

public enum MathParser {
    public static func parse(_ raw: String) -> MathStmt? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let eq = splitTopLevelEquals(trimmed) {
            let left = eq.0.trimmingCharacters(in: .whitespaces)
            let right = eq.1.trimmingCharacters(in: .whitespaces)
            var lp = Parser(left)
            var rp = Parser(right)
            guard let l = lp.parseExpr(), lp.atEnd else { return nil }
            guard let r = rp.parseExpr(), rp.atEnd else { return nil }
            if case .variable(let name) = l, l.variables().count <= 1 {
                return .assign(name, r)
            }
            return .equation(l, r)
        }
        var p = Parser(trimmed)
        guard let n = p.parseExpr(), p.atEnd else { return nil }
        return .expr(n)
    }

    public static func parseNode(_ raw: String) -> MathNode? {
        switch parse(raw) {
        case .expr(let n): return n
        case .assign(_, let n): return n
        case .equation(let l, let r): return .binary("=", l, r)
        default: return nil
        }
    }

    private static func splitTopLevelEquals(_ s: String) -> (String, String)? {
        var depth = 0
        let chars = Array(s)
        for i in chars.indices {
            if chars[i] == "(" { depth += 1 }
            else if chars[i] == ")" { depth -= 1 }
            else if chars[i] == "=", depth == 0, i > 0, i + 1 < chars.count {
                return (String(chars[0..<i]), String(chars[(i + 1)...]))
            }
        }
        return nil
    }

    struct Parser {
        let chars: [Character]
        var i = 0
        var atEnd: Bool {
            skip()
            return i >= chars.count
        }
        init(_ s: String) { chars = Array(normalize(s)) }

        static func normalize(_ raw: String) -> String {
            var s = raw
            let pairs: [(String, String)] = [
                ("×", "*"), ("·", "*"), ("÷", "/"), ("−", "-"),
                ("√", "sqrt"), ("π", "pi"), ("Δ", "delta"), ("δ", "delta"),
                ("Γ", "gamma"), ("γ", "gamma"), ("ζ", "zeta"),
                ("θ", "theta"), ("λ", "lambda"), ("ω", "omega"),
                ("φ", "phi"), ("σ", "sigma"), ("α", "alpha"), ("β", "beta"),
                ("²", "^2"), ("³", "^3"), ("⁴", "^4")
            ]
            for (a, b) in pairs { s = s.replacingOccurrences(of: a, with: b) }
            return s
        }

        mutating func skip() {
            while i < chars.count && chars[i].isWhitespace { i += 1 }
        }
        mutating func peek() -> Character? {
            skip()
            return i < chars.count ? chars[i] : nil
        }
        mutating func eat(_ c: Character) -> Bool {
            skip()
            guard i < chars.count, chars[i] == c else { return false }
            i += 1
            return true
        }

        mutating func parseExpr() -> MathNode? {
            guard var v = parseTerm() else { return nil }
            while true {
                if eat("+") {
                    guard let r = parseTerm() else { return nil }
                    v = .binary("+", v, r)
                } else if eat("-") {
                    guard let r = parseTerm() else { return nil }
                    v = .binary("-", v, r)
                } else { return v }
            }
        }

        mutating func parseTerm() -> MathNode? {
            guard var v = parsePower() else { return nil }
            while true {
                skip()
                if eat("*") {
                    guard let r = parsePower() else { return nil }
                    v = .binary("*", v, r)
                } else if eat("/") {
                    guard let r = parsePower() else { return nil }
                    v = .binary("/", v, r)
                } else if implicitComing() {
                    guard let r = parsePower() else { return nil }
                    v = .binary("*", v, r)
                } else { return v }
            }
        }

        mutating func implicitComing() -> Bool {
            skip()
            guard i < chars.count else { return false }
            let c = chars[i]
            if c == "(" { return true }
            if c.isLetter { return true }
            if c.isNumber { return true }
            return false
        }

        mutating func parsePower() -> MathNode? {
            guard let base = parseUnary() else { return nil }
            skip()
            if eat("^") {
                guard let exp = parsePower() else { return nil }
                return .binary("^", base, exp)
            }
            return base
        }

        mutating func parseUnary() -> MathNode? {
            skip()
            if eat("-") {
                guard let v = parseUnary() else { return nil }
                return .unary("-", v)
            }
            if eat("+") { return parseUnary() }
            return parsePrimary()
        }

        mutating func parsePrimary() -> MathNode? {
            skip()
            guard i < chars.count else { return nil }
            if eat("(") {
                guard let v = parseExpr() else { return nil }
                guard eat(")") else { return nil }
                return v
            }
            if eat("|") {
                guard let v = parseExpr() else { return nil }
                guard eat("|") else { return nil }
                return .call("abs", [v])
            }
            if chars[i].isLetter || chars[i] == "_" {
                let name = readIdent()
                skip()
                if eat("(") {
                    var args: [MathNode] = []
                    if peek() != ")" {
                        while true {
                            guard let a = parseExpr() else { return nil }
                            args.append(a)
                            if eat(",") { continue }
                            break
                        }
                    }
                    guard eat(")") else { return nil }
                    return .call(name, args)
                }
                if let c = MathRuntime.consts[name] ?? MathRuntime.consts[name.lowercased()] {
                    return .number(c)
                }
                return .variable(name)
            }
            return parseNumber()
        }

        mutating func readIdent() -> String {
            skip()
            let start = i
            while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                i += 1
            }
            return String(chars[start..<i])
        }

        mutating func parseNumber() -> MathNode? {
            skip()
            let start = i
            while i < chars.count && (chars[i].isNumber || chars[i] == ".") { i += 1 }
            guard i > start, let v = Double(String(chars[start..<i])) else { return nil }
            return .number(v)
        }
    }
}

public enum MathEval {
    public static func value(_ node: MathNode, env: [String: Double] = [:]) -> Double? {
        switch node {
        case .number(let n): return n
        case .variable(let name):
            if let v = env[name] ?? env[name.lowercased()] { return v }
            if let c = MathRuntime.consts[name] ?? MathRuntime.consts[name.lowercased()] { return c }
            return nil
        case .unary("-", let x):
            guard let v = value(x, env: env) else { return nil }
            return -v
        case .unary(let op, let x):
            guard let v = value(x, env: env) else { return nil }
            return MathRuntime.call(op, [v])
        case .binary("+", let a, let b):
            guard let x = value(a, env: env), let y = value(b, env: env) else { return nil }
            return x + y
        case .binary("-", let a, let b):
            guard let x = value(a, env: env), let y = value(b, env: env) else { return nil }
            return x - y
        case .binary("*", let a, let b):
            guard let x = value(a, env: env), let y = value(b, env: env) else { return nil }
            return x * y
        case .binary("/", let a, let b):
            guard let x = value(a, env: env), let y = value(b, env: env), y != 0 else { return nil }
            return x / y
        case .binary("^", let a, let b):
            guard let x = value(a, env: env), let y = value(b, env: env) else { return nil }
            return pow(x, y)
        case .binary("=", _, _):
            return nil
        case .binary:
            return nil
        case .call(let f, let args):
            var nums: [Double] = []
            for a in args {
                guard let v = value(a, env: env) else { return nil }
                nums.append(v)
            }
            return MathRuntime.call(f, nums)
        }
    }

    public static func format(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "undefined" }
        if abs(v - v.rounded()) < 1e-10 { return String(Int(v.rounded())) }
        var s = String(format: "%.10g", v)
        if s.hasSuffix(".0") { s = String(s.dropLast(2)) }
        return s
    }
}

public enum MathLatex {
    public static func ident(_ n: String) -> String {
        let map = [
            "delta": "\\Delta", "gamma": "\\Gamma", "zeta": "\\zeta",
            "theta": "\\theta", "lambda": "\\lambda", "omega": "\\omega",
            "phi": "\\phi", "sigma": "\\sigma", "alpha": "\\alpha",
            "beta": "\\beta", "pi": "\\pi"
        ]
        return map[n.lowercased()] ?? n
    }

    public static func emit(_ n: MathNode) -> String {
        switch n {
        case .number(let v): return MathEval.format(v)
        case .variable(let name): return ident(name)
        case .unary("-", let x): return "-{" + emit(x) + "}"
        case .unary(let op, let x): return "\\operatorname{\(op)}\\left(" + emit(x) + "\\right)"
        case .binary("+", let a, let b): return emit(a) + " + " + emit(b)
        case .binary("-", let a, let b): return emit(a) + " - " + emit(b)
        case .binary("*", let a, let b): return emit(a) + " \\cdot " + emit(b)
        case .binary("/", let a, let b): return "\\frac{" + emit(a) + "}{" + emit(b) + "}"
        case .binary("^", let a, let b): return "{" + grouped(a) + "}^{" + emit(b) + "}"
        case .binary("=", let a, let b): return emit(a) + " = " + emit(b)
        case .binary(let op, let a, let b): return emit(a) + " \(op) " + emit(b)
        case .call("sqrt", let args) where args.count == 1:
            return "\\sqrt{" + emit(args[0]) + "}"
        case .call("cbrt", let args) where args.count == 1:
            return "\\sqrt[3]{" + emit(args[0]) + "}"
        case .call("abs", let args) where args.count == 1:
            return "\\left|" + emit(args[0]) + "\\right|"
        case .call(let f, let args):
            return "\\operatorname{\(f)}\\left(" + args.map(emit).joined(separator: ", ") + "\\right)"
        }
    }

    private static func grouped(_ n: MathNode) -> String {
        switch n {
        case .number, .variable, .call: return emit(n)
        default: return "\\left(" + emit(n) + "\\right)"
        }
    }
}

public enum MathML {
    public static func emit(_ n: MathNode) -> String {
        wrap(inner(n))
    }
    public static func wrap(_ inner: String) -> String {
        "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\">\(inner)</math>"
    }
    public static func inner(_ n: MathNode) -> String {
        switch n {
        case .number(let v): return "<mn>\(MathEval.format(v))</mn>"
        case .variable(let name): return "<mi>\(name)</mi>"
        case .unary("-", let x): return "<mrow><mo>-</mo>\(inner(x))</mrow>"
        case .unary(let op, let x): return "<mrow><mi>\(op)</mi><mo>(</mo>\(inner(x))<mo>)</mo></mrow>"
        case .binary("+", let a, let b): return "<mrow>\(inner(a))<mo>+</mo>\(inner(b))</mrow>"
        case .binary("-", let a, let b): return "<mrow>\(inner(a))<mo>-</mo>\(inner(b))</mrow>"
        case .binary("*", let a, let b): return "<mrow>\(inner(a))<mo>&#x22C5;</mo>\(inner(b))</mrow>"
        case .binary("/", let a, let b): return "<mfrac>\(inner(a))\(inner(b))</mfrac>"
        case .binary("^", let a, let b): return "<msup>\(inner(a))\(inner(b))</msup>"
        case .binary("=", let a, let b): return "<mrow>\(inner(a))<mo>=</mo>\(inner(b))</mrow>"
        case .binary(let op, let a, let b): return "<mrow>\(inner(a))<mo>\(op)</mo>\(inner(b))</mrow>"
        case .call("sqrt", let args) where args.count == 1:
            return "<msqrt>\(inner(args[0]))</msqrt>"
        case .call("abs", let args) where args.count == 1:
            return "<mrow><mo>|</mo>\(inner(args[0]))<mo>|</mo></mrow>"
        case .call(let f, let args):
            return "<mrow><mi>\(f)</mi><mo>(</mo>" + args.map(inner).joined(separator: "<mo>,</mo>") + "<mo>)</mo></mrow>"
        }
    }
}

public enum MathInfix {
    public static func emit(_ n: MathNode) -> String {
        switch n {
        case .number(let v): return MathEval.format(v)
        case .variable(let name): return name
        case .unary("-", let x): return "-(" + emit(x) + ")"
        case .unary(let op, let x): return op + "(" + emit(x) + ")"
        case .binary("^", let a, let b): return "(" + emit(a) + ")^(" + emit(b) + ")"
        case .binary(let op, let a, let b): return "(" + emit(a) + op + emit(b) + ")"
        case .call(let f, let args): return f + "(" + args.map(emit).joined(separator: ",") + ")"
        }
    }
}

public enum GrammarIntegers {
    public static let words: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
        "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90, "hundred": 100, "thousand": 1000
    ]
    public static func isWord(_ n: String) -> Bool { words[n.lowercased()] != nil }
}
