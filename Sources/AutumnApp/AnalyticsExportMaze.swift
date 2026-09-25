import Foundation
import LEATRCore
import AutumnServices

/// TF158: rebuilt on the actual system the live BRPN scene's own maze uses
/// (LEMACEngineASH.generateCubic/solveCubic + MazeEngine.cubicShellAndPassageVerts
/// for real per-cell wall+passage geometry, randomized far-apart start/end
/// openings) rather than the simpler orbGenMaze/orbSolveMaze pair this
/// started with — same copy-and-make-independent approach, just pointed at
/// the actual code the live maze uses, per direct instruction to look at
/// that one specifically.
///
/// Face ID requirement removed per direct instruction — regeneration is a
/// plain in-panel action now, no separate confirmation step.
@MainActor
public final class AnalyticsExportMaze: ObservableObject {
    public static let shared = AnalyticsExportMaze()

    @Published public private(set) var cubic: LEMACEngineASH.CubicResult?
    @Published public private(set) var width = 10
    @Published public private(set) var height = 10
    @Published public private(set) var depth = 10
    @Published public private(set) var solution: [MazePt] = []
    @Published public private(set) var generatedAt: Date?
    @Published public var solveRevealed = false
    @Published public var solveAnimated = false

    private let defaultsKey = "analyticsExportMaze_v2"

    private init() {
        loadOrGenerate()
        NotificationCenter.default.addObserver(forName: .autumnDidSignIn, object: nil, queue: .main) { [weak self] _ in
            self?.regenerateForNewSession()
        }
    }

    public static let minDimension = 10
    public static let maxDimension = 50

    /// Called once per fresh sign-in — a genuinely new session gets a
    /// genuinely new maze.
    public func regenerateForNewSession() {
        generate(width: width, height: height, depth: depth)
    }

    /// Plain, in-panel regeneration — no auth step, per direct instruction.
    public func regenerate(width w: Int, height h: Int, depth d: Int) {
        let cw = min(max(w, Self.minDimension), Self.maxDimension)
        let ch = min(max(h, Self.minDimension), Self.maxDimension)
        let cd = min(max(d, Self.minDimension), Self.maxDimension)
        generate(width: cw, height: ch, depth: cd)
    }

    private func generate(width w: Int, height h: Int, depth d: Int) {
        let result = LEMACEngineASH.generateCubic(w, h, d)
        cubic = result
        width = w; height = h; depth = d
        solution = LEMACEngineASH.solveCubic(result)
        generatedAt = Date()
        solveRevealed = false
        persist()
    }

    private func loadOrGenerate() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode(LEMACEngineASH.CubicResult.self, from: data)
        else {
            generate(width: 10, height: 10, depth: 10)
            return
        }
        cubic = saved
        width = saved.w; height = saved.h; depth = saved.d
        solution = LEMACEngineASH.solveCubic(saved)
        generatedAt = (UserDefaults.standard.object(forKey: defaultsKey + "_date") as? Date) ?? Date()
    }

    private func persist() {
        guard let cubic else { return }
        if let data = try? JSONEncoder().encode(cubic) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
            UserDefaults.standard.set(generatedAt, forKey: defaultsKey + "_date")
        }
    }

    /// Ordered (x,y,z) list, entrance to exit, for nesting analytics data
    /// along the solution path — the "quick access index" into the cube
    /// container.
    public func solutionCells() -> [MazePt] { solution }

    /// Entrance/exit openings, in the same (x,y,z,face) form the live
    /// scene marks with its green/red spheres — included in the export so
    /// the path's start/end markers are part of what gets recorded, not
    /// just the cells in between.
    public var startOpening: LEMACEngineASH.Perimeter3D? { cubic?.start }
    public var endOpening: LEMACEngineASH.Perimeter3D? { cubic?.end }
}
