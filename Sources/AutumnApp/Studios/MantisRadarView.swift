import SwiftUI
import MapKit
import SceneKit
import CoreLocation
import UIKit
import AutumnServices

/// Native Mantis Radar (mr.html). 2D MapKit + 3D globe, live ADS-B, CelesTrak TLE.
/// Not a WKWebView of mr.html.
struct MantisRadarView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var authVM: AuthViewModel
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
                    RadarMapView(feed: feed, avatarURL: authVM.githubAvatarURL, avatarLetter: authVM.username)
                } else {
                    RadarGlobeView(feed: feed, avatarURL: authVM.githubAvatarURL, avatarLetter: authVM.username)
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

                    if let sat = feed.selectedSat {
                        satInfoCard(sat, cyan: cyan)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
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

    private func satInfoCard(_ sat: RadarSat, cyan: Color) -> some View {
        let classColor: Color = {
            switch sat.orbitClass {
            case "LEO": return cyan
            case "MEO": return Color(hex: "#ffd700")
            default: return Color(hex: "#ff8800")
            }
        }()
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(sat.name)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(cyan)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button { feed.selectedSat = nil } label: {
                    Text("✕")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            Text(sat.objectType.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
            HStack(spacing: 10) {
                Text(sat.orbitClass).foregroundColor(classColor)
                Text("\(Int(sat.altKm.rounded())) km").foregroundColor(.white.opacity(0.85))
                Text(String(format: "%.1f min", sat.periodMin)).foregroundColor(.white.opacity(0.85))
            }
            .font(.system(size: 9, design: .monospaced))
            HStack(spacing: 10) {
                Text(String(format: "INC %.1f°", sat.inc))
                Text(String(format: "ECC %.5f", sat.ecc))
                Text("NORAD \(sat.id)")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.7))
            Text(String(format: "LAT %.3f  LON %.3f", sat.lat, sat.lon))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(10)
        .frame(maxWidth: 280, alignment: .leading)
        .background(Color.black.opacity(0.72))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(cyan.opacity(0.35), lineWidth: 1))
        .padding(8)
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

// MARK: — shared circular GitHub avatar (map pin + globe billboard)
enum RadarAvatarArt {
    static let cyan = UIColor(red: 0, green: 0.96, blue: 1, alpha: 1)

    static func image(photo: UIImage?, letter: String, size: CGFloat) -> UIImage {
        let s = CGSize(width: size, height: size)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        fmt.scale = 2
        return UIGraphicsImageRenderer(size: s, format: fmt).image { _ in
            let rect = CGRect(origin: .zero, size: s).insetBy(dx: 1.5, dy: 1.5)
            let clip = UIBezierPath(ovalIn: rect)
            clip.addClip()
            UIColor(red: 0, green: 0.12, blue: 0.16, alpha: 1).setFill()
            clip.fill()
            if let photo {
                photo.draw(in: CGRect(origin: .zero, size: s))
            } else {
                let ch = String(letter.prefix(1)).uppercased() as NSString
                let font = UIFont.monospacedSystemFont(ofSize: size * 0.38, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: cyan]
                let sz = ch.size(withAttributes: attrs)
                ch.draw(at: CGPoint(x: (s.width - sz.width) / 2, y: (s.height - sz.height) / 2), withAttributes: attrs)
            }
            cyan.setStroke()
            let ring = UIBezierPath(ovalIn: rect)
            ring.lineWidth = max(2, size * 0.07)
            ring.stroke()
        }
    }
}

// MARK: — 2D map (MapKit + dark tiles + live aircraft annotations)
struct RadarMapView: UIViewRepresentable {
    @ObservedObject var feed: RadarFeed
    var avatarURL: URL?
    var avatarLetter: String

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
        context.coordinator.map = m
        context.coordinator.letter = avatarLetter
        context.coordinator.loadAvatar(avatarURL)
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) {
        context.coordinator.map = m
        context.coordinator.letter = avatarLetter
        context.coordinator.loadAvatar(avatarURL)
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
        weak var map: MKMapView?
        var letter = "G"
        var avatarImage: UIImage?
        private var loadedURL: URL?
        private var avatarTask: URLSessionDataTask?
        private var byId: [String: RadarACAnnotation] = [:]

        func loadAvatar(_ url: URL?) {
            if url == loadedURL { return }
            loadedURL = url
            avatarTask?.cancel()
            avatarImage = nil
            refreshUserPin()
            guard let url else { return }
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue("Autumn-iOS/1.0.2", forHTTPHeaderField: "User-Agent")
            avatarTask = URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                let img = data.flatMap(UIImage.init(data:))
                DispatchQueue.main.async {
                    guard let self, self.loadedURL == url else { return }
                    self.avatarImage = img
                    self.refreshUserPin()
                }
            }
            avatarTask?.resume()
        }

        private func refreshUserPin() {
            guard let map, let v = map.view(for: map.userLocation) as? RadarUserPinView else { return }
            v.apply(image: avatarImage, letter: letter)
        }

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
                    existing.subtitle = ac.altitude.map { String(format: "%.0f ft", $0) }
                    existing.icon = ac.icon
                    existing.trackDeg = ac.track
                    existing.rotates = ac.rotatesWithTrack
                    if let v = map.view(for: existing) as? RadarACPinView {
                        v.apply(existing)
                    }
                } else {
                    let a = RadarACAnnotation()
                    a.aircraftId = ac.id
                    a.coordinate = ac.coordinate
                    a.title = ac.callsign
                    a.subtitle = ac.altitude.map { String(format: "%.0f ft", $0) }
                    a.icon = ac.icon
                    a.trackDeg = ac.track
                    a.rotates = ac.rotatesWithTrack
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
            if annotation is MKUserLocation {
                let id = RadarUserPinView.reuse
                let v = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? RadarUserPinView)
                    ?? RadarUserPinView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.apply(image: avatarImage, letter: letter)
                return v
            }
            guard let ac = annotation as? RadarACAnnotation else { return nil }
            let id = RadarACPinView.reuse
            let v = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? RadarACPinView)
                ?? RadarACPinView(annotation: annotation, reuseIdentifier: id)
            v.annotation = ac
            v.apply(ac)
            return v
        }
    }
}

