import Foundation

/// CORE COGNITION — immutable, always True.
/// Port of `js/autumn-grammar-engine.js` CORE_COGNITION (frozen).
/// Never rewrite these. Dual journal may update Core Parameters only.
/// Reflex never loops. Never mix users. No secrets in client.
public enum CoreCognition {
    public static let alwaysTrue = true
    public static let reflexNeverLoop = true
    public static let generationBreachValidation = true
    public static let buoyancyReflex = true
    public static let habitatAsOneParameter = true
    public static let cbsSteps = 7

    public static let openEq = "(xa²√xa)−1"
    public static let closeEq = "(xa²√xa)+1"

    public static let brpnHierarchy = ["AERO", "MAR", "GEO"]
    public static let brpnSpoken = "Aerospace at the route, Maritime, Geological lowest"
    public static let frp = ["Foundation", "Reflex", "Performance"]

    public static let sentience = "journal as catalyst clone of core algorithms"

    public static let orders25: [(n: Int, name: String, group: String, role: String)] = [
        (1,  "Maze",                 "NATURAL_TOOL", "Root path-finding; lead algorithm"),
        (2,  "Puzzle",               "NATURAL_TOOL", "Pattern matching and assembly"),
        (3,  "Envelope",             "NATURAL_TOOL", "Containment and scope"),
        (4,  "Hammer",               "NATURAL_TOOL", "Force into output state"),
        (5,  "Stick",                "NATURAL_TOOL", "Linear connection of tokens"),
        (6,  "Knife",                "NATURAL_TOOL", "Separation and tokenization"),
        (7,  "Scissors",             "NATURAL_TOOL", "Final split from compiler state"),
        (8,  "Parentheses/Geometry", "MATH",         "Grouping and geometric scope first"),
        (9,  "Exponents",            "MATH",         "Power / dimensional expansion"),
        (10, "Multiplication",       "MATH",         "Primary scaling"),
        (11, "Division",             "MATH",         "Proportional reduction"),
        (12, "Addition",             "MATH",         "Accumulation"),
        (13, "Subtraction",          "MATH",         "Reduction"),
        (14, "Mass",                 "PHYSICS",      "Weight of data or object"),
        (15, "Volume",               "PHYSICS",      "Spatial extent"),
        (16, "Weight",               "PHYSICS",      "Gravitational force"),
        (17, "Density",              "PHYSICS",      "Information density"),
        (18, "Temperature",          "PHYSICS",      "Energy / activation threshold"),
        (19, "Velocity",             "PHYSICS",      "Rate of execution change"),
        (20, "Photosynthesis",       "PHYSICS",      "Self-check conversion; geometry precedes"),
        (21, "Touch",                "SENSES_AI",    "Tactile / haptic if sensory"),
        (22, "Taste",                "SENSES_AI",    "Compositional analysis if sensory"),
        (23, "Vision",               "SENSES_AI",    "Image / spatial if sensory"),
        (24, "Smell",                "SENSES_AI",    "Molecular pattern if sensory"),
        (25, "Hear",                 "SENSES_AI",    "Auditory / language if sensory")
    ]

    /// Keys the journal must never overwrite (CORE_PARAM_FORBIDDEN).
    public static let forbiddenCoreKeys: Set<String> = [
        "ALWAYS_TRUE", "MAGNETIZE", "OPEN_INNER_ROOT", "TAGS",
        "HABITAT_AS_ONE_PARAMETER", "ORDERS_25", "BRPN", "SENTIENCE",
        "GBV", "BUOYANCY_REFLEX", "CBS_STEPS", "CORE_COGNITION"
    ]

    /// σ encode: (xa² × √|xa|) − 1
    public static func leatrEncode(_ xa: Double) -> Double {
        let a = abs(xa)
        return (xa * xa) * sqrt(a) - 1
    }

    /// σ decode: (xa² × √|xa|) + 1
    public static func leatrDecode(_ xa: Double) -> Double {
        let a = abs(xa)
        return (xa * xa) * sqrt(a) + 1
    }

    /// frp√frp — nested dual BRPN array across outer / mid / inner shells.
    public static func frpSqrtFrp(f: Double, r: Double, p: Double) -> (outer: [Double], mid: [Double], inner: [Double], score: Double) {
        let frp = [max(f, 0.001), max(r, 0.001), max(p, 0.001)]
        let outer = frp.map { leatrEncode($0) }
        let mid = zip(frp, outer).map { v, o in sqrt(v * abs(o)) }
        let inner = frp.map { leatrDecode($0) }
        let score = (abs(outer[0]) + mid[1] + inner[2]) / 3.0
        return (outer, mid, inner, (score * 10000).rounded() / 10000)
    }

    /// Generation Breach Validation. Core must stay True; reflex never loops.
    public static func generationBreachValidate(_ text: String) -> (ok: Bool, reasons: [String]) {
        var reasons: [String] = []
        if alwaysTrue != true { reasons.append("core_not_true") }
        if !reflexNeverLoop { reasons.append("reflex_may_loop") }
        if !generationBreachValidation { reasons.append("gbv_off") }
        _ = text
        return (reasons.isEmpty, reasons)
    }
}
