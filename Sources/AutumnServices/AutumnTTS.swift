import AVFoundation
import LEATRCore

// MARK: — Autumn TTS
// Uses AVSpeechSynthesizer with Personal Voice when available
// Emotion-keyed rate/pitch matching the Kokoro-82M web behavior

public actor AutumnTTS {

    public static let shared = AutumnTTS()

    private let synthesizer = AVSpeechSynthesizer()
    private var personalVoice: AVSpeechSynthesisVoice?

    public func prepare() async {
        // Request Personal Voice authorization (iOS 17+)
        if #available(iOS 17.0, *) {
            let status = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
            if status == .authorized {
                personalVoice = AVSpeechSynthesisVoice.speechVoices()
                    .first(where: { $0.voiceTraits.contains(.isPersonalVoice) })
            }
        }
    }

    public func speak(_ text: String, emotion: EmotionType) async {
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)

        // Emotion-keyed prosody
        switch emotion {
        case .excited, .happy:
            utterance.rate = 0.55; utterance.pitchMultiplier = 1.15
        case .angry, .determined:
            utterance.rate = 0.52; utterance.pitchMultiplier = 0.92
        case .sad, .worried, .concerned:
            utterance.rate = 0.44; utterance.pitchMultiplier = 0.88
        case .inspiring, .guiding:
            utterance.rate = 0.50; utterance.pitchMultiplier = 1.05
        default:
            utterance.rate = 0.50; utterance.pitchMultiplier = 1.0
        }

        utterance.volume = 0.9

        // Prefer Personal Voice → Enhanced → Premium → any English
        if let personal = personalVoice {
            utterance.voice = personal
        } else {
            let voices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix("en") }
                .sorted { lhs, rhs in
                    let lScore = lhs.voiceTraits.contains(.isNoveltyVoice) ? 0 :
                                 (lhs.quality == .enhanced || lhs.quality == .premium) ? 2 : 1
                    let rScore = rhs.voiceTraits.contains(.isNoveltyVoice) ? 0 :
                                 (rhs.quality == .enhanced || rhs.quality == .premium) ? 2 : 1
                    return lScore > rScore
                }
            utterance.voice = voices.first
        }

        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .word)
    }
}