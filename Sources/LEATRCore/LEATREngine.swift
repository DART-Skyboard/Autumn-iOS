import Foundation

// MARK: — LEATR Core Engine v2.0
// 25 Natural Orders of Operation
// 7 Natural Tools → 7-panel glass pipeline
// 3 BRPN shells: Geological / Maritime / Aerospace

// MARK: — Natural Tool
public enum NaturalTool: Int, CaseIterable, Sendable {
    case maze      = 1   // Master sigma / pathfinding (Geological)
    case puzzle    = 2   // Affix structure (Maritime)
    case envelope  = 3   // Syllable boundary (Maritime)
    case hammer    = 4   // Consonant density (Aerospace)
    case stick     = 5   // Vowel-order trend (Maritime)
    case knife     = 6   // CVC detection (Aerospace)
    case scissors  = 7   // Terminal consonant (Geological)

    /// σ = (xa² × √xa) ± 1
    public var sigma: (plus: Double, minus: Double) {
        let xa = Double(rawValue)
        let base = (xa * xa) * sqrt(xa)
        return (plus: base + 1, minus: base - 1)
    }

    public var shell: BRPNShell {
        switch self {
        case .maze, .scissors: return .geological
        case .puzzle, .envelope, .stick: return .maritime
        case .hammer, .knife: return .aerospace
        }
    }

    public var displayName: String {
        switch self {
        case .maze: return "Maze"
        case .puzzle: return "Puzzle"
        case .envelope: return "Envelope"
        case .hammer: return "Hammer"
        case .stick: return "Stick"
        case .knife: return "Knife"
        case .scissors: return "Scissors"
        }
    }
}

// MARK: — BRPN Shell
public enum BRPNShell: Int, CaseIterable, Sendable {
    case geological = 0   // Outer — FOUNDATION
    case maritime   = 1   // Middle — REFLEX
    case aerospace  = 2   // Inner — PERFORMANCE

    public var displayName: String {
        switch self {
        case .geological: return "Geological"
        case .maritime: return "Maritime"
        case .aerospace: return "Aerospace"
        }
    }

    public var role: String {
        switch self {
        case .geological: return "FOUNDATION"
        case .maritime: return "REFLEX"
        case .aerospace: return "PERFORMANCE"
        }
    }
}

// MARK: — FRP Result (per shell)
public struct FRPResult: Sendable {
    public let outer: Double
    public let mid: Double
    public let inner: Double
    public let score: Double    // 0.000 – 1.000 buoyancy

    public var allocated: Bool { score >= 0.5 }

    public init(f: Double, r: Double, p: Double) {
        // outer = leatrEncode(f,r,p)  → (f+r+p) / 3.0
        // mid   = √(frp × outer)
        // inner = leatrDecode(f,r,p)  → (f*r*p) / max(f,r,p,1)
        let o = (f + r + p) / 3.0
        let frp = f * r * p
        let m = sqrt(frp * o)
        let mx = Swift.max(f, r, p, 1)
        let i = frp / mx
        let s = (abs(o) + m + i) / 3.0
        self.outer = o
        self.mid   = m
        self.inner = i
        self.score = Swift.min(1.0, Swift.max(0.0, s / 100.0))  // normalise
    }
}

// MARK: — Panel Result (one of 7 panels)
public struct PanelResult: Sendable {
    public let tool: NaturalTool
    public let frp: FRPResult
    public let allocated: Bool
    public let sigma: Double
}

// MARK: — LEATR Engine
public actor LEATREngine {

    public static let shared = LEATREngine()

    // 25 orders: 1–7 Natural Tools, 8–19 Math/Physics, 20–25 Direct Initial Subset
    public let naturalOrders: [String] = [
        // 1–7
        "Maze", "Puzzle", "Envelope", "Hammer", "Stick", "Knife", "Scissors",
        // 8–19
        "Geometry", "Exponents", "Multiplication", "Division", "Addition",
        "Subtraction", "Logarithm", "Trigonometry", "Temperature", "Velocity",
        "Pressure", "Mass",
        // 20–25 Direct Initial Subset
        "Photosynthesis", "Touch", "Taste", "Vision", "Smell", "Hear"
    ]

    // MARK: — 7-Panel Glass Pipeline
    /// Pass prompt metrics through all 7 tool panels.
    /// All 7 must allocate (T) before orders 8–19 execute.
    public func runPipeline(f: Double, r: Double, p: Double) -> [PanelResult] {
        NaturalTool.allCases.map { tool in
            let xa = Double(tool.rawValue)
            let frp = FRPResult(f: f * xa, r: r * xa, p: p * xa)
            let s = frp.allocated ? tool.sigma.plus : tool.sigma.minus
            return PanelResult(tool: tool, frp: frp, allocated: frp.allocated, sigma: s)
        }
    }

    /// Returns true if all 7 panels allocate → response generation proceeds
    public func pipelineClears(panels: [PanelResult]) -> Bool {
        panels.allSatisfy(\.allocated)
    }

    // MARK: — Quantum Socket coupling
    /// QS = (b×b) × (p×(a²)) / r
    public func quantumSocket(b: Double, p: Double, a: Double, r: Double) -> Double {
        guard r != 0 else { return 0 }
        return (b * b) * (p * (a * a)) / r
    }

    // MARK: — Sigma Master (Maze arbitration)
    /// Final tool routing after forward + backward pass
    public func masterSigma(panels: [PanelResult]) -> NaturalTool {
        // Maze (tool 1) arbitrates: picks the panel with highest buoyancy
        panels.max(by: { $0.frp.score < $1.frp.score })?.tool ?? .maze
    }
}
