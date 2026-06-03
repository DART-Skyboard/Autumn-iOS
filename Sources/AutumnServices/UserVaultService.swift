import Foundation

// MARK: — UserVaultService
// Manages the user's personal "Autumn-Ash" folder in iCloud Drive.
// On first sign-in this folder is created automatically and shows up
// in the Files app under iCloud Drive > Autumn-Ash.
// If GitHub is connected the same structure is mirrored to a private
// {username}/Autumn-Ash repo and kept in sync.
//
// Folder structure:
//   Autumn-Ash/
//     journal/        — personal journal entries (.json)
//     memory/         — rolling chat memory chunks (.txt)
//     projects/       — user project files
//     exports/        — manual exports land here

public actor UserVaultService {
    public static let shared = UserVaultService()

    private let folderName = "Autumn-Ash"
    private let github = GitHubClient.shared

    // Cached iCloud root URL
    private var _vaultURL: URL?

    // MARK: — Setup (call on every sign-in)
    public func setup(githubUsername: String?) async {
        await setupiCloudVault()
        if let gh = githubUsername, !gh.isEmpty {
            await setupGitHubVault(username: gh)
        }
    }

    // MARK: — iCloud Drive vault
    private func setupiCloudVault() async {
        guard let root = iCloudVaultURL() else {
            print("[UserVault] iCloud unavailable — falling back to local documents")
            await setupLocalVault()
            return
        }
        _vaultURL = root
        createSubfolders(at: root)
        print("[UserVault] iCloud vault ready at \(root.path)")
    }

    private func iCloudVaultURL() -> URL? {
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.dartmeadow.autumn"
        ) else { return nil }
        let docs = container.appendingPathComponent("Documents", isDirectory: true)
        let vault = docs.appendingPathComponent(folderName, isDirectory: true)
        return vault
    }

    // Fallback: local Documents if iCloud not available (guest, no Apple ID)
    private func setupLocalVault() async {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first else { return }
        let vault = docs.appendingPathComponent(folderName, isDirectory: true)
        _vaultURL = vault
        createSubfolders(at: vault)
        print("[UserVault] Local vault ready at \(vault.path)")
    }

    private func createSubfolders(at root: URL) {
        let fm = FileManager.default
        for sub in ["journal", "memory", "projects", "exports"] {
            let url = root.appendingPathComponent(sub, isDirectory: true)
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: — GitHub vault (mirror)
    private func setupGitHubVault(username: String) async {
        let repoName = "Autumn-Ash"
        // Check if repo exists; create if not
        do {
            let repos = try await github.listRepos()
            let exists = repos.contains { $0.name == repoName }
            if !exists {
                _ = try await github.createRepo(
                    name: repoName,
                    isPrivate: true,
                    description: "Personal Autumn-Ash vault — synced from Autumn iOS"
                )
                // Seed folder structure with .gitkeep files
                for sub in ["journal", "memory", "projects", "exports"] {
                    try? await github.writeFile(
                        owner: username, repo: repoName,
                        path: "\(sub)/.gitkeep",
                        content: "",
                        message: "init: create \(sub) folder"
                    )
                }
                print("[UserVault] GitHub repo \(username)/\(repoName) created")
            } else {
                print("[UserVault] GitHub repo \(username)/\(repoName) exists")
            }
        } catch {
            print("[UserVault] GitHub vault setup failed: \(error)")
        }
    }

    // MARK: — Write a file to vault (iCloud + GitHub if connected)
    public func write(
        subfolder: VaultFolder,
        filename: String,
        content: String,
        githubUsername: String? = nil
    ) async {
        // iCloud / local
        if let root = _vaultURL {
            let url = root
                .appendingPathComponent(subfolder.rawValue)
                .appendingPathComponent(filename)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        // GitHub mirror
        if let gh = githubUsername, !gh.isEmpty {
            let path = "\(subfolder.rawValue)/\(filename)"
            let sha = (try? await github.readFile(
                owner: gh, repo: "Autumn-Ash", path: path))?.sha
            try? await github.writeFile(
                owner: gh, repo: "Autumn-Ash",
                path: path, content: content,
                message: "sync: \(filename)",
                sha: sha
            )
        }
    }

    // MARK: — Read a file from vault
    public func read(subfolder: VaultFolder, filename: String) -> String? {
        guard let root = _vaultURL else { return nil }
        let url = root
            .appendingPathComponent(subfolder.rawValue)
            .appendingPathComponent(filename)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: — List files in a subfolder
    public func list(subfolder: VaultFolder) -> [String] {
        guard let root = _vaultURL else { return [] }
        let url = root.appendingPathComponent(subfolder.rawValue)
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    }

    // MARK: — Export: copy vault subfolder to user-chosen location
    // Returns the export folder URL for use with UIDocumentPickerViewController
    public func exportURL(subfolder: VaultFolder) -> URL? {
        guard let root = _vaultURL else { return nil }
        return root.appendingPathComponent(subfolder.rawValue)
    }

    public var vaultURL: URL? { _vaultURL }
}

// MARK: — Vault folder enum
public enum VaultFolder: String, CaseIterable {
    case journal  = "journal"
    case memory   = "memory"
    case projects = "projects"
    case exports  = "exports"
}
