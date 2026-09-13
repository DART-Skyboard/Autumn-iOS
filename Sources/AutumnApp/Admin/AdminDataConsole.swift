import SwiftUI
import AutumnServices
import LEATRCore

/// DATA console — port of `_admRenderData` / `_grantRole` / `_revokeRole`.
struct AdminDataConsole: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var circuit: AdminCircuitMonitor
    @State private var acl: [ACLUser] = []
    @State private var users: [AdminUserRow] = []
    @State private var aclStatus = "LOADING ACL…"
    @State private var userStatus = "LOADING USERS…"
    @State private var grantUser = ""
    @State private var grantRole = "engineer"
    @State private var grantExp = ""
    @State private var actionStatus = ""
    @State private var busy = false

    var body: some View {
        let chrome = themeVM.chrome
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    stat("USERS", "\(users.count)")
                    stat("ACL", "\(acl.count)")
                    stat("ACTIVE", "\(acl.filter(\.active).count)")
                }
                Text(circuit.status)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(circuit.allows(authVM) ? Color(hex: "#00ff88") : Color(hex: "#ffb347"))

                VStack(alignment: .leading, spacing: 6) {
                    Text("ROLE GRANT / REVOKE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(chrome.accent.opacity(0.55))
                    field("username", $grantUser)
                    field("role (e.g. engineer)", $grantRole)
                    field("expires ISO (optional)", $grantExp)
                    HStack {
                        Button("GRANT") { Task { await grant() } }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(chrome.accent)
                        Button("REVOKE") { Task { await revoke() } }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#ff7864"))
                        Spacer()
                    }
                    Text(actionStatus)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(chrome.accent.opacity(0.18), lineWidth: 1))

                Text("ACL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(chrome.accent.opacity(0.55))
                Text(aclStatus)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                ForEach(acl) { u in
                    HStack {
                        Text(u.username).foregroundColor(chrome.accent)
                        Text("· \(u.role) · \(u.active ? "active" : "revoked")")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                    }
                    .font(.system(size: 11, design: .monospaced))
                }

                Text("USERS · ashtree/users")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(chrome.accent.opacity(0.55))
                    .padding(.top, 6)
                Text(userStatus)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                ForEach(users) { r in
                    HStack {
                        Text(r.userId).foregroundColor(chrome.accent)
                        Spacer()
                        Text(r.cats.isEmpty ? "none" : r.cats.joined(separator: ", "))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
            }
            .padding(12)
        }
        .task { await reload() }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(themeVM.chrome.accent)
            Text(k).font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.4))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(themeVM.chrome.accent.opacity(0.16), lineWidth: 1))
    }

    private func field(_ p: String, _ t: Binding<String>) -> some View {
        TextField(p, text: t)
            .textFieldStyle(.plain).foregroundColor(.white)
            .font(.system(size: 12))
            .padding(8).background(themeVM.chrome.surface).cornerRadius(4)
    }

    private func reload() async {
        guard circuit.allows(authVM) else {
            acl = []; users = []
            aclStatus = "CIRCUIT OPEN — web admin must be live"
            userStatus = "Admin APIs no-op until circuit closed"
            return
        }
        busy = true
        let a = await AdminDataService.shared.loadACL()
        acl = a.users
        aclStatus = a.status
        let u = await AdminDataService.shared.loadUsers()
        users = u.rows
        userStatus = u.status
        busy = false
    }

    private func grant() async {
        guard circuit.allows(authVM) else { actionStatus = "CIRCUIT OPEN — write no-op"; return }
        let u = grantUser.trimmingCharacters(in: .whitespaces)
        let r = grantRole.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty, !r.isEmpty else { actionStatus = "Need username + role"; return }
        actionStatus = "Granting…"
        let exp = grantExp.trimmingCharacters(in: .whitespaces)
        actionStatus = await AdminDataService.shared.grant(
            username: u, role: r, expires: exp.isEmpty ? nil : exp, uid: authVM.githubUsername
        )
        await reload()
    }

    private func revoke() async {
        guard circuit.allows(authVM) else { actionStatus = "CIRCUIT OPEN — write no-op"; return }
        let u = grantUser.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty else { actionStatus = "Need username"; return }
        actionStatus = "Revoking…"
        actionStatus = await AdminDataService.shared.revoke(username: u, uid: authVM.githubUsername)
        await reload()
    }
}

