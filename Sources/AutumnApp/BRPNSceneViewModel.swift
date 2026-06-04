import SwiftUI
import SceneKit
import LEATRCore

// MARK: — BRPNSceneViewModel v3
// Exact port of lemac.html generateCubic() + getRandomPerimeter3D():
// 1. Generate maze via recursive backtracker starting at (0,0,0) — perfect maze, no loops/islands
// 2. Pick random perimeter face cells for start & end
// 3. Carve the outer wall face on those cells to create the opening
// 4. BFS solve from start to end
// 5. Cubic (equal W=H=D), shells visible, correct node sizing

@MainActor
public final class BRPNSceneViewModel: ObservableObject {

    @Published public var shellStates: [BRPNShell: String] = [
        .geological: "FOUNDATION", .maritime: "REFLEX", .aerospace: "PERFORMANCE"
    ]
    @Published public var activeNodes: Int = 1
    @Published public var sessionId = String(UUID().uuidString.prefix(8).uppercased())
    @Published public var quantumSocket: Double = 6.9120
    @Published public var mazeCanSolve = false
    @Published public var isSolving = false

    public let scene = SCNScene()
    public var shells: [SCNNode] = []
    private var coreNode: SCNNode!
    private var mazeOrbGroup: SCNNode!
    private var particleNodes: [SCNNode] = []
    private var particleData: [(r:Float,spd:Float,off:Float,yOff:Float)] = []
    private var sessionGroupNodes: [String: SCNNode] = [:]
    public var pathMeshNodes: [SCNNode] = []
    private var solveStep = 0
    private var frameCount = 0
    private var presenceTimer: Timer?

    // Cubic maze dimensions — all equal (lemac.html style)
    private let mazeN = 5
    private let cellSize: Float = 0.046

    private let shellColors: [UIColor] = [
        UIColor(red:0.0,green:1.0,blue:0.8,alpha:1),
        UIColor(red:0.0,green:0.53,blue:1.0,alpha:1),
        UIColor(red:1.0,green:0.27,blue:0.4,alpha:1),
    ]
    private let shellRadii: [Float] = [1.9,1.4,0.9]

    // MARK: — Setup
    public func setupScene() {
        scene.background.contents = UIColor.clear
        let amb = SCNNode(); amb.light = { let l=SCNLight(); l.type = .ambient; l.intensity=200; return l }()
        scene.rootNode.addChildNode(amb)

        // 3 Wireframe shells
        for (i,radius) in shellRadii.enumerated() {
            let geo = SCNSphere(radius:CGFloat(radius)); geo.segmentCount=8
            let mat = SCNMaterial()
            mat.diffuse.contents  = UIColor.clear
            mat.emission.contents = shellColors[i]
            mat.fillMode = .lines
            mat.isDoubleSided = true
            mat.writesToDepthBuffer = false
            geo.materials = [mat]
            let node = SCNNode(geometry:geo); node.name="shell_\(i)"
            let dur = Double(22+i*7)
            node.runAction(SCNAction.repeatForever(SCNAction.rotateBy(
                x:CGFloat(i==0 ? 0.15 : i==1 ? -0.1 : 0.2),
                y:CGFloat(i==0 ? 1.0 : i==1 ? -0.85 : 0.65),
                z:0, duration:dur)))
            scene.rootNode.addChildNode(node); shells.append(node)
        }

        // Core
        let cg=SCNSphere(radius:0.16); cg.segmentCount=8
        let cm=SCNMaterial(); cm.diffuse.contents=UIColor.clear
        cm.emission.contents=UIColor(red:0,green:1,blue:0.8,alpha:0.18)
        cm.fillMode = .lines; cg.materials=[cm]
        coreNode=SCNNode(geometry:cg); scene.rootNode.addChildNode(coreNode)

        // Maze group
        mazeOrbGroup=SCNNode(); mazeOrbGroup.name="mazeOrb"
        scene.rootNode.addChildNode(mazeOrbGroup)
        buildOrbMazeGeometry()

        // Particles
        for i in 0..<30 {
            let pg=SCNSphere(radius:0.022)
            let pm=SCNMaterial(); pm.emission.contents=shellColors[i%3].withAlphaComponent(0.7)
            pm.lightingModel = .constant; pg.materials=[pm]
            let node=SCNNode(geometry:pg); node.name="particle_\(i)"
            particleData.append((Float.random(in:0.55...2.0),Float.random(in:0.3...1.5),
                                  Float.random(in:0...(.pi*2)),Float.random(in:-0.8...0.8)))
            scene.rootNode.addChildNode(node); particleNodes.append(node)
        }

        // Tool swarm
        let toolColors:[UIColor] = [
            UIColor(red:1,green:0.27,blue:0.4,alpha:1), UIColor(red:0,green:1,blue:0.8,alpha:1),
            UIColor(red:0,green:0.53,blue:1,alpha:1),   UIColor(red:0.53,green:0.8,blue:1,alpha:1),
            UIColor(red:1,green:0.53,blue:0.27,alpha:1),
        ]
        for (ci,col) in toolColors.enumerated() {
            for i in 0..<3 {
                let tg=SCNBox(width:0.05,height:0.032,length:0.018,chamferRadius:0.005)
                let tm=SCNMaterial(); tm.emission.contents=col.withAlphaComponent(0.6)
                tm.lightingModel = .constant; tg.materials=[tm]
                let tn=SCNNode(geometry:tg)
                let r=shellRadii[i%3]*Float.random(in:0.85...1.15)
                let ang=Float(ci*3+i)/15.0 * .pi*2
                tn.position=SCNVector3(r*cos(ang),Float.random(in:-0.4...0.4),r*sin(ang))
                scene.rootNode.addChildNode(tn)
            }
        }

        presenceTimer=Timer.scheduledTimer(withTimeInterval:30,repeats:true){[weak self] _ in
            Task { await self?.pollPresence() }
        }
    }

