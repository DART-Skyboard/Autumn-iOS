import Foundation

/// BRPN 3-pass (web BuoyancyPendulumReflexNode.processBatch):
/// Pass 1 Foundation assign → Pass 2 Reflex sort deps → Pass 3 Performance execute
/// then report math/text in original prompt order. Circular deps detected.
public struct MathVarContext: Codable, Sendable, Equatable {
    public var name: String
    public var valueExpr: String?
    public var specialOperator: String?
    public var physicsField: String?
    public var mathOperation: String?

    public init(name: String, valueExpr: String? = nil,
                specialOperator: String? = nil, physicsField: String? = nil,
                mathOperation: String? = nil) {
        self.name = name
        self.valueExpr = valueExpr
        self.specialOperator = specialOperator
        self.physicsField = physicsField
        self.mathOperation = mathOperation
    }

    public var summary: String {
        let bits = [specialOperator, physicsField, mathOperation].compactMap { $0 }.filter { !$0.isEmpty }
        let ctx = bits.isEmpty ? "—" : bits.joined(separator: " · ")
        return "\(name)\(valueExpr.map { " = \($0)" } ?? "")  [\(ctx)]"
    }
}

public struct MathNote: Codable, Sendable, Equatable {
    public var ts: String
    public var prompt: String
    public var report: String
    public var identity: String?
}

public struct MathSnapshot: Codable, Sendable {
    public var version: String
    public var project: String
    public var saved: String
    public var platform: String
    public var variables: [String: Double]
    public var contexts: [String: MathVarContext]
    public var notes: [MathNote]
    public var lastBatch: String
    public var identitiesUsed: [String]
    public var selfOptimize: Bool
}

public struct BRPNBatchResult: Sendable {
    public var report: String
    public var lines: [String]
    public var env: [String: Double]
    public var circular: [String]
    public var identities: [String]
}

public struct MathWorkspace: Sendable {
    public var project: String
    public var env: [String: Double]
    public var contexts: [String: MathVarContext]
    public var notes: [MathNote]
    public var lastBatch: String
    public var identitiesUsed: [String]

    public init(project: String = "default") {
        self.project = project
        self.env = ["m": 0, "p": 0, "e": 0, "h": 0, "s": 0, "k": 0, "z": 0]
        self.contexts = [:]
        self.notes = []
        self.lastBatch = ""
        self.identitiesUsed = []
    }

    public mutating func assignContext(_ ctx: MathVarContext) {
        contexts[ctx.name] = ctx
        if let spec = ctx.specialOperator, let v = MathGlossary.applySpecial(spec) {
            env[ctx.name] = v
        }
        if let expr = ctx.valueExpr, let node = MathParser.parseNode(expr),
           let v = MathEval.value(node, env: env) {
            env[ctx.name] = v
        }
    }

    public mutating func remember(prompt: String, report: String, identity: String?) {
        let ts = ISO8601DateFormatter().string(from: Date())
        notes.append(MathNote(ts: ts, prompt: prompt, report: report, identity: identity))
        if notes.count > 80 { notes = Array(notes.suffix(80)) }
        if let identity { if !identitiesUsed.contains(identity) { identitiesUsed.append(identity) } }
        lastBatch = report
    }

    public func snapshot() -> MathSnapshot {
        MathSnapshot(
            version: "3.0",
            project: project,
            saved: ISO8601DateFormatter().string(from: Date()),
            platform: "ios",
            variables: env,
            contexts: contexts,
            notes: notes,
            lastBatch: lastBatch,
            identitiesUsed: identitiesUsed,
            selfOptimize: true
        )
    }

    public mutating func restore(_ snap: MathSnapshot) {
        project = snap.project
        env = snap.variables
        contexts = snap.contexts
        notes = snap.notes
        lastBatch = snap.lastBatch
        identitiesUsed = snap.identitiesUsed
    }
}

