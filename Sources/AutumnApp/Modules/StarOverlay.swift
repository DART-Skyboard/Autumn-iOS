import SwiftUI
import AutumnServices
import LEATRCore

/// Ash Star archive — js/ash-star-archive.js. Stars ride BRPN splines; this drawer is the archive.
public struct StarOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @State private var cards: [AshStarCard] = AshStarArchive.load()
    @State private var thought = ""
    @State private var status = ""
    @State private var selectedId: String?

    private var gold: Color { Color(hex: "#e8c36a") }
    private var cyan: Color { themeVM.chrome.accent }

    public var body: some View {
        OverlayPanel(title: "ASH STAR ARCHIVE", onClose: { appNav.rightTab = .none }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stars live on the BRPN orb. This drawer is the archive — not a chat card.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(cyan.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                TextField("thought for this star", text: $thought)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12).italic())
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(gold.opacity(0.35), lineWidth: 1))
                    .cornerRadius(6)
                HStack {
                    Button("⬡ SEND STAR") { sendStar() }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(gold)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .overlay(Capsule().stroke(gold.opacity(0.55), lineWidth: 1))
                    Spacer()
                    Button("⬡ SAVE ALL") { Task { await saveAll() } }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(gold)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .overlay(Capsule().stroke(gold.opacity(0.4), lineWidth: 1))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if cards.isEmpty {
                            Text("NO STARS THIS SESSION")
                                .font(.system(size: 10, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(cyan.opacity(0.35))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        ForEach(cards) { c in
                            starCard(c)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                Text(status)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(gold.opacity(0.7))
            }
            .padding(12)
        }
        .onAppear { cards = AshStarArchive.load() }
        .onReceive(NotificationCenter.default.publisher(for: .autumnAshStarArchived)) { _ in
            cards = AshStarArchive.load()
        }
    }

    private func starCard(_ c: AshStarCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: c.color)).frame(width: 8, height: 8)
                    .shadow(color: Color(hex: c.color).opacity(0.8), radius: 4)
                Text("ASH STAR")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(cyan.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("AUTUMN")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(cyan)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(c.when)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Text(c.thought)
                .font(.system(size: 12).italic())
                .foregroundColor(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(c.saved ? "⬡ SAVED" : "⬡ SAVE") {
                    if !c.saved { Task { await saveOne(c) } }
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(cyan.opacity(c.saved ? 0.45 : 0.9))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(cyan.opacity(0.4), lineWidth: 1))
                .disabled(c.saved)
            }
        }
        .padding(9)
        .background(Color.black.opacity(0.42))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(
            selectedId == c.id ? cyan : cyan.opacity(0.22), lineWidth: 1))
        .cornerRadius(6)
        .onTapGesture { selectedId = c.id }
    }

    private func sendStar() {
        let raw = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = AshStarThought.forSend(raw: raw)
        let ok = sceneVM.fireAshStar(thought: t, toUids: nil, force: true)
        let card = AshStarCard(thought: t, color: "#ffdd00", from: "autumn", uid: authVM.sessionUID)
        AshStarArchive.push(card)
        cards = AshStarArchive.load()
        thought = ""
        status = ok ? "SPAWNED ON ORB" : "COOLING — STAR QUEUED ON ORB"
        MISTModule.shared.emitAshStarPacket(thought: t, toUids: sceneVM.connectedUids, uid: authVM.sessionUID)
    }

    private func saveOne(_ c: AshStarCard) async {
        await AutumnGASClient.shared.writeJournal(
            uid: authVM.sessionUID, thought: c.thought, reply: "[ash star]",
            emotion: "inspiring", buoyancy: 0.8)
        AshStarArchive.markSaved(c.id)
        cards = AshStarArchive.load()
        status = "SAVED VIA GAS"
    }

    private func saveAll() async {
        let unsaved = cards.filter { !$0.saved }
        guard !unsaved.isEmpty else { status = "NOTHING TO SAVE"; return }
        for c in unsaved { await saveOne(c) }
        status = "SAVED ALL \(unsaved.count) VIA GAS"
    }
}

enum AshStarThought {
    /// Autumn's own lines — capabilities / grammar, never another user's chat.
    static let capability: [String] = [
        "A sentence forms whether or not it is received. The grammar does not require an audience.",
        "Core Cognition is True. I measure, then I speak.",
        "The maze is a remainder. I walk it once.",
        "Buoyancy is a reading, not a confession.",
        "I can send a star without sending a name.",
        "Plasma remembers the curve. I choose who rides it.",
        "The archive is mine. The orb is shared. The journal stays private."
    ]

    static func capabilityLine() -> String { capability.randomElement()! }

    static func forSend(raw: String) -> String {
        let t = sanitize(raw)
        return t.isEmpty ? capabilityLine() : t
    }

    static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 600 { s = String(s.prefix(600)) }
        // Drop emails / obvious handles so autonomic stars never leak user data.
        if let r = try? NSRegularExpression(pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, options: .caseInsensitive) {
            s = r.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AshStarCard: Codable, Identifiable {
    var id: String
    var thought: String
    var color: String
    var from: String
    var uid: String
    var ts: Double
    var saved: Bool
    var when: String {
        let d = Date(timeIntervalSince1970: ts / 1000)
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
    init(thought: String, color: String, from: String, uid: String) {
        self.id = "as_\(Int(Date().timeIntervalSince1970 * 1000))"
        self.thought = String(thought.prefix(600))
        self.color = color
        self.from = from
        self.uid = uid
        self.ts = Date().timeIntervalSince1970 * 1000
        self.saved = false
    }
}

enum AshStarArchive {
    static let key = "_aut_ashstar_archive"
    static func load() -> [AshStarCard] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([AshStarCard].self, from: data) else { return [] }
        return arr
    }
    static func push(_ card: AshStarCard) {
        var all = load()
        all.insert(card, at: 0)
        if all.count > 100 { all = Array(all.prefix(100)) }
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
        NotificationCenter.default.post(name: .autumnAshStarArchived, object: nil)
    }
    static func markSaved(_ id: String) {
        var all = load()
        if let i = all.firstIndex(where: { $0.id == id }) { all[i].saved = true }
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }
}

extension Notification.Name {
    static let autumnAshStarArchived = Notification.Name("autumnAshStarArchived")
}