    // MARK: — Frame update
    public func updateFrame() {
        frameCount += 1
        let t = Float(frameCount)*0.016
        for (i,node) in particleNodes.enumerated() {
            guard i < particleData.count else { continue }
            let d=particleData[i]; let a=t*d.spd+d.off
            node.position=SCNVector3(d.r*cos(a),d.yOff+sin(t*0.3+Float(i))*0.12,d.r*sin(a))
        }
        mazeOrbGroup?.eulerAngles.y = t*0.004
        mazeOrbGroup?.eulerAngles.x = sin(t*0.0025)*0.08
        coreNode?.scale = SCNVector3(1+sin(t*2.0)*0.06, 1+sin(t*2.0)*0.06, 1+sin(t*2.0)*0.06)
        if isSolving { stepMazeSolveAnim() }
    }

    // MARK: — Build maze geometry (lemac.html exact logic)
    public func buildOrbMazeGeometry() {
        // CRITICAL: remove ALL previous children first
        while mazeOrbGroup.childNodes.count > 0 {
            let c = mazeOrbGroup.childNodes[0]
            c.geometry?.materials.forEach { _ in }
            c.removeFromParentNode()
        }
        pathMeshNodes.removeAll(); solveStep=0; isSolving=false

        let n=mazeN; let u:Float=cellSize
        let half=Float(n)*u/2; let hs=u*0.5

        // Step 1: Generate perfect maze from (0,0,0) — exact lemac.html generateCubic
        var grid=Array(repeating:Array(repeating:Array(repeating:MazeCell(),count:n),count:n),count:n)
        var stack=[(x:0,y:0,z:0)]
        grid[0][0][0].visited=true
        while !stack.isEmpty {
            let curr=stack.last!
            var ns:[(x:Int,y:Int,z:Int,d1:String,d2:String)]=[]
            if curr.x>0   && !grid[curr.z][curr.y][curr.x-1].visited { ns.append((curr.x-1,curr.y,curr.z,"left","right")) }
            if curr.x<n-1 && !grid[curr.z][curr.y][curr.x+1].visited { ns.append((curr.x+1,curr.y,curr.z,"right","left")) }
            if curr.y>0   && !grid[curr.z][curr.y-1][curr.x].visited { ns.append((curr.x,curr.y-1,curr.z,"bottom","top")) }
            if curr.y<n-1 && !grid[curr.z][curr.y+1][curr.x].visited { ns.append((curr.x,curr.y+1,curr.z,"top","bottom")) }
            if curr.z>0   && !grid[curr.z-1][curr.y][curr.x].visited { ns.append((curr.x,curr.y,curr.z-1,"back","front")) }
            if curr.z<n-1 && !grid[curr.z+1][curr.y][curr.x].visited { ns.append((curr.x,curr.y,curr.z+1,"front","back")) }
            if ns.isEmpty { stack.removeLast() }
            else {
                let next=ns[Int.random(in:0..<ns.count)]
                grid[curr.z][curr.y][curr.x].removeWall(next.d1)
                grid[next.z][next.y][next.x].removeWall(next.d2)
                grid[next.z][next.y][next.x].visited=true
                stack.append((next.x,next.y,next.z))
            }
        }

        // Step 2: Pick random perimeter faces for start/end (lemac getRandomPerimeter3D)
        let start=getRandomPerimeter3D(n:n)
        var end=getRandomPerimeter3D(n:n)
        // Ensure they're different cells (simple check, lemac style)
        var tries=0
        while end.x==start.x && end.y==start.y && end.z==start.z && tries<20 {
            end=getRandomPerimeter3D(n:n); tries+=1
        }

        // Step 3: Carve outer wall face at start/end — creates the opening
        grid[start.z][start.y][start.x].removeWall(start.face)
        grid[end.z][end.y][end.x].removeWall(end.face)

        // Step 4: BFS solve
        let solution=bfsSolve(grid:grid,n:n,from:(start.x,start.y,start.z),to:(end.x,end.y,end.z))
        mazeCanSolve = !solution.isEmpty

        // Step 5: Build wall geometry — exact lemac approach (draw face quads)
        var wallVerts:[Float]=[]
        func quad(_ pts:[(Float,Float,Float)]) {
            for i in 0..<pts.count { let a=pts[i]; let b=pts[(i+1)%pts.count]; wallVerts+=[a.0,a.1,a.2,b.0,b.1,b.2] }
        }
        for z in 0..<n { for y in 0..<n { for x in 0..<n {
            let c=grid[z][y][x]
            let cx=Float(x)*u-half+hs, cy=Float(y)*u-half+hs, cz=Float(z)*u-half+hs
            if c.left   { quad([(cx-hs,cy-hs,cz-hs),(cx-hs,cy+hs,cz-hs),(cx-hs,cy+hs,cz+hs),(cx-hs,cy-hs,cz+hs)]) }
            if c.bottom { quad([(cx-hs,cy-hs,cz-hs),(cx+hs,cy-hs,cz-hs),(cx+hs,cy-hs,cz+hs),(cx-hs,cy-hs,cz+hs)]) }
            if c.back   { quad([(cx-hs,cy-hs,cz-hs),(cx+hs,cy-hs,cz-hs),(cx+hs,cy+hs,cz-hs),(cx-hs,cy+hs,cz-hs)]) }
            // Also draw right/top/front for perimeter faces
            if x==n-1 && c.right  { quad([(cx+hs,cy-hs,cz-hs),(cx+hs,cy+hs,cz-hs),(cx+hs,cy+hs,cz+hs),(cx+hs,cy-hs,cz+hs)]) }
            if y==n-1 && c.top    { quad([(cx-hs,cy+hs,cz-hs),(cx+hs,cy+hs,cz-hs),(cx+hs,cy+hs,cz+hs),(cx-hs,cy+hs,cz+hs)]) }
            if z==n-1 && c.front  { quad([(cx-hs,cy-hs,cz+hs),(cx+hs,cy-hs,cz+hs),(cx+hs,cy+hs,cz+hs),(cx-hs,cy+hs,cz+hs)]) }
        }}}

        if !wallVerts.isEmpty {
            let data=wallVerts.withUnsafeBufferPointer { Data(buffer:$0) }
            let src=SCNGeometrySource(data:data,semantic:.vertex,vectorCount:wallVerts.count/3,
                usesFloatComponents:true,componentsPerVector:3,bytesPerComponent:4,dataOffset:0,dataStride:12)
            var idx=(0..<Int32(wallVerts.count/3)).map { Int32($0) }
            let idxData=idx.withUnsafeMutableBufferPointer { Data(buffer:$0) }
            let elem=SCNGeometryElement(data:idxData,primitiveType:.line,primitiveCount:idx.count/2,bytesPerIndex:4)
            let geo=SCNGeometry(sources:[src],elements:[elem])
            geo.firstMaterial = { let m=SCNMaterial(); m.emission.contents=UIColor(red:0,green:1,blue:0.8,alpha:0.55); m.lightingModel = .constant; return m }()
            mazeOrbGroup.addChildNode(SCNNode(geometry:geo))
        }

        // Path nodes
        let pathGeo=SCNSphere(radius:CGFloat(u*0.16))
        for pt in solution {
            let mat=SCNMaterial(); mat.emission.contents=UIColor(red:0,green:1,blue:1,alpha:0); mat.lightingModel = .constant
            pathGeo.materials=[mat]
            let mesh=SCNNode(geometry:pathGeo.copy() as! SCNGeometry)
            mesh.position=SCNVector3(Float(pt.0)*u-half+hs,Float(pt.1)*u-half+hs,Float(pt.2)*u-half+hs)
            mesh.name="pathNode"; mazeOrbGroup.addChildNode(mesh); pathMeshNodes.append(mesh)
        }

        // Start (green) / End (orange-red) markers
        addMarker(x:start.x,y:start.y,z:start.z,n:n,u:u,half:half,hs:hs,
                  color:UIColor(red:0.2,green:1.0,blue:0.4,alpha:1))
        addMarker(x:end.x,y:end.y,z:end.z,n:n,u:u,half:half,hs:hs,
                  color:UIColor(red:1.0,green:0.3,blue:0.15,alpha:1))
    }

