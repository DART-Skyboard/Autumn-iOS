import Foundation

/// Port of leadEdgeExecutor.mathGlossary + physics/astro/SI + specials (Δ, Γ, ζ).
public enum MathGlossary {
    public static let terms: [String: String] = [
        "+": "Addition — combine magnitudes.",
        "-": "Subtraction — difference of magnitudes.",
        "*": "Multiplication — scaling of magnitudes.",
        "/": "Division — ratio of magnitudes.",
        "^": "Exponentiation — repeated multiplication.",
        "sqrt": "Square root — principal inverse of squaring.",
        "cbrt": "Cube root — principal inverse of cubing.",
        "log": "Logarithm — inverse of exponentiation (base 10 here).",
        "ln": "Natural logarithm — inverse of e^x.",
        "sin": "Sine — opposite over hypotenuse (radians).",
        "cos": "Cosine — adjacent over hypotenuse (radians).",
        "tan": "Tangent — sine over cosine (radians).",
        "delta": "Delta (Δ) — change, discriminant, or Dirac delta in context.",
        "delta_function": "Delta Function (Δ) — distribution that is 1 at 0, 0 elsewhere in this solver.",
        "gamma": "Gamma (Γ) — extension of factorial, Γ(n)=(n-1)! for positive integers.",
        "gamma_function": "Gamma Function (Γ) — Γ(z) = ∫ t^{z-1} e^{-t} dt.",
        "zeta": "Zeta (ζ) — Riemann zeta; ζ(2)=π²/6.",
        "zeta_function": "Zeta Function (ζ) — ζ(s) = Σ n^{-s}.",
        "gravitational_constant": "Gravitational Constant (G) ≈ 6.67430×10⁻¹¹ m³·kg⁻¹·s⁻².",
        "planck_constant": "Planck's Constant (h) = 6.62607015×10⁻³⁴ J·s.",
        "speed_of_light": "Speed of Light (c) = 299792458 m/s.",
        "boltzmann_constant": "Boltzmann Constant (kB) = 1.380649×10⁻²³ J/K.",
        "elementary_charge": "Elementary Charge (e) = 1.602176634×10⁻¹⁹ C.",
        "rydberg_formula": "Rydberg Formula — reciprocal wavelength of hydrogen spectral lines.",
        "astronomical_unit": "Astronomical Unit (AU) — mean Earth–Sun distance, 1.495978707×10¹¹ m.",
        "parsec": "Parsec (pc) — 206265 AU ≈ 3.0857×10¹⁶ m.",
        "light_year": "Light-year (ly) — distance light travels in one Julian year.",
        "solar_mass": "Solar Mass (M☉) ≈ 1.9885×10³⁰ kg.",
        "meter": "Meter (m) — SI length.",
        "kilogram": "Kilogram (kg) — SI mass.",
        "second": "Second (s) — SI time.",
        "ampere": "Ampere (A) — SI electric current.",
        "kelvin": "Kelvin (K) — SI temperature.",
        "mole": "Mole (mol) — SI amount of substance.",
        "candela": "Candela (cd) — SI luminous intensity.",
        "newton": "Newton (N) — SI force, kg·m/s². F = m a.",
        "joule": "Joule (J) — SI energy, N·m.",
        "watt": "Watt (W) — SI power, J/s.",
        "mass": "Mass — inertial/gravitational quantity (kg).",
        "volume": "Volume — space occupied (m³).",
        "weight": "Weight — gravitational force on a mass.",
        "density": "Density — mass per volume, ρ = m/V.",
        "temperature": "Temperature — thermal state (K).",
        "velocity": "Velocity — rate of change of position.",
        "acceleration": "Acceleration — rate of change of velocity. a = Δv/Δt.",
        "force": "Force — F = m a (newton).",
        "energy": "Energy — capacity to do work (joule). E = m c² in rest mass.",
        "power": "Power — energy per time (watt).",
        "pressure": "Pressure — force per area (pascal).",
        "frequency": "Frequency — cycles per second (hertz).",
        "add": "Addition (+).",
        "subtract": "Subtraction (-).",
        "multiply": "Multiplication (*).",
        "divide": "Division (/).",
        "power_op": "Exponent (^).",
        "bio_mole": "Mole — Avogadro amount; biochemistry stoichiometry.",
        "dna": "DNA quantities often use moles of base pairs and Dalton mass.",
        "parsec_astro": "Parsec — astrometry distance from annual parallax of 1 arcsecond."
    ]

