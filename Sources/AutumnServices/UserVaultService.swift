import Foundation

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
            "journal", "memory", "projects", "exports",
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
    private func setupGitHubVault(username: String) async {
        let repoName = "Autumn-Ash"
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
    public func write(
        folder: VaultFolder,
        filename: String,
        content: String,
        githubUsername: String? = nil
    ) async {
        if let root = _vaultURL {
            let url = root
                .appendingPathComponent(folder.path)
                .appendingPathComponent(filename)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        if let gh = githubUsername, !gh.isEmpty {
            let path = "\(folder.path)/\(filename)"
            let sha = (try? await github.readFile(
                owner: gh, repo: "Autumn-Ash", path: path))?.sha
            try? await github.writeFile(
                owner: gh, repo: "Autumn-Ash",
                path: path, content: content,
                message: "sync: \(filename)", sha: sha
            )
        }
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
        case .arcModels:   return "ArcLake Models"
        case .arcSessions: return "ArcLake Sessions"
        case .arcExports:  return "ArcLake Exports"
        }
    }
}
