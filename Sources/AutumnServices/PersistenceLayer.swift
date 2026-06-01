import Foundation
import CoreData
import LEATRCore

public final class PersistenceController: @unchecked Sendable {
    public static let shared = PersistenceController()

    public let container: NSPersistentCloudKitContainer

    public init(inMemory: Bool = false) {
        let model = NSManagedObjectModel.autumnModel
        container = NSPersistentCloudKitContainer(name: "AutumnData",
                                                  managedObjectModel: model)
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
                    containerIdentifier: "iCloud.com.dartmeadow.autumn")
        }
        container.loadPersistentStores { _, error in
            if let error {
                print("[Persistence] Store error: \(error.localizedDescription)")
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
        let jAttrs: [(String, NSAttributeType)] = [
            ("id", .stringAttributeType), ("content", .stringAttributeType),
            ("emotion", .stringAttributeType), ("buoyancy", .doubleAttributeType),
            ("isInternal", .booleanAttributeType), ("timestamp", .dateAttributeType)
        ]
        journal.properties = jAttrs.map { name, type in
            let a = NSAttributeDescription()
            a.name = name; a.attributeType = type; a.isOptional = true
            return a
        }

        let memory = NSEntityDescription()
        memory.name = "MemoryChunk"
        memory.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        let mAttrs: [(String, NSAttributeType)] = [
            ("key", .stringAttributeType), ("content", .stringAttributeType),
            ("sessionID", .stringAttributeType), ("createdAt", .dateAttributeType)
        ]
        memory.properties = mAttrs.map { name, type in
            let a = NSAttributeDescription()
            a.name = name; a.attributeType = type; a.isOptional = true
            return a
        }

        model.entities = [journal, memory]
        return model
    }()
}
