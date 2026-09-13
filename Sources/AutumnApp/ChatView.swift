import SwiftUI
import MarkdownUI
import LEATRCore
import AutumnServices
import UniformTypeIdentifiers
import UIKit
import PhotosUI

public struct ChatView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @Namespace private var bottomID

    public var body: some View {
        ZStack {
            // Chrome panel only — no extra dark wash over the BRPN/video (web #vid-scrim owns overlay).
            VStack(spacing: 0) {
                // EmoHUD lives in AppShellView under the 3D scene (web order).

                // MARK: — Message list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatVM.messages.filter { !$0.isInternal }) { msg in
                                MessageBubble(message: msg)
                            }
                            if chatVM.isThinking {
                                ThinkingIndicator()
                            }
                            Color.clear.frame(height: 1).id(bottomID)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                        if value.translation.height > 40 {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                to: nil, from: nil, for: nil)
                        }
                    })
                    .onChange(of: chatVM.messages.count) { newValue in
                        withAnimation { proxy.scrollTo(bottomID) }
                    }
                }

                // MARK: — Input bar
                InputBar()
            }
        }
    }
}

// MARK: — EMO HUD
struct EmoHUD: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var themeVM: ThemeViewModel

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text(chatVM.sentienceState.displayIcon)
                    .font(.system(size: 14))
                    .foregroundColor(themeVM.current.accent)
                Text(chatVM.sentienceState.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(themeVM.current.textSecondary)
            }

            Spacer()

            Text(chatVM.currentEmotion.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: chatVM.currentEmotion.accentHex))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: chatVM.currentEmotion.accentHex).opacity(0.15))
                .cornerRadius(6)

            VStack(alignment: .trailing, spacing: 2) {
                Text("BUOY")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.current.textSecondary)
                Text(String(format: "%.3f", chatVM.currentBuoyancy))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(themeVM.current.accent)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text("TOOL")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.current.textSecondary)
                Text(chatVM.currentTool.displayName.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(themeVM.current.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(themeVM.current.accent.opacity(0.2)),
            alignment: .bottom
        )
    }
}

// MARK: — Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var showMeta = false

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !message.attachments.isEmpty {
                    MessageAttachmentRow(attachments: message.attachments)
                        .frame(maxWidth: 220, alignment: isUser ? .trailing : .leading)
                }
                if !message.content.isEmpty {
                Markdown(message.content)
                    .markdownTextStyle { ForegroundColor(.white) }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser
                        ? themeVM.current.accent.opacity(0.2)
                        : themeVM.current.surface
                    )
                    .cornerRadius(isUser ? 16 : 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: isUser ? 16 : 12)
                            .stroke(
                                isUser
                                    ? themeVM.current.accent.opacity(0.4)
                                    : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
                    .onTapGesture { withAnimation { showMeta.toggle() } }
                }

                if showMeta, let meta = message.leatrMeta {
                    HStack(spacing: 8) {
                        Label(meta.toolRoute, systemImage: "arrow.triangle.branch")
                        Label(String(format: "%.3f", meta.buoyancy), systemImage: "waveform")
                        Label(meta.emotion, systemImage: "face.smiling")
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.current.textSecondary)
                    .padding(.horizontal, 4)
                }

                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 9))
                    .foregroundColor(themeVM.current.textSecondary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: — Thinking Indicator
struct ThinkingIndicator: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var phase = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(themeVM.current.accent)
                        .frame(width: 7, height: 7)
                        .opacity(phase == i ? 1.0 : 0.3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(themeVM.current.surface)
            .cornerRadius(12)
            Spacer(minLength: 40)
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

// MARK: — Input Bar
struct InputBar: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @FocusState var inputFocused: Bool

    @State private var showAttachMenu = false
    @State private var showImporter = false
    @State private var showPhotosPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []

    private var canSend: Bool {
        !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !chatVM.pendingAttachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
        PendingAttachmentStrip()
        // Keyboard collapse lives ONLY on ToolbarItemGroup(placement: .keyboard) —
        // do not float a chevron chip above Ask Autumn when focused without a real keyboard (TF81).
        HStack(spacing: 8) {
            Button {
                chatVM.toggleListening()
            } label: {
                Image(systemName: chatVM.isListening ? "mic.fill" : "mic")
                    .foregroundColor(chatVM.isListening ? .red : themeVM.current.accent)
                    .frame(width: 36, height: 36)
                    .background(themeVM.current.surface)
                    .cornerRadius(18)
            }

            Button { showAttachMenu = true } label: {
                Image(systemName: "paperclip")
                    .foregroundColor(themeVM.current.accent)
                    .frame(width: 36, height: 36)
                    .background(themeVM.current.surface)
                    .cornerRadius(18)
            }
            .accessibilityLabel("Attach")

            Button { appNav.showMathSolver = true } label: {
                Text("fx")
                    .font(.system(size: 13, weight: .bold, design: .serif)).italic()
                    .foregroundColor(themeVM.current.accent)
                    .frame(width: 36, height: 36)
                    .background(themeVM.current.surface)
                    .cornerRadius(18)
            }
            .accessibilityLabel("Math Solver")

            TextField("Ask Autumn...", text: $chatVM.inputText, axis: .vertical)
                .lineLimit(1...5)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(themeVM.current.surface)
                .cornerRadius(20)
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(themeVM.current.accent.opacity(0.25), lineWidth: 1)
                )
                .focused($inputFocused)
                .onSubmit {
                    Task { await chatVM.send() }
                }

            Button {
                Task { await chatVM.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(canSend ? themeVM.current.accent : themeVM.current.textSecondary)
            }
            .disabled(!canSend || chatVM.isThinking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(themeVM.current.accent.opacity(0.15)),
            alignment: .top
        )
        .confirmationDialog("Attach", isPresented: $showAttachMenu, titleVisibility: .visible) {
            Button("Photo Library") { showPhotosPicker = true }
            Button("Choose Files") { showImporter = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $photoPickerItems,
            maxSelectionCount: 30,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
        .onChange(of: photoPickerItems) { items in
            guard !items.isEmpty else { return }
            Task { await importPickedPhotos(items) }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: ChatAttachContentTypes.chooseFiles,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                chatVM.importFiles(from: urls)
            }
        }
        // Collapse control on the keyboard accessory (DART pattern) — swipe alone is not enough on device.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    inputFocused = false
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeVM.current.accent)
                }
                .accessibilityLabel("Hide keyboard")
            }
        }
    }

    /// Copy PhotosPicker items into temp files, then reuse importFiles (pending strip + send).
    private func importPickedPhotos(_ items: [PhotosPickerItem]) async {
        var urls: [URL] = []
        for item in items {
            if let url = await Self.materializePhotoItem(item) {
                urls.append(url)
            }
        }
        await MainActor.run {
            if !urls.isEmpty {
                chatVM.importFiles(from: urls)
            }
            photoPickerItems = []
        }
    }

    private static func materializePhotoItem(_ item: PhotosPickerItem) async -> URL? {
        // File copy first (videos); Data fallback for stills / HEIC.
        if let file = try? await item.loadTransferable(type: AutumnPickedFile.self) {
            return file.url
        }
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            return nil
        }
        let ext: String = {
            if let t = item.supportedContentTypes.first {
                if let e = t.preferredFilenameExtension { return e }
                if t.conforms(to: .movie) || t.conforms(to: .video) { return "mp4" }
                if t.conforms(to: .heic) { return "heic" }
                if t.conforms(to: .png) { return "png" }
                if t.conforms(to: .gif) { return "gif" }
                if t.conforms(to: .webP) { return "webp" }
            }
            return "jpg"
        }()
        let name = (item.itemIdentifier ?? UUID().uuidString)
            .replacingOccurrences(of: "/", with: "_")
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("autumn-photo-\(name)-\(UUID().uuidString.prefix(8)).\(ext)")
        do {
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }
}

