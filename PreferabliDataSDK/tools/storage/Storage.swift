//
//  Storage.swift
//  PreferabliDataSDK
//
//  Created by Nicholas Bortolussi on 8/29/25.
//  Copyright © 2025 RingIT, Inc,. All rights reserved.
//

//
//  Storage.swift  (actor-based)
//  PreferabliDataSDK
//
//  Converted to actor-based hybrid on request.
//  NOTE: Pure helpers remain static to avoid churn in call sites.
//

import SwiftData
import Foundation

/// Internal class used for interacting with our SwiftData storage.
@MainActor
public enum Storage {
    public static let storeURL: URL = {
        let dir = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return dir.appendingPathComponent("PreferabliSDK.sqlite")
    }()

    internal static func makeSchema() -> Schema {
        Schema(ModelRegistry.types)
    }

    internal static var container: ModelContainer = {
        makeContainer()
    }()

    @MainActor
    private static func makeContainer() -> ModelContainer {
        let schema = makeSchema()
        let config = ModelConfiguration(schema: schema, url: storeURL)
        
        // First attempt: normal creation (will migrate if possible)
        do {
                return try ModelContainer(for: schema,
                                          migrationPlan: nil,
                                          configurations: [config])
        } catch {
            // Most common case we care about: schema mismatch / migration failure.
            // At this point we *intentionally* drop all local data and recreate.
            NSLog("[PreferabliDataSDK] Failed to create ModelContainer. " +
                  "Will nuke store and retry. Error: \(error)")
            
            do {
                try nukePersistentStoreFiles()
                resetDatabaseKeystore()
                
                return try ModelContainer(for: schema,
                                              migrationPlan: nil,
                                              configurations: [config])
            } catch {
                // If we still fail here, something is seriously wrong (e.g. no disk).
                fatalError("[PreferabliDataSDK] Unable to create ModelContainer " +
                           "even after nuking the store: \(error)")
            }
        }
    }
    
    private static func nukePersistentStoreFiles() throws {
          let fm = FileManager.default
          let basePath = storeURL.path

          // SQLite uses `file`, `file-wal`, `file-shm`
          let paths = [
              basePath,              // PreferabliSDK.sqlite
              basePath + "-wal",     // PreferabliSDK.sqlite-wal
              basePath + "-shm"      // PreferabliSDK.sqlite-shm
          ]

          for path in paths {
              if fm.fileExists(atPath: path) {
                  try fm.removeItem(atPath: path)
              }
          }
      }

    @inline(__always)
        public static func withContext<T>(_ body: @MainActor (ModelContext) throws -> T) rethrows -> T {
            // --- FIX ---
            // Use the container's mainContext since we're on the MainActor
            try body(container.mainContext)
            // -----------
        }

    // still updates UI since it is from the same container
    nonisolated
    public static func withBackgroundContext<T: Sendable>(
      priority: TaskPriority = .userInitiated,
      _ body: @escaping @Sendable (ModelContext) throws -> T
    ) async throws -> T {
      let container = try await MainActor.run { Storage.container }
      return try await Task.detached(priority: priority) {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        return try body(ctx)
      }.value
    }

    internal static func reset() async throws {
        try await withBackgroundContext { ctx in
            for wipe in ModelRegistry.wipes { try wipe(ctx) }
            try ctx.save()
        }
    }

    @inline(__always)
    nonisolated internal static func deleteAll<T: PersistentModel>(_ type: T.Type, in ctx: ModelContext) throws {
        let fd = FetchDescriptor<T>()
        let all = try ctx.fetch(fd)
        for obj in all { ctx.delete(obj) }
    }
    
    internal static func databaseUpgraded() async throws {
        try await Storage.reset()
        resetDatabaseKeystore()
    }
    
    internal static func resetDatabaseKeystore() {
        for key in Storage.getKeyStore().dictionaryRepresentation().keys {
            if key.starts(with: "hasLoaded") {
                Storage.getKeyStore().set(false, forKey: key)
            }
            if key.starts(with: "collection_etags") || key.starts(with: "lastCalled") {
                Storage.getKeyStore().set(nil, forKey: key)
            }
        }
    }
    
    public nonisolated static func isKeyPresentInKeyStore(key: String) -> Bool {
        return Storage.getKeyStore().object(forKey: key) != nil
    }
    
    public nonisolated static func getKeyStore() -> UserDefaults {
        return UserDefaults.init(suiteName: "Preferabli")!
    }
}

private enum ModelRegistry {
    typealias Wipe = @Sendable (ModelContext) throws -> Void

