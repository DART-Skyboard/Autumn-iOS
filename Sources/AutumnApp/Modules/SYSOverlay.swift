import SwiftUI
import AutumnServices
import PhotosUI

/// SYSTEM BROADCAST — public read of system-broadcast.json; compose via GAS for dartsolarpunk.
/// Body is scrollable, pinch-zoomable, and tappable hyperlinks.
public struct SYSOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var circuit: AdminCircuitMonitor
    @State private var message = "LOADING…"
    @State private var updated = ""
    @State private var author = ""
    @State private var draft = ""
    @State private var draftSelection = NSRange(location: 0, length: 0)
    @State private var images: [SysBroadcastImage] = []
    @State private var draftImages: [SysBroadcastImage] = []
    @State private var status = ""
    @State private var showCompose = false
    @State private var live = false
    @State private var zoom: CGFloat = 1.0
    @State private var pinchBase: CGFloat = 1.0
    @State private var showLinkPrompt = false
    @State private var linkLabel = ""
    @State private var linkURL = ""
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var pendingImageLinkURL = ""
    @State private var uploadStatus = ""
    @State private var frontImageID: UUID?

    private let def = "No system updates today."

    public var body: some View {
        OverlayPanel(title: "SYSTEM MESSAGE", onClose: { appNav.rightTab = .none }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(updated.isEmpty ? "NO ACTIVE BROADCAST" : updated)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeVM.chrome.accent.opacity(0.45))
                    Spacer()
                    Button("−") { zoom = max(0.8, zoom - 0.15) }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(themeVM.chrome.accent)
                    Text("\(Int(zoom * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Button("+") { zoom = min(2.6, zoom + 0.15) }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(themeVM.chrome.accent)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(linkedBody)
                            .font(.system(size: 13 * zoom))
                            .foregroundColor(live ? .white.opacity(0.9) : .white.opacity(0.4))
                            .tint(themeVM.chrome.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        if !images.isEmpty {
                            SysBroadcastImageStack(images: images, frontID: $frontImageID)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { v in zoom = min(max(pinchBase * v, 0.8), 2.6) }
                        .onEnded { _ in pinchBase = zoom }
                )

                if circuit.allows(authVM) {
                    Button("⚡ COMPOSE") {
                        showCompose = true
                        draft = live ? message : ""
                        draftImages = images
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent)
                }
                Text(status).font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.chrome.accent.opacity(0.5))
            }
            .padding(12)
        }
        .task { await load() }
        .sheet(isPresented: $showCompose) {
            compose
                .environmentObject(themeVM)
        }
    }

    /// Detect raw URLs plus markdown [label](url) so SYS can carry hyperlinks.
    private var linkedBody: AttributedString {
        var src = message
        let md = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^)]+)\)"#, options: [])
        if let md {
            let ns = src as NSString
            let matches = md.matches(in: src, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                if m.numberOfRanges >= 3,
                   let label = Range(m.range(at: 1), in: src),
                   let url = Range(m.range(at: 2), in: src),
                   let full = Range(m.range, in: src) {
                    src.replaceSubrange(full, with: "\(src[label]) <\(src[url])>")
                }
            }
        }
        var attr = AttributedString(src)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = src as NSString
            for match in detector.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
                guard let url = match.url, let r = Range(match.range, in: attr) else { continue }
                attr[r].link = url
                attr[r].underlineStyle = .single
            }
        }
        return attr
    }

    private var compose: some View {
        NavigationStack {
            ZStack {
                themeVM.chrome.base.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Post a system message to all sessions. Writes via GAS ashwrite — no PAT. Links (https://…) stay tappable.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))

                    // TF156: real selection-aware link tool — wraps the
                    // actual selected text as [selection](url) when there
                    // is one, otherwise inserts [label](url) at the
                    // cursor. Needs SelectableTextEditor (plain TextEditor
                    // has no selection API) to know what's actually
                    // highlighted.
                    HStack(spacing: 10) {
                        Button {
                            let ns = draft as NSString
                            if draftSelection.length > 0, draftSelection.location + draftSelection.length <= ns.length {
                                linkLabel = ns.substring(with: draftSelection)
                            } else {
                                linkLabel = ""
                            }
                            linkURL = ""
                            showLinkPrompt = true
                        } label: {
                            Label("Link", systemImage: "link")
                        }
                        PhotosPicker(selection: $photoPickerItem, matching: .images) {
                            Label("Image", systemImage: "photo")
                        }
                        Spacer()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeVM.chrome.accent)
                    .onChange(of: photoPickerItem) { item in
                        guard let item else { return }
                        Task { await handlePickedImage(item) }
                    }

                    SelectableTextEditor(text: $draft, selectedRange: $draftSelection)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(themeVM.chrome.surface)
                        .cornerRadius(8)

                    if !draftImages.isEmpty {
                        Text("ATTACHED IMAGES").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 8) {
                            ForEach(draftImages) { img in
                                ZStack(alignment: .topTrailing) {
                                    AsyncImage(url: URL(string: img.url)) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.08) }
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    if img.linkURL != nil {
                                        Image(systemName: "link.circle.fill")
                                            .foregroundColor(themeVM.chrome.accent)
                                            .background(Circle().fill(Color.black))
                                            .offset(x: 4, y: -4)
                                    }
                                    Button {
                                        draftImages.removeAll { $0.id == img.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white.opacity(0.85))
                                            .background(Circle().fill(Color.black.opacity(0.5)))
                                    }
                                    .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }
                    if !uploadStatus.isEmpty {
                        Text(uploadStatus).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                    }

                    HStack {
                        Button("▲ POST") { Task { await post() } }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(themeVM.chrome.accent)
                        Button("✕ CLEAR") { Task { await post(clear: true) } }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#ff7864"))
                        Spacer()
                    }
                    Text(status).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                    Spacer()
                }.padding(16)
            }
            .navigationTitle("SYSTEM MESSAGE")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showCompose = false } } }
            .alert("Insert Link", isPresented: $showLinkPrompt) {
                TextField("Label", text: $linkLabel)
                TextField("https://…", text: $linkURL)
                Button("Cancel", role: .cancel) {}
                Button("Insert") { insertLink() }
            } message: {
                Text(draftSelection.length > 0 ? "This will become the link text." : "Enter the text to show, then the URL.")
            }
        }
    }

    /// Wraps the current selection (if any) as markdown [label](url); with
    /// no selection, inserts a new [label](url) at the cursor.
    private func insertLink() {
        guard !linkURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let label = linkLabel.trimmingCharacters(in: .whitespaces).isEmpty ? linkURL : linkLabel
        let markdown = "[\(label)](\(linkURL.trimmingCharacters(in: .whitespaces)))"
        let ns = draft as NSString
        if draftSelection.location != NSNotFound, draftSelection.location <= ns.length {
            let range = NSRange(location: draftSelection.location, length: min(draftSelection.length, ns.length - draftSelection.location))
            draft = ns.replacingCharacters(in: range, with: markdown)
        } else {
            draft += markdown
        }
    }

    /// Downscales to a 100x100 JPEG thumbnail for inline display, but
    /// uploads the ORIGINAL full-resolution image as its own file — tapping
    /// the thumbnail shows that same file at full size, per the actual ask
    /// ("click it, see the original full-size image"), not an upscaled
    /// thumbnail.
    private func handlePickedImage(_ item: PhotosPickerItem) async {
        photoPickerItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        uploadStatus = "UPLOADING IMAGE…"
        let id = UUID()
        let ext = "jpg"
        let path = "system-broadcast-images/\(id.uuidString).\(ext)"
        guard let jpeg = uiImage.jpegData(compressionQuality: 0.85) else { return }
        do {
            try await GitHubClient.shared.writeLargeFile(
                owner: "DART-Skyboard", repo: "Autumn", path: path,
                content: jpeg, message: "system broadcast image attach"
            )
            let url = "https://raw.githubusercontent.com/DART-Skyboard/Autumn/main/\(path)"
            draftImages.append(SysBroadcastImage(id: id, url: url, linkURL: pendingImageLinkURL.isEmpty ? nil : pendingImageLinkURL))
            pendingImageLinkURL = ""
            uploadStatus = "IMAGE ATTACHED"
        } catch {
            uploadStatus = "IMAGE UPLOAD FAILED"
        }
    }

    private func load() async {
        status = "FETCHING…"
        let urls = [
            URL(string: "https://raw.githubusercontent.com/DART-Skyboard/Autumn/main/system-broadcast.json")!,
            URL(string: "https://leatr.xyz/system-broadcast.json")!
        ]
        for url in urls {
            do {
                var req = URLRequest(url: url)
                req.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, _) = try await URLSession.shared.data(for: req)
                if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    apply(obj)
                    status = "LIVE"
                    return
                }
            } catch { continue }
        }
        if let gas = await AutumnGASClient.shared.ashread(path: "system-broadcast.json") as? [String: Any] {
            apply(gas)
            status = "GAS"
            return
        }
        message = def
        live = false
        status = "UNAVAILABLE"
    }

    private func apply(_ obj: [String: Any]) {
        let msg = (obj["message"] as? String) ?? def
        message = msg
        live = msg != def && !msg.isEmpty
        author = obj["author"] as? String ?? ""
        if let u = obj["updated"] as? String, let d = ISO8601DateFormatter().date(from: u) {
            let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
            updated = "UPDATED " + f.string(from: d)
        }
        if let imgs = obj["images"] as? [[String: Any]] {
            images = imgs.compactMap { dict in
                guard let url = dict["url"] as? String else { return nil }
                return SysBroadcastImage(id: UUID(), url: url, linkURL: dict["linkURL"] as? String)
            }
        } else {
            images = []
        }
    }

    private func post(clear: Bool = false) async {
        guard circuit.allows(authVM) else { status = "CIRCUIT OPEN — write no-op"; return }
        let msg = clear ? def : draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty || clear else { status = "Message cannot be empty"; return }
        status = "SAVING…"
        let imagesPayload: [[String: Any]] = clear ? [] : draftImages.map { img in
            var d: [String: Any] = ["url": img.url]
            if let link = img.linkURL { d["linkURL"] = link }
            return d
        }
        let payload: [String: Any] = [
            "message": msg,
            "updated": ISO8601DateFormatter().string(from: Date()),
            "author": "dartsolarpunk",
            "images": imagesPayload
        ]
        let ok = await AutumnGASClient.shared.ashwriteReplace(
            path: "system-broadcast.json",
            uid: authVM.sessionUID,
            payload: payload,
            message: clear ? "broadcast: clear system message" : "broadcast: admin system message update"
        )
        if ok {
            apply(payload)
            status = "UPDATED VIA GAS"
            showCompose = false
        } else {
            status = "GAS WRITE FAILED"
        }
    }
}

