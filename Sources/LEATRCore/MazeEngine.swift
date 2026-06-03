
import Foundation
import SceneKit

/// 3D cubic maze — matches web app's Lead Edge D1/D2/D3 algorithm
/// Randomized entry/exit on any wall surface
/// Path solving with BFS
public final class MazeEngine {

    // MARK: — Grid cell
    public struct Cell {
        public var walls: [Direction: Bool]  // wall present on each face
        public var visited = false
        public var isPath  = false

        public init() {
            walls = Dictionary(uniqueKeysWithValues: Direction.allCases.map { ($0, true) })
        }
    }

    public enum Direction: CaseIterable {
        case posX, negX, posY, negY, posZ, negZ

        var opposite: Direction {
            switch self {
            case .posX: return .negX; case .negX: return .posX
            case .posY: return .negY; case .negY: return .posY
            case .posZ: return .negZ; case .negZ: return .posZ
            }
        }

        var offset: (Int, Int, Int) {
            switch self {
            case .posX: return (1,0,0);  case .negX: return (-1,0,0)
            case .posY: return (0,1,0);  case .negY: return (0,-1,0)
            case .posZ: return (0,0,1);  case .negZ: return (0,0,-1)
            }
        }
    }

    // MARK: — State
    public let size: Int
    public private(set) var grid: [[[Cell]]]
    public private(set) var entry: (Int, Int, Int) = (0, 0, 0)
    public private(set) var exit:  (Int, Int, Int) = (0, 0, 0)
    public private(set) var solution: [(Int, Int, Int)] = []

    public init(size: Int = 5) {
        self.size = size
        grid = Array(repeating: Array(repeating: Array(repeating: Cell(), count: size),
                                      count: size), count: size)
        generate()
    }

    // MARK: — Generation (recursive backtracker — D1/D2/D3 inspired)
    private func generate() {
        // Randomized DFS
        var stack: [(Int,Int,Int)] = [(0,0,0)]
        grid[0][0][0].visited = true
        var visitedCount = 1
        let total = size * size * size

        while visitedCount < total {
            guard let (cx, cy, cz) = stack.last else { break }

            let neighbors = Direction.allCases.shuffled().compactMap { dir -> (Int,Int,Int,Direction)? in
                let (dx,dy,dz) = dir.offset
                let nx=cx+dx; let ny=cy+dy; let nz=cz+dz
                guard nx>=0 && nx<size && ny>=0 && ny<size && nz>=0 && nz<size else { return nil }
                guard !grid[nx][ny][nz].visited else { return nil }
                return (nx,ny,nz,dir)
            }

            if let (nx,ny,nz,dir) = neighbors.first {
                // Remove wall between current and neighbor
                grid[cx][cy][cz].walls[dir] = false
                grid[nx][ny][nz].walls[dir.opposite] = false
                grid[nx][ny][nz].visited = true
                stack.append((nx,ny,nz))
                visitedCount += 1
            } else {
                stack.removeLast()
            }
        }

        // Place entry and exit on random outer wall faces
        placeEntryExit()
        // Solve
        solution = solve(from: entry, to: exit) ?? []
    }

    private func placeEntryExit() {
        // Entry: random cell on any face
        let faces: [(Int,Int,Int)] = {
            var f: [(Int,Int,Int)] = []
            let last = size - 1
            for i in 0..<size { for j in 0..<size {
                f += [(0,i,j),(last,i,j),(i,0,j),(i,last,j),(i,j,0),(i,j,last)]
            }}
            return f
        }()
        let shuffled = faces.shuffled()
        entry = shuffled[0]
        // Exit must be on opposite side
        exit = faces.filter { abs($0.0 - entry.0) + abs($0.1 - entry.1) + abs($0.2 - entry.2) > size }.randomElement() ?? shuffled.last!
    }

    // MARK: — BFS solver
    private func solve(from start: (Int,Int,Int), to end: (Int,Int,Int)) -> [(Int,Int,Int)]? {
        var visited = Set<String>()
        var queue: [(path: [(Int,Int,Int)], pos: (Int,Int,Int))] = [([start], start)]
        visited.insert(key(start))

        while !queue.isEmpty {
            let (path, (cx,cy,cz)) = queue.removeFirst()
            if cx == end.0 && cy == end.1 && cz == end.2 { return path }
            for dir in Direction.allCases {
                guard grid[cx][cy][cz].walls[dir] == false else { continue }
                let (dx,dy,dz) = dir.offset
                let np = (cx+dx, cy+dy, cz+dz)
                guard np.0>=0 && np.0<size else { continue }
                guard np.1>=0 && np.1<size else { continue }
                guard np.2>=0 && np.2<size else { continue }
                let k = key(np)
                guard !visited.contains(k) else { continue }
                visited.insert(k)
                queue.append((path + [np], np))
            }
        }
        return nil
    }