    /// Single source of truth: call `add(<Type>.self)` here ONCE.
    private static func register(addType: (any PersistentModel.Type) -> Void, addWipe: (@escaping Wipe) -> Void) {
        func add<T: PersistentModel>(_ t: T.Type) {
            addType(T.self)
            addWipe { ctx in try Storage.deleteAll(T.self, in: ctx) }
        }

        add(Customer.self)
        add(PreferabliUser.self)
        add(Profile.self)
        add(ProfileStyle.self)
        add(Style.self)
        add(Product.self)
        add(ProductProfile.self)
        add(Variant.self)
        add(Tag.self)
        add(Media.self)
        add(Search.self)
        add(Venue.self)
        add(VenueHour.self)
        add(Collection.self)
        add(CollectionOrder.self)
        add(CollectionVersion.self)
        add(CollectionGroup.self)
        add(CollectionTrait.self)
        add(DeliveryMethod.self)
        add(Food.self)
        add(FoodCategory.self)
        add(UserCollection.self)
        add(Reservation.self)
        add(Location.self)
    }

    /// Publicly consumed lists—both derived from the single `register` body above.
    static let types: [any PersistentModel.Type] = {
        var out: [any PersistentModel.Type] = []
        register(addType: { out.append($0) }, addWipe: { _ in })
        return out
    }()

    static let wipes: [Wipe] = {
        var out: [Wipe] = []
        register(addType: { _ in }, addWipe: { out.append($0) })
        return out
    }()
}


@MainActor
public struct StorageFacade {
        
    public var container: ModelContainer { Storage.container }
    
    public struct QueriesNamespace {
        /// Products whose `id` is in the given list.
        public func products(withIDs ids: [Int]) -> Predicate<Product> { ids.isEmpty ? #Predicate { _ in false } : #Predicate { p in ids.contains(p.id) } }
        
        public func tagsQuery(for spec: CollectionSpec) -> (predicate: Predicate<Tag>, sort: [SortDescriptor<Tag>]) {
            let cid = Storage.getKeyStore().integer(forKey: spec.idKey)

            // Build fully-typed predicates per-branch to avoid opaque-type issues
            if let tt = spec.tagType {
                // Match optionality: if Tag.type is String?, compare to String?
                let raw: String = tt.getDatabaseName()
                let pred = #Predicate<Tag> { $0.collection_id == cid && $0.type == raw }
                return (pred, [SortDescriptor(\Tag.created_at, order: .reverse)])
            } else {
                let pred = #Predicate<Tag> { $0.collection_id == cid }
                return (pred, [SortDescriptor(\Tag.created_at, order: .reverse)])
            }
        }
    }
    
    public struct SortsNamespace {
        public var sortProductsByUpdatedDesc: [SortDescriptor<Product>] {
            [SortDescriptor(\Product.updated_at, order: .reverse)]
        }
    }
    
    public var queries: QueriesNamespace { QueriesNamespace() }
    public var sorts: SortsNamespace { SortsNamespace() }
}

extension Storage {
    @inline(__always)
    nonisolated static internal func fetchById<T: HasIntID>(
        _ type: T.Type,
        id: Int?,
        in ctx: ModelContext
    ) throws -> T? {
        guard let id else { return nil }
        var fd = FetchDescriptor<T>(predicate: T.predicate(forID: id))
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }
    
    /// Fetch an object by its `id` (from HasIntID), or create one via `makeNew`.
    /// Avoids dynamic key paths to keep `#Predicate` happy.
    nonisolated static func fetchOrInsert<T: HasIntID>(
        _ type: T.Type,
        id: Int,
        in ctx: ModelContext,
        makeNew: () -> T
    ) throws -> T {
        var fd = FetchDescriptor<T>(predicate: T.predicate(forID: id))
        fd.fetchLimit = 1

        if let existing = try ctx.fetch(fd).first {
            return existing
        }

        let obj = makeNew()
        obj.id = id
        ctx.insert(obj)
        return obj
    }
}


// Coercers / parsing
extension Storage {
    @inline(__always) nonisolated static internal func parseDate(_ any: Any?) -> Date? {
        guard let any else { return nil }
        if let s = any as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        if let n = any as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        if let i = any as? Int      { return Date(timeIntervalSince1970: TimeInterval(i)) }
        if let d = any as? Double   { return Date(timeIntervalSince1970: d) }
        return nil
    }
    @inline(__always) nonisolated static internal func asInt(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }
    @inline(__always) nonisolated static internal func asDouble(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
    @inline(__always) nonisolated static internal func asBool(_ v: Any?) -> Bool? {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return Bool(s) }
        return nil
    }
    @inline(__always) nonisolated static internal func asDecimal(_ v: Any?) -> Decimal? {
        if let d = v as? Decimal { return d }
        if let n = v as? NSNumber { return n.decimalValue }
        if let d = v as? Double { return Decimal(d) }
        if let s = v as? String { return Decimal(string: s) }
        return nil
    }
    @inline(__always) nonisolated static internal func asString(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
    @inline(__always) nonisolated static internal func asDataBase64(_ v: Any?) -> Data? {
        guard let s = v as? String else { return nil }
        return Data(base64Encoded: s)
    }
}

// MARK: - Tombstone Pruning
extension Storage {
    /// Hard-deletes tombstoned Tags first, then tombstoned Variants.
    /// Executes on a background ModelContext separate from the UI.
    nonisolated public static func pruneTombstones(
        batchSize: Int = 500,
        log: @Sendable @escaping (String) -> Void = { _ in }
    ) {
        let logger: @Sendable (String) -> Void = log

        Task.detached(priority: .background) {
            do {
                try await Storage.withBackgroundContext(priority: .background) { ctx in
                    ctx.autosaveEnabled = false
                    ctx.author = "TombstonePruner"

                    try pruneTags(in: ctx, batchSize: batchSize)
                    log("Pruned tombstoned Tags")

                    try pruneVariants(in: ctx, batchSize: batchSize)
                    log("Pruned tombstoned Variants")
                }
            } catch {
                log("Tombstone prune failed: \(error)")
            }
        }
    }

