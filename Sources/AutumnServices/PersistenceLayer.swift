import Foundation
import CoreData
import LEATRCore

public final class PersistenceController: @unchecked Sendable {
    public static let shared = PersistenceController()

    public let container: NSPersistentCloudKitContainer

    public init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "AutumnData")

        if inMemory {
            container.persistentStoreDescriptions.first?.url =
                URL(fileURLWithPath: "/dev/null")
        }

        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description?.cloudKitContainerOptions =
            NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.dartmeadow.autumn"
            )

        container.loadPersistentStores { _, error in
            if let error {
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
}

public extension NSManagedObjectModel {
    static var autumnModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        let journal = NSEntityDescription()
        journal.name = "JournalRecord"
        journal.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let attrs: [(String, NSAttributeType)] = [
            ("id", .stringAttributeType), ("content", .stringAttributeType),
            ("emotion", .stringAttributeType), ("buoyancy", .doubleAttributeType),
            ("isInternal", .booleanAttributeType), ("timestamp", .dateAttributeType)
        ]
        journal.properties = attrs.map { name, type in
            let attr = NSAttributeDescription()
            attr.name = name; attr.attributeType = type; attr.isOptional = true
            return attr
        }

        let memory = NSEntityDescription()
        memory.name = "MemoryChunk"
        memory.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let memAttrs: [(String, NSAttributeType)] = [
            ("key", .stringAttributeType), ("content", .stringAttributeType),
            ("sessionID", .stringAttributeType), ("createdAt", .dateAttributeType)
        ]
        memory.properties = memAttrs.map { name, type in
            let attr = NSAttributeDescription()
            attr.name = name; attr.attributeType = type; attr.isOptional = true
            return attr
        }

        model.entities = [journal, memory]
        return model
    }()
}
// NOTE: JournalViewModel Core Data extensions moved to JournalAndSettings.swift (AutumnApp target)
