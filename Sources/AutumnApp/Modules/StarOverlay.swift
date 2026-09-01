import SwiftUI
import AutumnServices
import LEATRCore

/// Ash Star archive drawer. Sending spawns 3D geometry on the orb — never a chat card.
public struct StarOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var sceneVM: BRPNSceneViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @State private var cards: [AshStarCard] = AshStarArchive.load()
    @State private var thought = ""
    @State private var status = ""

    public var body: some View {
        OverlayPanel(title: "ASH STAR ARCHIVE", onClose: { appNav.rightTab = .none }) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stars live on the BRPN orb. This drawer is the archive — not a chat card.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                TextField("thought for this star", text: $thought)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(themeVM.chrome.surface)
                    .cornerRadius(6)
                HStack {
                    Button("⬡ SEND STAR") {
                        let t = thought.trimmingCharacters(in: .whitespacesAndNewlines)
                        sceneVM.spawnAshStar()
                        sceneVM.emitMist(fromLocal: true)
                        let card = AshStarCard(thought: t.isEmpty ? chatVM.messages.last(where: { !$0.isInternal })?.content ?? "ash star" : t,
                                               color: "#ffdd00", from: "autumn", uid: authVM.sessionUID)
                        AshStarArchive.push(card)
                        cards = AshStarArchive.load()
                        thought = ""
                        status = "SPAWNED ON ORB"
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#ffdd00"))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color(hex: "#ffdd00").opacity(0.12))
                    .clipShape(Capsule())
                    Spacer()
                    Button("⬡ SAVE ALL") {
                        Task { await saveAll() }
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#ffdd00"))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .overlay(Capsule().stroke(Color(hex: "#ffdd00").opacity(0.4), lineWidth: 1))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if cards.isEmpty {
                            Text("NO STARS THIS SESSION")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        ForEach(cards) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Circle().fill(Color(hex: c.color)).frame(width: 8, height: 8)
                                    Text("ASH STAR").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(themeVM.chrome.accent)
                                    Spacer()
                                    Text(c.when).font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                                }
                                Text(c.thought).font(.system(size: 12)).foregroundColor(.white.opacity(0.85)).lineLimit(4)
                                if !c.saved {
                                    Button("⬡ SAVE") {
                                        Task {
                                            await AutumnGASClient.shared.writeJournal(
                                                uid: authVM.sessionUID,
                                                thought: c.thought,
                                                reply: "[ash star]",
                                                emotion: "inspiring",
                                                buoyancy: 0.8
                                            )
                                            AshStarArchive.markSaved(c.id)
                                            cards = AshStarArchive.load()
                                            status = "SAVED VIA GAS"
                                        }
                                    }
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(themeVM.chrome.accent)
                                }
                            }
                            .padding(8)
                            .background(themeVM.chrome.accent.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: 220)
                Text(status).font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.chrome.accent.opacity(0.5))
            }
            .padding(12)
        }
    }

    private func saveAll() async {
        let unsaved = cards.filter { !$0.saved }
        guard !unsaved.isEmpty else { status = "NOTHING TO SAVE"; return }
        for c in unsaved {
            await AutumnGASClient.shared.writeJournal(
                uid: authVM.sessionUID,
                thought: c.thought,
                reply: "[ash star]",
                emotion: "inspiring",
                buoyancy: 0.8
            )
            AshStarArchive.markSaved(c.id)
        }
        cards = AshStarArchive.load()
        status = "SAVED ALL \(unsaved.count) VIA GAS"
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
    }
    static func markSaved(_ id: String) {
        var all = load()
        if let i = all.firstIndex(where: { $0.id == id }) { all[i].saved = true }
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }
}