/// Grammar Study first-train button — port of `runGrammarStudy`.
struct GrammarStudyButton: View {
    @Binding var adminLog: [String]
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var circuit: AdminCircuitMonitor
    @State private var status = "Grammar study — not trained. First run uses the button."
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await run() }
            } label: {
                Text(running ? "STUDY RUNNING…" : "▶ FIRST TRAIN · GRAMMAR STUDY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#00e5ff"))
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.cyan.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
            }
            .disabled(running)
            Text(status)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
        }
        .task {
            status = await GrammarStudy.shared.status()
        }
    }

    private func run() async {
        if running { return }
        running = true
        adminLog.append("Grammar study — starting…")
        do {
            try await GrammarStudy.shared.run { msg in
                Task { @MainActor in
                    status = msg
                    adminLog.append(msg)
                }
            }
            let roles = await GrammarStudy.shared.wordRoles
            await GrammarEngine.shared.applyStudyRoles(roles)
            status = await GrammarStudy.shared.status()
            adminLog.append(status)
            if circuit.allows(authVM) {
                let payload = await GrammarStudy.shared.packedPayload()
                let ok = await AutumnGASClient.shared.ashwriteReplace(
                    path: AutumnConfig.grammarStudyPath,
                    uid: authVM.githubUsername,
                    payload: payload,
                    message: "grammar study: train complete (ios)"
                )
                adminLog.append(ok ? "Wrote ashtree/grammar-study/index.json via GAS" : "Study trained locally — GAS write skipped/failed")
            } else {
                adminLog.append("Study trained locally — circuit open, ashwrite no-op")
            }
        } catch {
            status = error.localizedDescription
            adminLog.append("Grammar study error: \(error.localizedDescription)")
        }
        running = false
    }
}

// MARK: — Custom grammar prompt (persists like web ASH prompt field)

struct AdminGrammarPromptPanel: View {
    @Binding var adminLog: [String]
    @State private var prompt = ""
    @State private var status = ""
    @State private var crossRef = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CUSTOM GRAMMAR PROMPT")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
            TextEditor(text: $prompt)
                .frame(minHeight: 72, maxHeight: 120)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
                .cornerRadius(6)
            HStack {
                Button {
                    Task {
                        await GrammarStudy.shared.setCustomPrompt(prompt)
                        status = await GrammarStudy.shared.status()
                        adminLog.append(status)
                    }
                } label: {
                    Text("SAVE PROMPT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#00e5ff"))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.cyan.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
                }
                if !status.isEmpty {
                    Text(status)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }
            Text("CROSS-REF NOTE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
            TextField("e.g. aerospace ↔ script-reference-types/aerospace", text: $crossRef)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
            Button {
                let note = crossRef.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !note.isEmpty else { return }
                Task {
                    let ok = await GrammarStudy.shared.appendOptimize(
                        GrammarOptimizeNote(role: "cross_ref", token: String(note.prefix(24)), pos: "training_xref")
                    )
                    let msg = ok
                        ? "Cross-ref noted in grammar optimize: \(note)"
                        : "Cross-ref already present or token unsafe."
                    adminLog.append(msg)
                    UserDefaults.standard.set(note, forKey: "autumn_admin_training_xref_v1")
                    crossRef = ""
                }
            } label: {
                Text("ADD CROSS-REF")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#ffb347"))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.35), lineWidth: 1))
            }
        }
        .task {
            prompt = await GrammarStudy.shared.customPrompt
            crossRef = UserDefaults.standard.string(forKey: "autumn_admin_training_xref_v1") ?? ""
        }
    }
}

// MARK: — leatr-ash training branch catalogs (public raw)

