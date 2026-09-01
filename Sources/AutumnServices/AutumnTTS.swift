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

public final class AutumnTTS: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    public static let shared = AutumnTTS()
    private let synthesizer  = AVSpeechSynthesizer()
    public var onSpeakingStart:  (() -> Void)?
    public var onSpeakingFinish: (() -> Void)?
    public var isSpeaking: Bool { synthesizer.isSpeaking }

    public override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
    }

    // MARK: - Audio Session
    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Speak
    public func speak(_ text: String, emotion: EmotionType) {
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance        = AVSpeechUtterance(string: text)
        utterance.voice      = bestVoice(for: emotion)
        let nate = NateVoiceParams.load()
        if nate.applied {
            let baseRate = rateFor(emotion: emotion)
            utterance.rate = Float(min(0.6, max(0.3, Double(baseRate) * nate.speed)))
            utterance.pitchMultiplier = Float(min(2.0, max(0.5, Double(pitchFor(emotion: emotion)) * nate.pitch * (0.85 + 0.15 * nate.formant))))
        } else {
            utterance.rate       = rateFor(emotion: emotion)
            utterance.pitchMultiplier = pitchFor(emotion: emotion)
        }
        utterance.volume     = 1.0
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .word)
    }

    // MARK: - Voice Selection
    /// Selects the best available neural voice for the given emotion
    private func bestVoice(for emotion: EmotionType) -> AVSpeechSynthesisVoice? {
        // Preferred neural voices — Autumn uses Allison/Samantha style
        let preferredIDs = [
            "com.apple.voice.premium.en-US.Zoe",      // iOS 17+ premium
            "com.apple.voice.enhanced.en-US.Zoe",     // iOS 16 enhanced
            "com.apple.voice.premium.en-US.Nicky",
            "com.apple.voice.enhanced.en-US.Nicky",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.voice.enhanced.en-US.Allison",
        ]
        for id in preferredIDs {
            if let voice = AVSpeechSynthesisVoice(identifier: id) {
                return voice
            }
        }
        // Fallback to any enhanced English voice
        if #available(iOS 17.0, *) {
            let voices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix("en") }
            let premium = voices.first { voice in
                let traits = voice.voiceTraits
                return traits.contains(.isPersonalVoice)
            }
            if let premium { return premium }
            let enhanced = voices.first { voice in
                let traits = voice.voiceTraits
                return !traits.contains(.isNoveltyVoice)
            }
            if let enhanced { return enhanced }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
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
