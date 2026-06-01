import Foundation
import CloudKit
import LEATRCore

// MARK: — Phase 3: CloudKit Memory Sync + leatr-ash Journal Parity
// Keeps CloudKit and GitHub (leatr-ash) in sync
// CloudKit = primary on-device; GitHub = persistent cross-platform backup

public actor CloudKitSync {
    public static let shared = CloudKitSync()

    private let cloud = AutumnCloud.shared
    private let github = GitHubClient.shared

    // Sync interval — memory chunks auto-save every 5 messages
    private let chunkSize = 5

    // MARK: — Rolling Memory Sync
    // Called from ChatViewModel after every N messages
    public func syncMemoryChunk(messages: [ChatMessage], sessionID: String) async {
        guard !messages.isEmpty else { return }

        let chunk = messages
            .filter { !$0.isInternal }
            .suffix(chunkSize)
            .map { "[\($0.role.rawValue)] \($0.content)" }
            .joined(separator: "\n---\n")

        let key = "memory_\(sessionID)_\(Date().timeIntervalSince1970.rounded())"

        try? await cloud.saveMemoryChunk(chunk, key: key)
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

    // MARK: — Journal Entry Dual-Write
    public func saveJournalEntry(thought: String, emotion: EmotionType, username: String) async {
        let entry = CloudJournalEntry(thought: thought, emotion: emotion.rawValue)
        try? await cloud.saveCloudJournalEntry(entry)
        try? await github.syncJournalEntry(entry, username: username)
    }

    // MARK: — Session Restore
    public func restoreSessionMemory(sessionID: String) async -> [ChatMessage] {
        if let raw = try? await cloud.fetchMemoryChunk(key: "memory_\(sessionID)_latest") {
            return parseChunk(raw)
        }

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

    // MARK: — leatr-ash Journal Parity Check
    public func parityCheck() async -> (cloudCount: Int, githubCount: Int, inSync: Bool) {
        async let cloudEntries = (try? await cloud.fetchJournalEntries(limit: 500)) ?? []
        async let githubCount = githubJournalCount()
        let (cloud, github) = await (cloudEntries, githubCount)
        let inSync = abs(cloud.count - github) <= 2
        return (cloud.count, github, inSync)
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
// NOTE: ChatViewModel.autosaveIfNeeded() extension moved to ChatViewModel.swift (AutumnApp target)
