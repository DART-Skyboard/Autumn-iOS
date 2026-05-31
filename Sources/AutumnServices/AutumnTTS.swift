import AVFoundation
import LEATRCore

/// AutumnTTS — Text-to-speech for Autumn iOS
/// Uses Apple's neural AVSpeechSynthesizer with best available voice
/// Falls back gracefully across iOS versions
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
        utterance.rate       = rateFor(emotion: emotion)
        utterance.pitchMultiplier = pitchFor(emotion: emotion)
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
                let traits: AVSpeechSynthesisVoiceTraits = voice.voiceTraits
                return traits.contains(.isPersonalVoice)
            }
            if let premium { return premium }
            let enhanced = voices.first { voice in
                let traits: AVSpeechSynthesisVoiceTraits = voice.voiceTraits
                return !traits.contains(.isNoveltyVoice)
            }
            if let enhanced { return enhanced }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private func rateFor(emotion: EmotionType) -> Float {
        switch emotion {
        case .excited, .inspired:  return 0.52
        case .calm, .thoughtful:   return 0.44
        case .concerned, .worried: return 0.46
        default:                   return 0.48
        }
    }

    private func pitchFor(emotion: EmotionType) -> Float {
        switch emotion {
        case .excited, .inspired:  return 1.08
        case .calm, .thoughtful:   return 0.95
        default:                   return 1.0
        }
    }

    // MARK: - Delegate
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance) { onSpeakingStart?() }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance) { onSpeakingFinish?() }
}
