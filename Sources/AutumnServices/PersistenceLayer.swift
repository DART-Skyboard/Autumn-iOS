import Foundation
import CoreData

public final class PersistenceController: @unchecked Sendable {
    public static let shared = PersistenceController()
    public let container: NSPersistentContainer

    public init(inMemory: Bool = false) {
        let model = NSManagedObjectModel.autumnModel
        let built = NSPersistentContainer(name: "AutumnData", managedObjectModel: model)
        if inMemory {
            built.persistentStoreDescriptions.first?.url =
                URL(fileURLWithPath: "/dev/null")
        }
        built.loadPersistentStores { _, error in
            if let error { print("[CoreData] \(error)") }
        }
        built.viewContext.automaticallyMergesChangesFromParent = true
        self.container = built
    }

    public var context: NSManagedObjectContext { container.viewContext }

    public func save() {
        let ctx = context
        guard ctx.hasChanges else { return }
        do { try ctx.save() }
        catch { print("[CoreData] Save: \(error)") }
    }
}

public extension NSManagedObjectModel {
    static var autumnModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        let journal = NSEntityDescription()
        journal.name = "JournalRecord"
        journal.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        journal.properties = [
            ("id", NSAttributeType.stringAttributeType),
            ("content", .stringAttributeType),
            ("emotion", .stringAttributeType),
            ("buoyancy", .doubleAttributeType),
            ("isInternal", .booleanAttributeType),
            ("timestamp", .dateAttributeType)
        ].map { name, type in
            let a = NSAttributeDescription()
            a.name = name; a.attributeType = type; a.isOptional = true; return a
        }

        let memory = NSEntityDescription()
        memory.name = "MemoryChunk"
        memory.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        memory.properties = [
            ("key", NSAttributeType.stringAttributeType),
            ("content", .stringAttributeType),
            ("sessionID", .stringAttributeType),
            ("createdAt", .dateAttributeType)
        ].map { name, type in
            let a = NSAttributeDescription()
            a.name = name; a.attributeType = type; a.isOptional = true; return a
        }

        model.entities = [journal, memory]
        return model
    }()
}