    public static let aliases: [String: String] = [
        "delta function": "delta_function", "δ": "delta", "Δ": "delta",
        "gamma function": "gamma_function", "Γ": "gamma", "γ": "gamma",
        "zeta function": "zeta_function", "ζ": "zeta",
        "planck": "planck_constant", "planck's constant": "planck_constant",
        "gravity constant": "gravitational_constant", "big g": "gravitational_constant",
        "speed of light": "speed_of_light", "lightspeed": "speed_of_light",
        "boltzmann": "boltzmann_constant", "kb": "boltzmann_constant",
        "charge": "elementary_charge", "au": "astronomical_unit",
        "ly": "light_year", "m☉": "solar_mass",
        "kg": "kilogram", "m": "meter", "s": "second",
        "n": "newton", "j": "joule", "w": "watt",
        "what is force": "force", "what's force": "force",
        "f=ma": "force", "f=m*a": "force"
    ]

    public static func define(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let d = terms[key] { return "Definition [\(raw)]: \(d)" }
        if let mapped = aliases[key], let d = terms[mapped] { return "Definition [\(raw)]: \(d)" }
        let stripped = key.replacingOccurrences(
            of: #"^(what(?:'s| is)|define|meaning of|glossary)\s+"#,
            with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
        if let d = terms[stripped] { return "Definition [\(stripped)]: \(d)" }
        if let mapped = aliases[stripped], let d = terms[mapped] { return "Definition [\(stripped)]: \(d)" }
        if let id = AlgebraIdentities.match(raw) {
            return "Identity [\(id.name)]: \(id.expansion). \(id.note)"
        }
        return nil
    }

    public static func looksLikeDefinitionAsk(_ raw: String) -> Bool {
        let s = raw.lowercased()
        if s.range(of: #"\b(what is|what's|define|meaning of|glossary)\b"#, options: .regularExpression) != nil {
            let rest = s.replacingOccurrences(
                of: #"^(what(?:'s| is)|define|meaning of|glossary)\s+"#,
                with: "", options: .regularExpression
            )
            if terms[rest] != nil || aliases[rest] != nil { return true }
            if rest.range(of: #"[0-9+\-*/^()]"#, options: .regularExpression) == nil {
                return terms.keys.contains(where: { rest.contains($0) && $0.count > 2 })
                    || aliases.keys.contains(where: { rest.contains($0) })
            }
        }
        let t = s.trimmingCharacters(in: .whitespaces)
        return terms[t] != nil || aliases[t] != nil
    }

    public static let specialOperators: [(id: String, label: String)] = [
        ("delta_function", "Delta Function (Δ)"),
        ("gamma_function", "Gamma Function (Γ)"),
        ("zeta_function", "Zeta Function (ζ)"),
        ("gravitational_constant", "Gravitational Constant (G)"),
        ("planck_constant", "Planck's Constant (h)"),
        ("speed_of_light", "Speed of Light (c)"),
        ("boltzmann_constant", "Boltzmann Constant (kB)"),
        ("elementary_charge", "Elementary Charge (e)")
    ]

    public static let mathOperations: [(id: String, label: String)] = [
        ("add", "Addition (+)"),
        ("subtract", "Subtraction (-)"),
        ("multiply", "Multiplication (*)"),
        ("divide", "Division (/)"),
        ("power", "Exponent (^)"),
        ("sqrt", "Square Root (√)"),
        ("log", "Logarithm (log)"),
        ("sin", "Sine (sin)"),
        ("cos", "Cosine (cos)"),
        ("tan", "Tangent (tan)")
    ]

    public static let physicsFields: [(id: String, label: String)] = [
        ("mass", "Mass"), ("volume", "Volume"), ("weight", "Weight"),
        ("density", "Density"), ("temperature", "Temperature"),
        ("velocity", "Velocity"), ("acceleration", "Acceleration"),
        ("force", "Force"), ("energy", "Energy"), ("power", "Power"),
        ("pressure", "Pressure"), ("frequency", "Frequency")
    ]

    public static func applySpecial(_ id: String) -> Double? {
        switch id {
        case "gravitational_constant": return 6.67430e-11
        case "planck_constant": return 6.62607015e-34
        case "speed_of_light": return 299_792_458
        case "boltzmann_constant": return 1.380649e-23
        case "elementary_charge": return 1.602176634e-19
        default: return nil
        }
    }
}