    private func key(_ p: (Int,Int,Int)) -> String { "\(p.0),\(p.1),\(p.2)" }

    // MARK: — Solve (public — called by Autumn for private/public animation)
    public func markSolutionPath() {
        // Reset
        for x in 0..<size { for y in 0..<size { for z in 0..<size {
            grid[x][y][z].isPath = false
        }}}
        for (x,y,z) in solution { grid[x][y][z].isPath = true }
    }

    // MARK: — Build SceneKit geometry
    public func buildScene(cellSize: Float = 0.4, wallThickness: Float = 0.02) -> SCNNode {
        let root = SCNNode()
        let s = cellSize
        let t = wallThickness

        // Wire-frame style — each open passage becomes a tube
        let wireMat = SCNMaterial()
        wireMat.diffuse.contents  = UIColor(red:0.0, green:0.9, blue:1.0, alpha:0.5)
        wireMat.emission.contents = UIColor(red:0.0, green:0.4, blue:0.5, alpha:0.3)
        wireMat.lightingModel = .constant
        wireMat.isDoubleSided = true

        let pathMat = SCNMaterial()
        pathMat.diffuse.contents  = UIColor(red:0.8, green:0.0, blue:1.0, alpha:0.9)
        pathMat.emission.contents = UIColor(red:0.4, green:0.0, blue:0.5, alpha:0.5)
        pathMat.lightingModel = .constant

        for x in 0..<size { for y in 0..<size { for z in 0..<size {
            let cell = grid[x][y][z]
            let cx = Float(x)*s - Float(size)*s*0.5
            let cy = Float(y)*s - Float(size)*s*0.5
            let cz = Float(z)*s - Float(size)*s*0.5

            let mat = cell.isPath ? pathMat : wireMat

            // Cell node (small sphere at center)
            let sphere = SCNSphere(radius: CGFloat(t * 1.5))
            sphere.segmentCount = 6
            sphere.firstMaterial = mat
            let sn = SCNNode(geometry: sphere)
            sn.position = SCNVector3(cx, cy, cz)
            root.addChildNode(sn)

            // Open passages — draw tube along each open direction
            for dir in Direction.allCases {
                guard cell.walls[dir] == false else { continue }
                let (dx,dy,dz) = dir.offset
                let halfS = s * 0.5
                let tube = SCNCylinder(radius: CGFloat(t), height: CGFloat(halfS))
                tube.segmentCount = 5
                tube.firstMaterial = mat
                let tn = SCNNode(geometry: tube)
                tn.position = SCNVector3(
                    cx + Float(dx)*halfS*0.5,
                    cy + Float(dy)*halfS*0.5,
                    cz + Float(dz)*halfS*0.5)
                // Orient tube along direction
                switch dir {
                case .posX, .negX:
                    tn.eulerAngles = SCNVector3(0, 0, .pi/2)
                case .posY, .negY:
                    tn.eulerAngles = SCNVector3(0, 0, 0)
                case .posZ, .negZ:
                    tn.eulerAngles = SCNVector3(.pi/2, 0, 0)
                }
                root.addChildNode(tn)
            }
        }}}

        // Entry/exit markers
        let entryGeo = SCNSphere(radius: 0.06)
        entryGeo.firstMaterial?.diffuse.contents  = UIColor.green
        entryGeo.firstMaterial?.emission.contents = UIColor.green
        entryGeo.firstMaterial?.lightingModel = .constant
        let entryNode = SCNNode(geometry: entryGeo)
        let (ex,ey,ez) = entry
        entryNode.position = SCNVector3(
            Float(ex)*cellSize - Float(size)*cellSize*0.5,
            Float(ey)*cellSize - Float(size)*cellSize*0.5,
            Float(ez)*cellSize - Float(size)*cellSize*0.5)
        root.addChildNode(entryNode)

        let exitGeo = SCNSphere(radius: 0.06)
        exitGeo.firstMaterial?.diffuse.contents  = UIColor.red
        exitGeo.firstMaterial?.emission.contents = UIColor.red
        exitGeo.firstMaterial?.lightingModel = .constant
        let exitNode = SCNNode(geometry: exitGeo)
        let (xx,xy,xz) = exit
        exitNode.position = SCNVector3(
            Float(xx)*cellSize - Float(size)*cellSize*0.5,
            Float(xy)*cellSize - Float(size)*cellSize*0.5,
            Float(xz)*cellSize - Float(size)*cellSize*0.5)
        root.addChildNode(exitNode)

        return root
    }
}
