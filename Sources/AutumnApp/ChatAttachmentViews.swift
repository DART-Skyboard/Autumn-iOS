import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import AVKit
import AutumnServices

/// Pending strip + bubble thumbs (web #img-preview-strip / handleImageFilesSelect).
struct PendingAttachmentStrip: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var themeVM: ThemeViewModel

    /// ~28–32% of screen width, capped ~140pt (was 56 — too small on device).
    private var pendingSize: CGFloat {
        let w = UIScreen.main.bounds.width
        return min(140, max(120, w * 0.30))
    }

    var body: some View {
        if !chatVM.pendingAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(chatVM.pendingAttachments) { a in
                        AttachmentThumb(attachment: a, size: pendingSize, onRemove: { chatVM.removePending(a.id) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}

struct MessageAttachmentRow: View {
    let attachments: [ChatAttachment]
    /// Bubble thumbs ~100–120pt (was 52).
    private var bubbleSize: CGFloat { 110 }

    var body: some View {
        if attachments.count == 1 {
            AttachmentThumb(attachment: attachments[0], size: bubbleSize, onRemove: nil)
        } else if attachments.count > 1 {
            StackedAttachmentDeck(attachments: attachments)
        }
    }
}

/// TF153: multiple images in one message fan out like a held hand of cards
/// rather than a plain scrolling row — tapping one brings it to the front,
/// enlarged in place; tapping anywhere else in the stack's own frame (not
/// on a card) sends it back to the fan. Selecting a different card while
/// one is already forward swaps which one is forward directly.
struct StackedAttachmentDeck: View {
    let attachments: [ChatAttachment]
    @State private var frontID: UUID?
    @State private var images: [UUID: UIImage] = [:]

    private let cardSize: CGFloat = 120
    private let frontSize: CGFloat = 230
    private let fanStep: CGFloat = 16   // per-card x/y offset in the resting fan
    private let rotStep: Double = 5     // per-card rotation in the resting fan

    private var totalWidth: CGFloat { frontSize + CGFloat(max(0, attachments.count - 1)) * fanStep + 20 }
    private var totalHeight: CGFloat { frontSize + CGFloat(max(0, attachments.count - 1)) * (fanStep * 0.6) + 20 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(attachments.enumerated()), id: \.element.id) { idx, a in
                let isFront = frontID == a.id
                let restOffset = CGFloat(idx) * fanStep
                let restRotation = (Double(idx) - Double(attachments.count - 1) / 2) * rotStep

                cardContent(a, isFront: isFront)
                    .frame(width: isFront ? frontSize : cardSize, height: isFront ? frontSize : cardSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(isFront ? 0.55 : 0.22), lineWidth: 1))
                    .shadow(color: .black.opacity(isFront ? 0.5 : 0.25), radius: isFront ? 14 : 3, y: isFront ? 8 : 2)
                    .rotationEffect(.degrees(isFront ? 0 : restRotation))
                    .offset(x: isFront ? 0 : restOffset, y: isFront ? 0 : restOffset * 0.6)
                    .zIndex(isFront ? 100 : Double(idx))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            frontID = isFront ? nil : a.id
                        }
                    }
                    .onAppear { loadImage(a) }
            }
        }
        .frame(width: totalWidth, height: totalHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard frontID != nil else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { frontID = nil }
        }
    }

    @ViewBuilder
    private func cardContent(_ a: ChatAttachment, isFront: Bool) -> some View {
        if let img = images[a.id] {
            Image(uiImage: img)
                .resizable()
                // TF153: the actual ask — brought-forward shows the FULL
                // original image (letterboxed if needed), not a crop; the
                // resting fan card stays a cropped-to-fill thumbnail, same
                // as any other thumbnail in this file.
                .aspectRatio(contentMode: isFront ? .fit : .fill)
                .background(isFront ? Color.black : Color.clear)
        } else {
            VStack(spacing: 4) {
                Image(systemName: a.systemIcon)
                    .font(.system(size: cardSize * 0.28, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                Text(a.badge)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.08))
        }
    }

    private func loadImage(_ a: ChatAttachment) {
        guard images[a.id] == nil else { return }
        if a.kind == .image, let img = UIImage(contentsOfFile: a.fileURL.path) {
            images[a.id] = img
        } else if a.kind == .video {
            let asset = AVAsset(url: a.fileURL)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            if let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.3, preferredTimescale: 600), actualTime: nil) {
                images[a.id] = UIImage(cgImage: cg)
            }
        }
    }
}

struct AttachmentThumb: View {
    let attachment: ChatAttachment
    var size: CGFloat = 56
    var onRemove: (() -> Void)?
    @State private var image: UIImage?
    @State private var showPreview = false

    private var canPreview: Bool {
        attachment.kind == .image || attachment.kind == .video
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard canPreview else { return }
                showPreview = true
            } label: {
                ZStack {
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: attachment.systemIcon)
                                    .font(.system(size: size * 0.28, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.92))
                                Text(attachment.badge)
                                    .font(.system(size: max(9, size * 0.08), weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white.opacity(0.08))
                        }
                    }
                    if attachment.kind == .video, image != nil {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: size * 0.32))
                            .foregroundColor(.white.opacity(0.95))
                            .shadow(radius: 2)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!canPreview)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: max(16, size * 0.14)))
                        .foregroundColor(.white.opacity(0.9))
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .offset(x: 6, y: -6)
            }
        }
        .onAppear { loadPreview() }
        .accessibilityLabel("\(attachment.fileName) \(attachment.badge)")
        .fullScreenCover(isPresented: $showPreview) {
            AttachmentPreviewCover(attachment: attachment, image: image)
        }
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

/// Full-screen quick-look style preview for image / video attachments.
struct AttachmentPreviewCover: View {
    let attachment: ChatAttachment
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Group {
                switch attachment.kind {
                case .image:
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let ui = UIImage(contentsOfFile: attachment.fileURL.path) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("Unable to load image")
                            .foregroundColor(.white.opacity(0.6))
                    }
                case .video:
                    VideoPlayer(player: AVPlayer(url: attachment.fileURL))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    Text(attachment.fileName)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(16)
            }
            .accessibilityLabel("Close preview")
        }
        .preferredColorScheme(.dark)
    }
}
