import SwiftUI
import AutumnServices

/// SYSTEM BROADCAST — public read of system-broadcast.json; compose via GAS for dartsolarpunk.
public struct SYSOverlay: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var circuit: AdminCircuitMonitor
    @State private var message = "LOADING…"
    @State private var updated = ""
    @State private var author = ""
    @State private var draft = ""
    @State private var status = ""
    @State private var showCompose = false
    @State private var live = false

    private let def = "No system updates today."

    public var body: some View {
        OverlayPanel(title: "SYSTEM MESSAGE", onClose: { appNav.rightTab = .none }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(updated.isEmpty ? "NO ACTIVE BROADCAST" : updated)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.chrome.accent.opacity(0.45))
                ScrollView {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(live ? .white.opacity(0.9) : .white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)

                if circuit.allows(authVM) {
                    Button("⚡ COMPOSE") { showCompose = true; draft = live ? message : "" }
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

    private var compose: some View {
        NavigationStack {
            ZStack {
                themeVM.chrome.base.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Post a system message to all sessions. Writes via GAS ashwrite — no PAT.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    TextEditor(text: $draft)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(themeVM.chrome.surface)
                        .cornerRadius(8)
                        .foregroundColor(.white)
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
    }

    private func post(clear: Bool = false) async {
        guard circuit.allows(authVM) else { status = "CIRCUIT OPEN — write no-op"; return }
        let msg = clear ? def : draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty || clear else { status = "Message cannot be empty"; return }
        status = "SAVING…"
        let payload: [String: Any] = [
            "message": msg,
            "updated": ISO8601DateFormatter().string(from: Date()),
            "author": "dartsolarpunk"
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
