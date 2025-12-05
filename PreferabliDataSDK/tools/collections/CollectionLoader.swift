//
//  CollectionEvent.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/31/25.
//


import Foundation
import SwiftData

// MARK: - Public Events

public enum CollectionEvent: Sendable {
    case snapshot(count: Int)
    case page(insertedCount: Int)
    case done(total: Int)
    case failed(PreferabliException)
}

// MARK: - Collection Spec

/// Describes how to locate and manage a specific collection that is backed by Tags.
public enum CollectionLoadMode: Sendable {
    case tags
    case orderings
}

public protocol CollectionSpec: Sendable {
    /// UserDefaults key that stores the collection's ID (e.g., "ratings_id", "wishlist_id", "jumpstart_id", "cellar_id").
    var idKey: String { get }
    /// Namespaced key prefix used for hasLoaded/lastCalled flags. When absent, `idKey` will be used.
    var namespace: String { get }
    /// Optional type filter for Tag.tag_type when querying locally (only relevant for `.tags` mode).
    var tagType: TagType? { get }
    /// Page size for network fetch.
    var pageLimit: Int { get }
    /// Freshness window in minutes for background warmups.
    var freshnessMinutes: Int { get }
    /// How this collection should be loaded.
    var loadMode: CollectionLoadMode { get }
}

public extension CollectionSpec {
    var namespace: String { idKey }
    var pageLimit: Int { 50 }
    var freshnessMinutes: Int { 86400 }
    var tagType: TagType? { nil }
}

/// Built-in specs for common collections.
public enum BuiltInCollection: CollectionSpec {
    case ratings
    case wishlist
    case jumpstart          // new, example
    case custom(
        idKey: String,
        tagType: TagType? = nil,
        freshnessMinutes: Int = 5,
        pageLimit: Int = 50,
        loadMode: CollectionLoadMode = .tags
    )
    
    public var idKey: String {
        switch self {
        case .ratings:  return "ratings_id"
        case .wishlist: return "wishlist_id"
        case .jumpstart: return "jumpstart_id"
        case .custom(let idKey, _, _, _, _): return idKey
        }
    }
    
    public var tagType: TagType? {
        switch self {
        case .ratings:  return .RATING
        case .wishlist: return .WISHLIST
        case .jumpstart: return .COLLECTION   // not tag-filtered; we use CollectionOrder
        case .custom(_, let tt, _, _, _): return tt
        }
    }
    
    public var pageLimit: Int {
        switch self {
        case .custom(_, _, _, let limit, _): return limit
        default: return 50
        }
    }
    
    public var freshnessMinutes: Int {
        switch self {
        case .custom(_, _, let m, _, _): return m
        default: return 86400
        }
    }
    
    public var loadMode: CollectionLoadMode {
        switch self {
        case .ratings, .wishlist:
            return .tags
        case .jumpstart:
            return .orderings
        case .custom(_, _, _, _, let mode):
            return mode
        }
    }
}


// MARK: - Loader

