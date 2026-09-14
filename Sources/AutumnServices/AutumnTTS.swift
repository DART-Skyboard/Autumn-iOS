import AVFoundation
import LEATRCore

/// AutumnTTS — Text-to-speech for Autumn iOS
/// Uses Apple's neural AVSpeechSynthesizer with best available voice
/// Falls back gracefully across iOS versions

/// N.A.T.E voice graph applied to Autumn TTS (nate.html APPLY TO AUTUMN).
public struct NateVoiceParams: Codable, Sendable, Equatable {
    public var pitch: Double
    public var speed: Double
    public var formant: Double
    public var resonance: Double
    public var warmth: Double
    public var clarity: Double
    public var vibrato: Double
    public var applied: Bool

    public init(pitch: Double, speed: Double, formant: Double, resonance: Double,
                warmth: Double, clarity: Double, vibrato: Double, applied: Bool) {
        self.pitch = pitch
        self.speed = speed
        self.formant = formant
        self.resonance = resonance
        self.warmth = warmth
        self.clarity = clarity
        self.vibrato = vibrato
        self.applied = applied
    }

    public static let baseline = NateVoiceParams(
        pitch: 1.0, speed: 1.0, formant: 1.0, resonance: 0.3,
        warmth: 0.5, clarity: 0.6, vibrato: 0.08, applied: false
    )

    public static func load() -> NateVoiceParams {
        guard let data = UserDefaults.standard.data(forKey: "nate_voice_params_v1"),
              let p = try? JSONDecoder().decode(NateVoiceParams.self, from: data) else {
            return .baseline
        }
        return p
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "nate_voice_params_v1")
        }
    }
}

/// User-adjustable Autumn voice — persisted like theme (`_aut_theme`) into the vault.
public struct AutumnTTSPrefs: Codable, Equatable, Sendable {
    public var voiceIdentifier: String
    public var rate: Float
    public var pitch: Float

    public static let `default` = AutumnTTSPrefs(voiceIdentifier: "", rate: 0.47, pitch: 1.0)

    public init(voiceIdentifier: String, rate: Float, pitch: Float) {
        self.voiceIdentifier = voiceIdentifier
        self.rate = rate
        self.pitch = pitch
    }

    public static func load() -> AutumnTTSPrefs {
        var p = AutumnTTSPrefs.default
        if let id = UserDefaults.standard.string(forKey: AutumnSettingsSync.ttsVoiceKey) {
            p.voiceIdentifier = id
        }
        if UserDefaults.standard.object(forKey: AutumnSettingsSync.ttsRateKey) != nil {
            p.rate = UserDefaults.standard.float(forKey: AutumnSettingsSync.ttsRateKey)
        }
        if UserDefaults.standard.object(forKey: AutumnSettingsSync.ttsPitchKey) != nil {
            p.pitch = UserDefaults.standard.float(forKey: AutumnSettingsSync.ttsPitchKey)
        }
        return p
    }

    public func save() {
        UserDefaults.standard.set(voiceIdentifier, forKey: AutumnSettingsSync.ttsVoiceKey)
        UserDefaults.standard.set(rate, forKey: AutumnSettingsSync.ttsRateKey)
        UserDefaults.standard.set(pitch, forKey: AutumnSettingsSync.ttsPitchKey)
        Task { @MainActor in AutumnSettingsSync.noteLocalChange() }
    }
}

public struct AutumnTTSVoiceOption: Identifiable, Hashable, Sendable {
    public var id: String { identifier }
    public let identifier: String
    public let name: String
    public let quality: String
}

public final class AutumnTTS: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    public static let shared = AutumnTTS()
    private let synthesizer  = AVSpeechSynthesizer()
    public var onSpeakingStart:  (() -> Void)?
    public var onSpeakingFinish: (() -> Void)?
    public var isSpeaking: Bool { synthesizer.isSpeaking }

    public override init() {
        super.init()
        synthesizer.delegate = self
        // Do NOT activate AVAudioSession here — TF91 ducked other apps on launch
        // when AutumnTTS.shared was first touched at boot.
    }

    // MARK: - Audio Session (speak-time only)
    private func activateSpeechSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
    }

    // MARK: - Speak
    public func speak(_ text: String, emotion: EmotionType) {
        guard !text.isEmpty else { return }
        activateSpeechSession()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance        = AVSpeechUtterance(string: text)
        let prefs            = AutumnTTSPrefs.load()
        utterance.voice      = bestVoice(identifier: prefs.voiceIdentifier)
        let nate = NateVoiceParams.load()
        let baseRate = prefs.rate > 0 ? prefs.rate : rateFor(emotion: emotion)
        let basePitch = prefs.pitch > 0 ? prefs.pitch : pitchFor(emotion: emotion)
        if nate.applied {
            utterance.rate = Float(min(0.6, max(0.3, Double(baseRate) * nate.speed)))
            utterance.pitchMultiplier = Float(min(2.0, max(0.5, Double(basePitch) * nate.pitch * (0.85 + 0.15 * nate.formant))))
        } else {
            utterance.rate = min(0.58, max(0.32, baseRate))
            utterance.pitchMultiplier = min(2.0, max(0.5, basePitch))
        }
        utterance.volume     = 1.0
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .word)
    }

    // MARK: - Voice Selection
    /// Premium/enhanced neural English voices first (Zoe → Nicky → Samantha). User pick wins.
    public func bestVoice(identifier: String = "") -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty, let v = AVSpeechSynthesisVoice(identifier: identifier) {
            return v
        }
        let preferredIDs = [
            "com.apple.voice.premium.en-US.Zoe",
            "com.apple.voice.enhanced.en-US.Zoe",
            "com.apple.ttsbundle.siri_female_en-US_compact",
            "com.apple.voice.premium.en-US.Nicky",
            "com.apple.voice.enhanced.en-US.Nicky",
            "com.apple.voice.premium.en-US.Samantha",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.voice.enhanced.en-US.Allison",
        ]
        for id in preferredIDs {
            if let voice = AVSpeechSynthesisVoice(identifier: id) {
                return voice
            }
        }
        let ranked = Self.englishVoices().sorted { a, b in
            Self.qualityRank(a.quality) > Self.qualityRank(b.quality)
        }
        if let id = ranked.first?.identifier, let v = AVSpeechSynthesisVoice(identifier: id) {
            return v
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    public static func englishVoices() -> [AutumnTTSVoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
            .map { AutumnTTSVoiceOption(identifier: $0.identifier, name: $0.name, quality: qualityLabel($0)) }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return qualityRank(lhs.quality) > qualityRank(rhs.quality)
                }
                return lhs.name < rhs.name
            }
    }

    private static func qualityLabel(_ v: AVSpeechSynthesisVoice) -> String {
        if #available(iOS 17.0, *) {
            switch v.quality {
            case .premium: return "Premium"
            case .enhanced: return "Enhanced"
            default: return "Standard"
            }
        }
        return v.quality == .enhanced ? "Enhanced" : "Standard"
    }

    private static func qualityRank(_ label: String) -> Int {
        switch label {
        case "Premium": return 3
        case "Enhanced": return 2
        default: return 1
        }
    }

    private func rateFor(emotion: EmotionType) -> Float {
        switch emotion {
        case .excited:   return 0.52
        case .concerned: return 0.44
        default:         return 0.48
        }
    }

    private func pitchFor(emotion: EmotionType) -> Float {
        switch emotion {
        case .excited: return 1.08
        default:       return 1.0
        }
    }

    // MARK: - Delegate
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance) { onSpeakingStart?() }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance) { onSpeakingFinish?() }
}