    // Delete tombstoned Tags in batches
    nonisolated private static func pruneTags(in ctx: ModelContext, batchSize: Int) throws {
        while true {
            var fd = FetchDescriptor<Tag>(
                predicate: #Predicate<Tag> { $0.isTombstoned == true }
            )
            fd.fetchLimit = batchSize

            let doomed = try ctx.fetch(fd)
            if doomed.isEmpty { break }

            doomed.forEach { ctx.delete($0) }
            try ctx.save()
            // no ctx.reset(); not universally available and not required
        }
    }

    // Delete tombstoned Variants in batches
    nonisolated private static func pruneVariants(in ctx: ModelContext, batchSize: Int) throws {
        while true {
            var fd = FetchDescriptor<Variant>(
                predicate: #Predicate<Variant> { $0.isTombstoned == true }
            )
            fd.fetchLimit = batchSize

            let doomed = try ctx.fetch(fd)
            if doomed.isEmpty { break }

            doomed.forEach { ctx.delete($0) }
            try ctx.save()
        }
    }
}

extension Storage {
    /// Re-indexes the `searchableContent` for all Tags.
    /// This is useful if underlying Product data (name, brand, etc.) has changed.
    /// Executes on a background ModelContext separate from the UI.
    nonisolated public static func reindexSearchableContent(
        batchSize: Int = 250, // Batches can be smaller for updates
        log: @Sendable @escaping (String) -> Void = { _ in }
    ) {
        Task.detached(priority: .background) {
            do {
                try await Storage.withBackgroundContext(priority: .background) { ctx in
                    ctx.autosaveEnabled = false
                    ctx.author = "SearchReindexer"
                    
                    try reindexTags(in: ctx, batchSize: batchSize, log: log)
                    
                    log("Completed search re-indexing for all Tags.")
                }
            } catch {
                log("Search re-indexing failed: \(error)")
            }
        }
    }
    
    /// Fetches all Tags in batches and updates their `searchableContent`.
    nonisolated private static func reindexTags(
        in ctx: ModelContext,
        batchSize: Int,
        log: @Sendable @escaping (String) -> Void
    ) throws {
        var offset = 0
        var totalProcessed = 0
        
        while true {
            var fd = FetchDescriptor<Tag>()
            fd.fetchOffset = offset
            fd.fetchLimit = batchSize
            
            // Ensure we get relationships.
            // This is crucial for accessing product.name.
            fd.relationshipKeyPathsForPrefetching = [\Tag.variant, \Tag.variant.product]
            
            let tagsToUpdate = try ctx.fetch(fd)
            if tagsToUpdate.isEmpty {
                break // No more tags to process
            }
            
            for tag in tagsToUpdate {
                tag.updateSearchableContent()
            }
            
            try ctx.save()
            
            offset += tagsToUpdate.count
            totalProcessed += tagsToUpdate.count
            log("Re-indexed batch of \(tagsToUpdate.count) tags (total: \(totalProcessed))")
        }
    }
}

extension Storage {
    /// Returns the subset of `candidateVariantIds` that are **not yet present** in SwiftData.
    @discardableResult
    nonisolated static func missingVariantIds(
        from candidateVariantIds: [Int],
        in ctx: ModelContext
    ) throws -> [Int] {
        guard !candidateVariantIds.isEmpty else { return [] }
        
        var fd = FetchDescriptor<Variant>(
            predicate: #Predicate<Variant> { variant in
                candidateVariantIds.contains(variant.id)
            }
        )
        // We only care about the IDs
        fd.propertiesToFetch = [\.id]
        
        let existing = try ctx.fetch(fd)
        let existingIds = Set(existing.map { $0.id })
        let allIds      = Set(candidateVariantIds)
        let missing     = allIds.subtracting(existingIds)
        
        return Array(missing)
    }
}
