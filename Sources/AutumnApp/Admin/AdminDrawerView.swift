import SwiftUI
import AutumnServices
import LEATRCore

/// Admin drawer — public-app left ADMIN tab.
/// Tabs: DATA / ASH / MESSAGES (TF111 — dropped the redundant inbox-only MSG tab,
/// MESSAGES is the full mailbox with folders/select/move/delete).
/// TF111: floating + translucent + draggable, matching the other HUD overlay panels
/// (Mist/Shard/etc.) instead of a fixed slide-in-from-edge drawer — opened from the
/// same small "⚙ ADMIN" tab on the left HUD either way.
public struct AdminDrawerView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appNav: AppNavigation
    @State private var adminInput = ""
    @State private var adminLog: [String] = [
        "═══ AUTUMN ADMIN — PUBLIC-APP DRAWER ═══",
        "You are operating in the admin drawer. The admin is Justin (dartsolarpunk)."
    ]
    @State private var dragOffset: CGSize = .zero
    @GestureState private var liveDrag: CGSize = .zero

    public var body: some View {
        let chrome = themeVM.chrome
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { appNav.showAdmin = false }

            VStack(spacing: 0) {
                HStack {
                    Text("⚙ ADMIN").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(Color(hex: "#ffb347"))
                    Spacer()
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                    Button("✕") { appNav.showAdmin = false }
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(Color(hex: "#ff4466"))
                }
                .padding(12)
                .background(chrome.accent.opacity(0.06))
                .contentShape(Rectangle())
                // Drag by the title bar only — avoids fighting the mailbox List's
                // own scroll gesture below it.
                .gesture(
                    DragGesture()
                        .updating($liveDrag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            dragOffset.width += value.translation.width
                            dragOffset.height += value.translation.height
                        }
                )
                HStack(spacing: 0) {
                    ForEach(AppNavigation.AdminTab.allCases, id: \.rawValue) { tab in
                        Button { appNav.adminTab = tab } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(appNav.adminTab == tab ? chrome.accent : chrome.textSecondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(appNav.adminTab == tab ? chrome.accent.opacity(0.12) : Color.clear)
                        }
                    }
                }
                .overlay(Rectangle().frame(height: 1).foregroundColor(chrome.accent.opacity(0.2)), alignment: .bottom)

                Group {
                    switch appNav.adminTab {
                    case .data: dataTab
                    case .ash: ashTab
                    case .messages: AdminMailboxView(inboxOnly: false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: min(380, UIScreen.main.bounds.width - 24), height: min(600, UIScreen.main.bounds.height * 0.75))
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(chrome.accent.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            .padding(.leading, 16).padding(.top, 60)
            .offset(x: dragOffset.width + liveDrag.width, y: dragOffset.height + liveDrag.height)
        }
    }

    private var dataTab: some View {
        AdminDataConsole()
    }

    private var ashTab: some View {
        VStack(spacing: 0) {
            Text("ASH · Grammar Study + Training")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(themeVM.chrome.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GrammarStudyButton(adminLog: $adminLog)
                    AdminGrammarPromptPanel(adminLog: $adminLog)
                    AdminTrainingCatalogPanel(adminLog: $adminLog)
                    StudyQueuePanel()
                    Divider().background(Color.white.opacity(0.15))
                    ForEach(adminLog.indices, id: \.self) { i in
                        Text(adminLog[i]).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.85)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
            HStack {
                TextField("[H] admin chat", text: $adminInput)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(themeVM.chrome.surface)
                    .cornerRadius(6)
                Button("SEND") {
                    let t = adminInput.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    adminInput = ""
                    adminLog.append("> \(t)")
                    Task {
                        let turn = await GrammarEngine.shared.processForChat(t, facts: ["_memoryOwner": authVM.githubUsername, "_admin": "1"])
                        await MainActor.run { adminLog.append(turn.reply) }
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(themeVM.chrome.accent)
            }.padding(10)
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            Spacer()
            Text(v).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
        }
    }
}

/// FEED/MSG mailbox — folders inbox/analysis/read/trash. Matches `_admMountFeedbackUI`.
/// `inboxOnly` mirrors web MSG overlay (`inboxOnly:true`).
public struct AdminMailboxView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var authVM: AuthViewModel
    var inboxOnly: Bool = false
    @State private var folder: MailboxFolder = .inbox
    @State private var entries: [FeedbackEntry] = []
    @State private var selected: Set<String> = []
    @State private var expanded: String?
    @State private var status = "LOADING..."
    @State private var busy = false
    @State private var showGitHubReconnect = false

    public var body: some View {
        let chrome = themeVM.chrome
        VStack(spacing: 0) {
            // TF119: the row is one button wider on non-Inbox folders (UNREAD
            // only shows there) than the fixed-width panel comfortably fits —
            // that's what was squeezing/deforming every button. A horizontal
            // scroll means the row never has to compress to fit; it just
            // scrolls the same way regardless of which folder is active.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    mini("ALL") { selected = Set(entries.map(\.id)) }
                    mini("NONE") { selected = [] }
                    if folder != .inbox {
                        mini("UNREAD", warn: true) { Task { await moveSel(.inbox) } }
                    }
                    mini("→ ANAL", warn: true) { Task { await moveSel(.analysis) } }
                    mini("→ READ", warn: true) { Task { await moveSel(.read) } }
                    mini("→ TRASH", warn: true) { Task { await moveSel(.trash) } }
                    mini("DELETE", danger: true) { Task { await deleteSel() } }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
            }

            if inboxOnly {
                Text("INBOX")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(chrome.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(chrome.accent.opacity(0.12)), alignment: .bottom)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(MailboxFolder.allCases), id: \.rawValue) { f in
                        Button {
                            folder = f
                            Task { await load() }
                        } label: {
                            Text(f.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.2)
                                .foregroundColor(folder == f ? chrome.accent : chrome.accent.opacity(0.4))
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .overlay(Rectangle().frame(height: 2).foregroundColor(folder == f ? chrome.accent : .clear), alignment: .bottom)
                        }
                    }
                    Spacer()
                }
                .overlay(Rectangle().frame(height: 1).foregroundColor(chrome.accent.opacity(0.12)), alignment: .bottom)
            }

            if entries.isEmpty {
                Spacer()
                if busy {
                    Text("LOADING…")
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(chrome.accent.opacity(0.35))
                } else if status.hasPrefix("Error") {
                    // TF111: was showing the misleading "NO ENTRIES" here even when the
                    // load genuinely failed — the real error sat only in the small status
                    // line at the bottom, easy to miss entirely.
                    VStack(spacing: 6) {
                        Text(status)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: "#ff7864"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        if status.localizedCaseInsensitiveContains("bad credentials")
                            || status.localizedCaseInsensitiveContains("401") {
                            Text("This account's GitHub connection has expired.")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.45))
                            Button("↻ Reconnect GitHub") { showGitHubReconnect = true }
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(chrome.accent)
                        } else {
                            Button("↻ Retry") { Task { await load() } }
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(chrome.accent)
                        }
                    }
                } else {
                    Text("NO ENTRIES")
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(chrome.accent.opacity(0.35))
                }
                Spacer()
            } else {
                List {
                    ForEach(entries) { e in
                        mailboxRow(e)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Text(status)
                .font(.system(size: 8, design: .monospaced))
                .tracking(1)
                .foregroundColor(chrome.accent.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .overlay(Rectangle().frame(height: 1).foregroundColor(chrome.accent.opacity(0.1)), alignment: .top)
        }
        .onAppear { if inboxOnly { folder = .inbox } }
        .task { await load() }
        .onChange(of: folder) { _ in selected = []; expanded = nil }
        .onChange(of: authVM.githubConnected) { connected in
            if connected { showGitHubReconnect = false; Task { await load() } }
        }
        .sheet(isPresented: $showGitHubReconnect) {
            GitHubDeviceFlowSheet()
        }
    }

    private func mailboxRow(_ e: FeedbackEntry) -> some View {
        let chrome = themeVM.chrome
        let open = expanded == e.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Button {
                    if selected.contains(e.id) { selected.remove(e.id) } else { selected.insert(e.id) }
                } label: {
                    Image(systemName: selected.contains(e.id) ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundColor(chrome.accent.opacity(0.7))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shortDate(e.ts)).font(.system(size: 8, design: .monospaced)).foregroundColor(chrome.accent.opacity(0.5))
                    Text(e.cat.uppercased()).font(.system(size: 8, design: .monospaced)).foregroundColor(Color(hex: "#ffb347").opacity(0.8))
                    Text(e.user).font(.system(size: 8, design: .monospaced)).foregroundColor(chrome.accent.opacity(0.35))
                }.frame(width: 92, alignment: .leading)
                Text(e.msg)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(open ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(open ? "[-]" : "[+]").font(.system(size: 9, design: .monospaced)).foregroundColor(chrome.accent.opacity(0.35))
            }
            .padding(8)
            .contentShape(Rectangle())
            .onTapGesture { expanded = open ? nil : e.id }
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    Text(e.msg).font(.system(size: 12)).foregroundColor(.white).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if folder != .inbox { mini("UNREAD") { Task { await moveOne(e, to: .inbox) } } }
                        if folder != .analysis { mini("ANALYSIS") { Task { await moveOne(e, to: .analysis) } } }
                        if folder != .read { mini("READ") { Task { await moveOne(e, to: .read) } } }
                        if folder != .trash { mini("TRASH") { Task { await moveOne(e, to: .trash) } } }
                        mini("DELETE", danger: true) { Task { await deleteOne(e) } }
                    }
                }
                .padding(.leading, 28).padding(.trailing, 8).padding(.bottom, 10)
                .background(chrome.accent.opacity(0.04))
            }
        }
        .overlay(Rectangle().frame(height: 1).foregroundColor(chrome.accent.opacity(0.08)), alignment: .bottom)
    }

    private func mini(_ label: String, warn: Bool = false, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .tracking(1)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .foregroundColor(danger ? Color(hex: "#ff3c3c").opacity(0.8) : (warn ? Color(hex: "#ff6450").opacity(0.85) : themeVM.chrome.accent.opacity(0.75)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(
                    danger ? Color(hex: "#c80000").opacity(0.3) : themeVM.chrome.accent.opacity(0.22), lineWidth: 1))
        }
        .disabled(busy)
    }

    private func shortDate(_ ts: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = iso.date(from: ts) ?? ISO8601DateFormatter().date(from: ts)
        guard let d else { return ts.prefix(16).description }
        let f = DateFormatter(); f.dateFormat = "M/d h:mm a"
        return f.string(from: d)
    }

    private func load() async {
        busy = true
        status = "LOADING \(folder.rawValue.uppercased())..."
        do {
            // TF119: was possible to hang indefinitely with no visible error —
            // loadFolder can fall through several fetch attempts internally
            // (GAS, then GitHub, and for ANALYSIS specifically several legacy
            // paths), and while each individual request has its own timeout,
            // nothing bounded the total. A hard overall timeout means the UI
            // always recovers to a real error + Retry instead of sitting on
            // "LOADING..." with no way to tell if it's still working or stuck.
            let snap = try await withTimeout(seconds: 15) {
                try await FeedbackService.shared.loadFolder(folder)
            }
            entries = snap.entries
            selected = []
            status = "\(entries.count) entries in \(folder.rawValue.uppercased()) (\(folder.path))"
        } catch {
            entries = []
            status = "Error: \(error.localizedDescription)"
        }
        busy = false
    }

    private func withTimeout<T>(seconds: Double, _ operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "AdminMailbox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timed out after \(Int(seconds))s"])
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func uid() -> String { authVM.githubUsername.isEmpty ? "admin" : authVM.githubUsername }

    private func moveOne(_ e: FeedbackEntry, to dest: MailboxFolder) async {
        let remaining = entries.filter { $0.id != e.id }
        busy = true; status = "Moving to \(dest.rawValue)..."
        do {
            try await FeedbackService.shared.move(entries: [e], from: folder, to: dest, remaining: remaining, uid: uid())
            await load()
            status = "Moved to \(dest.rawValue.uppercased())"
        } catch { status = "Move error: \(error.localizedDescription)"; busy = false }
    }

    private func moveSel(_ dest: MailboxFolder) async {
        let moving = entries.filter { selected.contains($0.id) }
        guard !moving.isEmpty else { status = "No entries selected"; return }
        let remaining = entries.filter { !selected.contains($0.id) }
        busy = true; status = "Moving \(moving.count) to \(dest.rawValue)..."
        do {
            try await FeedbackService.shared.move(entries: moving, from: folder, to: dest, remaining: remaining, uid: uid())
            await load()
            status = "Moved \(moving.count) to \(dest.rawValue.uppercased())"
        } catch { status = "Error: \(error.localizedDescription)"; busy = false }
    }

    private func deleteOne(_ e: FeedbackEntry) async {
        if folder != .trash {
            await moveOne(e, to: .trash)
            return
        }
        let remaining = entries.filter { $0.id != e.id }
        busy = true; status = "Deleting permanently from trash..."
        do {
            try await FeedbackService.shared.delete(remaining: remaining, folder: folder, uid: uid(), count: 1)
            await load()
            status = "Entry deleted."
        } catch { status = "Delete error: \(error.localizedDescription)"; busy = false }
    }

    private func deleteSel() async {
        let n = selected.count
        guard n > 0 else { status = "No entries selected"; return }
        if folder != .trash {
            await moveSel(.trash)
            return
        }
        let remaining = entries.filter { !selected.contains($0.id) }
        busy = true; status = "Deleting permanently from trash..."
        do {
            try await FeedbackService.shared.delete(remaining: remaining, folder: folder, uid: uid(), count: n)
            await load()
            status = "Deleted \(n) entries"
        } catch { status = "Error: \(error.localizedDescription)"; busy = false }
    }
}