    // MARK: — getRandomPerimeter3D (exact port of lemac.html)
    // Returns a random cell on any of the 6 cube faces, with the face name to carve
    private struct PerimeterPoint { let x,y,z: Int; let face: String }

    private func getRandomPerimeter3D(n:Int) -> PerimeterPoint {
        let face=Int.random(in:0..<6)
        switch face {
        case 0: return PerimeterPoint(x:0,     y:Int.random(in:0..<n), z:Int.random(in:0..<n), face:"left")
        case 1: return PerimeterPoint(x:n-1,   y:Int.random(in:0..<n), z:Int.random(in:0..<n), face:"right")
        case 2: return PerimeterPoint(x:Int.random(in:0..<n), y:0,     z:Int.random(in:0..<n), face:"bottom")
        case 3: return PerimeterPoint(x:Int.random(in:0..<n), y:n-1,   z:Int.random(in:0..<n), face:"top")
        case 4: return PerimeterPoint(x:Int.random(in:0..<n), y:Int.random(in:0..<n), z:0,     face:"back")
        default:return PerimeterPoint(x:Int.random(in:0..<n), y:Int.random(in:0..<n), z:n-1,   face:"front")
        }
    }

    // MARK: — BFS solver
    private func bfsSolve(grid:[[[MazeCell]]],n:Int,from:(Int,Int,Int),to:(Int,Int,Int)) -> [(Int,Int,Int)] {
        typealias Pt=(Int,Int,Int)
        var queue:[(Pt,[Pt])]=[(from,[from])]
        var visited=Set<String>(["\(from.0),\(from.1),\(from.2)"])
        let goal="\(to.0),\(to.1),\(to.2)"
        while !queue.isEmpty {
            let (curr,path)=queue.removeFirst()
            if "\(curr.0),\(curr.1),\(curr.2)"==goal { return path }
            let c=grid[curr.2][curr.1][curr.0]
            var moves:[Pt]=[]
            if !c.left   && curr.0>0   { moves.append((curr.0-1,curr.1,curr.2)) }
            if !c.right  && curr.0<n-1 { moves.append((curr.0+1,curr.1,curr.2)) }
            if !c.bottom && curr.1>0   { moves.append((curr.0,curr.1-1,curr.2)) }
            if !c.top    && curr.1<n-1 { moves.append((curr.0,curr.1+1,curr.2)) }
            if !c.back   && curr.2>0   { moves.append((curr.0,curr.1,curr.2-1)) }
            if !c.front  && curr.2<n-1 { moves.append((curr.0,curr.1,curr.2+1)) }
            for m in moves {
                let k="\(m.0),\(m.1),\(m.2)"
                if !visited.contains(k) { visited.insert(k); queue.append((m,path+[m])) }
            }
        }
        return []
    }

