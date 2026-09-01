import SwiftUI
import AVFoundation
import LEATRCore
import AutumnServices

/// N.A.T.E — Neutral Audio Tonal Exertion Engine (nate.html).
/// Oscillator + waveform + analysis + APPLY TO AUTUMN. Native, not WKWebView.
struct NateStudioView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @StateObject private var vm = NateViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("NEUTRAL AUDIO TONAL EXERTION ENGINE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#a78bfa"))
                Spacer()
                Text(vm.applied ? "NATE ACTIVE" : "BASELINE ACTIVE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(vm.applied ? Color(hex: "#00ff88") : .white.opacity(0.45))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            NateWaveform(phase: vm.phase, amp: vm.playing ? 1 : 0.25, warmth: vm.params.warmth)
                .frame(height: 72)
                .background(Color.black.opacity(0.5))
            NateSpectrum(f0: vm.f0, f1: vm.f1, f2: vm.f2)
                .frame(height: 48)
                .background(Color.black.opacity(0.4))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    nateSlider("PITCH", $vm.params.pitch, 0.4...2.0, "%.2f")
                    nateSlider("SPEED", $vm.params.speed, 0.4...2.5, "%.2f")
                    nateSlider("FORMANT", $vm.params.formant, 0.5...2.0, "%.2f")
                    nateSlider("RESONANCE", $vm.params.resonance, 0...1, "%.2f")
                    nateSlider("WARMTH", $vm.params.warmth, 0...1, "%.2f")
                    nateSlider("CLARITY", $vm.params.clarity, 0...1, "%.2f")
                    nateSlider("VIBRATO", $vm.params.vibrato, 0...0.5, "%.2f")

                    HStack(spacing: 8) {
                        nateBtn(vm.playing ? "■ STOP" : "▶ PLAY SELECTED") { vm.togglePlay() }
                        nateBtn("◈ ANALYZE") { vm.analyze() }
                        nateBtn("▶ SPEAK") { vm.speak() }
                    }
                    HStack(spacing: 8) {
                        nateBtn("⊕ SIGMA BLEND") { vm.sigmaBlend() }
                        nateBtn("▶ APPLY TO AUTUMN") { vm.applyToAutumn() }
                        nateBtn("↺ REVERT") { vm.revert() }
                    }

                    Text("PRESETS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#a78bfa").opacity(0.7))
                    HStack {
                        ForEach(NateViewModel.presets, id: \.name) { p in
                            Button(p.name) { vm.applyPreset(p) }
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(Color(hex: "#a78bfa").opacity(0.12))
                                .cornerRadius(4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("TONAL ANALYSIS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#a78bfa").opacity(0.7))
                        ana("F0", "\(Int(vm.f0)) Hz")
                        ana("F1", "\(Int(vm.f1)) Hz")
                        ana("F2", "\(Int(vm.f2)) Hz")
                        ana("SIGMA", String(format: "%.3f", vm.sigma))
                        ana("GEO", String(format: "%.2f", vm.geo))
                        ana("MAR", String(format: "%.2f", vm.mar))
                        ana("AERO", String(format: "%.2f", vm.aero))
                        ana("EMO", vm.emoTone)
                    }

                    TextField("voice test", text: $vm.testText)
                        .textFieldStyle(.plain).foregroundColor(.white)
                        .padding(8).background(Color.white.opacity(0.06)).cornerRadius(6)

                    Text(vm.log)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                }
                .padding(14)
            }
        }
        .onDisappear { vm.stop() }
    }

    private func nateSlider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                Spacer()
                Text(String(format: fmt, value.wrappedValue))
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: "#a78bfa"))
            }
            Slider(value: value, in: range).tint(Color(hex: "#a78bfa"))
                .onChange(of: value.wrappedValue) { _ in vm.syncTone() }
        }
    }

    private func nateBtn(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(t, action: a)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(Color(hex: "#a78bfa"))
            .padding(.horizontal, 8).padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#a78bfa").opacity(0.35), lineWidth: 1))
    }

    private func ana(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.4)).frame(width: 48, alignment: .leading)
            Text(v).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.85))
        }
    }
}

struct NateWaveform: View {
    var phase: Double
    var amp: Double
    var warmth: Double
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let n = Int(size.width)
            for i in 0..<n {
                let x = CGFloat(i)
                let t = Double(i) / Double(max(n, 1)) * .pi * 4 + phase
                let y = sin(t) * amp * 0.7 + sin(t * 2) * warmth * 0.2
                let pt = CGPoint(x: x, y: size.height / 2 + CGFloat(y) * size.height / 2)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(Color(hex: "#a78bfa")), lineWidth: 1.2)
        }
    }
}

struct NateSpectrum: View {
    var f0: Double; var f1: Double; var f2: Double
    var body: some View {
        Canvas { ctx, size in
            let peaks = [f0, f1, f2]
            for (i, f) in peaks.enumerated() {
                let x = CGFloat(min(f / 2000.0, 1)) * size.width
                var bar = Path(CGRect(x: x, y: 6, width: 4, height: size.height - 12))
                let col = [Color(hex: "#a78bfa"), Color(hex: "#00e5ff"), Color(hex: "#ffb347")][i]
                ctx.fill(bar, with: .color(col.opacity(0.8)))
            }
        }
    }
}