/// PhotosPicker → temp URL via FileRepresentation (keeps large videos off Data).
private struct AutumnPickedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .item) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("autumn-pick-\(UUID().uuidString)-\(received.file.lastPathComponent)")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

// MARK: — Broad UTTypes for Choose Files (explicit + catch-all)
enum ChatAttachContentTypes {
    static var chooseFiles: [UTType] {
        var types: [UTType] = [
            // Images (incl. HEIC/HDR-capable containers)
            .jpeg, .png, .gif, .webP, .heic, .heif, .tiff, .bmp, .svg, .rawImage, .image,
            // Video
            .movie, .mpeg4Movie, .quickTimeMovie, .avi, .video,
            // 3D
            .usdz, .threeDContent,
            // Code / text
            .plainText, .utf8PlainText, .sourceCode,
            .swiftSource, .cSource, .cPlusPlusSource, .pythonScript, .javaScript,
            .html, .json, .xml, .yaml, .shellScript,
            // Docs / catch-all so nothing capable is blocked
            .pdf, .rtf, .commaSeparatedText, .data, .item,
        ]
        // Optional / extension-backed types (nil-safe)
        let extras: [String] = [
            "hdr", "exr", "dng", "cr2", "nef", "arw", "orf", "rw2", "raf",
            "mkv", "webm", "m4v",
            "glb", "gltf", "obj", "stl", "fbx", "dae", "reality", "usd", "usda", "usdc",
            "md", "ts", "tsx", "jsx", "rs", "go", "rb", "kt", "java", "css", "sql", "toml", "ini", "php", "m", "mm", "h", "hpp", "asm", "s",
            "step", "stp", "iges", "igs", "dwg", "dxf",
        ]
        for ext in extras {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        if let reality = UTType("com.apple.reality") { types.append(reality) }
        if let gltf = UTType("model.gltf-binary") ?? UTType(mimeType: "model/gltf-binary") {
            types.append(gltf)
        }
        if let gltfJson = UTType("model.gltf+json") ?? UTType(mimeType: "model/gltf+json") {
            types.append(gltfJson)
        }
        // Deduce hdrImage when the SDK exposes it
        if let hdr = UTType("public.hdr-image") { types.append(hdr) }
        return types
    }
}
