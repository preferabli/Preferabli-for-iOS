//
//  Storage.swift
//  PreferabliDataSDK
//
//  Created by Nicholas Bortolussi on 8/29/25.
//

import SwiftData
import Foundation

private final class StorageLockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool = false

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        let result = value
        lock.unlock()
        return result
    }
}

private let storageLogoutSyncFlag = StorageLockedBool()

/// Internal class used for interacting with our SwiftData storage.
@MainActor
public enum Storage {
    // MARK: - Cancellation + Logout Epoch

    private actor _LogoutRegistry {
        private struct Operation {
            let epoch: UInt64
            var cancel: (@Sendable () -> Void)?
        }

        private var epoch: UInt64 = 0
        private var operations: [UUID: Operation] = [:]
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func currentEpoch() -> UInt64 {
            epoch
        }

        func registerOperation() -> (id: UUID, epoch: UInt64) {
            let id = UUID()
            operations[id] = Operation(epoch: epoch, cancel: nil)
            return (id, epoch)
        }

        func setCanceller(_ cancel: @escaping @Sendable () -> Void, for id: UUID) {
            guard var operation = operations[id] else {
                cancel()
                return
            }

            operation.cancel = cancel
            operations[id] = operation

            if operation.epoch != epoch {
                cancel()
            }
        }

        func finishOperation(_ id: UUID) {
            operations[id] = nil

            if operations.isEmpty {
                let continuations = waiters
                waiters.removeAll()
                for continuation in continuations {
                    continuation.resume()
                }
            }
        }

        func beginLogoutAndWaitForOperationsToDrain() async {
            epoch &+= 1

            let cancels = operations.values.compactMap(\.cancel)
            for cancel in cancels {
                cancel()
            }

            guard !operations.isEmpty else { return }

            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    private static let _logoutRegistry = _LogoutRegistry()

    public static func beginLogoutCancellation() async {
        storageLogoutSyncFlag.set(true)

        await MainActor.run {
            PreferabliTools._setLoggingOutFlag(true)
        }

        await _logoutRegistry.beginLogoutAndWaitForOperationsToDrain()
    }

    public static func endLogoutCancellation() async {
        storageLogoutSyncFlag.set(false)

        await MainActor.run {
            PreferabliTools._setLoggingOutFlag(false)
        }
    }

    nonisolated
    private static func isLogoutSyncFlagSet() -> Bool {
        storageLogoutSyncFlag.get()
    }

    private static let activeStoreFilenameKey = "PreferabliSDK.activeStoreFilename"
    private static let defaultStoreFilename = "PreferabliSDK.sqlite"

    @MainActor
    private static var activeStoreFilename: String = {
        Storage.getKeyStore().string(forKey: activeStoreFilenameKey) ?? defaultStoreFilename
    }()

    @MainActor
    public static var storeURL: URL {
        applicationSupportDirectory()
            .appendingPathComponent(activeStoreFilename)
    }

    private static func applicationSupportDirectory() -> URL {
        let dir = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )

        return dir
    }

    @MainActor
    private static func setActiveStoreFilename(_ filename: String) {
        activeStoreFilename = filename
        Storage.getKeyStore().set(filename, forKey: activeStoreFilenameKey)
    }

    private static func freshStoreFilename() -> String {
        "PreferabliSDK-\(UUID().uuidString).sqlite"
    }

    private static func defaultStoreURL() -> URL {
        let dir = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return dir.appendingPathComponent("PreferabliSDK.sqlite")
    }

    private static func freshStoreURL() -> URL {
        let dir = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return dir.appendingPathComponent("PreferabliSDK-\(UUID().uuidString).sqlite")
    }
    
    public nonisolated static func makeSchema() -> Schema {
        Schema(ModelRegistry.types)
    }
    
    public nonisolated static func makeSchemaForAllModels() -> Schema {
        Schema(ModelRegistry.types)
    }

    internal static var container: ModelContainer = {
        makeContainer()
    }()
    
    /// The SDK's current container (read-only to the app).
    public static var sharedContainer: ModelContainer {
        container
    }

    /// Create a brand-new container instance.
    /// Use this from the app when logging out (or when you need a fresh container).
    public static func makeNewContainer() -> ModelContainer {
        makeContainer()
    }

    /// (Optional) Replace the SDK's shared container reference.
    /// Only needed if SDK code elsewhere reads Storage.container directly.
    public static func replaceSharedContainer(_ newContainer: ModelContainer) {
        container = newContainer
    }
    
    public nonisolated static func generateRandomLongId() -> Int {
        return -Int(arc4random() % 28147497)
    }

    @MainActor
    private static func makeContainer() -> ModelContainer {
        let schema = makeSchema()
        let url = Storage.storeURL
        let config = ModelConfiguration(schema: schema, url: url)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: [config]
            )
        } catch {
            NSLog("[PreferabliDataSDK] Failed to create ModelContainer at \(url). Error: \(error)")

            do {
                try nukePersistentStoreFiles(at: url)
                resetDatabaseKeystore()

                return try ModelContainer(
                    for: schema,
                    migrationPlan: nil,
                    configurations: [config]
                )
            } catch {
                NSLog("[PreferabliDataSDK] Retry failed. Falling back to fresh store. Error: \(error)")

                setActiveStoreFilename(freshStoreFilename())

                let fallbackURL = Storage.storeURL
                let fallbackConfig = ModelConfiguration(schema: schema, url: fallbackURL)

                do {
                    return try ModelContainer(
                        for: schema,
                        migrationPlan: nil,
                        configurations: [fallbackConfig]
                    )
                } catch {
                    NSLog("[PreferabliDataSDK] Disk store fallback failed. Using in-memory store. Error: \(error)")

                    let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

                    do {
                        return try ModelContainer(
                            for: schema,
                            migrationPlan: nil,
                            configurations: [memoryConfig]
                        )
                    } catch {
                        fatalError("[PreferabliDataSDK] Unable to create any ModelContainer: \(error)")
                    }
                }
            }
        }
    }
    
    /// Create a brand-new container instance (no caching).
    @MainActor
    internal static func newContainerInstance() -> ModelContainer {
        makeContainer()
    }

    /// Replace the global container reference with a brand-new instance.
    /// Useful if parts of the SDK still reference Storage.container directly.
    @MainActor
    internal static func rebuildSharedContainer() {
        container = makeContainer()
    }
    
    private static func nukePersistentStoreFiles(at url: URL) throws {
        let fm = FileManager.default
        let basePath = url.path

        let paths = [
            basePath,
            basePath + "-wal",
            basePath + "-shm"
        ]
        for path in paths where fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
    }

    @inline(__always)
    public static func withContext<T>(
        _ body: @MainActor (
            ModelContext,
            () throws -> Void
        ) throws -> T
    ) throws -> T {

        if PreferabliTools.isLoggingOutSync() {
            throw CancellationError()
        }

        let ctx = container.mainContext
        let old = ctx.autosaveEnabled
        ctx.autosaveEnabled = false
        defer { ctx.autosaveEnabled = old }

        let save = {
            if PreferabliTools.isLoggingOutSync() {
                throw CancellationError()
            }

            try ctx.save()
        }

        return try body(ctx, save)
    }
    
    // still updates UI since it is from the same container
    nonisolated
    public static func withBackgroundContext<T: Sendable>(
        priority: TaskPriority = .userInitiated,
        _ body: @escaping @Sendable (ModelContext) throws -> T
    ) async throws -> T {
        try await withBackgroundContext(priority: priority, allowDuringLogout: false, body)
    }

    nonisolated
    public static func withBackgroundContext<T: Sendable>(
        priority: TaskPriority = .userInitiated,
        allowDuringLogout: Bool = false,
        _ body: @escaping @Sendable (ModelContext) throws -> T
    ) async throws -> T {
        try await withBackgroundContext(priority: priority, allowDuringLogout: allowDuringLogout) { ctx, _ in
            try body(ctx)
        }
    }

    nonisolated
    public static func withBackgroundContext<T: Sendable>(
        priority: TaskPriority = .userInitiated,
        allowDuringLogout: Bool = false,
        _ body: @escaping @Sendable (
            ModelContext,
            @escaping () throws -> Void
        ) throws -> T
    ) async throws -> T {
        if !allowDuringLogout, Storage.isLogoutSyncFlagSet() {
            throw CancellationError()
        }

        let registration = await _logoutRegistry.registerOperation()
        let startingEpoch = registration.epoch
        let container = await MainActor.run { Storage.container }

        let task = Task.detached(priority: priority) { () throws -> T in
            try Task.checkCancellation()

            if !allowDuringLogout, Storage.isLogoutSyncFlagSet() {
                throw CancellationError()
            }

            let nowEpoch = await _logoutRegistry.currentEpoch()
            if nowEpoch != startingEpoch {
                throw CancellationError()
            }

            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false

            let save: () throws -> Void = {
                try Task.checkCancellation()

                if !allowDuringLogout, Storage.isLogoutSyncFlagSet() {
                    throw CancellationError()
                }

                try ctx.save()

                try Task.checkCancellation()
            }

            let result = try body(ctx, save)

            try Task.checkCancellation()

            if !allowDuringLogout, Storage.isLogoutSyncFlagSet() {
                throw CancellationError()
            }

            let endEpoch = await _logoutRegistry.currentEpoch()
            if endEpoch != startingEpoch {
                throw CancellationError()
            }

            return result
        }

        await _logoutRegistry.setCanceller({ task.cancel() }, for: registration.id)

        do {
            let value = try await task.value
            await _logoutRegistry.finishOperation(registration.id)
            return value
        } catch {
            await _logoutRegistry.finishOperation(registration.id)
            throw error
        }
    }

    nonisolated
    public static func withBackgroundContextAsync<T: Sendable>(
        priority: TaskPriority = .background,
        allowDuringLogout: Bool = false,
        _ body: @escaping @Sendable (ModelContext) async throws -> T
    ) async throws -> T {
        if !allowDuringLogout, await PreferabliTools.isLoggingOut() {
            throw CancellationError()
        }

        let registration = await _logoutRegistry.registerOperation()
        let startingEpoch = registration.epoch
        let container = await MainActor.run { Storage.container }

        let task = Task.detached(priority: priority) { () async throws -> T in
            try Task.checkCancellation()

            if !allowDuringLogout, await PreferabliTools.isLoggingOut() {
                throw CancellationError()
            }

            let nowEpoch = await _logoutRegistry.currentEpoch()
            if nowEpoch != startingEpoch {
                throw CancellationError()
            }

            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false

            let result = try await body(ctx)

            try Task.checkCancellation()

            let endEpoch = await _logoutRegistry.currentEpoch()
            if endEpoch != startingEpoch {
                throw CancellationError()
            }

            return result
        }

        await _logoutRegistry.setCanceller({ task.cancel() }, for: registration.id)

        do {
            let value = try await task.value
            await _logoutRegistry.finishOperation(registration.id)
            return value
        } catch {
            await _logoutRegistry.finishOperation(registration.id)
            throw error
        }
    }

    internal static func reset() async throws {
        try await withBackgroundContextAsync(priority: .userInitiated, allowDuringLogout: true) { ctx in
            ctx.autosaveEnabled = false
            ctx.author = "LogoutWipe"

            for wipe in ModelRegistry.wipes {
                try await wipe(ctx)
            }
            return ()
        }
    }

    @MainActor
    internal static func databaseUpgraded() async throws {
        let oldURL = Storage.storeURL

        setActiveStoreFilename(freshStoreFilename())
        resetDatabaseKeystore()

        let newContainer = makeContainer()
        Storage.container = newContainer

        scheduleDeferredStoreCleanup(oldURL)
    }
    
    private static let pendingStoreCleanupURLsKey = "PreferabliSDK.pendingStoreCleanupURLs"

    @MainActor
    private static func scheduleDeferredStoreCleanup(_ url: URL) {
        enqueueStoreCleanup(url)

        Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(10))

            await MainActor.run {
                cleanupPendingStores()
            }
        }
    }

    @MainActor
    private static func enqueueStoreCleanup(_ url: URL) {
        var paths = Storage.getKeyStore().stringArray(forKey: pendingStoreCleanupURLsKey) ?? []
        let path = url.path

        if !paths.contains(path) {
            paths.append(path)
            Storage.getKeyStore().set(paths, forKey: pendingStoreCleanupURLsKey)
        }
    }

    @MainActor
    public static func cleanupPendingStores() {
        let currentPath = Storage.storeURL.path

        var paths = Storage.getKeyStore().stringArray(forKey: pendingStoreCleanupURLsKey) ?? []
        paths.removeAll { path in
            guard path != currentPath else { return false }

            do {
                try nukePersistentStoreFiles(at: URL(fileURLWithPath: path))
                return true
            } catch {
                NSLog("[PreferabliDataSDK] Deferred store cleanup failed for \(path): \(error)")
                return false
            }
        }

        Storage.getKeyStore().set(paths, forKey: pendingStoreCleanupURLsKey)
    }
    
    @MainActor
    public static func logoutReset() async throws {
        let oldURL = Storage.storeURL

        setActiveStoreFilename(freshStoreFilename())
        resetDatabaseKeystore()

        let newContainer = makeContainer()
        Storage.container = newContainer

        scheduleDeferredStoreCleanup(oldURL)
    }
    
    @MainActor
    private static func makeEphemeralContainer() -> ModelContainer {
        let schema = makeSchema()
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: [config]
            )
        } catch {
            fatalError("[PreferabliDataSDK] Unable to create ephemeral ModelContainer: \(error)")
        }
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
    
    @inline(__always)
    nonisolated internal static func deleteAllBatchedFreshContext<T: PersistentModel>(
      _ type: T.Type,
      container: ModelContainer,
      batchSize: Int = 5000
    ) throws {
      let limit = max(1, min(batchSize, 10_000))

      while true {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        var fd = FetchDescriptor<T>()
        fd.fetchLimit = limit

        let batch = try ctx.fetch(fd)
        if batch.isEmpty { break }

        for obj in batch { ctx.delete(obj) }
        try ctx.save()
        // ctx goes out of scope here -> drops invalidated faults
      }
    }
}

