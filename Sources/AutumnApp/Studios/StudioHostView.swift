import SwiftUI
import AutumnServices
import LEATRCore
import SceneKit
import MapKit

/// Full-screen native studios mapped from standalone web HTML/JS — not WKWebView of the site.
struct StudioHostView: View {
    let kind: AppNavigation.StudioKind
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var chatVM: ChatViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            themeVM.chrome.base.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(kind.title)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(themeVM.chrome.accent)
                    Spacer()
                    Button("✕ CLOSE") { appNav.studio = nil }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(themeVM.chrome.surface.opacity(0.95))
                Group {
                    switch kind {
                    case .arcForge: ArcForgeStudioView()
                    case .worldStudio: WorldStudioView()
                    case .nate: NateStudioView()
                    case .movement: MovementConjectureView()
                    case .help: HelpStudioView()
                    case .privacy: PrivacyStudioView()
                    case .arcLake: ArcLakePanel()
                    case .arcEdge: ArcEdgePanel()
                    case .calc: CalcPanel()
                    case .emoMap: EmoMapPanel()
                    }
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct ArcForgeStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var net = "AND"
    @State private var a = false
    @State private var b = false
    var out: Bool {
        switch net {
        case "OR": return a || b
        case "XOR": return a != b
        case "NAND": return !(a && b)
        default: return a && b
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RADICAL DEEPSCALE EDA")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(themeVM.chrome.accent.opacity(0.5))
            Text("Gate sandbox — native first pass of arc-forge.html. Drop a net, toggle inputs, read the bus.")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.75))
            Picker("NET", selection: $net) {
                ForEach(["AND","OR","XOR","NAND"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented)
            HStack(spacing: 16) {
                Toggle("A", isOn: $a).toggleStyle(.switch)
                Toggle("B", isOn: $b).toggleStyle(.switch)
                Spacer()
                Text(out ? "HIGH" : "LOW")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(out ? Color(hex: "#00ff88") : Color(hex: "#ff4466"))
            }
            Text("Y = A \(net) B → \(out ? 1 : 0)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(themeVM.chrome.accent)
            Spacer()
        }.padding(16)
    }
}

struct WorldStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var seed = "autumn"
    @State private var altitude: Double = 120
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DART MEADOW WORLD STUDIO")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(themeVM.chrome.accent.opacity(0.5))
            TextField("seed", text: $seed)
                .textFieldStyle(.plain).foregroundColor(.white)
                .padding(8).background(themeVM.chrome.surface).cornerRadius(6)
            Slider(value: $altitude, in: 0...400)
            Text(String(format: "ALT %.0f  ·  SEED %@", altitude, seed))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeVM.chrome.accent)
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#020a14"))
                VStack(spacing: 8) {
                    Text("VIEWPORT READY")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Text("GLB / space drop comes in a later pass. Controls and chrome run now.")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }
            }
            Spacer()
        }.padding(16)
    }
}

struct NateStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var freq: Double = 440
    @State private var running = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEUTRAL AUDIO TONAL EXERTION ENGINE")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(hex: "#a78bfa").opacity(0.7))
            Slider(value: $freq, in: 55...1760)
            Text(String(format: "%.1f Hz", freq))
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#a78bfa"))
            Button(running ? "STOP" : "TONE") {
                running.toggle()
                if running { AutumnTTS.shared.speak("Nate tone \(Int(freq)) hertz", emotion: .spiritual) }
                else { AutumnTTS.shared.stop() }
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(Color(hex: "#a78bfa"))
            Text("Native first pass of nate.html. Full oscillator graph is later; TTS + frequency HUD runs now.")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            Spacer()
        }.padding(16)
    }
}

struct MovementConjectureView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("MOVEMENT CONJECTURE EOD")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.5))
                Text("Arc Edge finite dynamics. DOC replaces pi. C = sqrt(d x DOC)^2 with DOC = \(LEATRIdentity.DOC).")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                Text(String(format: "Example d=10 -> C = %.4f", LEATRIdentity.arcEdgeCircumference(diameter: 10)))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent)
                Text("Native reading room for movement-conjecture.html. Identity math is live here.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }.padding(16)
        }
    }
}

struct HelpStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                help("CHAT", "Talk to Autumn. Grammar engine runs locally. Core Cognition frozen True. Reflex never loops.")
                help("THEME / SCRIM", "Cycle VOID DAY NIGHT STEALTH DEPARTURE ASH TREE ARIEL AUTO. Scrim FROST to VOID sits on the video, behind UI.")
                help("MIST", "Right rail. Solve the maze on the BRPN orb. Signals ride plasma splines to peers via GAS.")
                help("STAR", "Right rail. Spawns 3D Ash Star geometry on the orb and archives the thought.")
                help("SHARD", "Right rail. Design a textile, pick GitHub following, send along splines.")
                help("SYS", "Right rail. System broadcast. dartsolarpunk can compose; writes go through GAS ashwrite.")
                help("MANTIS / RADAR", "HUD tools. Flight sim (mn.html) and radar (mr.html) native views.")
                help("ARCLAKE", "HUD tools. Chemistry studio first pass — not a standalone App Store app.")
                help("ADMIN", "dartsolarpunk only. DATA / ASH / MESSAGES mailbox.")
            }.padding(16)
        }
    }
    private func help(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(themeVM.chrome.accent)
            Text(b).font(.system(size: 13)).foregroundColor(.white.opacity(0.75))
        }
    }
}

struct PrivacyStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Autumn stores conversation history locally. Journal writes go to leatr-ash through the GAS ashwrite proxy. No PAT is stored in the client. GitHub OAuth tokens live in Keychain only. Presence nodes are anonymized. Microphone is on only when you tap voice. Feedback is reviewed by Radical Deepscale LLC and is not public.")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                Text("Full policy: leatr.xyz/autumn-privacy.html")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent)
            }.padding(16)
        }
    }
}

struct MantisRadarView: View {
    @StateObject private var vm = MantisViewModel()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.009),
        span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
    )
    var body: some View {
        ZStack {
            Map(coordinateRegion: $region).ignoresSafeArea()
            VStack {
                HStack {
                    Text("MANTIS RADAR")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#00f5ff"))
                    Spacer()
                    Text("ADS-B \(vm.aircraftCount)  ORBIT \(vm.satelliteCount)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(12)
                .background(Color.black.opacity(0.55))
                Spacer()
                Text("Live ADS-B / TLE overlays share MantisViewModel. Map + counts run now.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "#00f5ff").opacity(0.7))
                    .padding(12)
                    .background(Color.black.opacity(0.55))
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}
