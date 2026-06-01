import Foundation
import CoreData
import LEATRCore

// MARK: — Persistence Layer
// Core Data stack for local journal + memory storage
// Syncs to CloudKit via NSPersistentCloudKitContainer

public final class PersistenceController: @unchecked Sendable {
    public static let shared = PersistenceController()

    public let container: NSPersistentCloudKitContainer

    public init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "AutumnData")

        if inMemory {
            container.persistentStoreDescriptions.first?.url =
                URL(fileURLWithPath: "/dev/null")
        }

        // CloudKit sync config
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey)
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

    // MARK: — Save
    public func save() {
        let ctx = context
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            print("[Persistence] Save error: \(error.localizedDescription)")
        }
    }
}

// MARK: — JournalViewModel wired to Core Data
extension JournalViewModel {

    public func loadFromCoreData() async {
        let ctx = PersistenceController.shared.context
        let request = NSFetchRequest<NSManagedObject>(entityName: "JournalRecord")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = 500

        await MainActor.run {
            let records = (try? ctx.fetch(request)) ?? []
            self.entries = records.compactMap { obj in
                guard
                    let id        = obj.value(forKey: "id") as? String,
                    let content   = obj.value(forKey: "content") as? String,
                    let emotion   = obj.value(forKey: "emotion") as? String,
                    let ts        = obj.value(forKey: "timestamp") as? Date,
                    let buoyancy  = obj.value(forKey: "buoyancy") as? Double,
                    let internal_ = obj.value(forKey: "isInternal") as? Bool
                else { return nil }
                return JournalEntryLocal(
                    id: id,
                    timestamp: ts.formatted(.dateTime.day().month().hour().minute()),
                    content: content,
                    emotion: emotion,
                    buoyancy: buoyancy,
                    isInternal: internal_
                )
            }
        }
    }

    public func saveToCoreData(entry: JournalEntryLocal) {
        let ctx = PersistenceController.shared.context
        let obj = NSEntityDescription.insertNewObject(
            forEntityName: "JournalRecord", into: ctx)
        obj.setValue(entry.id,         forKey: "id")
        obj.setValue(entry.content,    forKey: "content")
        obj.setValue(entry.emotion,    forKey: "emotion")
        obj.setValue(entry.buoyancy,   forKey: "buoyancy")
        obj.setValue(entry.isInternal, forKey: "isInternal")
        obj.setValue(Date(),           forKey: "timestamp")
        PersistenceController.shared.save()
    }
}

// MARK: — AutumnData Core Data Model (programmatic — no .xcdatamodeld needed)
public extension NSManagedObjectModel {

    static var autumnModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        // JournalRecord entity
        let journal = NSEntityDescription()
        journal.name = "JournalRecord"
        journal.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let attrs: [(String, NSAttributeType)] = [
            ("id",         .stringAttributeType),
            ("content",    .stringAttributeType),
            ("emotion",    .stringAttributeType),
            ("buoyancy",   .doubleAttributeType),
            ("isInternal", .booleanAttributeType),
            ("timestamp",  .dateAttributeType)
        ]
        journal.properties = attrs.map { name, type in
            let attr = NSAttributeDescription()
            attr.name = name
            attr.attributeType = type
            attr.isOptional = true
            return attr
        }

        // MemoryChunk entity
        let memory = NSEntityDescription()
        memory.name = "MemoryChunk"
        memory.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let memAttrs: [(String, NSAttributeType)] = [
            ("key",       .stringAttributeType),
            ("content",   .stringAttributeType),
            ("sessionID", .stringAttributeType),
            ("createdAt", .dateAttributeType)
        ]
        memory.properties = memAttrs.map { name, type in
            let attr = NSAttributeDescription()
            attr.name = name
            attr.attributeType = type
            attr.isOptional = true
            return attr
        }

        model.entities = [journal, memory]
        return model
    }()
}
