import Foundation

// Tool Radian: Swift port of scripts/ash/ash-radian.js (leatr-ash). Encodes data points into reflexive variable state
// (tool + kind + angle), decodes them for analysis, and generates a response. Integers only (angles are tenths of a degree).
// No outside AI, no network, no eval. Nothing a user types is stored or learned.
//   state  <tool>[f]<kind><angle>   md-0.1  mdb0.1  md0.0  mfdb0.0       limit: |angle| <= 45.0 degrees (1/8 of a diameter)
//   One angle per data point carries its whole context. Data points may share a state; to tell them apart the same angle gains decimal places (up to 6).
enum AshRadian {
    static let tools: [Character: String] = ["m": "Maze", "p": "Puzzle", "e": "Envelope", "h": "Hammer", "s": "Stick", "k": "Knife", "r": "Scissors"]
    static let limit = 450
    static let punct = Array("+-*/^%()<>,.:;!?")
    static let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

    /// kind: "-" data, "+" data that can build, "b" both, "0" neutral
    struct State: Equatable {
        var tool: Character, field: Bool, kind: Character, mag: Int, neg: Bool
        var prec = 1   // decimal places of the angle; mag is in units of 10^-prec degrees
        var signed: Int { (neg ? -1 : 1) * mag }
        func scaled(_ P: Int) -> Int { signed * AshRadian.pow10(P - prec) }
        var text: String {
            let k: String
            switch kind { case "-": k = "d-"; case "+": k = "d+"; case "b": k = (neg && mag > 0) ? "db-" : "db"; default: k = "d" }
            return "\(tool)\(field ? "f" : "")\(k)\(AshRadian.fixed(mag, prec))"
        }
    }

    static let maxPrec = 6
    static func pow10(_ n: Int) -> Int { var r = 1; for _ in 0..<max(0, n) { r *= 10 }; return r }
    static func fixed(_ mag: Int, _ prec: Int) -> String {
        let u = pow10(prec); var f = String(mag % u); while f.count < prec { f = "0" + f }
        return "\(mag / u).\(f)"
    }
    static func make(_ tool: Character, _ field: Bool, _ kind: Character, _ mag: Int, _ neg: Bool = false, prec: Int = 1) -> State {
        let m = kind == "0" ? 0 : max(0, min(45 * pow10(prec), mag))
        return State(tool: tool, field: field, kind: kind, mag: m, neg: kind == "-" ? true : (kind == "b" ? neg : false), prec: prec)
    }

    static func parseState(_ s: String) -> State? {
        guard let re = try? NSRegularExpression(pattern: "^([mpehskr])(f?)(d-|d\\+|db-?|d)(\\d{1,3}\\.\\d{1,6})$"),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        func g(_ i: Int) -> String { (s as NSString).substring(with: m.range(at: i)) }
        let parts = g(4).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let mag = Int(parts[0] + parts[1]) else { return nil }
        let prec = parts[1].count; if mag > 45 * pow10(prec) { return nil }
        let kd = g(3), kind: Character = kd == "d-" ? "-" : kd == "d+" ? "+" : kd == "d" ? "0" : "b"
        if kind == "0" && mag != 0 { return nil }
        return State(tool: Character(g(1)), field: g(2) == "f", kind: kind, mag: mag, neg: kind == "-" || kd == "db-", prec: prec)
    }

    // ── data-point assignment (seed table; optionally the mean with context angles = reflex states / emotion, in tenths) ──
    static func seed(_ ch: Character) -> State {
        if let d = ch.wholeNumberValue, ch.isASCII { return make("m", false, "-", d) }
        if ch == "=" { return make("m", false, "0", 0) }
        if let p = punct.firstIndex(of: ch) { return make("m", false, "b", p + 1) }
        let u = Int(ch.utf16.first ?? 0)
        if ch.isASCII && ch.isLowercase { return make("e", false, "+", u - 96) }
        if ch.isASCII && ch.isUppercase { return make("e", false, "+", 30 + u - 64) }
        return make("e", false, "b", u % 451)
    }
    static func mean(_ a: [Int]) -> Int { a.isEmpty ? 0 : a.reduce(0, +) / a.count }
    /// contexts: signed tenths from the remaining reflex states / emotional contexts; prec: decimal places of the angle (1 = tenths)
    static func assign(_ ch: Character, contexts: [Int] = [], prec: Int = 1) -> State {
        let s = seed(ch); if s.kind == "0" { return s }
        if contexts.isEmpty { return make(s.tool, false, s.kind, s.mag * pow10(prec - 1), s.neg, prec: prec) }
        let m = mean(([s.signed] + contexts).map { $0 * pow10(prec - 1) })
        return make(s.tool, false, s.kind, abs(m), m < 0, prec: prec)
    }

