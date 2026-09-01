import SceneKit
import UIKit

// MARK: — Three.js geometry ports for SceneKit
// JS: THREE.IcosahedronGeometry(radius, detail)
//     THREE.TetrahedronGeometry(radius, detail)
//     THREE.OctahedronGeometry(radius, detail)
//     THREE.SphereGeometry(radius, widthSegments, heightSegments)
//     THREE.LineSegments / MeshBasicMaterial({wireframe:true})

enum ThreeJSGeometry {

    struct V3 {
        var x: Float
        var y: Float
        var z: Float
        func lerp(_ b: V3, _ t: Float) -> V3 {
            V3(x: x + (b.x - x) * t, y: y + (b.y - y) * t, z: z + (b.z - z) * t)
        }
        func applyRadius(_ r: Float) -> V3 {
            let l = sqrt(x * x + y * y + z * z)
            if l == 0 { return self }
            return V3(x: x / l * r, y: y / l * r, z: z / l * r)
        }
    }

    // JS: three/src/geometries/PolyhedronGeometry.js
    static func polyhedron(vertices: [Float], indices: [Int], radius: Float, detail: Int) -> SCNGeometry {
        var buf: [V3] = []

        func vertex(_ i: Int) -> V3 {
            V3(x: vertices[i * 3], y: vertices[i * 3 + 1], z: vertices[i * 3 + 2])
        }

        func subdivide(_ v1: V3, _ v2: V3, _ v3: V3, _ detail: Int) {
            let cols = detail + 1
            var a: [[V3]] = Array(repeating: [], count: cols + 1)
            for i in 0...cols {
                let aj = v1.lerp(v3, Float(i) / Float(cols))
                let bj = v2.lerp(v3, Float(i) / Float(cols))
                let rows = cols - i
                a[i] = Array(repeating: V3(x: 0, y: 0, z: 0), count: rows + 1)
                for j in 0...rows {
                    if j == 0 && i == cols {
                        a[i][j] = aj
                    } else {
                        a[i][j] = aj.lerp(bj, rows == 0 ? 0 : Float(j) / Float(rows))
                    }
                }
            }
            for i in 0..<cols {
                for j in 0..<(2 * (cols - i) - 1) {
                    let k = j / 2
                    if j % 2 == 0 {
                        buf.append(a[i][k + 1])
                        buf.append(a[i + 1][k])
                        buf.append(a[i][k])
                    } else {
                        buf.append(a[i][k + 1])
                        buf.append(a[i + 1][k + 1])
                        buf.append(a[i + 1][k])
                    }
                }
            }
        }

        var i = 0
        while i < indices.count {
            subdivide(vertex(indices[i]), vertex(indices[i + 1]), vertex(indices[i + 2]), detail)
            i += 3
        }
        buf = buf.map { $0.applyRadius(radius) }

        var floats: [Float] = []
        floats.reserveCapacity(buf.count * 3)
        for v in buf { floats += [v.x, v.y, v.z] }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let src = SCNGeometrySource(
            data: data, semantic: .vertex, vectorCount: buf.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        var idx = (0..<Int32(buf.count)).map { $0 }
        let idxData = idx.withUnsafeMutableBufferPointer { Data(buffer: $0) }
        let elem = SCNGeometryElement(
            data: idxData, primitiveType: .triangles,
            primitiveCount: buf.count / 3, bytesPerIndex: 4
        )
        return SCNGeometry(sources: [src], elements: [elem])
    }

    /// JS: `new THREE.IcosahedronGeometry(radius, detail)`
    static func icosahedron(radius: Float, detail: Int = 1) -> SCNGeometry {
        let t = Float((1.0 + sqrt(5.0)) / 2.0)
        let vertices: [Float] = [
            -1, t, 0,   1, t, 0,  -1, -t, 0,   1, -t, 0,
             0, -1, t,   0, 1, t,   0, -1, -t,   0, 1, -t,
             t, 0, -1,   t, 0, 1,  -t, 0, -1,  -t, 0, 1
        ]
        let indices: [Int] = [
            0, 11, 5,  0, 5, 1,  0, 1, 7,  0, 7, 10,  0, 10, 11,
            1, 5, 9,  5, 11, 4,  11, 10, 2,  10, 7, 6,  7, 1, 8,
            3, 9, 4,  3, 4, 2,  3, 2, 6,  3, 6, 8,  3, 8, 9,
            4, 9, 5,  2, 11, 4,  6, 10, 2,  8, 7, 6,  9, 1, 8
        ]
        return polyhedron(vertices: vertices, indices: indices, radius: radius, detail: detail)
    }

    /// JS: `new THREE.TetrahedronGeometry(radius, detail)`
    static func tetrahedron(radius: Float, detail: Int = 0) -> SCNGeometry {
        let vertices: [Float] = [
            1, 1, 1,   -1, -1, 1,   -1, 1, -1,   1, -1, -1
        ]
        let indices: [Int] = [
            2, 1, 0,  0, 3, 2,  1, 3, 0,  2, 3, 1
        ]
        return polyhedron(vertices: vertices, indices: indices, radius: radius, detail: detail)
    }

    /// JS: `new THREE.OctahedronGeometry(radius, detail)`
    static func octahedron(radius: Float, detail: Int = 0) -> SCNGeometry {
        let vertices: [Float] = [
            1, 0, 0,  -1, 0, 0,  0, 1, 0,  0, -1, 0,  0, 0, 1,  0, 0, -1
        ]
        let indices: [Int] = [
            0, 2, 4,  0, 4, 3,  0, 3, 5,  0, 5, 2,
            1, 2, 5,  1, 5, 3,  1, 3, 4,  1, 4, 2
        ]
        return polyhedron(vertices: vertices, indices: indices, radius: radius, detail: detail)
    }

    /// JS: LineSegments from interleaved xyz floats (2 verts per segment)
    static func lineSegments(_ verts: [Float], color: UIColor, opacity: CGFloat = 1) -> SCNNode? {
        guard verts.count >= 6 else { return nil }
        let data = verts.withUnsafeBufferPointer { Data(buffer: $0) }
        let src = SCNGeometrySource(
            data: data, semantic: .vertex, vectorCount: verts.count / 3,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        var idx = (0..<Int32(verts.count / 3)).map { $0 }
        let idxData = idx.withUnsafeMutableBufferPointer { Data(buffer: $0) }
        let elem = SCNGeometryElement(
            data: idxData, primitiveType: .line,
            primitiveCount: idx.count / 2, bytesPerIndex: 4
        )
        let geo = SCNGeometry(sources: [src], elements: [elem])
        geo.firstMaterial = wireMat(color, opacity: opacity, lines: true)
        return SCNNode(geometry: geo)
    }

    /// JS: MeshBasicMaterial({color, wireframe:true, transparent:true, opacity})
    static func wireMat(_ color: UIColor, opacity: CGFloat, lines: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        let c = color.withAlphaComponent(opacity)
        m.diffuse.contents = c
        m.emission.contents = c
        m.ambient.contents = c
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        if lines { m.fillMode = .lines }
        return m
    }

    static func basicMat(_ color: UIColor, opacity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        let c = color.withAlphaComponent(opacity)
        m.diffuse.contents = c
        m.emission.contents = c
        m.lightingModel = .constant
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        return m
    }

    static func hex(_ v: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((v >> 16) & 0xFF) / 255.0,
            green: CGFloat((v >> 8) & 0xFF) / 255.0,
            blue: CGFloat(v & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
