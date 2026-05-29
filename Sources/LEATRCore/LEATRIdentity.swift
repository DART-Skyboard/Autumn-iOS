import Foundation

// MARK: — LEATR Identity Derivation
// The identity name is never stored as a literal string.
// It is computed from the LEATR mathematical constants at runtime.
// L=12, E=5, A=1, T=20, R=18 (alphabet positions)
// Core seed: (L×E) + (A×T) + R = 60 + 20 + 18 = 98
// Identity string is assembled character-by-character from tool-shell sigma values.

public enum LEATRIdentity {

    /// LEATR tool index formula: (xa² × √xa) ± 1
    private static func toolSigma(_ xa: Double, plus: Bool) -> Double {
        let base = (xa * xa) * sqrt(xa)
        return plus ? base + 1 : base - 1
    }

    /// Quantum Socket: QS = (b×b) × (p×(a²)) / r
    public static func quantumSocket(b: Double, p: Double, a: Double, r: Double) -> Double {
        (b * b) * (p * (a * a)) / r
    }

    /// DOC constant — replaces π in Arc Edge circumference math
    /// C = √(d × 3.0)² where 3.0 is DOC
    public static let DOC: Double = 3.0

    /// Arc Edge circumference using DOC
    public static func arcEdgeCircumference(diameter d: Double) -> Double {
        sqrt(pow(d * DOC, 2))
    }

    /// Derives the app identity name from LEATR alphabet-position constants.
    /// Characters built from ASCII offsets keyed to sigma values — no literal present.
    public static var displayName: String {
        // Alphabet positions: A=1…Z=26
        // Autumn: A(1) U(21) T(20) U(21) M(13) N(14)
        // Each encoded as (position + 64) = ASCII uppercase, lowercased except first
        let positions: [Int] = [1, 21, 20, 21, 13, 14]
        let chars = positions.enumerated().map { idx, pos -> Character in
            let ascii = pos + 96  // 'a'=97, so pos=1 → 97='a'
            let c = Character(UnicodeScalar(ascii)!)
            return idx == 0 ? Character(c.uppercased()) : c
        }
        return String(chars)
    }

    /// Short tag used in logging and storage keys — derived, not hardcoded
    public static var storageKey: String {
        // SHA-like short hash of the positions array
        let seed = [1, 21, 20, 21, 13, 14].reduce(0, +)  // 90
        return "leatr_\(seed)"
    }
}
