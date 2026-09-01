import Foundation

// MARK: — MazeEngine
// 1:1 ports of web maze generators. Do not invent a different maze.
//
// JS map:
//   orbGenMaze / orbSolveMaze / mazeOrbState     → index.html ~13017–13148  (BRPN core cube)
//   generateMaze / solveMaze                     → js/mist-module.js ~751–802 (MIST 2D)
//   LEMAC_ENGINE_ASH.generateCubic / solveCubic  → index.html ~17859–18032  (Ash/LEMAC sigma)

// ═══════════════════════════════════════════════════════════════════════════
//  CORE ORB MAZE  — index.html orbGenMaze / orbSolveMaze / mazeOrbState
//  Cells: { top, bottom, left, right, front, back, visited }
//  Grid indexed [z][y][x]. Stack from (0,0,0). Neighbor order:
//    left, right, bottom, top, back, front. Pick with Math.random.
// ═══════════════════════════════════════════════════════════════════════════

/// JS: cell `{top,bottom,left,right,front,back,visited}` — true = wall present
public struct OrbMazeCell {
    public var top = true
    public var bottom = true
    public var left = true
    public var right = true
    public var front = true
    public var back = true
    public var visited = false
    public init() {}

    /// JS: `grid[z][y][x][dir]`
    public subscript(_ dir: String) -> Bool {
        get {
            switch dir {
            case "top": return top
            case "bottom": return bottom
            case "left": return left
            case "right": return right
            case "front": return front
            case "back": return back
            default: return true
            }
        }
        set {
            switch dir {
            case "top": top = newValue
            case "bottom": bottom = newValue
            case "left": left = newValue
            case "right": right = newValue
            case "front": front = newValue
            case "back": back = newValue
            default: break
            }
        }
    }
}

/// JS: `{x,y,z}` maze coordinate
public struct MazePt: Equatable, Hashable {
    public var x: Int
    public var y: Int
    public var z: Int
    public init(x: Int, y: Int, z: Int) { self.x = x; self.y = y; self.z = z }
}

/// JS: mazeOrbState = {grid,width:7,height:7,depth:7,solution,pathMeshes,frame,solveStep,solveActive,regenTimer}
public struct MazeOrbState {
    public var grid: [[[OrbMazeCell]]] = []
    public var width: Int = 7
    public var height: Int = 7
    public var depth: Int = 7
    public var solution: [MazePt] = []
    public var frame: Int = 0
    public var solveStep: Int = 0
    public var solveActive: Bool = false
    public var regenTimer: Int = 0
    /// JS: cell size `u=0.065` — fits inside core sphere (~0.18 radius)
    public static let u: Float = 0.065
    public init() {}
}

public enum MazeEngine {

    // MARK: — orbGenMaze(w,h,d)  index.html 13025–13048
    /// Recursive-backtracker 3D. Returns grid[z][y][x].
    public static func orbGenMaze(_ w: Int, _ h: Int, _ d: Int) -> [[[OrbMazeCell]]] {
        // JS: Array.from({length:d},()=>Array.from({length:h},()=>Array.from({length:w},()=>({...}))))
        var grid: [[[OrbMazeCell]]] = (0..<d).map { _ in
            (0..<h).map { _ in
                (0..<w).map { _ in OrbMazeCell() }
            }
        }
        var stack: [MazePt] = [MazePt(x: 0, y: 0, z: 0)]
        grid[0][0][0].visited = true
        while !stack.isEmpty {
            let curr = stack[stack.count - 1]
            var ns: [(x: Int, y: Int, z: Int, d1: String, d2: String)] = []
            // Neighbor order matches JS exactly: left, right, bottom, top, back, front
            if curr.x > 0 && !grid[curr.z][curr.y][curr.x - 1].visited {
                ns.append((curr.x - 1, curr.y, curr.z, "left", "right"))
            }
            if curr.x < w - 1 && !grid[curr.z][curr.y][curr.x + 1].visited {
                ns.append((curr.x + 1, curr.y, curr.z, "right", "left"))
            }
            if curr.y > 0 && !grid[curr.z][curr.y - 1][curr.x].visited {
                ns.append((curr.x, curr.y - 1, curr.z, "bottom", "top"))
            }
            if curr.y < h - 1 && !grid[curr.z][curr.y + 1][curr.x].visited {
                ns.append((curr.x, curr.y + 1, curr.z, "top", "bottom"))
            }
            if curr.z > 0 && !grid[curr.z - 1][curr.y][curr.x].visited {
                ns.append((curr.x, curr.y, curr.z - 1, "back", "front"))
            }
            if curr.z < d - 1 && !grid[curr.z + 1][curr.y][curr.x].visited {
                ns.append((curr.x, curr.y, curr.z + 1, "front", "back"))
            }
            if !ns.isEmpty {
                // JS: ns[Math.floor(Math.random()*ns.length)]
                let next = ns[Int.random(in: 0..<ns.count)]
                grid[curr.z][curr.y][curr.x][next.d1] = false
                grid[next.z][next.y][next.x][next.d2] = false
                grid[next.z][next.y][next.x].visited = true
                stack.append(MazePt(x: next.x, y: next.y, z: next.z))
            } else {
                stack.removeLast()
            }
        }
        return grid
    }

