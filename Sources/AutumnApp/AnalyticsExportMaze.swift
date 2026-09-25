import Foundation
import LocalAuthentication
import LEATRCore
import AutumnServices

/// TF157: a completely separate maze instance from the one the live BRPN
/// scene solves and regenerates constantly — this one exists purely as a
/// fixed structure to nest analytics export data into, and stays static
/// for as long as the person stays signed in, by design. Reuses
/// MazeEngine's real 3D generator/solver directly rather than
/// reimplementing maze logic, since that's genuinely the same algorithm
/// this needs, just kept as an independent instance with its own
/// lifecycle.
@MainActor
public final class AnalyticsExportMaze: ObservableObject {
    public static let shared = AnalyticsExportMaze()

    @Published public private(set) var grid: [[[OrbMazeCell]]] = []
    @Published public private(set) var width = 10
    @Published public private(set) var height = 10
    @Published public private(set) var depth = 10
    @Published public private(set) var solution: [MazePt] = []
    @Published public private(set) var generatedAt: Date?
    @Published public var solveRevealed = false

    private let defaultsKey = "analyticsExportMaze_v1"

    private init() {
        loadOrGenerate()
        NotificationCenter.default.addObserver(forName: .autumnDidSignIn, object: nil, queue: .main) { [weak self] _ in
            self?.regenerateForNewSession()
        }
    }

    public static let minDimension = 10
    public static let maxDimension = 50

    /// Called once per fresh sign-in (see AuthViewModel) — a genuinely new
    /// session gets a genuinely new maze, matching "next time they log
    /// back in, generate a new one" directly. No Face ID needed here since
    /// this happens automatically, not on demand.
    public func regenerateForNewSession() {
        generate(width: width, height: height, depth: depth)
    }

    /// The on-demand path — always Face ID gated, since this destructively
    /// replaces the maze that's currently the fixed reference structure
    /// for exports.
    public func regenerateWithFaceID(width w: Int, height h: Int, depth d: Int) async -> Bool {
        guard await authenticate() else { return false }
        let cw = min(max(w, Self.minDimension), Self.maxDimension)
        let ch = min(max(h, Self.minDimension), Self.maxDimension)
        let cd = min(max(d, Self.minDimension), Self.maxDimension)
        generate(width: cw, height: ch, depth: cd)
        return true
    }

    private func authenticate() async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // No Face ID/Touch ID enrolled on this device — fall back to
            // the device passcode rather than silently blocking the
            // feature entirely.
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
            return await withCheckedContinuation { cont in
                ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Confirm to generate a new analytics export maze") { ok, _ in
                    cont.resume(returning: ok)
                }
            }
        }
        return await withCheckedContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Confirm to generate a new analytics export maze") { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }

    private func generate(width w: Int, height h: Int, depth d: Int) {
        grid = MazeEngine.orbGenMaze(w, h, d)
        width = w; height = h; depth = d
        solution = MazeEngine.orbSolveMaze(grid, w, h, d)
        generatedAt = Date()
        solveRevealed = false
        persist()
    }

    private func loadOrGenerate() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode(SavedMaze.self, from: data)
        else {
            generate(width: 10, height: 10, depth: 10)
            return
        }
        width = saved.width; height = saved.height; depth = saved.depth
        generatedAt = saved.generatedAt
        grid = saved.grid
        solution = MazeEngine.orbSolveMaze(grid, width, height, depth)
    }

    private func persist() {
        let saved = SavedMaze(width: width, height: height, depth: depth, generatedAt: generatedAt ?? Date(), grid: grid)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private struct SavedMaze: Codable {
        let width: Int, height: Int, depth: Int
        let generatedAt: Date
        let grid: [[[OrbMazeCell]]]
    }

    /// Ordered (x,y,z) → cell list, entrance to exit, for nesting analytics
    /// data along the solution path in the export.
    public func solutionCells() -> [MazePt] { solution }
}
