import SwiftUI
import MarkdownUI
import LEATRCore
import AutumnServices
import UniformTypeIdentifiers
import UIKit

public struct ChatView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @Namespace private var bottomID
    @FocusState private var inputFocused: Bool

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
                    .onTapGesture {
                        inputFocused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                        if value.translation.height > 40 {
                            inputFocused = false
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                to: nil, from: nil, for: nil)
                        }
                    })
                    .onChange(of: chatVM.messages.count) { newValue in
                        withAnimation { proxy.scrollTo(bottomID) }
                    }
                }

                // MARK: — Input bar
                InputBar(inputFocused: _inputFocused)
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
    @FocusState var inputFocused: Bool

    @State private var showImporter = false
    private var canSend: Bool {
        !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !chatVM.pendingAttachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
        PendingAttachmentStrip()
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

            Button { showImporter = true } label: {
                Image(systemName: "paperclip")
                    .foregroundColor(themeVM.current.accent)
                    .frame(width: 36, height: 36)
                    .background(themeVM.current.surface)
                    .cornerRadius(18)
            }

            TextField("Ask Autumn...", text: $chatVM.inputText, axis: .vertical)
                .lineLimit(1...5)
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
                // Down arrow button appears when keyboard is showing
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            inputFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .foregroundColor(.cyan)
                        }
                    }
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
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                chatVM.importFiles(from: urls)
            }
        }
    }
}