    // MARK: — orbSolveMaze(grid,w,h,d)  index.html 13051–13073
    /// BFS from (0,0,0) to (w-1,h-1,d-1)
    public static func orbSolveMaze(_ grid: [[[OrbMazeCell]]], _ w: Int, _ h: Int, _ d: Int) -> [MazePt] {
        func key(_ x: Int, _ y: Int, _ z: Int) -> String { "\(x),\(y),\(z)" }
        var queue: [(x: Int, y: Int, z: Int, path: [MazePt])] = [
            (0, 0, 0, [MazePt(x: 0, y: 0, z: 0)])
        ]
        var visited = Set<String>([key(0, 0, 0)])
        let goal = key(w - 1, h - 1, d - 1)
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            if key(cur.x, cur.y, cur.z) == goal { return cur.path }
            let c = grid[cur.z][cur.y][cur.x]
            var moves: [MazePt] = []
            if !c.left && cur.x > 0 { moves.append(MazePt(x: cur.x - 1, y: cur.y, z: cur.z)) }
            if !c.right && cur.x < w - 1 { moves.append(MazePt(x: cur.x + 1, y: cur.y, z: cur.z)) }
            if !c.bottom && cur.y > 0 { moves.append(MazePt(x: cur.x, y: cur.y - 1, z: cur.z)) }
            if !c.top && cur.y < h - 1 { moves.append(MazePt(x: cur.x, y: cur.y + 1, z: cur.z)) }
            if !c.back && cur.z > 0 { moves.append(MazePt(x: cur.x, y: cur.y, z: cur.z - 1)) }
            if !c.front && cur.z < d - 1 { moves.append(MazePt(x: cur.x, y: cur.y, z: cur.z + 1)) }
            for n in moves {
                let nk = key(n.x, n.y, n.z)
                if !visited.contains(nk) {
                    visited.insert(nk)
                    queue.append((n.x, n.y, n.z, cur.path + [n]))
                }
            }
        }
        return []
    }

    // MARK: — buildOrbMazeGeometry wall verts  index.html 13076–13118
    /// LineSegments of wall QUAD OUTLINES only for left / bottom / back faces (not all 6).
    /// Returns interleaved xyz floats, 2 verts per line segment.
    public static func orbMazeWallVerts(grid: [[[OrbMazeCell]]], w: Int, h: Int, d: Int, u: Float = MazeOrbState.u) -> [Float] {
        var wallVerts: [Float] = []
        let ox = (Float(w) * u) / 2
        let oy = (Float(h) * u) / 2
        let oz = (Float(d) * u) / 2
        let hs = u * 0.5
        for z in 0..<d {
            for y in 0..<h {
                for x in 0..<w {
                    let c = grid[z][y][x]
                    let cx = Float(x) * u - ox + hs
                    let cy = Float(y) * u - oy + hs
                    let cz = Float(z) * u - oz + hs
                    if c.left {
                        let px = cx - hs, py0 = cy - hs, py1 = cy + hs, pz0 = cz - hs, pz1 = cz + hs
                        wallVerts += [px, py0, pz0, px, py1, pz0,  px, py1, pz0, px, py1, pz1,  px, py1, pz1, px, py0, pz1,  px, py0, pz1, px, py0, pz0]
                    }
                    if c.bottom {
                        let py = cy - hs, px0 = cx - hs, px1 = cx + hs, pz0 = cz - hs, pz1 = cz + hs
                        wallVerts += [px0, py, pz0, px1, py, pz0,  px1, py, pz0, px1, py, pz1,  px1, py, pz1, px0, py, pz1,  px0, py, pz1, px0, py, pz0]
                    }
                    if c.back {
                        let pz = cz - hs, px0 = cx - hs, px1 = cx + hs, py0 = cy - hs, py1 = cy + hs
                        wallVerts += [px0, py0, pz, px1, py0, pz,  px1, py0, pz, px1, py1, pz,  px1, py1, pz, px0, py1, pz,  px0, py1, pz, px0, py0, pz]
                    }
                }
            }
        }
        return wallVerts
    }

    public static func orbCellCenter(x: Int, y: Int, z: Int, w: Int, h: Int, d: Int, u: Float = MazeOrbState.u) -> (Float, Float, Float) {
        let ox = (Float(w) * u) / 2
        let oy = (Float(h) * u) / 2
        let oz = (Float(d) * u) / 2
        let hs = u * 0.5
        return (Float(x) * u - ox + hs, Float(y) * u - oy + hs, Float(z) * u - oz + hs)
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  MIST 2D  — js/mist-module.js generateMaze / solveMaze  751–802
    //  Walls n/s/e/w as 1=wall 0=open. carve(0,0). Entry/exit sides, LOS reject,
    //  sol.length < (w+h)/1.4 reject. DIFF: I 5×5, II 9×9, III 13×13.
    // ═══════════════════════════════════════════════════════════════════════

    /// JS: `{n:1,s:1,e:1,w:1,v:false}`  — 1 = wall present, 0 = open
    public struct MistCell {
        public var n: Int = 1
        public var s: Int = 1
        public var e: Int = 1
        public var w: Int = 1
        public var v: Bool = false
        public init() {}
        public subscript(_ dir: String) -> Int {
            get {
                switch dir {
                case "n": return n
                case "s": return s
                case "e": return e
                case "w": return w
                default: return 1
                }
            }
            set {
                switch dir {
                case "n": n = newValue
                case "s": s = newValue
                case "e": e = newValue
                case "w": w = newValue
                default: break
                }
            }
        }
    }

    public struct MistPt: Equatable {
        public var x: Int
        public var y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    public struct MistMaze {
        public var grid: [[MistCell]]
        public var w: Int
        public var h: Int
        public var entry: MistPt
        public var exit: MistPt
        public var entrySide: String
        public var exitSide: String
        public var solution: [MistPt]?
        public var solved: Bool = false
        public init(grid: [[MistCell]], w: Int, h: Int, entry: MistPt, exit: MistPt, entrySide: String, exitSide: String, solution: [MistPt]?, solved: Bool = false) {
            self.grid = grid; self.w = w; self.h = h
            self.entry = entry; self.exit = exit
            self.entrySide = entrySide; self.exitSide = exitSide
            self.solution = solution; self.solved = solved
        }
    }

    /// JS: `var DIFF = {1:{w:5,h:5},2:{w:9,h:9},3:{w:13,h:13}};`
    public static let mistDIFF: [Int: (w: Int, h: Int)] = [1: (5, 5), 2: (9, 9), 3: (13, 13)]

    /// JS: generateMaze(w,h)  mist-module.js 751–787
    public static func generateMaze(_ w: Int, _ h: Int) -> MistMaze {
        var grid: [[MistCell]] = (0..<h).map { _ in (0..<w).map { _ in MistCell() } }

        func carve(_ x: Int, _ y: Int) {
            grid[y][x].v = true
            // JS: d=[['n',0,-1],['s',0,1],['e',1,0],['w',-1,0]]; d.sort(function(){return Math.random()-.5;});
            var d: [(String, Int, Int)] = [("n", 0, -1), ("s", 0, 1), ("e", 1, 0), ("w", -1, 0)]
            d.sort { _, _ in Double.random(in: 0..<1) - 0.5 < 0 }
            for dd in d {
                let nx = x + dd.1, ny = y + dd.2
                if nx >= 0 && nx < w && ny >= 0 && ny < h && !grid[ny][nx].v {
                    grid[y][x][dd.0] = 0
                    let opp: [String: String] = ["n": "s", "s": "n", "e": "w", "w": "e"]
                    grid[ny][nx][opp[dd.0]!] = 0
                    carve(nx, ny)
                }
            }
        }
        carve(0, 0)

        func ps() -> String { ["n", "s", "e", "w"][Int.random(in: 0..<4)] }
        func pp(_ s: String) -> Int {
            (s == "n" || s == "s") ? Int.random(in: 0..<w) : Int.random(in: 0..<h)
        }
        func cs(_ s: String, _ p: Int) -> MistPt {
            if s == "n" { return MistPt(x: p, y: 0) }
            if s == "s" { return MistPt(x: p, y: h - 1) }
            if s == "w" { return MistPt(x: 0, y: p) }
            return MistPt(x: w - 1, y: p)
        }

        var es = "n", ep = 0, xs = "s", xp = 0
        var entry = MistPt(x: 0, y: 0)
        var exit = MistPt(x: w - 1, y: h - 1)
        var att = 0
        var ok = false
        while !ok && att < 500 {
            att += 1
            es = ps(); ep = pp(es); xs = ps(); xp = pp(xs)
            if es == xs && abs(ep - xp) < 2 { continue }
            entry = cs(es, ep)
            exit = cs(xs, xp)
            func los(_ a: MistPt, _ b: MistPt) -> Bool {
                if a.x == b.x {
                    let y1 = min(a.y, b.y), y2 = max(a.y, b.y)
                    var ty = y1
                    while ty < y2 {
                        if grid[ty][a.x].s != 0 { return false }
                        ty += 1
                    }
                    return true
                }
                if a.y == b.y {
                    let x1 = min(a.x, b.x), x2 = max(a.x, b.x)
                    var tx = x1
                    while tx < x2 {
                        if grid[a.y][tx].e != 0 { return false }
                        tx += 1
                    }
                    return true
                }
                return false
            }
            if los(entry, exit) { continue }
            let probe = MistMaze(grid: grid, w: w, h: h, entry: entry, exit: exit, entrySide: es, exitSide: xs, solution: nil)
            let sol = solveMaze(probe)
            if sol == nil || Double(sol!.count) < Double(w + h) / 1.4 { continue }
            ok = true
        }
        grid[entry.y][entry.x][es] = 0
        grid[exit.y][exit.x][xs] = 0
        let built = MistMaze(grid: grid, w: w, h: h, entry: entry, exit: exit, entrySide: es, exitSide: xs, solution: nil)
        return MistMaze(grid: grid, w: w, h: h, entry: entry, exit: exit, entrySide: es, exitSide: xs, solution: solveMaze(built))
    }

    /// JS: solveMaze(maze)  mist-module.js 788–802
    public static func solveMaze(_ maze: MistMaze) -> [MistPt]? {
        var q: [(x: Int, y: Int, path: [MistPt])] = [
            (maze.entry.x, maze.entry.y, [MistPt(x: maze.entry.x, y: maze.entry.y)])
        ]
        var seen: [String: Bool] = ["\(maze.entry.x),\(maze.entry.y)": true]
        // JS Object.keys insertion order: n, s, e, w
        let dirs: [(String, Int, Int)] = [("n", 0, -1), ("s", 0, 1), ("e", 1, 0), ("w", -1, 0)]
        while !q.isEmpty {
            let c = q.removeFirst()
            if c.x == maze.exit.x && c.y == maze.exit.y { return c.path }
            let cell = maze.grid[c.y][c.x]
            for d in dirs {
                if cell[d.0] == 0 {
                    let nx = c.x + d.1, ny = c.y + d.2
                    let k = "\(nx),\(ny)"
                    if nx >= 0 && nx < maze.w && ny >= 0 && ny < maze.h && seen[k] != true {
                        seen[k] = true
                        q.append((nx, ny, c.path + [MistPt(x: nx, y: ny)]))
                    }
                }
            }
        }
        return nil
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  LEMAC_ENGINE_ASH  — index.html 17779–18032
    //  Two-branch degree-map sigma solver. SIGMA SOLVE on the Ash/MIST studio
    //  cube MUST use this, not generic BFS.
    // ═══════════════════════════════════════════════════════════════════════
}

/// JS: `const LEMAC_ENGINE_ASH = { mode, engine, generatePlanar, generateCubic, solvePlanar, solveCubic }`
public enum LEMACEngineASH {
    public static var mode: String = "cubic"
    public static var engine: String = "chat"

    public struct Perimeter2D {
        public var x: Int
        public var y: Int
        public var face: String
        public init(x: Int, y: Int, face: String) { self.x = x; self.y = y; self.face = face }
    }
    public struct Perimeter3D {
        public var x: Int
        public var y: Int
        public var z: Int
        public var face: String
        public init(x: Int, y: Int, z: Int, face: String) { self.x = x; self.y = y; self.z = z; self.face = face }
    }
    public struct PlanarResult {
        public var grid: [[OrbMazeCell]]
        public var start: Perimeter2D
        public var end: Perimeter2D
        public var w: Int
        public var h: Int
        public init(grid: [[OrbMazeCell]], start: Perimeter2D, end: Perimeter2D, w: Int, h: Int) {
            self.grid = grid; self.start = start; self.end = end; self.w = w; self.h = h
        }
    }
    public struct CubicResult {
        public var grid: [[[OrbMazeCell]]]
        public var start: Perimeter3D
        public var end: Perimeter3D
        public var w: Int
        public var h: Int
        public var d: Int
        public init(grid: [[[OrbMazeCell]]], start: Perimeter3D, end: Perimeter3D, w: Int, h: Int, d: Int) {
            self.grid = grid; self.start = start; self.end = end; self.w = w; self.h = h; self.d = d
        }
    }

    // MARK: — generatePlanar(w,h)  index.html 17818–17845
    public static func generatePlanar(_ w: Int, _ h: Int) -> PlanarResult {
        var grid: [[OrbMazeCell]] = (0..<h).map { _ in (0..<w).map { _ in OrbMazeCell() } }
        var stack: [(x: Int, y: Int)] = [(0, 0)]
        grid[0][0].visited = true
        while !stack.isEmpty {
            let curr = stack[stack.count - 1]
            var ns: [(x: Int, y: Int, d1: String, d2: String)] = []
            if curr.y > 0 && !grid[curr.y - 1][curr.x].visited {
                ns.append((curr.x, curr.y - 1, "top", "bottom"))
            }
            if curr.y < h - 1 && !grid[curr.y + 1][curr.x].visited {
                ns.append((curr.x, curr.y + 1, "bottom", "top"))
            }
            if curr.x > 0 && !grid[curr.y][curr.x - 1].visited {
                ns.append((curr.x - 1, curr.y, "left", "right"))
            }
            if curr.x < w - 1 && !grid[curr.y][curr.x + 1].visited {
                ns.append((curr.x + 1, curr.y, "right", "left"))
            }
            if !ns.isEmpty {
                let next = ns[Int.random(in: 0..<ns.count)]
                grid[curr.y][curr.x][next.d1] = false
                grid[next.y][next.x][next.d2] = false
                grid[next.y][next.x].visited = true
                stack.append((next.x, next.y))
            } else {
                stack.removeLast()
            }
        }
        let start = randPerimeter2D(w, h, exclude: nil)
        let end = randPerimeter2D(w, h, exclude: start)
        grid[start.y][start.x][start.face] = false
        grid[end.y][end.x][end.face] = false
        return PlanarResult(grid: grid, start: start, end: end, w: w, h: h)
    }

    /// JS: `_randPerimeter2D(w,h,exclude)`
    public static func randPerimeter2D(_ w: Int, _ h: Int, exclude: Perimeter2D?) -> Perimeter2D {
        var res: Perimeter2D
        repeat {
            let side = Int.random(in: 0..<4)
            if side == 0 { res = Perimeter2D(x: Int.random(in: 0..<w), y: 0, face: "top") }
            else if side == 1 { res = Perimeter2D(x: Int.random(in: 0..<w), y: h - 1, face: "bottom") }
            else if side == 2 { res = Perimeter2D(x: 0, y: Int.random(in: 0..<h), face: "left") }
            else { res = Perimeter2D(x: w - 1, y: Int.random(in: 0..<h), face: "right") }
        } while exclude != nil && res.x == exclude!.x && res.y == exclude!.y
        return res
    }

    // MARK: — generateCubic(w,h,d)  index.html 17861–17893
    public static func generateCubic(_ w: Int, _ h: Int, _ d: Int) -> CubicResult {
        var grid: [[[OrbMazeCell]]] = (0..<d).map { _ in
            (0..<h).map { _ in (0..<w).map { _ in OrbMazeCell() } }
        }
        var stack: [MazePt] = [MazePt(x: 0, y: 0, z: 0)]
        grid[0][0][0].visited = true
        while !stack.isEmpty {
            let curr = stack[stack.count - 1]
            var ns: [(x: Int, y: Int, z: Int, d1: String, d2: String)] = []
            if curr.x > 0 && !grid[curr.z][curr.y][curr.x - 1].visited {
                ns.append((curr.x - 1, curr.y, curr.z, "left", "right"))
            }
            if curr.x < w - 1 && !grid[curr.z][curr.y][curr.x + 1].visited {
                ns.append((curr.x + 1, curr.y, curr.z, "right", "left"))
            }
            if curr.y > 0 && !grid[curr.z][curr.y - 1][curr.x].visited {
                ns.append((curr.x, curr.y - 1, curr.z, "bottom", "top"))
            }
            if curr.y < h - 1 && !grid[curr.z][curr.y + 1][curr.x].visited {
                ns.append((curr.x, curr.y + 1, curr.z, "top", "bottom"))
            }
            if curr.z > 0 && !grid[curr.z - 1][curr.y][curr.x].visited {
                ns.append((curr.x, curr.y, curr.z - 1, "back", "front"))
            }
            if curr.z < d - 1 && !grid[curr.z + 1][curr.y][curr.x].visited {
                ns.append((curr.x, curr.y, curr.z + 1, "front", "back"))
            }
            if !ns.isEmpty {
                let next = ns[Int.random(in: 0..<ns.count)]
                grid[curr.z][curr.y][curr.x][next.d1] = false
                grid[next.z][next.y][next.x][next.d2] = false
                grid[next.z][next.y][next.x].visited = true
                stack.append(MazePt(x: next.x, y: next.y, z: next.z))
            } else {
                stack.removeLast()
            }
        }
        let start = randPerimeter3D(w, h, d, exclude: nil)
        let end = randPerimeter3D(w, h, d, exclude: start)
        grid[start.z][start.y][start.x][start.face] = false
        grid[end.z][end.y][end.x][end.face] = false
        return CubicResult(grid: grid, start: start, end: end, w: w, h: h, d: d)
    }

    /// JS: `_randPerimeter3D(w,h,d,exclude)`
    public static func randPerimeter3D(_ w: Int, _ h: Int, _ d: Int, exclude: Perimeter3D?) -> Perimeter3D {
        var res: Perimeter3D
        repeat {
            let face = Int.random(in: 0..<6)
            if face == 0 {
                res = Perimeter3D(x: 0, y: Int.random(in: 0..<h), z: Int.random(in: 0..<d), face: "left")
            } else if face == 1 {
                res = Perimeter3D(x: w - 1, y: Int.random(in: 0..<h), z: Int.random(in: 0..<d), face: "right")
            } else if face == 2 {
                res = Perimeter3D(x: Int.random(in: 0..<w), y: 0, z: Int.random(in: 0..<d), face: "bottom")
            } else if face == 3 {
                res = Perimeter3D(x: Int.random(in: 0..<w), y: h - 1, z: Int.random(in: 0..<d), face: "top")
            } else if face == 4 {
                res = Perimeter3D(x: Int.random(in: 0..<w), y: Int.random(in: 0..<h), z: 0, face: "back")
            } else {
                res = Perimeter3D(x: Int.random(in: 0..<w), y: Int.random(in: 0..<h), z: d - 1, face: "front")
            }
        } while exclude != nil && res.x == exclude!.x && res.y == exclude!.y && res.z == exclude!.z
        return res
    }

    // MARK: — solvePlanar  two-branch degree-map sigma  index.html 17914–17973
    public static func solvePlanar(_ mazeResult: PlanarResult) -> [MazeEngine.MistPt] {
        let grid = mazeResult.grid
        let start = mazeResult.start
        let end = mazeResult.end
        let w = mazeResult.w, h = mazeResult.h

        // BRANCH 1 — degree map
        var degreeMap: [String: Int] = [:]
        var allCells: [(x: Int, y: Int)] = []
        for y in 0..<h {
            for x in 0..<w {
                let c = grid[y][x]
                var deg = 0
                if !c.top { deg += 1 }
                if !c.bottom { deg += 1 }
                if !c.left { deg += 1 }
                if !c.right { deg += 1 }
                degreeMap["\(x),\(y)"] = deg
                allCells.append((x, y))
            }
        }
        let sK = "\(start.x),\(start.y)"
        let eK = "\(end.x),\(end.y)"
        degreeMap[sK] = 10
        degreeMap[eK] = 10

        // BRANCH 2 — dead-end pruning (sigma collapse)
        var changed = true
        var pruned = Set<String>()
        while changed {
            changed = false
            for cell in allCells {
                let key = "\(cell.x),\(cell.y)"
                if !pruned.contains(key) && degreeMap[key] == 1 {
                    pruned.insert(key)
                    changed = true
                    let c = grid[cell.y][cell.x]
                    if !c.top && cell.y > 0 {
                        let nk = "\(cell.x),\(cell.y - 1)"
                        degreeMap[nk] = (degreeMap[nk] ?? 0) - 1
                    }
                    if !c.bottom && cell.y < h - 1 {
                        let nk = "\(cell.x),\(cell.y + 1)"
                        degreeMap[nk] = (degreeMap[nk] ?? 0) - 1
                    }
                    if !c.left && cell.x > 0 {
                        let nk = "\(cell.x - 1),\(cell.y)"
                        degreeMap[nk] = (degreeMap[nk] ?? 0) - 1
                    }
                    if !c.right && cell.x < w - 1 {
                        let nk = "\(cell.x + 1),\(cell.y)"
                        degreeMap[nk] = (degreeMap[nk] ?? 0) - 1
                    }
                }
            }
        }

        let pathCells = allCells.filter { !pruned.contains("\($0.x),\($0.y)") }
        let pathSet = Set(pathCells.map { "\($0.x),\($0.y)" })
        var ordered: [MazeEngine.MistPt] = []
        var visited = Set<String>()
        var stack: [(x: Int, y: Int)] = [(start.x, start.y)]
        while !stack.isEmpty {
            let p = stack.removeLast()
            let key = "\(p.x),\(p.y)"
            if visited.contains(key) { continue }
            visited.insert(key)
            ordered.append(MazeEngine.MistPt(x: p.x, y: p.y))
            let c = grid[p.y][p.x]
            if !c.top && p.y > 0 && pathSet.contains("\(p.x),\(p.y - 1)") { stack.append((p.x, p.y - 1)) }
            if !c.bottom && p.y < h - 1 && pathSet.contains("\(p.x),\(p.y + 1)") { stack.append((p.x, p.y + 1)) }
            if !c.left && p.x > 0 && pathSet.contains("\(p.x - 1),\(p.y)") { stack.append((p.x - 1, p.y)) }
            if !c.right && p.x < w - 1 && pathSet.contains("\(p.x + 1),\(p.y)") { stack.append((p.x + 1, p.y)) }
        }
        return ordered
    }

    // MARK: — solveCubic  two-branch degree-map sigma  index.html 17975–18032
    /// SIGMA SOLVE for the Ash/MIST studio cube. Not generic BFS.
    public static func solveCubic(_ mazeResult: CubicResult) -> [MazePt] {
        let grid = mazeResult.grid
        let start = mazeResult.start
        let end = mazeResult.end
        let w = mazeResult.w, h = mazeResult.h, d = mazeResult.d

        // BRANCH 1 — degree map for 3D
        var degreeMap: [String: Int] = [:]
        var allCells: [(x: Int, y: Int, z: Int)] = []
        for z in 0..<d {
            for y in 0..<h {
                for x in 0..<w {
                    let c = grid[z][y][x]
                    var deg = 0
                    if !c.top { deg += 1 }
                    if !c.bottom { deg += 1 }
                    if !c.left { deg += 1 }
                    if !c.right { deg += 1 }
                    if !c.front { deg += 1 }
                    if !c.back { deg += 1 }
                    degreeMap["\(x),\(y),\(z)"] = deg
                    allCells.append((x, y, z))
                }
            }
        }
        let sK = "\(start.x),\(start.y),\(start.z)"
        let eK = "\(end.x),\(end.y),\(end.z)"
        degreeMap[sK] = 10
        degreeMap[eK] = 10

        // BRANCH 2 — 3D dead-end pruning
        var changed = true
        var pruned = Set<String>()
        while changed {
            changed = false
            for cell in allCells {
                let key = "\(cell.x),\(cell.y),\(cell.z)"
                if !pruned.contains(key) && degreeMap[key] == 1 {
                    pruned.insert(key)
                    changed = true
                    let c = grid[cell.z][cell.y][cell.x]
                    if !c.left && cell.x > 0 {
                        let nk = "\(cell.x - 1),\(cell.y),\(cell.z)"
                        degreeMap[nk] = (degreeMap[nk] ?? 0) - 1
                    }
                    if !c.right && cell.x < w - 1 {
                        let nk = "\(cell.x + 1),\(cell.y),\(cell.z)"
                        degreeMap[nk] = (degreeMap[nk] ?? 0) - 1
                    }
                    if !c.bottom && cell.y > 0 {
                        let nk = "\(cell.x),\(cell.y - 1),\(cell.z)"
                        degreeMap[nk] = (degreeMap[nk] ?? 0) - 1
                    }
                    if !c.top && cell.y < h - 1 {
                        let nk = "\(cell.x),\(cell.y + 1),\(cell.z)"
                        degreeMap[nk] = (degreeMap[nk] ?? 0) - 1
                    }
                    if !c.back && cell.z > 0 {
                        let nk = "\(cell.x),\(cell.y),\(cell.z - 1)"
                        degreeMap[nk] = (degreeMap[nk] ?? 0) - 1
                    }
                    if !c.front && cell.z < d - 1 {
                        let nk = "\(cell.x),\(cell.y),\(cell.z + 1)"
                        degreeMap[nk] = (degreeMap[nk] ?? 0) - 1
                    }
                }
            }
        }

        // SIGMA remainder + DFS ordering
        let pathCells = allCells.filter { !pruned.contains("\($0.x),\($0.y),\($0.z)") }
        let pathSet = Set(pathCells.map { "\($0.x),\($0.y),\($0.z)" })
        var ordered: [MazePt] = []
        var visited = Set<String>()
        var stack: [MazePt] = [MazePt(x: start.x, y: start.y, z: start.z)]
        while !stack.isEmpty {
            let p = stack.removeLast()
            let key = "\(p.x),\(p.y),\(p.z)"
            if visited.contains(key) { continue }
            visited.insert(key)
            ordered.append(p)
            let c = grid[p.z][p.y][p.x]
            if !c.left && p.x > 0 {
                let nk = "\(p.x - 1),\(p.y),\(p.z)"
                if pathSet.contains(nk) { stack.append(MazePt(x: p.x - 1, y: p.y, z: p.z)) }
            }
            if !c.right && p.x < w - 1 {
                let nk = "\(p.x + 1),\(p.y),\(p.z)"
                if pathSet.contains(nk) { stack.append(MazePt(x: p.x + 1, y: p.y, z: p.z)) }
            }
            if !c.bottom && p.y > 0 {
                let nk = "\(p.x),\(p.y - 1),\(p.z)"
                if pathSet.contains(nk) { stack.append(MazePt(x: p.x, y: p.y - 1, z: p.z)) }
            }
            if !c.top && p.y < h - 1 {
                let nk = "\(p.x),\(p.y + 1),\(p.z)"
                if pathSet.contains(nk) { stack.append(MazePt(x: p.x, y: p.y + 1, z: p.z)) }
            }
            if !c.back && p.z > 0 {
                let nk = "\(p.x),\(p.y),\(p.z - 1)"
                if pathSet.contains(nk) { stack.append(MazePt(x: p.x, y: p.y, z: p.z - 1)) }
            }
            if !c.front && p.z < d - 1 {
                let nk = "\(p.x),\(p.y),\(p.z + 1)"
                if pathSet.contains(nk) { stack.append(MazePt(x: p.x, y: p.y, z: p.z + 1)) }
            }
        }
        return ordered
    }
}
