import Foundation
import CoreData
import LEATRCore

public final class PersistenceController: @unchecked Sendable {
    public static let shared = PersistenceController()

    public let container: NSPersistentCloudKitContainer

    public init(inMemory: Bool = false) {
        // Build model programmatically — no .xcdatamodeld file needed
        container = NSPersistentCloudKitContainer(
            name: "AutumnData",
            managedObjectModel: Self.autumnModel
        )

        if inMemory {
            container.persistentStoreDescriptions.first?.url =
                URL(fileURLWithPath: "/dev/null")
        } else {
            let description = container.persistentStoreDescriptions.first
            description?.setOption(true as NSNumber,
                forKey: NSPersistentHistoryTrackingKey)
            description?.setOption(true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description?.cloudKitContainerOptions =
                NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.dartmeadow.autumn"
                )
        }

        container.loadPersistentStores { _, error in
            if let error {
                // Log but don't crash — app can work without persistence
                print("[Persistence] Store load error: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    public var context: NSManagedObjectContext { container.viewContext }

    public func save() {
        let ctx = context
        guard ctx.hasChanges else { return }
        do { try ctx.save() }
        catch { print("[Persistence] Save error: \(error.localizedDescription)") }
    }

    // MARK: — Programmatic Core Data Model
    static let autumnModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        // JournalRecord entity
        let journal = NSEntityDescription()
        journal.name = "JournalRecord"
        journal.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        journal.properties = makeAttrs([
            ("id",        .stringAttributeType),
            ("content",   .stringAttributeType),
            ("emotion",   .stringAttributeType),
            ("buoyancy",  .doubleAttributeType),
            ("isInternal",.booleanAttributeType),
            ("timestamp", .dateAttributeType)
        ])

        // MemoryChunk entity
        let memory = NSEntityDescription()
        memory.name = "MemoryChunk"
        memory.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        memory.properties = makeAttrs([
            ("key",       .stringAttributeType),
            ("content",   .stringAttributeType),
            ("sessionID", .stringAttributeType),
            ("createdAt", .dateAttributeType)
        ])

        model.entities = [journal, memory]
        return model
    }()
}

private func makeAttrs(_ pairs: [(String, NSAttributeType)]) -> [NSAttributeDescription] {
    pairs.map { name, type in
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = true
        return a
    }
}
// NOTE: JournalViewModel Core Data extensions are in JournalAndSettings.swift (AutumnApp target)