struct AdminTrainingCatalogPanel: View {
    @Binding var adminLog: [String]
    @State private var section: Section = .grammarCategories
    @State private var selectedSlug: String?
    @State private var catalogPreview = ""
    @State private var loading = false
    @State private var error: String?

    enum Section: String, CaseIterable {
        case grammarCategories = "grammar-categories"
        case scriptRefs = "script-reference-types"
        var title: String {
            switch self {
            case .grammarCategories: return "GRAMMAR*"
            case .scriptRefs: return "SCRIPT REFS"
            }
        }
        var pathPrefix: String {
            switch self {
            case .grammarCategories: return "grammar-categories"
            case .scriptRefs: return "script-reference-types"
            }
        }
    }

    /// Curated slug lists from leatr-ash `training` branch (Training/README).
    private var slugs: [String] {
        switch section {
        case .grammarCategories:
            return [
                "advertising", "aerospace", "agility", "architecture", "art", "audio",
                "biology", "business", "chemistry", "economics", "emotion", "empathy",
                "engineering", "fiction", "film", "gaming", "geology", "law", "llm",
                "math", "music", "mythology", "nature", "nonfiction", "poetry",
                "psychology", "science", "security", "sociology", "technology", "travel"
            ]
        case .scriptRefs:
            return [
                "aerospace", "animation", "apple", "ar", "architecture", "art", "audio", "aviation"
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRAINING · leatr-ash/training")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
            HStack(spacing: 6) {
                ForEach(Section.allCases, id: \.rawValue) { s in
                    Button {
                        section = s
                        selectedSlug = nil
                        catalogPreview = ""
                        error = nil
                    } label: {
                        Text(s.title)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(section == s ? Color(hex: "#00e5ff") : .white.opacity(0.45))
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(section == s ? Color.cyan.opacity(0.1) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cyan.opacity(section == s ? 0.4 : 0.15), lineWidth: 1))
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(slugs, id: \.self) { slug in
                        Button {
                            Task { await loadCatalog(slug) }
                        } label: {
                            Text(slug)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(selectedSlug == slug ? .black : .white.opacity(0.8))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(selectedSlug == slug ? Color(hex: "#00e5ff") : Color.white.opacity(0.08))
                                .cornerRadius(4)
                        }
                        .disabled(loading)
                    }
                }
            }
            if loading {
                Text("Loading catalog…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            if let error {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "#ff6688"))
            }
            if !catalogPreview.isEmpty {
                Text(catalogPreview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
            }
            Text("Catalogs are public refs on branch training — workers seed ≥20 open-license refs per topic.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private func loadCatalog(_ slug: String) async {
        loading = true
        error = nil
        selectedSlug = slug
        catalogPreview = ""
        let urlStr = "\(AutumnConfig.trainingRawBase)/\(section.pathPrefix)/\(slug)/refs/catalog.json"
        guard let url = URL(string: urlStr) else {
            error = "Bad catalog URL"
            loading = false
            return
        }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                error = "HTTP \(code) for \(slug)"
                loading = false
                return
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                error = "Invalid JSON"
                loading = false
                return
            }
            let meta = obj["_meta"] as? [String: Any] ?? [:]
            let refs = obj["refs"] as? [[String: Any]] ?? []
            let topic = meta["topic"] as? String ?? slug
            let count = meta["ref_count"] as? Int ?? refs.count
            let sources = (meta["sources"] as? [String])?.joined(separator: ", ") ?? "—"
            var lines = ["\(topic) · \(count) refs · \(sources)"]
            for r in refs.prefix(6) {
                let title = r["title"] as? String ?? "?"
                let license = r["license"] as? String ?? ""
                lines.append("• \(title) (\(license))")
            }
            if refs.count > 6 { lines.append("… +\(refs.count - 6) more") }
            catalogPreview = lines.joined(separator: "\n")
            adminLog.append("Training catalog loaded: \(section.pathPrefix)/\(slug) (\(count) refs)")
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
