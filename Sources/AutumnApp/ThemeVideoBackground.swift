import SwiftUI
import AVFoundation
import AVKit

/// Looping, muted, aspect-fill theme video. Sits behind the scrim (web #backdrop-video, z-index:-2).
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

        func apply(resourceName: String?, videoOn: Bool) {
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
                if queue?.rate == 0 { queue?.play() }
                return
            }
            currentName = name
            guard let url = Self.locate(name) else {
                queue?.pause()
                return
            }
            let item = AVPlayerItem(url: url)
            let q = AVQueuePlayer()
            q.isMuted = true
            q.actionAtItemEnd = .none
            looper = AVPlayerLooper(player: q, templateItem: item)
            queue = q
            playerLayer.player = q
            q.play()
        }

        func teardown() {
            queue?.pause()
            looper = nil
            queue = nil
            playerLayer.player = nil
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