/// TF124: the study queue admin can actually act on — every word she was
/// asked about and couldn't answer from her curated topics or WordNet.
/// Read-only here by design: filling a gap means writing real content to
/// ashtree/reference/, which happens by editing that file directly (same as
/// every other reference addition this session), not through this panel.
struct StudyQueuePanel: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @State private var entries: [[String: Any]] = []
    @State private var status = "Not loaded"
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("STUDY QUEUE — unanswered gaps").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(themeVM.chrome.accent)
                Spacer()
                Button(busy ? "…" : "↻ Load") { Task { await load() } }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent)
                    .disabled(busy)
            }
            if entries.isEmpty {
                Text(status).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                    HStack(alignment: .top, spacing: 8) {
                        Text((e["word"] as? String ?? "?").uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#ffb347"))
                        Text(e["context"] as? String ?? "")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
        .task { await load() }
    }

    private func load() async {
        busy = true
        let raw = await AutumnGASClient.shared.ashread(path: AutumnConfig.studyQueuePath)
        if let arr = raw as? [[String: Any]] {
            entries = Array(arr.suffix(15).reversed())
            status = entries.isEmpty ? "No gaps recorded yet" : ""
        } else if let dict = raw as? [String: Any], let content = dict["content"] as? String,
                  let decoded = Data(base64Encoded: content.replacingOccurrences(of: "\n", with: "")),
                  let arr = try? JSONSerialization.jsonObject(with: decoded) as? [[String: Any]] {
            entries = Array(arr.suffix(15).reversed())
            status = entries.isEmpty ? "No gaps recorded yet" : ""
        } else {
            status = "No gaps recorded yet"
        }
        busy = false
    }
}
