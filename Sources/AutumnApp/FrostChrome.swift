import SwiftUI
import UIKit

/// Web HUD glass: rgba(255,255,255,.05) + backdrop-filter blur(6–14px) saturate.
/// Not opaque chrome.surface slabs.
struct ModuleFrost: ViewModifier {
    var stroke: Color
    var corner: CGFloat = 8
    var fill: Double = 0.08
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(fill))
            .overlay(RoundedRectangle(cornerRadius: corner).stroke(stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

extension View {
    func moduleFrost(stroke: Color, corner: CGFloat = 8, fill: Double = 0.08) -> some View {
        modifier(ModuleFrost(stroke: stroke, corner: corner, fill: fill))
    }
}

/// Header logo — Image.scaledToFill in a circle clip. Frame first so the square PNG cannot leak.
struct AutumnLogoMark: View {
    var size: CGFloat = 28
    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay(
                Image("AutumnLogo")
                    .resizable()
                    .scaledToFill()
            )
            .clipped()
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.6))
            .contentShape(Circle())
    }
}

/// Average color from a GitHub avatar for profile-card frost tint.
@MainActor
final class AvatarTintSampler: ObservableObject {
    @Published var tint = Color(red: 0.07, green: 0.08, blue: 0.10)
    private var lastURL: URL?

    func sample(url: URL?) {
        guard let url else {
            lastURL = nil
            tint = Color(red: 0.07, green: 0.08, blue: 0.10)
            return
        }
        if lastURL == url { return }
        lastURL = url
        Task {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue("Autumn-iOS/1.0.2", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let img = UIImage(data: data),
                  let avg = img.averageColor else { return }
            tint = Color(avg)
        }
    }
}

extension UIImage {
    var averageColor: UIColor? {
        guard let cg = cgImage else { return nil }
        let w = 8, h = 8
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var r: Double = 0, g: Double = 0, b: Double = 0, n: Double = 0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let a = Double(rgba[i + 3]) / 255
            if a < 0.2 { continue }
            r += Double(rgba[i]) / 255
            g += Double(rgba[i + 1]) / 255
            b += Double(rgba[i + 2]) / 255
            n += 1
        }
        guard n > 0 else { return nil }
        // Darken so frost stays readable
        return UIColor(red: (r / n) * 0.35, green: (g / n) * 0.35, blue: (b / n) * 0.38, alpha: 1)
    }
}
