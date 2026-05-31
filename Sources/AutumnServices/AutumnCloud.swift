import Foundation
import CloudKit

/// AutumnCloud — iCloud/CloudKit backend for Autumn iOS
/// Mirrors GitHub-based memory/journal for Apple ID users
/// Creates ashtree/autumn-ash directory structure in iCloud
public actor AutumnCloud {
    public static let shared = AutumnCloud()
    private let container = CKContainer(identifier: "iCloud.DART-Meadow-LLC.Autumn")
    private var db: CKDatabase { container.privateCloudDatabase }

    public init() {}

    // MARK: - Ash Directory Setup
    /// Creates the Autumn Ash directory structure on first sign-in
    public func setupAshDirectory(for userID: String) async throws {
        let zoneID = CKRecordZone.ID(zoneName: "AutumnAsh-\(userID)", ownerName: CKCurrentUserDefaultName)
        let zone   = CKRecordZone(zoneID: zoneID)
        let (_, _) = try await db.modifyRecordZones(saving: [zone], deleting: [])
    }

    // MARK: - Journal Sync
    public func saveJournalEntry(_ entry: JournalEntry) async throws {
        let record          = CKRecord(recordType: "JournalEntry")
        record["thought"]   = entry.thought as CKRecordValue
        record["timestamp"] = entry.timestamp as CKRecordValue
        record["emotion"]   = entry.emotion as CKRecordValue
        try await db.save(record)
    }

    public func fetchJournalEntries(limit: Int = 50) async throws -> [JournalEntry] {
        let pred  = NSPredicate(value: true)
        let query = CKQuery(recordType: "JournalEntry", predicate: pred)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        let (results, _) = try await db.records(matching: query, resultsLimit: limit)
        return results.compactMap { _, result in
            guard let record = try? result.get() else { return nil }
            return JournalEntry(
                thought:   record["thought"]   as? String ?? "",
                timestamp: record["timestamp"] as? Date   ?? Date(),
                emotion:   record["emotion"]   as? String ?? "neutral"
            )
        }
    }

    // MARK: - Session Memory
    public func saveMemoryChunk(_ chunk: String, key: String) async throws {
        let record        = CKRecord(recordType: "MemoryChunk", recordID: CKRecord.ID(recordName: key))
        record["content"] = chunk as CKRecordValue
        record["updated"] = Date() as CKRecordValue
        try await db.save(record)
    }

    public func fetchMemoryChunk(key: String) async throws -> String? {
        let recordID = CKRecord.ID(recordName: key)
        let record   = try await db.record(for: recordID)
        return record["content"] as? String
    }

    // MARK: - Project File Backup
    public func backupProjectFile(name: String, data: Data) async throws {
        let asset         = CKAsset(fileURL: writeTemp(data: data, name: name))
        let record        = CKRecord(recordType: "ProjectFile")
        record["name"]    = name as CKRecordValue
        record["file"]    = asset
        record["backed"]  = Date() as CKRecordValue
        try await db.save(record)
    }

    private func writeTemp(data: Data, name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }
}

public struct JournalEntry: Codable, Sendable {
    public let thought:   String
    public let timestamp: Date
    public let emotion:   String
    public init(thought: String, timestamp: Date = Date(), emotion: String = "neutral") {
        self.thought   = thought
        self.timestamp = timestamp
        self.emotion   = emotion
    }
}