struct SysBroadcastImage: Identifiable, Equatable {
    let id: UUID
    let url: String
    let linkURL: String?
}

/// 100x100 thumbnails, stacked like the chat attachment deck when there's
/// more than one — tapping opens the SAME file at full resolution, or (if
/// this image was attached as a hyperlink) opens that link instead.
struct SysBroadcastImageStack: View {
    let images: [SysBroadcastImage]
    @Binding var frontID: UUID?
    @State private var fullScreenImage: SysBroadcastImage?

    var body: some View {
        HStack(spacing: -20) {
            ForEach(Array(images.enumerated()), id: \.element.id) { idx, img in
                Button {
                    if let link = img.linkURL, let url = URL(string: link) {
                        UIApplication.shared.open(url)
                    } else {
                        fullScreenImage = img
                    }
                } label: {
                    AsyncImage(url: URL(string: img.url)) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.08) }
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.25), lineWidth: 1))
                        .rotationEffect(.degrees(Double(idx) * 4 - Double(images.count - 1) * 2))
                        .zIndex(Double(idx))
                }
                .buttonStyle(.plain)
            }
        }
        .fullScreenCover(item: $fullScreenImage) { img in
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: URL(string: img.url)) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                VStack {
                    HStack {
                        Spacer()
                        Button { fullScreenImage = nil } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundColor(.white.opacity(0.9)).padding(16)
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}

extension SysBroadcastImage: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