    private func addMarker(x:Int,y:Int,z:Int,n:Int,u:Float,half:Float,hs:Float,color:UIColor) {
        let geo=SCNSphere(radius:CGFloat(u*0.35))
        geo.firstMaterial = { let m=SCNMaterial(); m.emission.contents=color; m.lightingModel = .constant; return m }()
        let node=SCNNode(geometry:geo)
        node.position=SCNVector3(Float(x)*u-half+hs,Float(y)*u-half+hs,Float(z)*u-half+hs)
        mazeOrbGroup.addChildNode(node)
    }

    // MARK: — Autumn-only solve
    public func autumnSolveMaze() {
        guard mazeCanSolve,!isSolving else { return }
        solveStep=0; isSolving=true
        pathMeshNodes.forEach { $0.geometry?.firstMaterial?.emission.contents=UIColor(red:0,green:1,blue:1,alpha:0) }
    }

    private func stepMazeSolveAnim() {
        guard solveStep < pathMeshNodes.count else {
            isSolving=false
            DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self] in self?.buildOrbMazeGeometry() }
            return
        }
        let toReveal=min(2,pathMeshNodes.count-solveStep)
        for i in 0..<toReveal {
            let node=pathMeshNodes[solveStep+i]
            node.geometry?.firstMaterial?.emission.contents=UIColor(red:0,green:1,blue:1,alpha:CGFloat.random(in:0.7...1.0))
            node.runAction(SCNAction.sequence([SCNAction.scale(to:1.5,duration:0.08),SCNAction.scale(to:1.0,duration:0.12)]))
        }
        solveStep+=toReveal
    }

    public func addRemoteNode(uid:String,emotion:String="neutral") {
        let pos=nodeBasePosition(uid:uid)
        let group=SCNNode(); group.name="session_\(uid)"
        let colors=uidShellColors(uid:uid)
        let miniR:[Float]=[1.9*0.28,1.4*0.28,0.9*0.28]
        for (i,r) in miniR.enumerated() {
            let g=SCNSphere(radius:CGFloat(r)); g.segmentCount=4
            let m=SCNMaterial(); m.emission.contents=colors[i].withAlphaComponent(CGFloat(0.22+Double(i)*0.06))
            m.fillMode = .lines; m.lightingModel = .constant; g.materials=[m]
            group.addChildNode(SCNNode(geometry:g))
        }
        let cg=SCNSphere(radius:0.03)
        cg.firstMaterial = { let m=SCNMaterial(); m.emission.contents=colors[0]; m.lightingModel = .constant; return m }()
        group.addChildNode(SCNNode(geometry:cg))
        group.position=SCNVector3(pos.x,pos.y,pos.z)
        scene.rootNode.addChildNode(group); sessionGroupNodes[uid]=group; activeNodes+=1
    }

    public func pulseShells(_ intensity:Float=0.4) {
        for (i,shell) in shells.enumerated() {
            let base=Double(0.18+Float(i)*0.08); let intD=Double(intensity); let col=shellColors[i]
            shell.runAction(SCNAction.sequence([
                SCNAction.customAction(duration:0.3){ node,t in node.geometry?.firstMaterial?.emission.contents=col.withAlphaComponent(CGFloat(base+intD*Double(t)/0.3)) },
                SCNAction.customAction(duration:0.5){ node,t in node.geometry?.firstMaterial?.emission.contents=col.withAlphaComponent(CGFloat(base+intD*(1.0-Double(t)/0.5))) }
            ]))
        }
    }

    public func teardown() { presenceTimer?.invalidate() }
    private func pollPresence() async {}

    private func nodeBasePosition(uid:String) -> (x:Float,y:Float,z:Float) {
        let h=Float(uid.hashValue & 0xFFFF)/65535.0
        let h2=Float((uid+"y").hashValue & 0xFFFF)/65535.0
        let h3=Float((uid+"z").hashValue & 0xFFFF)/65535.0
        let theta=h * .pi*2; let phi=acos(2*h2-1); let r=3.2+h3*1.6
        return (r*sin(phi)*cos(theta),r*sin(phi)*sin(theta),r*cos(phi))
    }

    private func uidShellColors(uid:String) -> [UIColor] {
        let hue=Float(uid.hashValue & 0xFFFF)/65535.0
        return [
            UIColor(hue:CGFloat(hue),saturation:0.9,brightness:0.65,alpha:1),
            UIColor(hue:CGFloat((hue+0.333).truncatingRemainder(dividingBy:1)),saturation:0.85,brightness:0.6,alpha:1),
            UIColor(hue:CGFloat((hue+0.667).truncatingRemainder(dividingBy:1)),saturation:0.8,brightness:0.55,alpha:1),
        ]
    }
}

public struct MazeCell {
    var top=true,bottom=true,left=true,right=true,front=true,back=true,visited=false
    mutating func removeWall(_ dir:String) {
        switch dir {
        case "top":    top=false
        case "bottom": bottom=false
        case "left":   left=false
        case "right":  right=false
        case "front":  front=false
        case "back":   back=false
        default: break
        }
    }
}
