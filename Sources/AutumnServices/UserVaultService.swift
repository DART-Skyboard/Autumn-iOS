import Foundation
import LEATRCore

// MARK: — UserVaultService
// Shared vault service used by both Autumn and ArcLake.
// Creates/manages the Autumn-Ash folder in iCloud Drive (visible in Files app)
// and mirrors to a private GitHub repo if connected.
//
// iCloud Drive structure:
//   Autumn-Ash/
//     journal/        — Autumn journal entries
//     memory/         — Autumn chat memory chunks
//     projects/       — Autumn projects
//     exports/        — Autumn exports
//     ash-shard/      — Autumn LEATR/grammar backup shards
//     ArcLake/        — ArcLake subfolder
//       models/       — exported GLB / 3D model files
//       sessions/     — saved molecular sessions
//       exports/      — ArcLake manual exports

public actor UserVaultService {
    public static let shared = UserVaultService()

    private let containerID = "iCloud.com.dartmeadow.autumn"
    private let vaultName   = "Autumn-Ash"
    private let github      = GitHubClient.shared

    private var _vaultURL: URL?
    public var vaultURL: URL? { _vaultURL }

    // MARK: — Setup (call on every sign-in from either app)
    public func setup(githubUsername: String?) async {
        await setupiCloudVault()
        if let gh = githubUsername, !gh.isEmpty {
            await setupGitHubVault(username: gh)
        }
    }

    // MARK: — iCloud Drive vault
    private func setupiCloudVault() async {
        if let root = iCloudVaultURL() {
            _vaultURL = root
            createAllSubfolders(at: root)
            print("[UserVault] iCloud vault ready: \(root.path)")
        } else {
            print("[UserVault] iCloud unavailable — using local Documents")
            await setupLocalVault()
        }
    }

    private func iCloudVaultURL() -> URL? {
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: containerID
        ) else { return nil }
        let vault = container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(vaultName, isDirectory: true)
        return vault
    }

    private func setupLocalVault() async {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first else { return }
        let vault = docs.appendingPathComponent(vaultName, isDirectory: true)
        _vaultURL = vault
        createAllSubfolders(at: vault)
    }

    private func createAllSubfolders(at root: URL) {
        let fm = FileManager.default
        let folders = [
            "journal", "memory", "projects", "exports", "ash-shard", "math",
            "ArcLake", "ArcLake/models", "ArcLake/sessions", "ArcLake/exports"
        ]
        for sub in folders {
            let url = root.appendingPathComponent(sub, isDirectory: true)
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: — GitHub vault mirror
    public static func repoName(for username: String) -> String {
        "Autumn-Ash-\(username)"
    }

    /// Read a vault file from the user's private Autumn-Ash-{username} repo.
    public func readRemote(folder: VaultFolder, filename: String, githubUsername: String) async -> String? {
        let repo = Self.repoName(for: githubUsername)
        guard let file = try? await github.readFile(owner: githubUsername, repo: repo, path: "\(folder.path)/\(filename)"),
              let text = file.decodedContent
        else { return nil }
        return text
    }

    @discardableResult
    public func saveMemorySnapshot(username: String, json: String) async -> Bool {
        await write(folder: .memory, filename: "chunk_001.json", content: json, githubUsername: username)
    }

    /// Load memory/chunk_001.json from Autumn-Ash-{username} as a JSON object.
    public func loadMemorySnapshot(username: String) async -> [String: Any]? {
        guard let json = await readRemote(folder: .memory, filename: "chunk_001.json", githubUsername: username),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    /// Merge `settings` into the existing memory snapshot (create minimal stub if missing).
    @discardableResult
    public func mergeSettingsIntoSnapshot(username: String, settings: [String: Any]) async -> Bool {
        var payload = await loadMemorySnapshot(username: username) ?? [
            "version": "2.2",
            "username": username,
            "platform": "ios",
            "sessions": [] as [[String: Any]]
        ]
        payload["settings"] = settings
        payload["saved"] = ISO8601DateFormatter().string(from: Date())
        payload["platform"] = payload["platform"] ?? "ios"
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return false }
        return await saveMemorySnapshot(username: username, json: json)
    }

    public func saveMathSnapshot(username: String, json: String) async {
        await write(folder: .math, filename: "session.json", content: json, githubUsername: username)
        let note = """
        {
          "selfOptimize": true,
          "source": "ios-math",
          "saved": "\(ISO8601DateFormatter().string(from: Date()))"
        }
        """
        await write(folder: .math, filename: "notes.json", content: note, githubUsername: username)
    }

    private func setupGitHubVault(username: String) async {
        let repoName = Self.repoName(for: username)
        do {
            let repos = try await github.listRepos()
            if !repos.contains(where: { $0.name == repoName }) {
                _ = try await github.createRepo(
                    name: repoName, isPrivate: true,
                    description: "Personal Autumn-Ash vault — synced from Autumn & ArcLake iOS"
                )
                let seedPaths = [
                    "journal/.gitkeep", "memory/.gitkeep",
                    "projects/.gitkeep", "exports/.gitkeep",
                    "ash-shard/.gitkeep",
                    "math/.gitkeep",
                    "ash-memory/README.md",
                    "ArcLake/models/.gitkeep",
                    "ArcLake/sessions/.gitkeep",
                    "ArcLake/exports/.gitkeep"
                ]
                for path in seedPaths {
                    try? await github.writeFile(
                        owner: username, repo: repoName,
                        path: path, content: "",
                        message: "init: vault structure"
                    )
                }
                print("[UserVault] GitHub repo \(username)/\(repoName) created")
            }
        } catch {
            print("[UserVault] GitHub vault setup error: \(error)")
        }
    }

    // MARK: — Write (iCloud + GitHub mirror)
    @discardableResult
    public func write(
        folder: VaultFolder,
        filename: String,
        content: String,
        githubUsername: String? = nil
    ) async -> Bool {
        var wroteLocal = false
        if let root = _vaultURL {
            let url = root
                .appendingPathComponent(folder.path)
                .appendingPathComponent(filename)
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                wroteLocal = true
            } catch {
                print("[UserVault] local write failed: \(error)")
            }
        }
        var wroteRemote = false
        if let gh = githubUsername, !gh.isEmpty {
            let repo = Self.repoName(for: gh)
            let path = "\(folder.path)/\(filename)"
            let sha = (try? await github.readFile(
                owner: gh, repo: repo, path: path))?.sha
            do {
                try await github.writeFile(
                    owner: gh, repo: repo,
                    path: path, content: content,
                    message: "sync: \(filename)", sha: sha
                )
                wroteRemote = true
            } catch {
                print("[UserVault] GitHub write failed: \(error)")
            }
        }
        // Success if we mirrored to GitHub, or at least wrote locally when no GH user.
        if let gh = githubUsername, !gh.isEmpty { return wroteRemote || wroteLocal }
        return wroteLocal
    }

    // MARK: — Write Data (for binary files like GLB exports)
    public func writeData(
        folder: VaultFolder,
        filename: String,
        data: Data
    ) async {
        guard let root = _vaultURL else { return }
        let url = root
            .appendingPathComponent(folder.path)
            .appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: — Read
    public func read(folder: VaultFolder, filename: String) -> String? {
        guard let root = _vaultURL else { return nil }
        let url = root
            .appendingPathComponent(folder.path)
            .appendingPathComponent(filename)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: — List files
    public func list(folder: VaultFolder) -> [String] {
        guard let root = _vaultURL else { return [] }
        let url = root.appendingPathComponent(folder.path)
        return (try? FileManager.default
            .contentsOfDirectory(atPath: url.path)
            .filter { !$0.hasPrefix(".") }) ?? []
    }

    // MARK: — Export URL (for UIDocumentPickerViewController)
    // Default save location for exports — opens directly to this folder
    public func exportFolderURL(for folder: VaultFolder) -> URL? {
        guard let root = _vaultURL else { return nil }
        return root.appendingPathComponent(folder.path)
    }
}

// MARK: — Vault folders
public enum VaultFolder: String, CaseIterable {
    // Autumn folders
    case journal    = "journal"
    case memory     = "memory"
    case projects   = "projects"
    case exports    = "exports"
    case shard      = "ash-shard"
    case math       = "math"
    // ArcLake folders
    case arcModels  = "ArcLake/models"
    case arcSessions = "ArcLake/sessions"
    case arcExports = "ArcLake/exports"

    public var path: String { rawValue }

    public var displayName: String {
        switch self {
        case .journal:     return "Journal"
        case .memory:      return "Memory"
        case .projects:    return "Projects"
        case .exports:     return "Exports"
        case .shard:       return "Ash Shard"
        case .math:        return "Math"
        case .arcModels:   return "ArcLake Models"
        case .arcSessions: return "ArcLake Sessions"
        case .arcExports:  return "ArcLake Exports"
        }
    }
}


/// Web `_autosave` / `_ensureUserRepo` / `_ghAutosaveNow` — snapshot into Autumn-Ash-{username},
/// plus Autumn LEATR backup + grammar self-optimize (one-shot Save Data).
public enum AutumnMemorySync {
    public enum SaveError: LocalizedError {
        case notSignedIn
        case invalidPayload
        case vaultWriteFailed

        public var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Connect GitHub to save data to your Autumn-Ash vault."
            case .invalidPayload:
                return "Could not build memory snapshot."
            case .vaultWriteFailed:
                return "Vault write failed — check GitHub connection and try again."
            }
        }
    }

    /// Legacy entry — returns status string for UI toasts.
    @MainActor
    @discardableResult
    public static func saveNow(username: String, sessionUID: String, messages: [ChatMessage] = [], mathJSON: String? = nil) async -> Result<String, Error> {
        await saveAllNow(username: username, sessionUID: sessionUID, messages: messages, mathJSON: mathJSON)
    }

    /// One-shot Save Data pipeline (match web intent):
    /// 1) User vault/memory snapshot → Autumn-Ash-{username} (includes math session)
    /// 2) Backup Autumn LEATR / grammar-study / optimize notes (local vault + GAS ashwrite best-effort)
    /// 3) Analyze recent chat sentences for self-optimizations (no admin required)
    @MainActor
    @discardableResult
    public static func saveAllNow(username: String, sessionUID: String, messages: [ChatMessage] = [], mathJSON: String? = nil) async -> Result<String, Error> {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty,
              user.lowercased() != "guest",
              !user.hasPrefix("ios-"),
              !user.hasPrefix("apple-") else {
            return .failure(SaveError.notSignedIn)
        }

        await UserVaultService.shared.setup(githubUsername: user)

        let mathPayload: String? = mathJSON ?? {
            let snap = MathWorkspaceHolder.current.snapshot()
            guard let data = try? JSONEncoder().encode(snap) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        // ── 1) User memory snapshot (web `_autosave` / `_ghAutosaveNow`) ──
        let publicMsgs = messages.filter { !$0.isInternal }.suffix(200)
        var payload: [String: Any] = [
            "version": "2.2",
            "username": user,
            "saved": ISO8601DateFormatter().string(from: Date()),
            "platform": "ios",
            "manual_save": true,
            "sid": sessionUID,
            "hasMath": mathPayload != nil,
            "sessions": [[
                "id": sessionUID,
                "messages": publicMsgs.map { ["role": $0.role.rawValue, "content": $0.content] as [String: String] }
            ]],
            "settings": AutumnSettingsSync.captureCurrent()
        ]
        if let mathPayload, let mathData = mathPayload.data(using: .utf8),
           let mathObj = try? JSONSerialization.jsonObject(with: mathData) {
            payload["math"] = mathObj
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return .failure(SaveError.invalidPayload)
        }
        let vaultOK = await UserVaultService.shared.saveMemorySnapshot(username: user, json: json)
        guard vaultOK else {
            return .failure(SaveError.vaultWriteFailed)
        }
        if let mathPayload {
            await UserVaultService.shared.saveMathSnapshot(username: user, json: mathPayload)
        }

        // ── 3) Self-optimize from recent user sentences (before packing backup) ──
        let userTexts = messages
            .filter { !$0.isInternal && $0.role == .user }
            .map(\.content)
        var optimizeCount = await GrammarStudy.shared.optimizeFromSentences(userTexts)
        let mathNotes = MathWorkspaceHolder.current.notes.map(\.prompt)
        if !mathNotes.isEmpty {
            optimizeCount += await GrammarStudy.shared.optimizeFromSentences(mathNotes)
        }

        // ── 2) Autumn LEATR / grammar-study / optimize backup ──
        let study = await GrammarStudy.shared.packedPayload()
        let optimize = await GrammarStudy.shared.packedOptimizePayload()
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        var autumnBackup: [String: Any] = [
            "version": "1.0",
            "kind": "autumn_leatr_backup",
            "saved": ISO8601DateFormatter().string(from: Date()),
            "platform": "ios",
            "sid": sessionUID,
            "username": user,
            "grammarStudy": study,
            "optimize": optimize,
            "selfmodel": [
                "notes": "iOS Save Data backup of Autumn LEATR/grammar-study/math state.",
                "optimizeCount": optimizeCount,
                "updated": ISO8601DateFormatter().string(from: Date())
            ] as [String: Any]
        ]
        if let mathPayload, let mathData = mathPayload.data(using: .utf8),
           let mathObj = try? JSONSerialization.jsonObject(with: mathData) {
            autumnBackup["math"] = mathObj
        }
        if JSONSerialization.isValidJSONObject(autumnBackup),
           let bakData = try? JSONSerialization.data(withJSONObject: autumnBackup, options: [.sortedKeys]),
           let bakJSON = String(data: bakData, encoding: .utf8) {
            _ = await UserVaultService.shared.write(
                folder: .shard,
                filename: "autumn-backup-\(stamp).json",
                content: bakJSON,
                githubUsername: user
            )
            _ = await UserVaultService.shared.write(
                folder: .shard,
                filename: "autumn-leatr-latest.json",
                content: bakJSON,
                githubUsername: user
            )
        }

        // Best-effort ashwrite to leatr-ash (same paths web uses). May no-op without circuit/PAT proxy.
        var ashBits: [String] = []
        let studyOK = await AutumnGASClient.shared.ashwriteReplace(
            path: AutumnConfig.grammarStudyPath,
            uid: user,
            payload: study,
            message: "grammar study: ios save-data backup"
        )
        if studyOK { ashBits.append("grammar-study") }
        let optOK = await AutumnGASClient.shared.ashwriteReplace(
            path: AutumnConfig.grammarOptimizePath,
            uid: user,
            payload: optimize,
            message: "grammar study: ios optimize notes"
        )
        if optOK { ashBits.append("optimize") }
        let selfOK = await AutumnGASClient.shared.ashwriteReplace(
            path: AutumnConfig.selfModelPath,
            uid: user,
            payload: [
                "platform": "ios",
                "updated": ISO8601DateFormatter().string(from: Date()),
                "optimizeCount": optimizeCount,
                "sid": sessionUID,
                "hasMath": mathPayload != nil
            ] as [String: Any],
            message: "sentient: ios selfmodel save-data"
        )
        if selfOK { ashBits.append("selfmodel") }

        var parts = ["Data saved"]
        if mathPayload != nil { parts.append("math snapshot") }
        if optimizeCount > 0 {
            parts.append("\(optimizeCount) self-optimize note\(optimizeCount == 1 ? "" : "s")")
        }
        if !ashBits.isEmpty {
            parts.append("ash:\(ashBits.joined(separator: "+"))")
        } else {
            parts.append("Autumn backup in vault")
        }
        return .success(parts.joined(separator: " · "))
    }
}

// MARK: — Theme / Profile settings ↔ private Autumn-Ash vault
/// Mirrors web localStorage theme/scrim into memory snapshot `settings` and restores on sign-in.
public enum AutumnSettingsSync {
    public static let themeKey = "_aut_theme"
    public static let scrimKey = "_aut_scrim"
    public static let adminKey = "_aut_admin_enabled"
    public static let liveFeedKey = "autumn_live_feed"
    public static let ttsVoiceKey = "_aut_tts_voice"
    public static let ttsRateKey = "_aut_tts_rate"
    public static let ttsPitchKey = "_aut_tts_pitch"

    public static let didRestoreNotification = Notification.Name("AutumnSettingsDidRestore")
    public static let localChangeNotification = Notification.Name("AutumnSettingsLocalChange")

    private static var dirty = false
    private static var debounceTask: Task<Void, Never>?

    /// Snapshot of Profile/Settings prefs for vault JSON under `settings`.
    @MainActor
    public static func captureCurrent() -> [String: Any] {
        var s: [String: Any] = [:]
        if let t = UserDefaults.standard.string(forKey: themeKey) {
            s["theme"] = t
        }
        s["scrim"] = UserDefaults.standard.integer(forKey: scrimKey)
        if let admin = UserDefaults.standard.string(forKey: adminKey) {
            s["adminEnabled"] = admin
        } else if UserDefaults.standard.object(forKey: adminKey) != nil {
            s["adminEnabled"] = UserDefaults.standard.bool(forKey: adminKey) ? "1" : "0"
        }
        if UserDefaults.standard.object(forKey: liveFeedKey) != nil {
            s["liveFeed"] = UserDefaults.standard.bool(forKey: liveFeedKey)
        }
        if let v = UserDefaults.standard.string(forKey: ttsVoiceKey) {
            s["ttsVoice"] = v
        }
        if UserDefaults.standard.object(forKey: ttsRateKey) != nil {
            s["ttsRate"] = UserDefaults.standard.float(forKey: ttsRateKey)
        }
        if UserDefaults.standard.object(forKey: ttsPitchKey) != nil {
            s["ttsPitch"] = UserDefaults.standard.float(forKey: ttsPitchKey)
        }
        return s
    }

    /// Last-saved vault settings win on load — write into UserDefaults then notify UI.
    @MainActor
    public static func applyFromVault(_ settings: [String: Any]) {
        if let theme = settings["theme"] as? String, !theme.isEmpty {
            UserDefaults.standard.set(theme, forKey: themeKey)
        }
        if let scrim = settings["scrim"] as? Int {
            UserDefaults.standard.set(scrim, forKey: scrimKey)
        } else if let scrim = settings["scrim"] as? NSNumber {
            UserDefaults.standard.set(scrim.intValue, forKey: scrimKey)
        }
        if let admin = settings["adminEnabled"] as? String {
            UserDefaults.standard.set(admin, forKey: adminKey)
        } else if let admin = settings["adminEnabled"] as? Bool {
            UserDefaults.standard.set(admin ? "1" : "0", forKey: adminKey)
        }
        if let live = settings["liveFeed"] as? Bool {
            UserDefaults.standard.set(live, forKey: liveFeedKey)
        }
        if let v = settings["ttsVoice"] as? String {
            UserDefaults.standard.set(v, forKey: ttsVoiceKey)
        }
        if let r = settings["ttsRate"] as? Float {
            UserDefaults.standard.set(r, forKey: ttsRateKey)
        } else if let r = settings["ttsRate"] as? Double {
            UserDefaults.standard.set(Float(r), forKey: ttsRateKey)
        } else if let r = settings["ttsRate"] as? NSNumber {
            UserDefaults.standard.set(r.floatValue, forKey: ttsRateKey)
        }
        if let r = settings["ttsPitch"] as? Float {
            UserDefaults.standard.set(r, forKey: ttsPitchKey)
        } else if let r = settings["ttsPitch"] as? Double {
            UserDefaults.standard.set(Float(r), forKey: ttsPitchKey)
        } else if let r = settings["ttsPitch"] as? NSNumber {
            UserDefaults.standard.set(r.floatValue, forKey: ttsPitchKey)
        }
        NotificationCenter.default.post(name: didRestoreNotification, object: nil)
    }

    /// Mark local prefs dirty and notify listeners (AutumnApp schedules vault write).
    @MainActor
    public static func noteLocalChange() {
        dirty = true
        NotificationCenter.default.post(name: localChangeNotification, object: nil)
    }

    /// Debounced write of current settings into Autumn-Ash-{username} memory snapshot.
    @MainActor
    public static func scheduleDebouncedVaultWrite(username: String?) {
        let user = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else {
            dirty = true
            return
        }
        dirty = true
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await flushToVault(username: user)
        }
    }

    @MainActor
    public static func flushToVault(username: String) async {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { return }
        let settings = captureCurrent()
        let ok = await UserVaultService.shared.mergeSettingsIntoSnapshot(username: user, settings: settings)
        if ok { dirty = false }
    }

    /// On GitHub connect / vault load: restore settings from snapshot if present, else keep UserDefaults;
    /// then push current (possibly restored) settings back so the vault stays warm.
    @MainActor
    public static func restoreFromVaultThenPush(username: String) async {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty,
              user.lowercased() != "guest",
              !user.hasPrefix("ios-"),
              !user.hasPrefix("apple-") else { return }
        await UserVaultService.shared.setup(githubUsername: user)
        if let snap = await UserVaultService.shared.loadMemorySnapshot(username: user),
           let settings = snap["settings"] as? [String: Any], !settings.isEmpty {
            applyFromVault(settings)
        }
        await flushToVault(username: user)
    }
}
