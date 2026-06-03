import Foundation
import LEATRCore

// MARK: — CloudKitSync (GitHub-only, CloudKit disabled until entitlement configured)
// Memory chunks and journal entries sync to leatr-ash repo only.

public actor CloudKitSync {
    public static let shared = CloudKitSync()

    private let github = GitHubClient.shared
    private let chunkSize = 5

    // MARK: — Rolling Memory Sync
    public func syncMemoryChunk(messages: [ChatMessage], sessionID: String) async {
        guard !messages.isEmpty else { return }

        let chunk = messages
            .filter { !$0.isInternal }
            .suffix(chunkSize)
            .map { "[\($0.role.rawValue)] \($0.content)" }
            .joined(separator: "\n---\n")

        let key = "memory_\(sessionID)_\(Date().timeIntervalSince1970.rounded())"
        await syncChunkToGitHub(chunk: chunk, key: key)
    }

    private func syncChunkToGitHub(chunk: String, key: String) async {
        let owner = "DART-Skyboard"
        let repo  = "leatr-ash"
        let path  = "ashtree/autumn-ios/memory/\(key).txt"

        let sha = (try? await github.readFile(owner: owner, repo: repo, path: path))?.sha
        try? await github.writeFile(
            owner: owner, repo: repo, path: path,
            content: chunk,
            message: "memory chunk \(key)",
            sha: sha
        )
    }

    // MARK: — Journal Entry (GitHub only)
    public func saveJournalEntry(thought: String, emotion: EmotionType, username: String) async {
        let entry = CloudJournalEntry(thought: thought, emotion: emotion.rawValue)
        try? await github.syncJournalEntry(entry, username: username)
    }

    // MARK: — Session Restore (GitHub only)
    public func restoreSessionMemory(sessionID: String) async -> [ChatMessage] {
        let owner = "DART-Skyboard"
        let repo  = "leatr-ash"
        let path  = "ashtree/autumn-ios/memory"

        if let file = try? await github.readFile(owner: owner, repo: repo, path: path),
           let content = file.decodedContent {
            return parseChunk(content)
        }
        return []
    }

    private func parseChunk(_ raw: String) -> [ChatMessage] {
        raw.components(separatedBy: "\n---\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[user] ") {
                return ChatMessage(role: .user, content: String(trimmed.dropFirst(7)))
            } else if trimmed.hasPrefix("[assistant] ") {
                return ChatMessage(role: .assistant, content: String(trimmed.dropFirst(12)))
            }
            return nil
        }
    }

    // MARK: — Parity Check (stub — CloudKit disabled)
    public func parityCheck() async -> (cloudCount: Int, githubCount: Int, inSync: Bool) {
        let gc = await githubJournalCount()
        return (0, gc, true)
    }

    private func githubJournalCount() async -> Int {
        guard
            let file = try? await github.readFile(
                owner: "DART-Skyboard", repo: "leatr-ash",
                path: "ashtree/sentient/journal.json"
            ),
            let content = file.decodedContent,
            let data = content.data(using: .utf8),
            let entries = try? JSONDecoder().decode([CloudJournalEntry].self, from: data)
        else { return 0 }
        return entries.count
    }
}
