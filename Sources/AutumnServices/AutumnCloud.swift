import Foundation

// AutumnCloud — CloudKit stub
// CloudKit entitlement not yet configured in provisioning profile.
// All methods are no-ops / return empty data.
// Re-enable by adding iCloud capability + container in App ID on developer.apple.com,
// then restore full implementation from git history.

public struct CloudJournalEntry: Codable, Sendable {
    public let thought: String
    public let timestamp: Date
    public let emotion: String

    public init(thought: String, timestamp: Date = Date(), emotion: String = "neutral") {
        self.thought = thought
        self.timestamp = timestamp
        self.emotion = emotion
    }
}

public actor AutumnCloud {
    public static let shared = AutumnCloud()
    public init() {}

    public func setupAshDirectory(for userID: String) async throws {}

    public func saveCloudJournalEntry(_ entry: CloudJournalEntry) async throws {}
    public func fetchJournalEntries(limit: Int = 50) async throws -> [CloudJournalEntry] { [] }

    public func saveMemoryChunk(_ chunk: String, key: String) async throws {}
    public func fetchMemoryChunk(key: String) async throws -> String? { nil }

    public func backupProjectFile(name: String, data: Data) async throws {}
}