final class RadarACAnnotation: MKPointAnnotation {
    var aircraftId: String = ""
    var icon: String = "✈"
    var trackDeg: Double?
    var rotates = false
}

final class RadarACPinView: MKAnnotationView {
    static let reuse = "radar-ac"
    private let badge = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        centerOffset = .zero
        canShowCallout = true
        displayPriority = .required
        clusteringIdentifier = nil
        badge.frame = CGRect(x: 2, y: 2, width: 28, height: 28)
        badge.textAlignment = .center
        badge.font = UIFont.systemFont(ofSize: 14)
        badge.backgroundColor = UIColor(red: 0, green: 0.22, blue: 0.28, alpha: 0.94)
        badge.textColor = .white
        badge.layer.cornerRadius = 14
        badge.layer.masksToBounds = true
        badge.layer.borderWidth = 1.5
        badge.layer.borderColor = UIColor(red: 0, green: 0.96, blue: 1, alpha: 1).cgColor
        addSubview(badge)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ a: RadarACAnnotation) {
        badge.text = a.icon
        if a.rotates, let t = a.trackDeg {
            badge.transform = CGAffineTransform(rotationAngle: CGFloat(t * .pi / 180.0))
        } else {
            badge.transform = .identity
        }
    }
}

final class RadarUserPinView: MKAnnotationView {
    static let reuse = "radar-user"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = true
        displayPriority = .required
        centerOffset = .zero
        collisionMode = .circle
        clusteringIdentifier = nil
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(image: UIImage?, letter: String) {
        let img = RadarAvatarArt.image(photo: image, letter: letter, size: 36)
        self.image = img
        bounds = CGRect(x: 0, y: 0, width: 36, height: 36)
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
    var avatarURL: URL?
    var avatarLetter: String

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = context.coordinator.buildScene()
        v.backgroundColor = UIColor(red: 0.01, green: 0.04, blue: 0.06, alpha: 1)
        v.allowsCameraControl = true
        v.antialiasingMode = .multisampling4X
        v.autoenablesDefaultLighting = false
        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 80))
        context.coordinator.root.runAction(spin)
        context.coordinator.scnView = v
        let tap = RadarShortTapRecognizer(target: context.coordinator, action: #selector(Globe.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        v.addGestureRecognizer(tap)
        context.coordinator.letter = avatarLetter
        context.coordinator.loadAvatar(avatarURL)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        context.coordinator.feed = feed
        context.coordinator.scnView = v
        context.coordinator.letter = avatarLetter
        context.coordinator.loadAvatar(avatarURL)
        context.coordinator.sync(
            sats: feed.satellites,
            aircraft: feed.aircraft,
            userLat: feed.userLat,
            userLon: feed.userLon,
            selectedId: feed.selectedSat?.id
        )
    }

    func makeCoordinator() -> Globe { Globe() }

    final class Globe: NSObject, UIGestureRecognizerDelegate {
        let root = SCNNode()
        let satRoot = SCNNode()
        let acRoot = SCNNode()
        let userNode = SCNNode()
        let earthR: Float = 1.0
        weak var scnView: SCNView?
        weak var feed: RadarFeed?
        var letter = "G"
        var avatarImage: UIImage?
        private var loadedURL: URL?
        private var avatarTask: URLSessionDataTask?
        private var satNodes: [String: SCNNode] = [:]
        private var acNodes: [String: SCNNode] = [:]
        private var lastSats: [RadarSat] = []
        private var orbitNode: SCNNode?
        private var tickNode: SCNNode?
        private var orbitSatId: String?
        private var lastAvatarKey = ""

        func buildScene() -> SCNScene {
            let scene = SCNScene()
            let earth = SCNSphere(radius: CGFloat(earthR))
            earth.segmentCount = 64
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(red: 0.02, green: 0.08, blue: 0.16, alpha: 1)
            mat.emission.contents = UIColor(red: 0, green: 0.12, blue: 0.18, alpha: 1)
            mat.lightingModel = .phong
            mat.locksAmbientWithDiffuse = true
            mat.specular.contents = UIColor(white: 0.18, alpha: 1)
            earth.firstMaterial = mat
            let earthNode = SCNNode(geometry: earth)
            earthNode.name = "earth"
            root.addChildNode(earthNode)
            addGeoJSONLines(resource: "ne_110m_coastline", color: UIColor(red: 0, green: 0.96, blue: 1, alpha: 1), opacity: 0.85, rScale: 1.0025)
            addGeoJSONLines(resource: "ne_110m_admin_0_boundary_lines_land", color: UIColor(red: 0, green: 0.78, blue: 0.847, alpha: 1), opacity: 0.35, rScale: 1.003)

            let grid = SCNSphere(radius: CGFloat(earthR) * 1.002)
            grid.segmentCount = 24
            let gm = SCNMaterial()
            gm.fillMode = .lines
            gm.diffuse.contents = UIColor.cyan.withAlphaComponent(0.18)
            gm.lightingModel = .constant
            gm.isDoubleSided = true
            grid.firstMaterial = gm
            root.addChildNode(SCNNode(geometry: grid))

            applyUserAvatar(force: true)
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

        func loadAvatar(_ url: URL?) {
            if url == loadedURL { return }
            loadedURL = url
            avatarTask?.cancel()
            avatarImage = nil
            applyUserAvatar(force: true)
            guard let url else { return }
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue("Autumn-iOS/1.0.2", forHTTPHeaderField: "User-Agent")
            avatarTask = URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                let img = data.flatMap(UIImage.init(data:))
                DispatchQueue.main.async {
                    guard let self, self.loadedURL == url else { return }
                    self.avatarImage = img
                    self.applyUserAvatar(force: true)
                }
            }
            avatarTask?.resume()
        }

        func applyUserAvatar(force: Bool) {
            let key = "\(avatarImage != nil)-\(letter)"
            if !force && key == lastAvatarKey { return }
            lastAvatarKey = key
            let img = RadarAvatarArt.image(photo: avatarImage, letter: letter, size: 64)
            let plane = SCNPlane(width: 0.09, height: 0.09)
            let mat = SCNMaterial()
            mat.diffuse.contents = img
            mat.emission.contents = img
            mat.transparent.contents = img
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.writesToDepthBuffer = false
            plane.firstMaterial = mat
            userNode.geometry = plane
            userNode.name = "user"
            if userNode.constraints == nil || userNode.constraints?.isEmpty == true {
                userNode.constraints = [SCNBillboardConstraint()]
            }
        }

        func sync(sats: [RadarSat], aircraft: [RadarAircraft], userLat: Double, userLon: Double, selectedId: String?) {
            lastSats = Array(sats.prefix(220))
            userNode.position = xyz(lat: userLat, lon: userLon, altKm: 50)
            applyUserAvatar(force: false)

            let live = Set(lastSats.map(\.id))
            for (id, n) in satNodes where !live.contains(id) {
                n.removeFromParentNode()
                satNodes.removeValue(forKey: id)
            }
            for s in lastSats {
                let pos = xyz(lat: s.lat, lon: s.lon, altKm: max(200, s.altKm))
                let selected = s.id == selectedId
                let r: CGFloat = selected ? 0.022 : 0.014
                let col = Self.uiColor(s)
                if let n = satNodes[s.id] {
                    n.position = pos
                    if let sph = n.geometry as? SCNSphere, abs(sph.radius - r) > 0.0005 {
                        sph.radius = r
                    }
                    n.geometry?.firstMaterial?.diffuse.contents = col
                    n.geometry?.firstMaterial?.emission.contents = selected ? UIColor.white : col
                } else {
                    let sph = SCNSphere(radius: r)
                    sph.segmentCount = 12
                    let m = SCNMaterial()
                    m.diffuse.contents = col
                    m.emission.contents = col
                    m.lightingModel = .constant
                    sph.firstMaterial = m
                    let n = SCNNode(geometry: sph)
                    n.name = "sat:\(s.id)"
                    n.position = pos
                    satRoot.addChildNode(n)
                    satNodes[s.id] = n
                }
            }

            let acLive = Set(aircraft.prefix(80).map(\.id))
            for (id, n) in acNodes where !acLive.contains(id) {
                n.removeFromParentNode()
                acNodes.removeValue(forKey: id)
            }
            for a in aircraft.prefix(80) {
                let altKm = (a.altitude ?? 30000) * 0.0003048
                let pos = xyz(lat: a.lat, lon: a.lon, altKm: max(8, altKm))
                if let n = acNodes[a.id] {
                    n.position = pos
                } else {
                    let acg = SCNSphere(radius: 0.01)
                    acg.firstMaterial?.diffuse.contents = UIColor.cyan
                    acg.firstMaterial?.emission.contents = UIColor.cyan
                    acg.firstMaterial?.lightingModel = .constant
                    let n = SCNNode(geometry: acg)
                    n.name = a.callsign
                    n.position = pos
                    acRoot.addChildNode(n)
                    acNodes[a.id] = n
                }
            }

            if selectedId != orbitSatId {
                rebuildOrbit(id: selectedId)
            }
            if let id = selectedId, let s = lastSats.first(where: { $0.id == id }) {
                updateTick(s)
            } else {
                tickNode?.removeFromParentNode()
                tickNode = nil
            }
        }

        private func rebuildOrbit(id: String?) {
            orbitNode?.removeFromParentNode()
            orbitNode = nil
            orbitSatId = id
            guard let id, let s = lastSats.first(where: { $0.id == id }) else { return }
            let body = s.keplerBody()
            let periodMin = s.periodMin
            let steps = 240
            let dt = periodMin / Double(steps)
            let now = Date()
            var verts: [Float] = []
            var prev: SCNVector3?
            for i in 0...steps {
                let t = now.addingTimeInterval((Double(i) * dt - periodMin / 2.0) * 60)
                let p = body.geodetic(at: t)
                let v = xyz(lat: p.lat, lon: p.lon, altKm: max(200, p.altKm))
                if let prev {
                    verts += [prev.x, prev.y, prev.z, v.x, v.y, v.z]
                }
                prev = v
            }
            if let node = ThreeJSGeometry.lineSegments(verts, color: UIColor(red: 0.15, green: 1, blue: 0.45, alpha: 1), opacity: 0.78) {
                node.name = "orbit"
                root.addChildNode(node)
                orbitNode = node
            }
        }

        private func updateTick(_ s: RadarSat) {
            tickNode?.removeFromParentNode()
            let body = s.keplerBody()
            let now = Date()
            let p0 = body.geodetic(at: now)
            let p1 = body.geodetic(at: now.addingTimeInterval(90))
            let a = xyz(lat: p0.lat, lon: p0.lon, altKm: max(200, p0.altKm))
            let b = xyz(lat: p1.lat, lon: p1.lon, altKm: max(200, p1.altKm))
            let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
            let len = max(0.0001, sqrt(dx * dx + dy * dy + dz * dz))
            let scale: Float = 0.09 / len
            let c = SCNVector3(a.x + dx * scale, a.y + dy * scale, a.z + dz * scale)
            // small barb for flight-path direction
            let px: Float = -dy * 0.18, py: Float = dx * 0.18
            let left = SCNVector3(c.x - dx * scale * 0.35 + px * 0.015, c.y - dy * scale * 0.35 + py * 0.015, c.z - dz * scale * 0.35)
            let right = SCNVector3(c.x - dx * scale * 0.35 - px * 0.015, c.y - dy * scale * 0.35 - py * 0.015, c.z - dz * scale * 0.35)
            let verts: [Float] = [
                a.x, a.y, a.z, c.x, c.y, c.z,
                c.x, c.y, c.z, left.x, left.y, left.z,
                c.x, c.y, c.z, right.x, right.y, right.z
            ]
            if let node = ThreeJSGeometry.lineSegments(verts, color: UIColor(red: 0.7, green: 1, blue: 0.85, alpha: 1), opacity: 0.95) {
                node.name = "orbit-tick"
                root.addChildNode(node)
                tickNode = node
            }
        }

        @objc func handleTap(_ g: UIGestureRecognizer) {
            guard g.state == .recognized, let view = scnView else { return }
            let pt = g.location(in: view)
            guard let id = pickSat(at: pt, in: view),
                  let sat = lastSats.first(where: { $0.id == id }) else { return }
            Task { @MainActor in
                self.feed?.selectedSat = sat
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        private func pickSat(at point: CGPoint, in view: SCNView) -> String? {
            var best: (String, CGFloat)?
            for (id, node) in satNodes {
                let p = view.projectPoint(node.worldPosition)
                guard p.z > 0, p.z < 1 else { continue }
                let d = hypot(CGFloat(p.x) - point.x, CGFloat(p.y) - point.y)
                if d < 32, best == nil || d < best!.1 {
                    best = (id, d)
                }
            }
            if let best { return best.0 }
            let hits = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .boundingBoxOnly: true
            ])
            for h in hits {
                if let name = h.node.name, name.hasPrefix("sat:") {
                    return String(name.dropFirst(4))
                }
            }
            return nil
        }

        static func uiColor(_ s: RadarSat) -> UIColor {
            let c = s.markerColor()
            return UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
        }

        /// mr.html latLonToV3 — continents, sats, and the user mark must share this.
        private func xyz(lat: Double, lon: Double, altKm: Double) -> SCNVector3 {
            let r = earthR * Float(1.0 + max(0, altKm) / 6371.0 * 0.18)
            return latLon(lat: lat, lon: lon, r: r)
        }

        private func latLon(lat: Double, lon: Double, r: Float) -> SCNVector3 {
            let la = Float(lat * .pi / 180)
            let lo = Float(lon * .pi / 180)
            return SCNVector3(r * cos(la) * cos(lo), r * sin(la), -r * cos(la) * sin(lo))
        }

        static func num(_ v: Any) -> Double? {
            if let n = v as? NSNumber { return n.doubleValue }
            if let d = v as? Double { return d }
            return nil
        }

        private func addGeoJSONLines(resource: String, color: UIColor, opacity: CGFloat, rScale: Float) {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "geojson"),
                  let data = try? Data(contentsOf: url),
                  let rootObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let features = rootObj["features"] as? [[String: Any]] else { return }
            var verts: [Float] = []
            let rr = earthR * rScale
            for f in features {
                guard let geom = f["geometry"] as? [String: Any] else { continue }
                let type = geom["type"] as? String ?? ""
                let rings: [[[Any]]]
                if type == "LineString", let c = geom["coordinates"] as? [[Any]] {
                    rings = [c]
                } else if type == "MultiLineString", let c = geom["coordinates"] as? [[[Any]]] {
                    rings = c
                } else if type == "Polygon", let c = geom["coordinates"] as? [[[Any]]] {
                    rings = c
                } else if type == "MultiPolygon", let c = geom["coordinates"] as? [[[[Any]]]] {
                    rings = c.flatMap { $0 }
                } else {
                    continue
                }
                for ring in rings {
                    var pts: [SCNVector3] = []
                    pts.reserveCapacity(ring.count)
                    for pair in ring {
                        guard pair.count >= 2, let lon = Self.num(pair[0]), let lat = Self.num(pair[1]) else { continue }
                        pts.append(latLon(lat: lat, lon: lon, r: rr))
                    }
                    guard pts.count >= 2 else { continue }
                    for i in 0..<(pts.count - 1) {
                        let a = pts[i], b = pts[i + 1]
                        verts += [a.x, a.y, a.z, b.x, b.y, b.z]
                    }
                }
            }
            if let node = ThreeJSGeometry.lineSegments(verts, color: color, opacity: opacity) {
                node.name = resource
                root.addChildNode(node)
            }
        }
    }
}

/// Short tap that fails if the finger dragged — SceneKit camera pan still works.
final class RadarShortTapRecognizer: UIGestureRecognizer {
    private var origin = CGPoint.zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let t = touches.first else { state = .failed; return }
        origin = t.location(in: view)
        state = .possible
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = touches.first else { return }
        let p = t.location(in: view)
        if hypot(p.x - origin.x, p.y - origin.y) > 10 {
            state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible {
            state = .recognized
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }
}
