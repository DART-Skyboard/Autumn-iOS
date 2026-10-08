import SwiftUI
import AVFoundation
import AVKit
import ImageIO

/// Looping, muted, aspect-fill art video (the user's own file). Sits behind the scrim.
/// VOID overlay hides it; CLEAR still plays and loops.
struct ThemeVideoBackground: UIViewRepresentable {
    let fileURL: URL?
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
        uiView.apply(fileURL: fileURL, videoOn: videoOn)
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

        func apply(fileURL: URL?, videoOn: Bool) {
            Self.ensureAmbientSession()
            if !videoOn || fileURL == nil {
                alpha = 0
                isHidden = true
                queue?.pause()
                return
            }
            isHidden = false
            alpha = 1
            let url = fileURL!
            let name = url.path
            if name == currentName {
                ensurePlaying()
                return
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
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
    }
}

/// Still-image art (PNG / JPEG / HEIC / TGA / BMP / GIF / TIFF...), downsampled so large files stay light.
struct ArtImageBackground: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            let loaded: UIImage? = await Task.detached(priority: .userInitiated) {
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2800
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
                return UIImage(cgImage: cg)
            }.value
            image = loaded
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