public enum BRPNMathBatch {
    public static func process(_ prompts: [String], workspace: inout MathWorkspace) -> BRPNBatchResult {
        var env = workspace.env
        var finalAssign: [String: String] = [:]
        var receipts: [(original: String, math: String?, assign: (var: String, expr: String)?, text: String?)] = []
        let textOnly = try! NSRegularExpression(pattern: #"^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*$"#)
        let assignment = try! NSRegularExpression(pattern: #"^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$"#)

        // Pass 1 — Foundation
        for prompt in prompts {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            var math: String? = nil
            var assign: (String, String)? = nil
            var text: String? = nil
            let ns = trimmed as NSString
            if textOnly.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) != nil,
               MathParser.parseNode(trimmed) == nil || MathGlossary.define(trimmed) != nil,
               trimmed.range(of: #"[+\-*/^()]"#, options: .regularExpression) == nil {
                text = trimmed
            } else if let m = assignment.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
                      m.numberOfRanges >= 3 {
                let v = ns.substring(with: m.range(at: 1))
                let e = ns.substring(with: m.range(at: 2))
                assign = (v, e)
                finalAssign[v] = e
            } else {
                math = trimmed
            }
            receipts.append((trimmed, math, assign, text))
        }

        // Pass 2 — Reflex dependency sort
        var nodes: [String: (expr: String, deps: [String])] = [:]
        let reserved = MathRuntime.functions.union(MathRuntime.consts.keys)
        for (name, expr) in finalAssign {
            var deps: [String] = []
            if let node = MathParser.parseNode(expr) {
                deps = node.variables().filter { finalAssign[$0] != nil && !reserved.contains($0) }
            }
            nodes[name] = (expr, deps)
        }
        var sorted: [(String, String)] = []
        var circular: [String] = []
        var guardCount = nodes.count + 1
        var i = 0
        while !nodes.isEmpty && i < guardCount {
            let ready = nodes.filter { $0.value.deps.isEmpty }.map(\.key)
            if ready.isEmpty {
                circular = Array(nodes.keys)
                for (k, v) in nodes { sorted.append((k, v.expr)) }
                break
            }
            for name in ready {
                if let n = nodes[name] {
                    sorted.append((name, n.expr))
                    nodes.removeValue(forKey: name)
                    for k in nodes.keys {
                        nodes[k]?.deps.removeAll { $0 == name }
                    }
                }
            }
            i += 1
        }

        // Pass 3 — Performance execute assignments
        var logs: [String] = []
        if !circular.isEmpty {
            logs.append("Circular dependency detected: \(circular.joined(separator: ", ")).")
        }
        logs.append("Reflex order: \(sorted.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")).")
        for (name, expr) in sorted {
            if let node = MathParser.parseNode(expr), let v = MathEval.value(node, env: env) {
                env[name] = v
                logs.append("Assignment \(name) = \(expr) → \(MathEval.format(v)).")
            } else {
                logs.append("Assignment \(name) = \(expr) held (needs values).")
            }
        }

        // Report in original prompt order
        var lines: [String] = []
        var identities: [String] = []
        for r in receipts {
            var out: [String] = []
            if let math = r.math {
                out.append(solveLine(math, env: env, identities: &identities))
            }
            if let a = r.assign {
                if let v = env[a.var] {
                    out.append("\(a.var) = \(a.expr) → \(a.var) = \(MathEval.format(v)).")
                } else {
                    out.append("\(a.var) = \(a.expr) (assignment recorded).")
                }
            }
            if let t = r.text {
                if let def = MathGlossary.define(t) {
                    out.append(def)
                } else {
                    out.append(textAnalyze(t))
                }
            }
            if !out.isEmpty {
                lines.append("Prompt: \"\(r.original)\"\n" + out.joined(separator: "\n"))
            }
        }
        workspace.env = env
        let report: String
        if lines.isEmpty {
            report = logs.joined(separator: " ") + " Batch processed. No math or text tasks to display."
        } else {
            report = (logs + lines).joined(separator: "\n\n")
        }
        let identityNote = identities.first
        if let first = receipts.first {
            workspace.remember(prompt: first.original, report: report, identity: identityNote)
        }
        return BRPNBatchResult(report: report, lines: lines, env: env, circular: circular, identities: identities)
    }

