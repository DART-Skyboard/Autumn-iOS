import SwiftUI
import AVFoundation
import AVKit

/// Looping, muted, aspect-fill theme video. Sits behind the scrim (web #backdrop-video:
/// loop muted autoplay playsinline). VOID overlay hides it; CLEAR still plays and loops.
struct ThemeVideoBackground: UIViewRepresentable {
    let resourceName: String?
    var videoOn: Bool

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.playerLayer.videoGravity = .resizeAspectFill
        v.playerLayer.backgroundColor = UIColor.clear.cgColor
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.apply(resourceName: resourceName, videoOn: videoOn)
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.teardown()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        private var looper: AVPlayerLooper?
        private var queue: AVQueuePlayer?
        private var currentName: String?
        private var endObs: NSObjectProtocol?
        private var activeObs: NSObjectProtocol?

        func apply(resourceName: String?, videoOn: Bool) {
            Self.ensureAmbientSession()
            if !videoOn || resourceName == nil {
                alpha = 0
                isHidden = true
                queue?.pause()
                return
            }
            isHidden = false
            alpha = 1
            let name = resourceName!
            if name == currentName {
                ensurePlaying()
                return
            }
            guard let url = Self.locate(name) else {
                teardown()
                return
            }
            startLooping(url: url, name: name)
        }

        private func startLooping(url: URL, name: String) {
            teardown()
            currentName = name
            let item = AVPlayerItem(url: url)
            let q = AVQueuePlayer()
            q.isMuted = true
            q.volume = 0
            q.actionAtItemEnd = .none
            q.automaticallyWaitsToMinimizeStalling = true
            q.allowsExternalPlayback = false
            q.preventsDisplaySleepDuringVideoPlayback = false
            // AVPlayerLooper = web `loop`. Keep it retained for the life of the clip.
            looper = AVPlayerLooper(player: q, templateItem: item)
            queue = q
            playerLayer.player = q
            // Belt-and-suspenders: if looper ever drops a cycle, seek + play.
            endObs = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self, let ended = note.object as? AVPlayerItem else { return }
                guard self.queue?.items().contains(ended) == true || self.queue?.currentItem == ended else { return }
                self.queue?.seek(to: .zero)
                self.queue?.play()
            }
            activeObs = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.ensurePlaying()
            }
            q.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.ensurePlaying()
            }
        }

        private func ensurePlaying() {
            guard !isHidden else { return }
            queue?.isMuted = true
            queue?.volume = 0
            if queue?.rate == 0 { queue?.play() }
        }

        func teardown() {
            if let endObs { NotificationCenter.default.removeObserver(endObs) }
            if let activeObs { NotificationCenter.default.removeObserver(activeObs) }
            endObs = nil
            activeObs = nil
            queue?.pause()
            looper?.disableLooping()
            looper = nil
            queue = nil
            playerLayer.player = nil
            currentName = nil
        }

        /// Don't steal the mic session. Muted video is ambient so TTS/voice still work.
        private static func ensureAmbientSession() {
            let s = AVAudioSession.sharedInstance()
            if s.category == .playAndRecord { return }
            try? s.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? s.setActive(true, options: [])
        }

        private static func locate(_ name: String) -> URL? {
            let bundle = Bundle.main
            if let u = bundle.url(forResource: name, withExtension: "mp4") { return u }
            if let u = bundle.url(forResource: name, withExtension: "mp4", subdirectory: "Themes") { return u }
            if let u = bundle.url(forResource: name, withExtension: "mp4", subdirectory: "Resources/Themes") { return u }
            if let u = bundle.url(forResource: name, withExtension: "mp4", subdirectory: "Resources") { return u }
            return nil
        }
    }
}

/// VisualEffect blur that only covers the video (not chrome).
struct VideoBlur: UIViewRepresentable {
    var radius: CGFloat
    func makeUIView(context: Context) -> UIVisualEffectView {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.alpha = min(1, radius / 20.0)
        uiView.isHidden = radius <= 0
    }
}
