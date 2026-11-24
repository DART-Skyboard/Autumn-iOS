import Foundation
import ShazamKit
import AVFoundation

/// AutumnShazam — Audio recognition via ShazamKit
/// Wired into Autumn's mic button for music identification
@available(iOS 15.0, *)
public final class AutumnShazam: NSObject, SHSessionDelegate, Sendable {
    public static let shared = AutumnShazam()
    private let session   = SHSession()
    private let audioEngine = AVAudioEngine()
    public var onMatch:   ((SHMatchedMediaItem) -> Void)?
    public var onNoMatch: (() -> Void)?

    public override init() {
        super.init()
        session.delegate = self
        NotificationCenter.default.addObserver(
            forName: .autumnAudioShouldStop, object: nil, queue: .main
        ) { [weak self] _ in self?.stopListening() }
    }

    // MARK: - Listen
    public func startListening() throws {
        let inputNode   = audioEngine.inputNode
        let format      = inputNode.outputFormat(forBus: 0)
        let signature   = SHSignatureGenerator()
        AutumnAudioSession.begin(.shazam)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            try? signature.append(buffer, at: nil)
        }
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            AutumnAudioSession.end(.shazam)
            throw error
        }
        // Generate and match after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            let sig = signature.signature()
            self.session.match(sig)
            self.stopListening()
        }
    }

    public func stopListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        AutumnAudioSession.end(.shazam)
    }

    // MARK: - Delegate
    public func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        onMatch?(item)
    }

    public func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        onNoMatch?()
    }
}