    // ── sequences (fields) ──
    static func stripOuter(_ t: String) -> String {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s.hasPrefix("(") && s.hasSuffix(")") && s.count >= 2) ? String(s.dropFirst().dropLast()) : s
    }
    static func fieldState(_ members: [State], prec: Int = 1) -> State {
        let P = max(prec, members.map { $0.prec }.max() ?? 1)
        let hasMath = members.contains { $0.tool == "m" }
        let kinds = Set(members.map { $0.kind })
        let both = kinds.contains("b") || (kinds.contains("-") && kinds.contains("+"))
        let kind: Character = both ? "b" : (kinds.contains("-") ? "-" : kinds.contains("+") ? "+" : "0")
        let m = mean(members.map { $0.scaled(P) })
        return make(hasMath ? "m" : "e", true, kind, abs(m), m < 0, prec: P)
    }
    struct Encoded { let text: String; let tokens: [(ch: Character, state: String)]; let field: String? }
    static func encode(_ text: String, contexts: [Int] = [], prec: Int = 1) -> Encoded {
        let body = stripOuter(text).filter { !$0.isWhitespace }
        let sts = body.map { assign($0, contexts: contexts, prec: prec) }
        return Encoded(text: "(\(body))", tokens: zip(body, sts).map { ($0, $1.text) }, field: sts.isEmpty ? nil : fieldState(sts, prec: prec).text)
    }

    // ── decode ──
    static func inverse(_ s: State) -> [Character] {
        let all = Array("0123456789=") + punct + Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return all.filter { let q = seed($0); return q.tool == s.tool && q.kind == s.kind && q.mag * pow10(s.prec - 1) == s.mag && q.neg == s.neg }
    }
    struct Decoded { let state: String, tool: String, field: Bool, kind: Character, deg: String, candidates: [Character], common: Bool, meaning: Character? }
    static func decode(_ str: String, table: Table = .seedTable) -> Decoded? {
        guard let s = parseState(str) else { return nil }
        let cands = inverse(s), seen = table.byState[str]?.first
        return Decoded(state: str, tool: tools[s.tool] ?? "?", field: s.field, kind: s.kind, deg: ((s.neg && s.mag > 0) ? "-" : "") + fixed(s.mag, s.prec),
                       candidates: cands, common: (seen?.n ?? 0) >= 2, meaning: seen?.d.count == 1 ? seen?.d.first : cands.first)
    }

    // ── training table (read only on device) ──
    struct Table {
        struct Rec { let v: String; let d: String; let n: Int }
        var recs: [Rec] = []
        var byState: [String: [Rec]] { Dictionary(grouping: recs, by: { $0.v }).mapValues { $0.sorted { $0.n > $1.n } } }
        static func parse(_ text: String) -> Table {
            guard let re = try? NSRegularExpression(pattern: "^\\s*irin \\(\"Radian: v=(\\S+) d=(\\S*) n=(\\d+)") else { return Table() }
            var t = Table()
            for ln in text.components(separatedBy: "\n") {
                let ns = ln as NSString
                if let m = re.firstMatch(in: ln, range: NSRange(location: 0, length: ns.length)) {
                    t.recs.append(Rec(v: ns.substring(with: m.range(at: 1)), d: unescape(ns.substring(with: m.range(at: 2))), n: Int(ns.substring(with: m.range(at: 3))) ?? 1))
                }
            }
            return t
        }
        static func unescape(_ s: String) -> String {
            var out = "", it = s.makeIterator()
            while let c = it.next() {
                if c == "%" { let a = it.next(), b = it.next()
                    if let a = a, let b = b, let v = UInt32(String([a, b]), radix: 16), let u = Unicode.Scalar(v) { out.append(Character(u)) } else { out.append(c) }
                } else { out.append(c) }
            }
            return out
        }
        /// the worked example shipped with the app (same as leatr-ash Training/radian/training.ash)
        static let seedTable = parse("""
        irin ("Radian: v=md-0.1 d=1 n=4")
        irin ("Radian: v=mdb0.1 d=+ n=2")
        irin ("Radian: v=md0.0 d== n=2")
        irin ("Radian: v=mfdb0.0 d=(1+1=) n=1")
        """)
    }

    // ── integer-only evaluator: + - * / ^ ( ) and unary minus; "/" that does not divide exactly yields a fraction a/b ──
    private struct Fr { var n: Int; var d: Int }
    private struct EvalFail: Error {}
    static func evaluate(_ src: String) -> String? {
        var s = Array(src.filter { !$0.isWhitespace }); var i = 0
        if s.last == "=" { s.removeLast() }
        func gcd(_ a: Int, _ b: Int) -> Int { var a = abs(a), b = abs(b); while b != 0 { (a, b) = (b, a % b) }; return a == 0 ? 1 : a }
        func fr(_ n: Int, _ d: Int) throws -> Fr {
            if d == 0 { throw EvalFail() }
            var n = n, d = d; if d < 0 { n = -n; d = -d }
            let g = gcd(n, d); let f = Fr(n: n / g, d: d / g)
            if abs(f.n) > 1_000_000_000_000_000 || f.d > 1_000_000_000_000_000 { throw EvalFail() }
            return f
        }
        func mulI(_ a: Int, _ b: Int) throws -> Int { let (r, o) = a.multipliedReportingOverflow(by: b); if o { throw EvalFail() }; return r }
        func addI(_ a: Int, _ b: Int) throws -> Int { let (r, o) = a.addingReportingOverflow(b); if o { throw EvalFail() }; return r }
        func prim() throws -> Fr {
            if i < s.count, s[i] == "(" { i += 1; let f = try add(); guard i < s.count, s[i] == ")" else { throw EvalFail() }; i += 1; return f }
            let st = i; while i < s.count, s[i].isASCII, s[i].isNumber { i += 1 }
            guard st < i, i - st <= 15, let v = Int(String(s[st..<i])) else { throw EvalFail() }
            return try fr(v, 1)
        }
        func num() throws -> Fr {
            if i < s.count, s[i] == "-" { i += 1; let f = try prim(); return try fr(-f.n, f.d) }
            if i < s.count, s[i] == "+" { i += 1; return try prim() }
            return try prim()
        }
        func pow() throws -> Fr {
            let b = try num()
            if i < s.count, s[i] == "^" {
                i += 1; let e = try pow(); guard e.d == 1, e.n >= 0, e.n <= 64 else { throw EvalFail() }
                var r = try fr(1, 1); for _ in 0..<e.n { r = try fr(try mulI(r.n, b.n), try mulI(r.d, b.d)) }; return r
            }
            return b
        }
        func mul() throws -> Fr {
            var f = try pow()
            while i < s.count, s[i] == "*" || s[i] == "/" {
                let o = s[i]; i += 1; let g = try pow()
                f = o == "*" ? try fr(try mulI(f.n, g.n), try mulI(f.d, g.d)) : try fr(try mulI(f.n, g.d), try mulI(f.d, g.n))
            }
            return f
        }
        func add() throws -> Fr {
            var f = try mul()
            while i < s.count, s[i] == "+" || s[i] == "-" {
                let o = s[i]; i += 1; let g = try mul()
                let a = try mulI(f.n, g.d), b = try mulI(g.n, f.d), d = try mulI(f.d, g.d)
                f = try fr(o == "+" ? try addI(a, b) : try addI(a, -b), d)
            }
            return f
        }
        guard let r = try? add(), i == s.count else { return nil }
        return r.d == 1 ? String(r.n) : "\(r.n)/\(r.d)"
    }

    // ── analysis + generation ──
    static func describe(_ ch: Character) -> String {
        if ch.isASCII && ch.isNumber { return "an integer" }
        if ch == "=" { return "an equals (relation)" }
        if punct.contains(ch) { return "an operator or punctuation mark" }
        if ch.isLetter { return "a letter" }
        return "a symbol"
    }
    struct Analysis { let lines: [String]; let response: String }
    static func analyze(_ text: String, table: Table = .seedTable) -> Analysis {
        let enc = encode(text), body = String(enc.text.dropFirst().dropLast())
        var lines: [String] = []
        for t in enc.tokens {
            guard let d = decode(t.state, table: table) else { continue }
            lines.append("Data of \(d.tool) at \(d.deg) degrees - \(d.common ? "Common Context" : "New Context"), Presumably \(describe(d.meaning ?? t.ch)) = \(t.ch)")
        }
        if let f = enc.field { lines.append("Sequence \(f) over \(enc.tokens.count) variable states: \(enc.text)") }   // second stair step: the sequence assignment
        var statement: String?
        for r in table.recs where statement == nil && r.v.dropFirst().first == "f" && r.d.count > 2 && !body.isEmpty {
            let inner = String(r.d.dropFirst().dropLast()); if inner.contains(body) { statement = inner }
        }
        let whole = statement ?? body
        let answer = whole.contains(where: { $0.isASCII && $0.isNumber }) ? evaluate(whole) : nil
        let lead = enc.tokens.first { $0.ch.isASCII && $0.ch.isNumber }
        var trimmed = whole; if trimmed.hasSuffix("=") { trimmed.removeLast() }
        let response: String
        if let a = answer, let l = lead, let d = l.ch.wholeNumberValue {
            response = "(\(l.ch), \(words[d]), Integer \(l.ch) \(statement != nil ? "completes the statement" : "solves the statement"): \(trimmed)=\(a))"
        } else if let a = answer { response = "(\(trimmed)=\(a))" }
        else { response = "(" + (enc.tokens.isEmpty ? "nothing to analyze" : "\(enc.tokens.count) data points reflexed" + (enc.field.map { " as field \($0)" } ?? "")) + ")" }
        return Analysis(lines: lines, response: response)
    }

    /// Shell 64 record -> Tool Radian state: kind from its own variable state, angle = 45 degrees / 7 depth levels (6.4 each).
    static func fromRecord(tool: String, bl: Int, rbli: Int) -> String {
        let t = tools.first(where: { $0.value == tool })?.key ?? "e"
        return make(t, false, bl == 0 ? "-" : (rbli >= 1 ? "+" : "b"), min(bl, 7) * 64).text
    }

    /// Chat entry point: reply text when the message is a Tool Radian request (encode / decode / analyze / bare math), else nil.
    static func respond(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var cmd = "", arg = t
        if let re = try? NSRegularExpression(pattern: "^(encode|decode|analy[sz]e|radian)\\b[:\\s]*(.*)$", options: [.caseInsensitive]),
           let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) {
            cmd = (t as NSString).substring(with: m.range(at: 1)).lowercased(); arg = (t as NSString).substring(with: m.range(at: 2))
        } else {
            let mathy = t.allSatisfy { "0123456789+-*/^().= ".contains($0) }
            guard mathy, t.contains(where: { $0.isASCII && $0.isNumber }), t.contains(where: { "+-*/^=".contains($0) }) else { return nil }
        }
        if arg.trimmingCharacters(in: .whitespaces).isEmpty { return "Tool Radian: give me something to \(cmd.isEmpty ? "analyze" : cmd), e.g. \"encode 1+1=\" or \"decode md-0.1\"." }
        if cmd == "decode" {
            let a = arg.trimmingCharacters(in: .whitespaces)
            guard let d = decode(a) else { return "\"\(a)\" is not a legal state (tool m/p/e/h/s/k/r, kind d-/d+/db/d, angle within 45.0 degrees)." }
            let kind = ["-": "data (d-)", "+": "data that can build (d+)", "b": "both (db)", "0": "neutral (d)"][String(d.kind)] ?? ""
            return "\(d.state) = \(d.tool)\(d.field ? " field" : ""), kind \(kind), \(d.deg) degrees" + (d.candidates.isEmpty ? "" : ", reads as " + d.candidates.map(String.init).joined(separator: " or "))
        }
        if cmd == "encode" {
            let e = encode(arg)
            return e.tokens.map { "\($0.ch) = \($0.state)" }.joined(separator: "\n") + (e.field.map { "\n\(e.text) = \($0)" } ?? "")
        }
        let a = analyze(arg)
        return (a.lines.isEmpty ? "" : a.lines.joined(separator: "\n") + "\n") + "LEATR: " + a.response
    }
}
