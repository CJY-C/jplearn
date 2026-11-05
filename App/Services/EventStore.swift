import Foundation
import CoreData
import LearningCore

/// The journal is authoritative; derived FSRS state is rebuilt deterministically.
final class EventStore {
    private let container: NSPersistentContainer

    init(directory: URL) throws {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "JournalEvent"
        entity.managedObjectClassName = "NSManagedObject"
        let identifier = NSAttributeDescription()
        identifier.name = "eventID"; identifier.attributeType = .stringAttributeType
        identifier.isOptional = false
        let payload = NSAttributeDescription()
        payload.name = "payload"; payload.attributeType = .binaryDataAttributeType
        payload.isOptional = false
        entity.properties = [identifier, payload]
        entity.uniquenessConstraints = [["eventID"]]
        model.entities = [entity]
        container = NSPersistentContainer(name: "LearningJournal", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("learning.sqlite"))
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let error = loadError { throw error }
        container.viewContext.mergePolicy = NSErrorMergePolicy
    }

    func load() throws -> [LearningEvent] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "JournalEvent")
        let events = try container.viewContext.fetch(request).map { object -> LearningEvent in
            guard let data = object.value(forKey: "payload") as? Data else {
                throw LearningError.invalid("本地学习记录无法读取，请保留数据并从备份恢复。")
            }
            return try ExchangeCoding.decoder().decode(LearningEvent.self, from: data)
        }
        return try EventMerge.merge([], events)
    }

    /// One Core Data transaction: a failed import cannot leave a partly imported archive.
    func append(_ events: [LearningEvent], existing: [LearningEvent]) throws -> [LearningEvent] {
        let merged = try EventMerge.merge(existing, events)
        let existingIDs = Set(existing.map(\.id))
        let context = container.viewContext
        do {
            for event in merged where !existingIDs.contains(event.id) {
                let object = NSEntityDescription.insertNewObject(forEntityName: "JournalEvent", into: context)
                object.setValue(event.id.uuidString, forKey: "eventID")
                object.setValue(try ExchangeCoding.encoder().encode(event), forKey: "payload")
            }
            if context.hasChanges { try context.save() }
            return merged
        } catch {
            context.rollback()
            throw error
        }
    }
}
