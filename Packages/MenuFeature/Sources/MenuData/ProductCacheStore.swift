import CoreData
import Foundation

public struct ProductCacheEntry: Sendable, Equatable {
    public let payload: Data
    public let cachedAt: Date

    public init(payload: Data, cachedAt: Date) {
        self.payload = payload
        self.cachedAt = cachedAt
    }
}

public protocol ProductCacheStore: Sendable {
    func entry(for key: String) async throws -> ProductCacheEntry?
    func save(_ entry: ProductCacheEntry, for key: String) async throws
    func invalidate(key: String) async throws
    func removeAll() async throws
}

/// Core Data-backed cache. The model is created in code so the package has no
/// runtime .xcdatamodel resource to copy or accidentally omit from an app.
public actor CoreDataProductCacheStore: ProductCacheStore {
    private let container: NSPersistentContainer

    public init(inMemory: Bool = false) {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "ProductCacheEntry"
        entity.managedObjectClassName = "NSManagedObject"
        let key = NSAttributeDescription()
        key.name = "key"
        key.attributeType = .stringAttributeType
        key.isOptional = false
        let payload = NSAttributeDescription()
        payload.name = "payload"
        payload.attributeType = .binaryDataAttributeType
        payload.isOptional = false
        let cachedAt = NSAttributeDescription()
        cachedAt.name = "cachedAt"
        cachedAt.attributeType = .dateAttributeType
        cachedAt.isOptional = false
        entity.properties = [key, payload, cachedAt]
        entity.uniquenessConstraints = [["key"]]
        model.entities = [entity]

        container = NSPersistentContainer(
            name: "ProductCache",
            managedObjectModel: model
        )
        let description = NSPersistentStoreDescription()
        if inMemory { description.url = URL(fileURLWithPath: "/dev/null") }
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            fatalError("Unable to load product cache: \(loadError)")
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
    }

    public func entry(for key: String) async throws -> ProductCacheEntry? {
        try perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ProductCacheEntry")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key)
            guard let object = try context.fetch(request).first,
                  let payload = object.value(forKey: "payload") as? Data,
                  let cachedAt = object.value(forKey: "cachedAt") as? Date else { return nil }
            return ProductCacheEntry(payload: payload, cachedAt: cachedAt)
        }
    }

    public func save(_ entry: ProductCacheEntry, for key: String) async throws {
        try perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ProductCacheEntry")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key)
            let object = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(
                    forEntityName: "ProductCacheEntry",
                    into: context
                )
            object.setValue(key, forKey: "key")
            object.setValue(entry.payload, forKey: "payload")
            object.setValue(entry.cachedAt, forKey: "cachedAt")
            try context.save()
        }
    }

    public func invalidate(key: String) async throws {
        try perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ProductCacheEntry")
            request.predicate = NSPredicate(format: "key == %@", key)
            for object in try context.fetch(request) { context.delete(object) }
            try context.save()
        }
    }

    public func removeAll() async throws {
        try perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ProductCacheEntry")
            for object in try context.fetch(request) { context.delete(object) }
            try context.save()
        }
    }

    private func perform<T: Sendable>(_ work: (NSManagedObjectContext) throws -> T) throws -> T {
        var result: Result<T, Error>!
        container.viewContext.performAndWait { result = Result { try work(container.viewContext) } }
        return try result.get()
    }
}
