import Foundation
import CoreData
import LEATRCore

public final class PersistenceController: @unchecked Sendable {
    public static let shared = PersistenceController()

    public let container: NSPersistentContainer

    public init(inMemory: Bool = false) {
        let model = NSManagedObjectModel.autumnModel

        // Try CloudKit first, fall back to local store
        // CloudKit requires iCloud entitlement AND signed-in account
        // On fresh install or no iCloud, it can crash
        let useCloudKit = !inMemory && isCloudKitAvailable()

        if useCloudKit {
            let ckContainer = NSPersistentCloudKitContainer(name: "AutumnData",
                                                            managedObjectModel: model)
            let description = ckContainer.persistentStoreDescriptions.first
            description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description?.setOption(true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description?.cloudKitContainerOptions =
                NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.dartmeadow.autumn")
            ckContainer.loadPersistentStores { _, error in
                if let error {
                    print("[Persistence] CloudKit store error: \(error)")
                }
            }
            ckContainer.viewContext.automaticallyMergesChangesFromParent = true
            ckContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            container = ckContainer
        } else {
            // Pure local store — no CloudKit
            let localContainer = NSPersistentContainer(name: "AutumnData",
                                                       managedObjectModel: model)
            if inMemory {
                localContainer.persistentStoreDescriptions.first?.url =
                    URL(fileURLWithPath: "/dev/null")
            }
            localContainer.loadPersistentStores { _, error in
                if let error { print("[Persistence] Local store error: \(error)") }
            }
            localContainer.viewContext.automaticallyMergesChangesFromParent = true
            container = localContainer
        }
    }

    private func isCloudKitAvailable() -> Bool {
        // Check if iCloud is available without crashing
        guard FileManager.default.ubiquityIdentityToken != nil else { return false }
        return true
    }

    public var context: NSManagedObjectContext { container.viewContext }

    public func save() {
        let ctx = context
        guard ctx.hasChanges else { return }
        do { try ctx.save() }
        catch { print("[Persistence] Save error: \(error)") }
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

// MARK: — JournalViewModel Core Data extensions
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
                    let id       = obj.value(forKey: "id") as? String,
                    let content  = obj.value(forKey: "content") as? String,
                    let emotion  = obj.value(forKey: "emotion") as? String,
                    let ts       = obj.value(forKey: "timestamp") as? Date,
                    let buoyancy = obj.value(forKey: "buoyancy") as? Double,
                    let internal_ = obj.value(forKey: "isInternal") as? Bool
                else { return nil }
                return JournalEntryLocal(
                    id: id,
                    timestamp: ts.formatted(.dateTime.day().month().hour().minute()),
                    content: content, emotion: emotion,
                    buoyancy: buoyancy, isInternal: internal_
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