@MainActor
final class NateViewModel: ObservableObject {
    struct Preset { let name: String; let params: NateVoiceParams }
    static let presets: [Preset] = [
        Preset(name: "HEART", params: NateVoiceParams(pitch: 1.05, speed: 1.0, formant: 1.1, resonance: 0.4, warmth: 0.7, clarity: 0.55, vibrato: 0.1, applied: false)),
        Preset(name: "DEEP", params: NateVoiceParams(pitch: 0.72, speed: 0.9, formant: 0.8, resonance: 0.55, warmth: 0.8, clarity: 0.4, vibrato: 0.05, applied: false)),
        Preset(name: "BRIGHT", params: NateVoiceParams(pitch: 1.25, speed: 1.1, formant: 1.4, resonance: 0.25, warmth: 0.3, clarity: 0.85, vibrato: 0.04, applied: false)),
        Preset(name: "WHISPER", params: NateVoiceParams(pitch: 1.15, speed: 0.85, formant: 1.2, resonance: 0.15, warmth: 0.4, clarity: 0.7, vibrato: 0.12, applied: false))
    ]

    @Published var params = NateVoiceParams.baseline
    @Published var playing = false
    @Published var applied = false
    @Published var phase: Double = 0
    @Published var testText = "Hello. I am Autumn."
    @Published var log = "NATE ready."
    @Published var f0: Double = 220
    @Published var f1: Double = 660
    @Published var f2: Double = 1320
    @Published var sigma: Double = 0
    @Published var geo: Double = 0
    @Published var mar: Double = 0
    @Published var aero: Double = 0
    @Published var emoTone = "NEUTRAL / CONCERNED"

    private var engine: AVAudioEngine?
    private var src: AVAudioSourceNode?
    private var timer: Timer?
    private var blend: [NateVoiceParams] = []

    init() {
        let loaded = NateVoiceParams.load()
        params = loaded
        applied = loaded.applied
        analyze()
    }

    func togglePlay() {
        if playing { stop() } else { play() }
    }

    func play() {
        stop()
        let engine = AVAudioEngine()
        var phase: Double = 0
        var lfo: Double = 0
        let sr = 44100.0
        let node = AVAudioSourceNode { _, _, frameCount, abl in
            let p = self.params
            let buf = UnsafeMutableAudioBufferListPointer(abl)
            for f in 0..<Int(frameCount) {
                lfo += 2 * Double.pi * 5.0 / sr
                let vib = 1.0 + p.vibrato * sin(lfo)
                let freq = 220.0 * p.pitch * vib
                phase += 2 * Double.pi * freq / sr
                if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                let s1 = sin(phase)
                let s2 = sin(phase * 2) * p.warmth * 0.35
                let s3 = sin(phase * (2.0 + p.formant)) * p.resonance * 0.25
                var sample = (s1 + s2 + s3) * (0.22 + 0.15 * p.clarity)
                sample = max(-1, min(1, sample))
                let v = Float(sample)
                for b in buf {
                    let ptr = b.mData?.assumingMemoryBound(to: Float.self)
                    ptr?[f] = v
                }
            }
            return noErr
        }
        let fmt = engine.outputNode.inputFormat(forBus: 0)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            self.engine = engine
            self.src = node
            playing = true
            log = "PLAY \(Int(220 * params.pitch)) Hz"
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.phase += 0.18
                }
            }
        } catch {
            log = "Audio error: \(error.localizedDescription)"
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        engine?.stop()
        engine = nil
        src = nil
        playing = false
    }

    func syncTone() { analyze() }

    func analyze() {
        f0 = 220 * params.pitch
        f1 = max(400, f0 * 3 * params.formant)
        f2 = f1 + 200 + 400 * params.clarity
        sigma = (f1 * params.formant) / 1200 + params.pitch * 0.5
        geo = max(0, 1 - abs(f0 - 150) / 200)
        mar = max(0, 1 - abs(f0 - 200) / 200)
        aero = max(0, 1 - abs(f0 - 260) / 200)
        let ratio = f1 / max(f0, 1)
        emoTone = ratio > 6 ? "SPIRITUAL / APATHETIC"
            : ratio > 4 ? "EMPATHETIC / GUIDING"
            : ratio > 3 ? "NEUTRAL / CONCERNED"
            : ratio > 2 ? "DETERMINED / HAPPY" : "GROUNDED / DEEP"
        log = String(format: "ANALYZE F0 %.0f  σ %.3f  %@", f0, sigma, emoTone)
    }

    func speak() {
        analyze()
        var p = params
        p.applied = true
        p.save()
        AutumnTTS.shared.speak(testText, emotion: .spiritual)
        log = "SPEAK via AutumnTTS with NATE graph"
    }

    func applyToAutumn() {
        var p = params
        p.applied = true
        p.save()
        applied = true
        log = String(format: "Voice applied: pitch=%.2f speed=%.2f formant=%.2f", p.pitch, p.speed, p.formant)
    }

    func revert() {
        params = .baseline
        var p = params
        p.applied = false
        p.save()
        applied = false
        analyze()
        log = "Reverted to Autumn baseline voice"
    }

    func applyPreset(_ p: Preset) {
        params = p.params
        analyze()
        log = "PRESET \(p.name)"
    }

    func sigmaBlend() {
        blend.append(params)
        guard blend.count >= 2 else {
            log = "Select at least 2 samples for sigma blend — preset then ⊕ again"
            return
        }
        let n = Double(blend.count)
        params.pitch = blend.map(\.pitch).reduce(0, +) / n
        params.speed = blend.map(\.speed).reduce(0, +) / n
        params.formant = blend.map(\.formant).reduce(0, +) / n
        params.resonance = blend.map(\.resonance).reduce(0, +) / n
        params.warmth = blend.map(\.warmth).reduce(0, +) / n
        params.clarity = blend.map(\.clarity).reduce(0, +) / n
        params.vibrato = blend.map(\.vibrato).reduce(0, +) / n
        analyze()
        log = "Sigma blend of \(blend.count) samples"
    }
}
