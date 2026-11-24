import AVFoundation
import UIKit

public extension Notification.Name {
    /// Posted when the app backgrounds: every audio client stops its engine / tap / speech.
    static let autumnAudioShouldStop = Notification.Name("autumnAudioShouldStop")
}

/// AutumnAudioSession — the ONLY place the app touches AVAudioSession.
///
/// Rules (fixes background YouTube / Apple Music / Spotify being ducked ~50% on launch):
///  1. Nothing configures or activates the session on launch, init or onAppear.
///  2. Idle = `.ambient` + `.mixWithOthers`, never activated by us.
///  3. A client calls `begin(_:)` only inside a user-initiated start (record / speak / tone);
///     category is `.playAndRecord` or `.playback`, always `.mixWithOthers`, never `.duckOthers`.
///  4. `end(_:)` on stop / disappear / background: deactivate with
///     `.notifyOthersOnDeactivation` and reset to `.ambient` + `.mixWithOthers`.
public enum AutumnAudioSession {
    public enum Client: String {
        case speech      // AutumnTTS (AVSpeechSynthesizer)
        case dictation   // SFSpeechRecognizer mic tap (ChatViewModel)
        case shazam      // ShazamKit mic tap
        case tone        // N.A.T.E tone generator (AVAudioEngine output)
    }

    private static let lock = NSLock()
    private static var active = Set<Client>()
    private static var observer: NSObjectProtocol?

    /// Idle configuration. Sets the category only — does NOT activate the session.
    public static func configureIdle() {
        let s = AVAudioSession.sharedInstance()
        if s.category == .ambient && s.categoryOptions.contains(.mixWithOthers) { return }
        try? s.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    /// Call once at launch. Only registers a background observer; no session work.
    public static func installLifecycleObserver() {
        lock.lock(); defer { lock.unlock() }
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .autumnAudioShouldStop, object: nil)
            endAll()
        }
    }

    public static var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return active.contains(.dictation) || active.contains(.shazam)
    }

    /// Start of a user action that needs audio. Returns false if the session could not activate.
    @discardableResult
    public static func begin(_ client: Client) -> Bool {
        lock.lock()
        active.insert(client)
        let snapshot = active
        lock.unlock()
        return apply(snapshot)
    }

    /// End of a user action. When nothing else is using audio, deactivate and go idle.
    public static func end(_ client: Client) {
        lock.lock()
        let wasActive = active.remove(client) != nil
        let snapshot = active
        lock.unlock()
        guard wasActive else { return }
        if snapshot.isEmpty {
            deactivate()
        } else {
            _ = apply(snapshot)   // e.g. dictation ended while TTS still speaking → back to .playback
        }
    }

    public static func endAll() {
        lock.lock()
        let had = !active.isEmpty
        active.removeAll()
        lock.unlock()
        if had { deactivate() } else { configureIdle() }
    }

    private static func apply(_ clients: Set<Client>) -> Bool {
        let s = AVAudioSession.sharedInstance()
        do {
            if clients.contains(.dictation) || clients.contains(.shazam) {
                // Mic needed. Mix (do not duck) so the user's music keeps its level.
                try s.setCategory(.playAndRecord, mode: .default,
                                  options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
            } else if clients == [.speech] {
                try s.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            } else {
                try s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try s.setActive(true, options: [])
            return true
        } catch {
            print("[Autumn] audio session begin error: \(error)")
            return false
        }
    }

    private static func deactivate() {
        let s = AVAudioSession.sharedInstance()
        try? s.setActive(false, options: [.notifyOthersOnDeactivation])
        try? s.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }
}
