import Foundation

/// Admin DATA console — port of index.html `_admRenderData` / `_grantRole` / `_revokeRole`.
/// Reads ACL via GAS then GitHub. Users from `ashtree/users`. No PAT in the client.
public struct ACLUser: Identifiable, Sendable, Hashable {
    public var id: String { username }
    public var username: String
    public var role: String
    public var active: Bool
    public var grantedBy: String
    public var grantedAt: String
    public var expires: String?
}

public struct AdminUserRow: Identifiable, Sendable, Hashable {
    public var id: String { userId }
    public var userId: String
    public var cats: [String]
    public var updated: String
    public var registered: String
}

public actor AdminDataService {
    public static let shared = AdminDataService()

    public func loadACL() async -> (users: [ACLUser], status: String) {
        if let parsed = await readACLViaGAS() {
            return (parsed, "ACL via GAS · \(parsed.count) roles")
        }
        do {
            let any = try await GitHubClient.shared.readJSON(
                owner: AutumnConfig.ashOwner, repo: AutumnConfig.ashRepo, path: AutumnConfig.aclPath
            )
            let users = Self.parseACL(any)
            return (users, "ACL via GitHub · \(users.count) roles")
        } catch {
            return ([], "ACL unavailable — \(error.localizedDescription)")
        }
    }

    public func loadUsers() async -> (rows: [AdminUserRow], status: String) {
        do {
            let entries = try await GitHubClient.shared.listDirectory(
                owner: AutumnConfig.ashOwner, repo: AutumnConfig.ashRepo, path: AutumnConfig.usersPrefix
            )
            if entries.isEmpty {
                return ([], "No users found yet. (Empty or Access Denied — GitHub login required.)")
            }
            var rows: [AdminUserRow] = []
            for e in entries where e.type == "dir" {
                rows.append(AdminUserRow(userId: e.name, cats: [], updated: "--", registered: "dir"))
            }
            return (rows, "\(rows.count) users in ashtree/users")
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("403") || msg.lowercased().contains("401") || msg.lowercased().contains("bad credential") {
                return ([], "Access Denied — sign in with GitHub as dartsolarpunk.")
            }
            return ([], "No user data available. \(msg)")
        }
    }

    public func grant(username: String, role: String, expires: String?, uid: String) async -> String {
        guard await AdminCircuitStore.shared.allows(username: uid, githubConnected: true, adminEnabled: true) else {
            return "CIRCUIT OPEN — write no-op"
        }
        var (users, _) = await loadACL()
        let rec = ACLUser(
            username: username,
            role: role,
            active: true,
            grantedBy: uid,
            grantedAt: ISO8601DateFormatter().string(from: Date()),
            expires: expires
        )
        if let i = users.firstIndex(where: { $0.username.lowercased() == username.lowercased() }) {
            users[i] = rec
        } else {
            users.append(rec)
        }
        return await writeACL(users, uid: uid, message: "acl: grant \(role) to \(username)")
    }

    public func revoke(username: String, uid: String) async -> String {
        guard await AdminCircuitStore.shared.allows(username: uid, githubConnected: true, adminEnabled: true) else {
            return "CIRCUIT OPEN — write no-op"
        }
        var (users, _) = await loadACL()
        if let i = users.firstIndex(where: { $0.username.lowercased() == username.lowercased() }) {
            users[i].active = false
        } else {
            return "Need an existing ACL user"
        }
        return await writeACL(users, uid: uid, message: "acl: revoke \(username)")
    }

    private func writeACL(_ users: [ACLUser], uid: String, message: String) async -> String {
        let payload: [String: Any] = [
            "users": Dictionary(uniqueKeysWithValues: users.map { u in
                (u.username, [
                    "role": u.role,
                    "granted_by": u.grantedBy,
                    "granted_at": u.grantedAt,
                    "expires": u.expires as Any,
                    "active": u.active
                ] as [String: Any])
            }),
            "updated": ISO8601DateFormatter().string(from: Date())
        ]
        let ok = await AutumnGASClient.shared.ashwriteReplace(
            path: AutumnConfig.aclPath, uid: uid, payload: payload, message: message
        )
        if ok { return "Wrote ACL via GAS" }
        do {
            let json = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            let content = String(data: json, encoding: .utf8) ?? "{}"
            let sha = (try? await GitHubClient.shared.readFile(
                owner: AutumnConfig.ashOwner, repo: AutumnConfig.ashRepo, path: AutumnConfig.aclPath
            ))?.sha
            try await GitHubClient.shared.writeFile(
                owner: AutumnConfig.ashOwner, repo: AutumnConfig.ashRepo,
                path: AutumnConfig.aclPath, content: content, message: message, sha: sha
            )
            return "Wrote ACL via GitHub"
        } catch {
            return "ACL write failed — \(error.localizedDescription)"
        }
    }

    private func readACLViaGAS() async -> [ACLUser]? {
        guard let any = await AutumnGASClient.shared.ashread(path: AutumnConfig.aclPath) else { return nil }
        let parsed = Self.parseACL(any)
        return parsed.isEmpty ? nil : parsed
    }

    static func parseACL(_ any: Any) -> [ACLUser] {
        var root: [String: Any]?
        if let d = any as? [String: Any] {
            if let users = d["users"] as? [String: Any] {
                root = d
                _ = users
            } else if let payload = d["payload"] as? [String: Any] {
                root = payload
            } else if let data = d["data"] as? [String: Any] {
                root = data
            } else if let content = d["content"] as? String {
                let cleaned = content.replacingOccurrences(of: "\n", with: "")
                if let decoded = Data(base64Encoded: cleaned),
                   let obj = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] {
                    root = obj
                } else if let data = content.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    root = obj
                }
            }
        }
        guard let users = root?["users"] as? [String: Any] else { return [] }
        return users.keys.sorted().compactMap { name in
            guard let rec = users[name] as? [String: Any] else { return nil }
            let active: Bool
            if let b = rec["active"] as? Bool { active = b }
            else if let s = rec["active"] as? String { active = s != "false" }
            else { active = true }
            return ACLUser(
                username: name,
                role: rec["role"] as? String ?? "?",
                active: active,
                grantedBy: rec["granted_by"] as? String ?? "",
                grantedAt: rec["granted_at"] as? String ?? "",
                expires: rec["expires"] as? String
            )
        }
    }
}
