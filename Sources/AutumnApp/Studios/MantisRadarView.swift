import SwiftUI
import MapKit
import SceneKit
import CoreLocation

/// Native Mantis Radar (mr.html). 2D MapKit + 3D globe, live ADS-B, CelesTrak TLE.
/// Not a WKWebView of mr.html.
struct MantisRadarView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @ObservedObject private var feed = RadarFeed.shared
    @State private var aerial = true

    var body: some View {
        let cyan = Color(hex: "#00f5ff")
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("MANTIS RADAR")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(cyan)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 0) {
                    tab("2D AERIAL", on: aerial) { aerial = true }
                    tab("3D ORBIT", on: !aerial) { aerial = false }
                }
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(cyan.opacity(0.25), lineWidth: 1))
                Button { appNav.showRadar = false } label: {
                    Text("✕ CLOSE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.black.opacity(0.55))

            ZStack(alignment: .topLeading) {
                if aerial {
                    RadarMapView(feed: feed)
                } else {
                    RadarGlobeView(feed: feed)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CELESTRAK TLE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(cyan)
                        Text(feed.orbitStatus)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                        Text("\(feed.satellites.count) SAT / DEBRIS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(cyan)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.55))
                    .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text(aerial ? "2D AERIAL  \(feed.adsbStatus)" : "3D ORBITAL  \(feed.orbitStatus)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(cyan)
                Spacer()
                Text(String(format: "%.4f  %.4f", feed.userLat, feed.userLon))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Text(aerial ? "\(feed.aircraft.count) AC" : "\(feed.satellites.count) SAT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(cyan)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.black.opacity(0.55))
        }
        .background(Color(red: 0.01, green: 0.04, blue: 0.05).ignoresSafeArea())
        .onAppear { feed.start() }
    }

    private func tab(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(on ? Color(hex: "#00f5ff") : Color(hex: "#00f5ff").opacity(0.45))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(on ? Color(hex: "#00f5ff").opacity(0.14) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: — 2D map (MapKit + dark tiles + live aircraft annotations)
struct RadarMapView: UIViewRepresentable {
    @ObservedObject var feed: RadarFeed

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.mapType = .mutedStandard
        m.overrideUserInterfaceStyle = .dark
        m.showsUserLocation = true
        m.showsCompass = true
        m.isRotateEnabled = false
        let overlay = RadarTileOverlay()
        overlay.canReplaceMapContent = true
        m.addOverlay(overlay, level: .aboveLabels)
        context.coordinator.overlay = overlay
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) {
        let ready = feed.hasFix || feed.authSettled
        if ready && !context.coordinator.didCenterOnFix {
            let center = CLLocationCoordinate2D(latitude: feed.userLat, longitude: feed.userLon)
            m.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)), animated: feed.hasFix)
            context.coordinator.didCenterOnFix = true
        }
        context.coordinator.sync(aircraft: feed.aircraft, on: m)
    }

    func makeCoordinator() -> Coord { Coord() }

    final class Coord: NSObject, MKMapViewDelegate {
        var didCenterOnFix = false
        var overlay: MKTileOverlay?
        private var byId: [String: MKPointAnnotation] = [:]

        func sync(aircraft: [RadarAircraft], on map: MKMapView) {
            let live = Set(aircraft.map(\.id))
            for (id, ann) in byId where !live.contains(id) {
                map.removeAnnotation(ann)
                byId.removeValue(forKey: id)
            }
            for ac in aircraft {
                if let existing = byId[ac.id] {
                    existing.coordinate = ac.coordinate
                    existing.title = ac.callsign
                } else {
                    let a = MKPointAnnotation()
                    a.coordinate = ac.coordinate
                    a.title = ac.callsign
                    a.subtitle = ac.altitude.map { String(format: "%.0f ft", $0) }
                    byId[ac.id] = a
                    map.addAnnotation(a)
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let t = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: t)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let id = "ac"
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            v.annotation = annotation
            if let marker = v as? MKMarkerAnnotationView {
                marker.markerTintColor = UIColor(red: 0, green: 0.96, blue: 1, alpha: 1)
                marker.glyphText = "✈"
                marker.titleVisibility = .adaptive
            }
            v.canShowCallout = true
            return v
        }
    }
}

final class RadarTileOverlay: MKTileOverlay {
    init() {
        if RadarFeed.cartoBasemapKey.isEmpty {
            super.init(urlTemplate: "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}")
        } else {
            super.init(urlTemplate: nil)
        }
        canReplaceMapContent = true
        maximumZ = RadarFeed.cartoBasemapKey.isEmpty ? 16 : 20
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let key = RadarFeed.cartoBasemapKey
        if key.isEmpty {
            return URL(string: "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/\(path.z)/\(path.y)/\(path.x)")!
        }
        let s = ["a", "b", "c", "d"][abs(path.x) % 4]
        return URL(string: "https://\(s).basemaps.cartocdn.com/dark_all/\(path.z)/\(path.x)/\(path.y)@2x.png?key=\(key)")!
    }
}

// MARK: — 3D globe (SceneKit) + TLE sats
struct RadarGlobeView: UIViewRepresentable {
    @ObservedObject var feed: RadarFeed

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = context.coordinator.buildScene()
        v.backgroundColor = UIColor(red: 0.01, green: 0.04, blue: 0.06, alpha: 1)
        v.allowsCameraControl = true
        v.antialiasingMode = .multisampling4X
        v.autoenablesDefaultLighting = false
        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 80))
        context.coordinator.root.runAction(spin)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        context.coordinator.sync(sats: feed.satellites, aircraft: feed.aircraft, userLat: feed.userLat, userLon: feed.userLon)
    }

    func makeCoordinator() -> Globe { Globe() }

    final class Globe {
        let root = SCNNode()
        let satRoot = SCNNode()
        let acRoot = SCNNode()
        let userNode = SCNNode()
        let earthR: Float = 1.0

        func buildScene() -> SCNScene {
            let scene = SCNScene()
            let earth = SCNSphere(radius: CGFloat(earthR))
            earth.segmentCount = 64
            let mat = SCNMaterial()
            mat.diffuse.contents = Self.earthTexture()
            mat.emission.contents = UIColor(red: 0, green: 0.25, blue: 0.35, alpha: 0.18)
            mat.lightingModel = .phong
            mat.locksAmbientWithDiffuse = true
            mat.specular.contents = UIColor(white: 0.25, alpha: 1)
            earth.firstMaterial = mat
            let earthNode = SCNNode(geometry: earth)
            earthNode.name = "earth"
            root.addChildNode(earthNode)

            let grid = SCNSphere(radius: CGFloat(earthR) * 1.002)
            grid.segmentCount = 24
            let gm = SCNMaterial()
            gm.fillMode = .lines
            gm.diffuse.contents = UIColor.cyan.withAlphaComponent(0.18)
            gm.lightingModel = .constant
            gm.isDoubleSided = true
            grid.firstMaterial = gm
            root.addChildNode(SCNNode(geometry: grid))

            let userGeo = SCNSphere(radius: 0.02)
            userGeo.firstMaterial?.diffuse.contents = UIColor.cyan
            userGeo.firstMaterial?.emission.contents = UIColor.cyan
            userGeo.firstMaterial?.lightingModel = .constant
            userNode.geometry = userGeo
            root.addChildNode(userNode)
            root.addChildNode(satRoot)
            root.addChildNode(acRoot)

            let amb = SCNNode()
            amb.light = { let l = SCNLight(); l.type = .ambient; l.intensity = 400; l.color = UIColor.white; return l }()
            let dir = SCNNode()
            dir.light = { let l = SCNLight(); l.type = .directional; l.intensity = 600; l.color = UIColor.white; return l }()
            dir.eulerAngles = SCNVector3(-0.6, 0.4, 0)

            let cam = SCNNode()
            cam.camera = { let c = SCNCamera(); c.fieldOfView = 50; c.zFar = 100; return c }()
            cam.position = SCNVector3(0, 0, 3.2)

            scene.rootNode.addChildNode(root)
            scene.rootNode.addChildNode(amb)
            scene.rootNode.addChildNode(dir)
            scene.rootNode.addChildNode(cam)
            return scene
        }

        func sync(sats: [RadarSat], aircraft: [RadarAircraft], userLat: Double, userLon: Double) {
            userNode.position = xyz(lat: userLat, lon: userLon, altKm: 0)
            satRoot.childNodes.forEach { $0.removeFromParentNode() }
            acRoot.childNodes.forEach { $0.removeFromParentNode() }
            let geo = SCNSphere(radius: 0.012)
            geo.firstMaterial?.diffuse.contents = UIColor.orange
            geo.firstMaterial?.emission.contents = UIColor.orange.withAlphaComponent(0.8)
            geo.firstMaterial?.lightingModel = .constant
            for s in sats.prefix(220) {
                let n = SCNNode(geometry: geo)
                n.position = xyz(lat: s.lat, lon: s.lon, altKm: max(200, s.altKm))
                n.name = s.name
                satRoot.addChildNode(n)
            }
            let acg = SCNSphere(radius: 0.01)
            acg.firstMaterial?.diffuse.contents = UIColor.cyan
            acg.firstMaterial?.emission.contents = UIColor.cyan
            acg.firstMaterial?.lightingModel = .constant
            for a in aircraft.prefix(80) {
                let n = SCNNode(geometry: acg)
                let altKm = (a.altitude ?? 30000) * 0.0003048
                n.position = xyz(lat: a.lat, lon: a.lon, altKm: max(8, altKm))
                n.name = a.callsign
                acRoot.addChildNode(n)
            }
        }

        static func earthTexture() -> UIImage {
            let s: CGFloat = 512
            let r = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
            return r.image { ctx in
                UIColor(red: 0.02, green: 0.08, blue: 0.16, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                let c = ctx.cgContext
                // land blobs
                UIColor(red: 0.12, green: 0.32, blue: 0.22, alpha: 1).setFill()
                let lands: [(CGFloat,CGFloat,CGFloat,CGFloat)] = [
                    (40,90,130,90),(200,70,90,70),(320,110,140,80),(80,250,160,70),
                    (280,280,120,90),(420,160,70,110),(10,360,180,80),(250,380,160,60)
                ]
                for (x,y,w,h) in lands {
                    c.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
                }
                // night terminator wash
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.45).cgColor] as CFArray,
                                   locations: [0,1])!
                c.drawLinearGradient(g, start: CGPoint(x: s*0.35, y: 0), end: CGPoint(x: s, y: 0), options: [])
            }
        }

        private func xyz(lat: Double, lon: Double, altKm: Double) -> SCNVector3 {
            let r = earthR * Float(1.0 + max(0, altKm) / 6371.0 * 0.18)
            let la = Float(lat * .pi / 180)
            let lo = Float(lon * .pi / 180)
            return SCNVector3(r * cos(la) * sin(lo), r * sin(la), r * cos(la) * cos(lo))
        }
    }
}
