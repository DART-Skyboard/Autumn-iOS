import SwiftUI
import SceneKit
import CoreMotion

// MARK: — MantisNavigationView
// Full port of mn.html — Three.js flight simulator in SceneKit
// Features: GLB model loading, physics flight, joystick, thrust,
//           ADS-B aircraft tracking, TLE orbital satellites, FPV/Follow cam

public struct MantisNavigationView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @StateObject private var vm = MantisViewModel()
    @State private var showModelPicker = false

    public var body: some View {
        ZStack {
            Color(red:0.01, green:0.02, blue:0.05).ignoresSafeArea()

            // ── 3D Scene ──────────────────────────────────────────
            MantisSceneView(vm: vm)
                .ignoresSafeArea()

            // ── HUD overlay ───────────────────────────────────────
            VStack(spacing:0) {
                MantisTopBar(vm: vm, showModelPicker: $showModelPicker)
                Spacer()
                MantisBottomHUD(vm: vm)
            }
            .ignoresSafeArea(edges: .bottom)

            // ── Joystick + Thrust ─────────────────────────────────
            VStack {
                Spacer()
                HStack(alignment:.bottom, spacing:30) {
                    MantisJoystick(x: $vm.joystickX, y: $vm.joystickY)
                        .frame(width:130, height:130)
                    Spacer()
                    MantisThrustSlider(value: $vm.thrust)
                        .frame(width:44, height:130)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 60)
            }
        }
        .sheet(isPresented: $showModelPicker) {
            MantisModelPickerSheet(vm: vm)
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

// MARK: — Top Bar
struct MantisTopBar: View {
    @ObservedObject var vm: MantisViewModel
    @Binding var showModelPicker: Bool

    var body: some View {
        HStack(spacing:8) {
            // Logo
            HStack(spacing:6) {
                Image(systemName:"antenna.radiowaves.left.and.right")
                    .font(.system(size:12))
                    .foregroundColor(.cyan)
                Text("MANTIS")
                    .font(.custom("Orbitron-Bold", size:13))
                    .foregroundColor(.white)
                    .tracking(2)
                Text("NAV")
                    .font(.system(size:9, design:.monospaced))
                    .foregroundColor(.cyan.opacity(0.6))
            }

            // Source badges
            HStack(spacing:4) {
                MantisBadge("ADS-B", active: vm.adsbActive, color: .orange)
                MantisBadge("ORBITAL", active: vm.orbitalActive, color: .purple)
            }

            Spacer()

            // Camera mode
            Button {
                vm.toggleCameraMode()
            } label: {
                Text(vm.cameraMode.rawValue.uppercased())
                    .font(.system(size:9, weight:.semibold, design:.monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal,8).padding(.vertical,4)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Model picker
            Button { showModelPicker = true } label: {
                Image(systemName:"square.3.layers.3d")
                    .font(.system(size:14))
                    .foregroundColor(.cyan)
                    .frame(width:30,height:30)
                    .background(Color.cyan.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius:6))
            }
        }
        .padding(.horizontal,14).padding(.vertical,8)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height:0.5).foregroundColor(.cyan.opacity(0.2)), alignment:.bottom)
    }
}

struct MantisBadge: View {
    let label: String; let active: Bool; let color: Color
    init(_ label: String, active: Bool, color: Color) {
        self.label=label; self.active=active; self.color=color
    }
    var body: some View {
        HStack(spacing:4) {
            Circle().fill(active ? color : .red).frame(width:5,height:5)
            Text(label).font(.system(size:8,weight:.semibold,design:.monospaced))
                .foregroundColor(active ? color : .red)
        }
        .padding(.horizontal,7).padding(.vertical,3)
        .background((active ? color : Color.red).opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke((active ? color : Color.red).opacity(0.25), lineWidth:0.6))
    }
}

// MARK: — Bottom HUD
struct MantisBottomHUD: View {
    @ObservedObject var vm: MantisViewModel

    var body: some View {
        VStack(spacing:0) {
            // Telemetry strip
            HStack(spacing:0) {
                hudItem("VIEW", vm.cameraMode.rawValue, .white)
                Divider().frame(height:20).background(Color.white.opacity(0.1))
                hudItem("VELOCITY", String(format:"%.2f", vm.velocity), .cyan)
                Divider().frame(height:20).background(Color.white.opacity(0.1))
                hudItem("THRUST", String(format:"%.0f%%", vm.thrust*100), .orange)
                Divider().frame(height:20).background(Color.white.opacity(0.1))
                hudItem("ALT", String(format:"%.1fm", vm.altitude), .green)
                Spacer()
                // Idle button
                Button { vm.idle() } label: {
                    Text("IDLE")
                        .font(.system(size:9,weight:.bold,design:.monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal,12).padding(.vertical,5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius:5))
                        .overlay(RoundedRectangle(cornerRadius:5)
                            .stroke(Color.white.opacity(0.15),lineWidth:0.6))
                }
                .padding(.trailing,14)
            }
            .padding(.vertical,6).padding(.leading,14)
            .background(.ultraThinMaterial)
            .overlay(Rectangle().frame(height:0.5)
                .foregroundColor(.cyan.opacity(0.15)), alignment:.top)

            // Status bar
            HStack(spacing:16) {
                statusItem("AIRCRAFT", vm.adsbActive ? "\(vm.aircraftCount)" : "ERR",
                           vm.adsbActive ? .orange : .red)
                statusItem("ORBITAL", vm.orbitalActive ? "\(vm.satelliteCount)" : "ERR",
                           vm.orbitalActive ? .purple : .red)
                statusItem("RANGE", "\(vm.rangeNm)nm", .cyan)
                Spacer()
                statusItem("SRC", "ADS-B", .orange)
            }
            .font(.system(size:8, design:.monospaced))
            .padding(.horizontal,14).padding(.vertical,4)
            .background(Color.black.opacity(0.6))
        }
    }

    private func hudItem(_ label:String,_ value:String,_ color:Color) -> some View {
        VStack(spacing:1) {
            Text(label).font(.system(size:6,design:.monospaced)).foregroundColor(.white.opacity(0.35))
            Text(value).font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundColor(color)
        }.padding(.horizontal,10)
    }

    private func statusItem(_ label:String,_ value:String,_ color:Color) -> some View {
        HStack(spacing:4) {
            Circle().fill(color).frame(width:4,height:4)
            Text(label).foregroundColor(.white.opacity(0.35))
            Text(value).foregroundColor(color)
        }.font(.system(size:8,design:.monospaced))
    }
}

// MARK: — Joystick
struct MantisJoystick: View {
    @Binding var x: Float; @Binding var y: Float
    @State private var offset: CGSize = .zero
    private let maxRadius: CGFloat = 45

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.05))
                .overlay(Circle().stroke(Color.cyan.opacity(0.3), lineWidth:1.5))
            Circle().fill(Color.cyan.opacity(0.15))
                .frame(width:44,height:44)
                .overlay(Circle().stroke(Color.cyan.opacity(0.5), lineWidth:1))
                .offset(offset)
        }
        .gesture(DragGesture(minimumDistance:0)
            .onChanged { val in
                let dx = max(-maxRadius, min(maxRadius, val.translation.width))
                let dy = max(-maxRadius, min(maxRadius, val.translation.height))
                offset = CGSize(width:dx, height:dy)
                x = Float(dx / maxRadius)
                y = Float(dy / maxRadius)
            }
            .onEnded { _ in
                withAnimation(.spring(response:0.2)) { offset = .zero }
                x = 0; y = 0
            }
        )
    }
}