/// A single, generalized loader capable of streaming any tag-backed collection (ratings, wishlist, etc.).
public actor CollectionLoader {
    public static let shared = CollectionLoader()
    
    // Per-collection state
    private struct RunState {
        var task: Task<Void, Never>?
        var listeners: [UUID: AsyncStream<CollectionEvent>.Continuation] = [:]
        var isRunning: Bool = false
    }
    
    private var runs: [String: RunState] = [:] // key = namespace + resolvedId
    
    // MARK: Public API
    
    /// Warm a collection in the background if needed (e.g., app start).
    public func ensureWarm(_ spec: CollectionSpec) {
        guard let key = resolvedKey(spec) else { return }
        if shouldStart(spec) { startIfNeeded(key: key, spec: spec) }
    }
    
    /// Observe streaming progress for a collection (e.g., when a screen appears).
    public func observe(_ spec: CollectionSpec, forceRefresh: Bool = false) -> AsyncStream<CollectionEvent> {
        let id = UUID()
        let key = resolvedKey(spec) ?? "\(spec.namespace)#-1"
        
        return AsyncStream<CollectionEvent> { continuation in
            Task { await self.register(id: id, key: key, spec: spec, cont: continuation, forceRefresh: forceRefresh) }
        }
    }
    
    /// Optional: explicit refresh hook for pull-to-refresh UX.
    public func forceRefresh(_ spec: CollectionSpec) {
        guard let key = resolvedKey(spec) else { return }
        startIfNeeded(key: key, spec: spec, forceRefresh: true)
    }
    
    // MARK: Internals
    
    private func register(
        id: UUID,
        key: String,
        spec: CollectionSpec,
        cont: AsyncStream<CollectionEvent>.Continuation,
        forceRefresh: Bool
    ) async {
        ensureState(for: key)
        runs[key]!.listeners[id] = cont
        
        // Immediate snapshot from local store
        Task {
            let count: Int = try await Storage.withBackgroundContext { ctx in
                let cid = Storage.getKeyStore().integer(forKey: spec.idKey)
                
                switch spec.loadMode {
                case .tags:
                    let fd: FetchDescriptor<Tag>
                    if let tt = spec.tagType {
                        let raw = tt.getDatabaseName()
                        fd = FetchDescriptor(
                            predicate: #Predicate<Tag> {
                                $0.collection_id == cid && $0.type == raw
                            }
                        )
                    } else {
                        fd = FetchDescriptor(
                            predicate: #Predicate<Tag> {
                                $0.collection_id == cid
                            }
                        )
                    }
                    return try ctx.fetchCount(fd)
                    
                case .orderings:
                    let fd = FetchDescriptor<CollectionOrder>(
                        predicate: #Predicate<CollectionOrder> {
                            $0.group.version.collection.id == cid
                        }
                    )
                    return try ctx.fetchCount(fd)
                }
            }
            cont.yield(.snapshot(count: count))
        }
        
        if forceRefresh || shouldStart(spec) {
            startIfNeeded(key: key, spec: spec, forceRefresh: forceRefresh)
        }
        
        cont.onTermination = { _ in
            Task { await self.removeListener(id: id, key: key) }
        }
    }
    
    private func shouldStart(_ spec: CollectionSpec) -> Bool {
        let ks = Storage.getKeyStore()
        let cid = ks.integer(forKey: spec.idKey)
        let has = ks.bool(forKey: "hasLoaded\(spec.namespace)#\(cid)")
        let last = ks.object(forKey: "lastCalled\(spec.namespace)#\(cid)") as? Date
        let stale = PreferabliTools.hasMinutesPassed(minutes: spec.freshnessMinutes, startDate: last)
        return !has || stale
    }
    
    private func resolvedKey(_ spec: CollectionSpec) -> String? {
        let ks = Storage.getKeyStore()
        let cid = ks.integer(forKey: spec.idKey)
        guard cid > 0 else { return nil }
        return "\(spec.namespace)#\(cid)"
    }
    
    private func ensureState(for key: String) {
        if runs[key] == nil { runs[key] = RunState() }
    }
    
    private func removeListener(id: UUID, key: String) {
        guard runs[key] != nil else { return }
        runs[key]!.listeners.removeValue(forKey: id)
        // if no listeners and not running, we could prune state (optional)
    }
    
    private func startIfNeeded(key: String, spec: CollectionSpec, forceRefresh: Bool = false) {
        ensureState(for: key)
        guard runs[key]!.isRunning == false else { return }
        runs[key]!.isRunning = true
        
        runs[key]!.task = Task.detached { [weak self] in
            do {
                try await self?.run(key: key, spec: spec, forceRefresh: forceRefresh)
            } catch let e as PreferabliException {
                await self?.broadcast(.failed(e), key: key)
            } catch {
                await self?.broadcast(.failed(PreferabliException(type: .OtherError, message: error.localizedDescription)), key: key)
            }
            await self?.finish(key: key)
        }
    }
    
    private func run(key: String, spec: CollectionSpec, forceRefresh: Bool) async throws {
        try await Preferabli.main.canWeContinue(needsToBeLoggedIn: false)
        
        switch spec.loadMode {
        case .tags:
            try await runTags(key: key, spec: spec, forceRefresh: forceRefresh)
        case .orderings:
            try await runOrderings(key: key, spec: spec, forceRefresh: forceRefresh)
        }
    }

    private func runOrderings(
        key: String,
        spec: CollectionSpec,
        forceRefresh: Bool
    ) async throws {
        let ks = Storage.getKeyStore()
        let cid = ks.integer(forKey: spec.idKey)
        guard cid > 0 else { return }
        
        let has = ks.bool(forKey: "hasLoaded\(key)")
        let last = ks.object(forKey: "lastCalled\(key)") as? Date
        let stale = PreferabliTools.hasMinutesPassed(
            minutes: spec.freshnessMinutes,
            startDate: last
        )
        
        if has && !forceRefresh && !stale {
            await broadcast(.done(total: 0), key: key)
            return
        }
        
        // 1) Ensure we have the Collection + versions/groups in SwiftData.
        try await ensureCollectionMetadata(collectionId: cid)
        
        // 2) Get first version + ordered groups.
        let (versionId, groupIds) = try await Storage.withBackgroundContext { ctx -> (Int, [Int]) in
            guard let collection = try Storage.fetchById(Collection.self, id: cid, in: ctx) else {
                throw PreferabliException(
                    type: .BadSwiftData,
                    message: "Collection \(cid) not found for ordered load.",
                    code: 700
                )
            }
            
            guard let version = collection
                .versions
                .sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) })
                .first
            else {
                throw PreferabliException(
                    type: .BadSwiftData,
                    message: "Collection \(cid) has no versions.",
                    code: 701
                )
            }

            let groups = CollectionGroup.sortGroups(groups: Array(version.groups))
            return (version.id, groups.map { $0.id })
        }
        
        let limit = spec.pageLimit
        var totalInserted = 0
        
        // 3) Walk each group, load orderings + tags + products page by page.
        for gid in groupIds {
            var offset = 0
            
            groupLoop: while true {
                // A) Fetch orderings page
                let orderDTOs: [CollectionOrderDTO] = try await Preferabli.main.api
                    .getAlamo()
                    .get(
                        APIEndpoints.orderings(
                            collectionId: cid,
                            versionId: versionId,
                            groupId: gid
                        ),
                        sparams: ["offset": offset, "limit": limit]
                    )
                
                if orderDTOs.isEmpty {
                    break groupLoop
                }
                
                // B) Tags for these orderings
                let tagIds = orderDTOs.map { $0.tag_id }
                let tagDTOs: [TagDTO] = try await Preferabli.main.api
                    .getAlamo()
                    .get(APIEndpoints.tags(id: cid),
                         sparams: ["tag_ids": tagIds])
                
                // C) Products for tags’ variants (only for missing variants)
                let allVariantIds = tagDTOs.compactMap { $0.variant_id }
                let productDTOs: [ProductDTO]

                if !allVariantIds.isEmpty {
                    // Determine which variant IDs are **not yet** stored in SwiftData
                    let missingVariantIds: [Int] = try await Storage.withBackgroundContext { ctx in
                        try Storage.missingVariantIds(from: allVariantIds, in: ctx)
                    }
                    
                    if !missingVariantIds.isEmpty {
                        // Only fetch products for the missing variants
                        productDTOs = try await Preferabli.main.api
                            .getAlamo()
                            .get(
                                APIEndpoints.products,
                                sparams: ["variant_ids": missingVariantIds]
                            )
                    } else {
                        // Everything already present locally
                        productDTOs = []
                    }
                } else {
                    // No variants on this page
                    productDTOs = []
                }

                
                // D) Persist everything in a background context
                let errors: [PreferabliException] = try await Storage.withBackgroundContext { ctx in
                    var localErrors: [PreferabliException] = []
                    
                    // 1) Products
                    for pd in productDTOs {
                        _ = try Storage.upsertProduct(from: pd, in: ctx)
                    }
                    
                    // 2) Tags (remember by id)
                    var tagById: [Int: Tag] = [:]
                    for td in tagDTOs {
                        let vid = td.variant_id
                        guard let variant = try Storage.fetchById(Variant.self, id: vid, in: ctx)
                        else { continue }
                        let tag = try Storage.upsertTag(from: td, variant: variant, in: ctx)
                        tagById[tag.id] = tag
                    }
                    
                    // 3) Group
                    guard let group = try Storage.fetchById(CollectionGroup.self, id: gid, in: ctx) else {
                        localErrors.append(
                            PreferabliException(
                                type: .BadSwiftData,
                                message: "Group \(gid) missing in ordered loader.",
                                code: 702
                            )
                        )
                        try ctx.save()
                        return localErrors
                    }
                    
                    // 4) Orders
                    for orderDTO in orderDTOs {
                        guard
                            let tag   = tagById[orderDTO.tag_id]
                        else { continue }
                        
                        _ = try Storage.upsertCollectionOrder(
                            from: orderDTO,
                            group: group,
                            tag: tag,
                            in: ctx
                        )
                    }
                    
                    try ctx.save()
                    return localErrors
                }
                
                if !errors.isEmpty {
                    await MainActor.run {
                        for e in errors {
                            Preferabli.main.handleError(error: e)
                        }
                    }
                }
                
                totalInserted += orderDTOs.count
                await broadcast(.page(insertedCount: orderDTOs.count), key: key)
                
                offset += limit
            }
        }
        
        ks.set(Date(), forKey: "lastCalled\(key)")
        ks.set(true, forKey: "hasLoaded\(key)")
        
        await broadcast(.done(total: totalInserted), key: key)
    }

    
    private func runTags(key: String, spec: CollectionSpec, forceRefresh: Bool) async throws {
        let ks = Storage.getKeyStore()
        let cid = ks.integer(forKey: spec.idKey)
        var offset = 0
        let limit = spec.pageLimit
        
        if forceRefresh {
            // e.g., APIService.clearCache(for: key)
        }
        
        var totalInserted = 0
        while true {
            // 1) Fetch a page of tags
            let tagDTOS: [TagDTO] = try await Preferabli.main.api.getAlamo().get(APIEndpoints.tags(id: cid), sparams: ["offset": offset, "limit": limit])
            if tagDTOS.isEmpty { break }
            
            // 2) Collect variant ids on this page
            let allVariantIDsOnPage = tagDTOS.compactMap { $0.variant_id }
            
            // 3) Determine missing variants and fetch only those products
            let productDTOs: [ProductDTO]
            if !allVariantIDsOnPage.isEmpty {
                let missingVariantIDs: [Int] = try await Storage.withBackgroundContext { ctx in
                    try Storage.missingVariantIds(from: allVariantIDsOnPage, in: ctx)
                }
                
                if !missingVariantIDs.isEmpty {
                    productDTOs = try await Preferabli.main.api
                        .getAlamo()
                        .get(APIEndpoints.products,
                             sparams: ["variant_ids": missingVariantIDs])
                } else {
                    productDTOs = []
                }
            } else {
                productDTOs = []
            }
            // --- FIX END ---
            // 'productDTOs' is now an immutable 'let' and is safe to capture.
            
            // 5) Save products (if any) and all tags
            let errors: [PreferabliException] = try await Storage.withBackgroundContext { ctx in
                var localErrors: [PreferabliException] = []
                
                // This capture is now safe.
                for pd in productDTOs {
                    _ = try Storage.upsertProduct(from: pd, in: ctx)
                }
                
                for td in tagDTOS {
                    guard let variant = try Storage.fetchById(Variant.self, id: td.variant_id, in: ctx) else {
                        localErrors.append(
                            PreferabliException(
                                type: .BadSwiftData,
                                message: "Could not save tag \(td.id) because its Variant \(td.variant_id) was not found in the database.",
                                code: 601
                            )
                        )
                        continue
                    }
                    _ = try Storage.upsertTag(from: td, variant: variant, in: ctx)
                }
                
                try ctx.save()
                return localErrors
            }
            
            // 6) Handle errors
            if !errors.isEmpty {
                await MainActor.run {
                    for e in errors {
                        Preferabli.main.handleError(error: e)
                    }
                }
            }
            
            // 7) Update state and broadcast
            totalInserted += tagDTOS.count
            await broadcast(.page(insertedCount: tagDTOS.count), key: key)
            offset += limit
        }
        
        // 8) Flags
        ks.set(Date(), forKey: "lastCalled\(key)")
        ks.set(true, forKey: "hasLoaded\(key)")
        
        await broadcast(.done(total: totalInserted), key: key)
    }
    
    private func ensureCollectionMetadata(collectionId: Int) async throws {
        // 1) Check if the Collection already exists (background context)
        let exists = try await Storage.withBackgroundContext { ctx in
            try Storage.fetchById(Collection.self, id: collectionId, in: ctx) != nil
        }
        if exists { return }
        
        // 2) Fetch from API
        let dto: CollectionDTO = try await Preferabli.main.api
            .getAlamo()
            .get(APIEndpoints.collection(id: collectionId))
        
        // 3) Upsert into SwiftData (background context again)
        try await Storage.withBackgroundContext { ctx in
            _ = try Storage.upsertCollection(from: dto, in: ctx)
            try ctx.save()
        }
    }

    private func finish(key: String) {
        guard runs[key] != nil else { return }
        runs[key]!.isRunning = false
        runs[key]!.task = nil
    }
    
    private func broadcast(_ event: CollectionEvent, key: String) {
        guard let listeners = runs[key]?.listeners else { return }
        for (_, cont) in listeners { cont.yield(event) }
    }
}
