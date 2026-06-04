import SwiftUI
import MarkdownUI
import LEATRCore
import AutumnServices

public struct ChatView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var themeVM: ThemeViewModel
    @Namespace private var bottomID

    public var body: some View {
        ZStack {
            themeVM.current.gradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: — EMO HUD
                EmoHUD()

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
            // Sentience state indicator
            HStack(spacing: 6) {
                Text(chatVM.sentienceState.displayIcon)
                    .font(.system(size: 14))
                    .foregroundColor(themeVM.current.accent)
                Text(chatVM.sentienceState.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(themeVM.current.textSecondary)
            }

            Spacer()

            // Emotion badge
            Text(chatVM.currentEmotion.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: chatVM.currentEmotion.accentHex))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: chatVM.currentEmotion.accentHex).opacity(0.15))
                .cornerRadius(6)

            // Buoyancy
            VStack(alignment: .trailing, spacing: 2) {
                Text("BUOY")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.current.textSecondary)
                Text(String(format: "%.3f", chatVM.currentBuoyancy))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(themeVM.current.accent)
            }

            // Active tool
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
        .padding(.vertical, 10)
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
                // Bubble
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

                // Metadata (tap to reveal)
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

                // Timestamp
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

    var body: some View {
        HStack(spacing: 12) {
            // Voice button
            Button {
                chatVM.toggleListening()
            } label: {
                Image(systemName: chatVM.isListening ? "mic.fill" : "mic")
                    .foregroundColor(chatVM.isListening ? .red : themeVM.current.accent)
                    .frame(width: 36, height: 36)
                    .background(themeVM.current.surface)
                    .cornerRadius(18)
            }

            // Text input
            TextField("Message \(LEATRIdentity.displayName)…", text: $chatVM.inputText, axis: .vertical)
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
                .onSubmit {
                    Task { await chatVM.send() }
                }

            // Send button
            Button {
                Task { await chatVM.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(chatVM.inputText.isEmpty ? themeVM.current.textSecondary : themeVM.current.accent)
            }
            .disabled(chatVM.inputText.isEmpty || chatVM.isThinking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(themeVM.current.accent.opacity(0.15)),
            alignment: .top
        )
    }
}