    public static func solveLine(_ raw: String, env: [String: Double], identities: inout [String]) -> String {
        let expr = MathNL.toExpr(raw) ?? raw
        if let id = AlgebraIdentities.match(expr) {
            identities.append(id.id)
            var extra = ""
            if let node = MathParser.parseNode(id.expansion.replacingOccurrences(of: " ", with: "")),
               let v = MathEval.value(node, env: env) {
                extra = " Numeric: \(MathEval.format(v))."
            } else if let stmt = MathParser.parse(expr) {
                switch stmt {
                case .expr(let n):
                    if let v = MathEval.value(n, env: env) { extra = " Numeric: \(MathEval.format(v))." }
                case .assign(let name, let n):
                    if let v = MathEval.value(n, env: env) { extra = " \(name) = \(MathEval.format(v))." }
                case .equation(let l, let r):
                    extra = solveEquation(l, r, env: env)
                case .text: break
                }
            }
            return "\(id.latex.replacingOccurrences(of: "\\", with: "")). \(id.note).\(extra) Geometry (parentheses) first, then exponents, multiply/divide, add/subtract — Natural Tool math orders, not the web."
        }
        guard let stmt = MathParser.parse(expr) else {
            if let def = MathGlossary.define(raw) { return def }
            return "Could not parse: \(raw)"
        }
        switch stmt {
        case .expr(let n):
            if let v = MathEval.value(n, env: env) {
                return "\(n.infix) = \(MathEval.format(v)). Geometry (parentheses) first, then exponents, multiply/divide, add/subtract — Natural Tool math orders, not the web."
            }
            return "\(n.infix) held — unknowns \(n.variables().sorted().joined(separator: ", ")). LaTeX: \(n.latex)"
        case .assign(let name, let n):
            if let v = MathEval.value(n, env: env) {
                return "\(name) = \(n.infix) → \(MathEval.format(v))."
            }
            return "\(name) = \(n.infix) (symbolic). LaTeX: \(n.latex)"
        case .equation(let l, let r):
            let s = solveEquation(l, r, env: env)
            return "\(l.infix) = \(r.infix). \(s)"
        case .text(let t):
            return MathGlossary.define(t) ?? t
        }
    }

    /// Linear-ish isolate when one unknown remains.
    public static func solveEquation(_ l: MathNode, _ r: MathNode, env: [String: Double]) -> String {
        if let lv = MathEval.value(l, env: env), let rv = MathEval.value(r, env: env) {
            let ok = abs(lv - rv) < 1e-8
            return ok ? "Both sides = \(MathEval.format(lv))." : "Left \(MathEval.format(lv)) ≠ right \(MathEval.format(rv))."
        }
        let unknowns = l.variables().union(r.variables()).subtracting(Set(env.keys))
        if unknowns.count == 1, let u = unknowns.first {
            if case .variable(let name) = l, name == u, let rv = MathEval.value(r, env: env) {
                return "Solve \(u) = \(MathEval.format(rv))."
            }
            if case .variable(let name) = r, name == u, let lv = MathEval.value(l, env: env) {
                return "Solve \(u) = \(MathEval.format(lv))."
            }
            if case .binary("*", .variable(let name), let other) = r, name == u,
               let lv = MathEval.value(l, env: env), let o = MathEval.value(other, env: env), o != 0 {
                return "Solve \(u) = \(MathEval.format(lv / o))."
            }
            if case .binary("*", let other, .variable(let name)) = r, name == u,
               let lv = MathEval.value(l, env: env), let o = MathEval.value(other, env: env), o != 0 {
                return "Solve \(u) = \(MathEval.format(lv / o))."
            }
            if case .binary("*", .variable(let name), let other) = l, name == u,
               let rv = MathEval.value(r, env: env), let o = MathEval.value(other, env: env), o != 0 {
                return "Solve \(u) = \(MathEval.format(rv / o))."
            }
            if case .binary("*", let other, .variable(let name)) = l, name == u,
               let rv = MathEval.value(r, env: env), let o = MathEval.value(other, env: env), o != 0 {
                return "Solve \(u) = \(MathEval.format(rv / o))."
            }
            return "One unknown \(u) — assign a value or context in Math Solver."
        }
        return "Symbolic. Unknowns: \(unknowns.sorted().joined(separator: ", ")). LaTeX: \(l.latex) = \(r.latex)"
    }

    public static func textAnalyze(_ text: String) -> String {
        let lower = text.lowercased()
        var v = 0, c = 0, n = 0, o = 0
        for ch in lower {
            if "aeiou".contains(ch) { v += 1 }
            else if "bcdfghjklmnpqrstvwxyz".contains(ch) { c += 1 }
            else if ch.isNumber { n += 1 }
            else if ch != " " { o += 1 }
        }
        return "Basic analysis for \"\(text)\": [V: \(v), C: \(c), N: \(n), O: \(o)]"
    }
}