// MARK: — Thrust Slider
struct MantisThrustSlider: View {
    @Binding var value: Float

    var body: some View {
        GeometryReader { g in
            ZStack(alignment:.bottom) {
                RoundedRectangle(cornerRadius:8)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius:8)
                        .stroke(Color.orange.opacity(0.3), lineWidth:1))
                // Fill
                RoundedRectangle(cornerRadius:8)
                    .fill(LinearGradient(
                        colors:[.orange,.red],
                        startPoint:.bottom, endPoint:.top))
                    .frame(height: g.size.height * CGFloat(value))
                // Knob
                Circle()
                    .fill(Color.orange)
                    .frame(width:28,height:28)
                    .shadow(color:.orange.opacity(0.5), radius:6)
                    .offset(y: -(g.size.height * CGFloat(value) - 14))
            }
            .gesture(DragGesture(minimumDistance:0)
                .onChanged { val in
                    let pct = 1.0 - Float(val.location.y / g.size.height)
                    value = max(0, min(1, pct))
                }
            )
        }
    }
}

// MARK: — Model Picker Sheet
struct MantisModelPickerSheet: View {
    @ObservedObject var vm: MantisViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color(red:0.03,green:0.05,blue:0.10).ignoresSafeArea()
            VStack(spacing:20) {
                Capsule().fill(Color.white.opacity(0.2))
                    .frame(width:40,height:4).padding(.top,14)
                Text("NAVIGATION MODEL")
                    .font(.custom("Orbitron-Bold",size:16))
                    .foregroundColor(.cyan).tracking(2)

                // Preloaded models
                VStack(spacing:10) {
                    modelBtn("Load | ArielNPU",    color:.purple) { vm.loadPreset(.ariel); dismiss() }
                    modelBtn("Load | Arrow",       color:.cyan)   { vm.loadPreset(.arrow); dismiss() }
                    modelBtn("Load | Autumn & MG", color:.orange) { vm.loadPreset(.autumn); dismiss() }
                }
                .padding(.horizontal,24)

                // Custom GLB
                Text("or upload a .glb / .gltf file")
                    .font(.system(size:11,design:.monospaced))
                    .foregroundColor(.white.opacity(0.35))

                Button {
                    vm.showFilePicker = true
                    dismiss()
                } label: {
                    Label("Choose File", systemImage:"folder")
                        .font(.system(size:13,weight:.semibold,design:.monospaced))
                        .foregroundColor(.black)
                        .frame(maxWidth:.infinity).frame(height:44)
                        .background(Color.cyan)
                        .clipShape(RoundedRectangle(cornerRadius:10))
                }
                .padding(.horizontal,24)

                Toggle("Flip Model 180° on Load", isOn: $vm.flipOnLoad)
                    .font(.system(size:11,design:.monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal,24)
                    .toggleStyle(SwitchToggleStyle(tint:.cyan))

                Spacer()
            }
        }
        .presentationDetents([.medium])
    }

    private func modelBtn(_ title:String, color:Color, action:@escaping()->Void) -> some View {
        Button(action:action) {
            Text(title)
                .font(.system(size:12,weight:.semibold,design:.monospaced))
                .foregroundColor(color)
                .frame(maxWidth:.infinity).frame(height:44)
                .background(color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10)
                    .stroke(color.opacity(0.3),lineWidth:0.8))
        }
    }
}

// MARK: — SceneKit View
struct MantisSceneView: UIViewRepresentable {
    @ObservedObject var vm: MantisViewModel

    func makeUIView(context:Context) -> SCNView {
        let v = SCNView()
        v.scene = vm.scene
        v.allowsCameraControl = false
        v.backgroundColor = UIColor(red:0.01,green:0.02,blue:0.05,alpha:1)
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ v:SCNView, context:Context) {
        if v.scene !== vm.scene { v.scene = vm.scene }
    }

    func makeCoordinator() -> Coordinator { Coordinator(vm:vm) }

    class Coordinator: NSObject, SCNSceneRendererDelegate {
        let vm: MantisViewModel
        init(vm:MantisViewModel) { self.vm=vm }
        func renderer(_ renderer:SCNSceneRenderer, updateAtTime time:TimeInterval) {
            DispatchQueue.main.async { self.vm.updatePhysics() }
        }
    }
}
