import SwiftUI
import AutumnServices

/// Submit feedback — same GAS ashwrite path as web: feedback/inbox.json {id,ts,cat,msg,user}.
public struct FeedbackSheet: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appNav: AppNavigation
    @State private var cat = "GENERAL"
    @State private var msg = ""
    @State private var status = ""
    @State private var busy = false

    public var body: some View {
        let chrome = themeVM.chrome
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea().onTapGesture { appNav.showFeedback = false }
            VStack(alignment: .leading, spacing: 12) {
                Text("◇ SUBMIT FEEDBACK")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(chrome.accent)
                Text("We do not collect personal information. If you choose to share identifying details, you consent to their inclusion. Feedback is reviewed only by Radical Deepscale LLC and is not publicly visible.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(chrome.accent.opacity(0.12), lineWidth: 1))
                HStack(spacing: 6) {
                    ForEach(FeedbackService.categories, id: \.self) { c in
                        Button(c) { cat = c }
                            .font(.system(size: 8, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .foregroundColor(cat == c ? chrome.accent : chrome.accent.opacity(0.5))
                            .background(cat == c ? chrome.accent.opacity(0.12) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(chrome.accent.opacity(cat == c ? 0.6 : 0.2), lineWidth: 1))
                    }
                }
                TextEditor(text: $msg)
                    .frame(minHeight: 110)
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(.white)
                    .background(chrome.accent.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(chrome.accent.opacity(0.25), lineWidth: 1))
                Text("\(msg.count) / 1000")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(chrome.accent.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                HStack {
                    Button {
                        Task { await submit() }
                    } label: {
                        Text(busy ? "SUBMITTING…" : "▲ SUBMIT")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundColor(chrome.accent)
                            .background(chrome.accent.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(chrome.accent.opacity(0.5), lineWidth: 1))
                    }
                    .disabled(busy)
                    Button("CANCEL") { appNav.showFeedback = false }
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 12)
                }
                Text(status)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(status.contains("THANK") ? chrome.accent : Color(hex: "#ff6450"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 16)
            }
            .padding(20)
            .frame(maxWidth: 400)
            .background(Color(hex: "#040a14").opacity(0.98))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(chrome.accent.opacity(0.25), lineWidth: 1))
            .cornerRadius(12)
            .padding(18)
        }
    }

    private func submit() async {
        let t = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { status = "⚠ Please enter a message"; return }
        busy = true
        status = "SUBMITTING…"
        do {
            try await FeedbackService.shared.submit(
                msg: String(t.prefix(1000)),
                cat: cat,
                user: authVM.githubConnected ? authVM.githubUsername : "guest",
                uid: authVM.sessionUID
            )
            status = "✓ FEEDBACK SUBMITTED — THANK YOU"
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run { appNav.showFeedback = false }
        } catch {
            status = "⚠ Submission failed — please try again"
            busy = false
        }
    }
}
