import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import AutumnServices

/// Pending strip + bubble thumbs (web #img-preview-strip / handleImageFilesSelect).
struct PendingAttachmentStrip: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var themeVM: ThemeViewModel

    var body: some View {
        if !chatVM.pendingAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chatVM.pendingAttachments) { a in
                        AttachmentThumb(attachment: a, size: 56, onRemove: { chatVM.removePending(a.id) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

struct MessageAttachmentRow: View {
    let attachments: [ChatAttachment]
    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(attachments) { a in
                        AttachmentThumb(attachment: a, size: 52, onRemove: nil)
                    }
                }
            }
        }
    }
}

struct AttachmentThumb: View {
    let attachment: ChatAttachment
    var size: CGFloat = 56
    var onRemove: (() -> Void)?
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 2) {
                        Text(attachment.glyph)
                            .font(.system(size: size * 0.28))
                        Text(attachment.badge)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.08))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.18), lineWidth: 1))

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .offset(x: 4, y: -4)
            }
        }
        .onAppear { loadPreview() }
    }

    private func loadPreview() {
        let url = attachment.fileURL
        switch attachment.kind {
        case .image:
            image = UIImage(contentsOfFile: url.path)
        case .video:
            image = videoThumb(url)
        default:
            break
        }
    }

    private func videoThumb(_ url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let t = CMTime(seconds: 0.3, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: t, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }
}