private enum ModelRegistry {
    typealias Wipe = @Sendable (ModelContext) async throws -> Void
    
    /// Single source of truth: call `add(<Type>.self)` here ONCE.
    private static func register(addType: (any PersistentModel.Type) -> Void, addWipe: (@escaping Wipe) -> Void) {
        func add<T: PersistentModel>(_ t: T.Type) {
            addType(T.self)
            addWipe { ctx in
              // ignore `ctx` and delete using fresh contexts
              let container = ctx.container
              try Storage.deleteAllBatchedFreshContext(T.self, container: container)
            }
        }
        
        // try to order these children -> parents

        // Itinerary associations/children must be wiped before their parent records,
        // and before the Venue, Experience, MarketTrait, Market, and Media targets.
        add(ItineraryItemAssociation.self)
        add(ItineraryMarketTrait.self)
        add(ItineraryItem.self)
        add(Itinerary.self)
        
        add(ExperienceType.self)
        add(ExperiencePrice.self)
        add(ExperienceOperationHoursNormal.self)
        add(Experience.self)
        add(Affiliate.self)
        
        add(GenAIUtteranceContent.self)
        add(GenAIUtterance.self)
        add(GenAIMessage.self)
        

        add(Location.self)
        add(Media.self)
        add(Customer.self)
        add(PreferabliUser.self)
        add(PreferenceData.self)

        add(Style.self)
        add(ProfileStyle.self)
        add(Profile.self)
        
        add(Search.self)
        add(Occasion.self)
        add(PushNotificationReceipt.self)
        
        add(VenueHour.self)
        add(MarketTrait.self)
        add(VenueMarketTrait.self)
        add(Venue.self)
        
        add(Recipe.self)
        add(RecipeGroup.self)
        
        add(UserCollection.self)
        add(CollectionTrait.self)
        add(CollectionOrder.self)
        add(CollectionGroup.self)
        add(CollectionVersion.self)
        add(Collection.self)
        add(ChannelVenue.self)
        add(Channel.self)
        
        add(DeliveryMethod.self)
        add(Food.self)
        add(FoodCategory.self)
        add(ReservationRequestGuest.self)
        add(Reservation.self)
        
        add(ProductProfile.self)
        add(Tag.self)
        add(Variant.self)
        add(ProductRecipe.self)
        add(Product.self)
        
        add(MarketTraitAssociation.self)
        add(Market.self)
        
        add(CTABucketItem.self)
        add(CTABucketItemAssociation.self)
        add(CTABucket.self)
        add(CTABucketAssociation.self)
        add(CTAPage.self)
        
        // Content / Personality
        // Keep association rows before their parent/root models for wipe ordering.
        add(ContentPersonalityAssociation.self)
        add(ContentVariantAssociation.self)
        add(ContentChannelAssociation.self)
        add(ContentVenueAssociation.self)
        add(ContentExperienceAssociation.self)
        add(ContentMarketTraitAssociation.self)
        add(ContentItem.self)
        add(Personality.self)
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
        
        public func experiences(withIDs ids: [Int]) -> Predicate<Experience> { ids.isEmpty ? #Predicate { _ in false } : #Predicate { p in ids.contains(p.id) } }
        
        public func venues(withIDs ids: [Int]) -> Predicate<Venue> { ids.isEmpty ? #Predicate { _ in false } : #Predicate { p in ids.contains(p.id) } }

        public func itineraries(forMarketID marketID: Int) -> Predicate<Itinerary> {
            #Predicate<Itinerary> { itinerary in
                itinerary.market_id == marketID
            }
        }
        
        public func tags(for spec: CollectionSpec) -> (predicate: Predicate<Tag>, sort: [SortDescriptor<Tag>]) {
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
        
        public func cellars() -> Predicate<UserCollection> {
            #Predicate<UserCollection> { uc in
                (uc.relationship_type ?? "") == "mycellar"
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
    nonisolated static public func fetchById<T: HasIntID>(
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
    
    @inline(__always)
    nonisolated static public func fetchById<T: HasStringID>(
        _ type: T.Type,
        id: String?,
        in ctx: ModelContext
    ) throws -> T? {
        guard let id else { return nil }
        var fd = FetchDescriptor<T>(predicate: T.predicate(forID: id))
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }

    nonisolated static func fetchOrInsert<T: HasStringID>(
        _ type: T.Type,
        id: String,
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
    
    nonisolated static func fetchByKey<T: PersistentModel>(
        _ type: T.Type,
        key: String,
        in ctx: ModelContext
    ) throws -> T? where T: AnyObject {
        // Key-backed SwiftData models use the specialized overloads below.
        fatalError("Use specialized fetchByKey implementations.")
    }

    nonisolated static func fetchByKey(
        _ type: VenueMarketTrait.Type,
        key: String,
        in ctx: ModelContext
    ) throws -> VenueMarketTrait? {
        var fd = FetchDescriptor<VenueMarketTrait>(predicate: VenueMarketTrait.predicate(forKey: key))
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }

    nonisolated static func fetchByKey(
        _ type: ItineraryMarketTrait.Type,
        key: String,
        in ctx: ModelContext
    ) throws -> ItineraryMarketTrait? {
        var fd = FetchDescriptor<ItineraryMarketTrait>(
            predicate: ItineraryMarketTrait.predicate(forKey: key)
        )
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }
    
    nonisolated static func fetchByKey(
        _ type: ProductRecipe.Type,
        key: String,
        in ctx: ModelContext
    ) throws -> ProductRecipe? {
        var fd = FetchDescriptor<ProductRecipe>(predicate: ProductRecipe.predicate(forKey: key))
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }
    
    nonisolated static func fetchByKey(
        _ type: ReservationRequestGuest.Type,
        key: String,
        in ctx: ModelContext
    ) throws -> ReservationRequestGuest? {
        var fd = FetchDescriptor<ReservationRequestGuest>(
            predicate: ReservationRequestGuest.predicate(forKey: key)
        )
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }
}


// Coercers / parsing
extension Storage {
    
    // this is for Fabricio's Tastefuli calls
    nonisolated static func normalizeAPIDateString(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = iso.date(from: raw) else { return raw }

        let out = DateFormatter()
        out.calendar = Calendar(identifier: .gregorian)
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = TimeZone(secondsFromGMT: 0)
        out.dateFormat = "yyyy-MM-dd"

        return out.string(from: date)
    }
    
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
        batchSize: Int = 150,
        log: @Sendable @escaping (String) -> Void = { _ in }
    ) async {
        do {
            try await Storage.withBackgroundContextAsync(priority: .background) { ctx in
                ctx.autosaveEnabled = false
                ctx.author = "TombstonePruner"

                try await pruneTags(in: ctx, batchSize: batchSize, log: log)
                log("Pruned tombstoned Tags")

                try await pruneVariants(in: ctx, batchSize: batchSize, log: log)
                log("Pruned tombstoned Variants")

                return ()
            }
        } catch {
            log("Tombstone prune failed: \(error)")
        }
    }

    nonisolated private static func pruneBatched<T: PersistentModel>(
        _ type: T.Type,
        in ctx: ModelContext,
        batchSize: Int,
        predicate: Predicate<T>,
        sort: [SortDescriptor<T>],
        label: String,
        log: @Sendable @escaping (String) -> Void
    ) async throws {
        let limit = max(1, min(batchSize, 2_000))

        while true {
            try Task.checkCancellation()

            let deletedCount: Int = try autoreleasepool {
                var fd = FetchDescriptor<T>(predicate: predicate)
                fd.fetchLimit = limit
                fd.sortBy = sort

                let doomed = try ctx.fetch(fd)
                if doomed.isEmpty { return 0 }

                for obj in doomed { ctx.delete(obj) }

                try ctx.save()
                return doomed.count
            }

            if deletedCount == 0 { return }

            log("Pruned \(deletedCount) \(label) (batch)")

            // ✅ True cooperative yield
            await Task.yield()
        }
    }
    
    nonisolated private static func pruneTags(
        in ctx: ModelContext,
        batchSize: Int,
        log: @Sendable @escaping (String) -> Void
    ) async throws {
        try await pruneBatched(
            Tag.self,
            in: ctx,
            batchSize: batchSize,
            predicate: #Predicate<Tag> { $0.isTombstoned == true },
            sort: [SortDescriptor(\Tag.id, order: .forward)],
            label: "Tags",
            log: log
        )
    }

    nonisolated private static func pruneVariants(
        in ctx: ModelContext,
        batchSize: Int,
        log: @Sendable @escaping (String) -> Void
    ) async throws {
        try await pruneBatched(
            Variant.self,
            in: ctx,
            batchSize: batchSize,
            predicate: #Predicate<Variant> { $0.isTombstoned == true },
            sort: [SortDescriptor(\Variant.id, order: .forward)],
            label: "Variants",
            log: log
        )
    }
}

extension Storage {
    /// Re-indexes the `searchableContent` for all Tags.
    /// This is useful if underlying Product data (name, brand, etc.) has changed.
    /// Executes on a background ModelContext separate from the UI.
    nonisolated public static func reindexSearchableContent(
        batchSize: Int = 150,
        log: @Sendable @escaping (String) -> Void = { _ in }
    ) async {
        do {
            try await Storage.withBackgroundContextAsync(priority: .background) { ctx in
                ctx.autosaveEnabled = false
                ctx.author = "SearchReindexer"

                try await reindexTags(in: ctx, batchSize: batchSize, log: log)
                log("Completed search re-indexing for all Tags.")
                return ()
            }
        } catch is CancellationError {
            log("Search re-indexing cancelled.")
        } catch {
            log("Search re-indexing failed: \(error)")
        }
    }
    
    /// Fetches all Tags in batches and updates their `searchableContent`.
    nonisolated private static func reindexTags(
        in ctx: ModelContext,
        batchSize: Int,
        log: @Sendable @escaping (String) -> Void
    ) async throws {
        let limit = max(1, min(batchSize, 500))     // keep interactive-friendly
        var lastID: Int = Int.min
        var totalProcessed = 0

        while true {
            try Task.checkCancellation()

            let processedThisBatch: Int = try autoreleasepool {
                // Cursor paging avoids `fetchOffset` overhead.
                var fd = FetchDescriptor<Tag>(
                    predicate: #Predicate<Tag> { $0.id > lastID }
                )
                fd.fetchLimit = limit
                fd.sortBy = [SortDescriptor(\Tag.id, order: .forward)]

                // Prefetch what updateSearchableContent() needs
                fd.relationshipKeyPathsForPrefetching = [
                    \Tag.variant,
                    \Tag.variant.product
                ]

                let tags = try ctx.fetch(fd)
                if tags.isEmpty { return 0 }

                for tag in tags {
                    tag.updateSearchableContent()
                }

                try ctx.save()

                lastID = tags.last?.id ?? lastID
                return tags.count
            }

            if processedThisBatch == 0 { break }

            totalProcessed += processedThisBatch
            log("Re-indexed batch of \(processedThisBatch) tags (total: \(totalProcessed))")

            // ✅ Cooperative scheduling so UI work can proceed
            await Task.yield()
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
