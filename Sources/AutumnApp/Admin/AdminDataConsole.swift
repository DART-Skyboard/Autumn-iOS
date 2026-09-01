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
