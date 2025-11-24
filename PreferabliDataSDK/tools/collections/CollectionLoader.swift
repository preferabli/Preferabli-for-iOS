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
public protocol CollectionSpec: Sendable {
    /// UserDefaults key that stores the collection's ID (e.g., "ratings_id", "wishlist_id").
    var idKey: String { get }
    /// Namespaced key prefix used for hasLoaded/lastCalled flags. When absent, `idKey` will be used.
    var namespace: String { get }
    /// Optional type filter for Tag.tag_type when querying locally.
    var tagType: TagType? { get }
    /// Page size for network fetch. Defaults to 50.
    var pageLimit: Int { get }
    /// Freshness window in minutes for background warmups.
    var freshnessMinutes: Int { get }
}

public extension CollectionSpec {
    var namespace: String { idKey }
    var extraTagParams: [String: Any] { [:] }
    var pageLimit: Int { 50 }
    var freshnessMinutes: Int { 86400 }
}

/// Built-in specs for common collections.
public enum BuiltInCollection: CollectionSpec {
    case ratings
    case wishlist
    case custom(idKey: String, tagType: TagType? = nil, freshnessMinutes: Int = 5, pageLimit: Int = 50)
    
    public var idKey: String {
        switch self {
        case .ratings: return "ratings_id"
        case .wishlist: return "wishlist_id"
        case .custom(let idKey, _, _, _): return idKey
        }
    }
    public var tagType: TagType? {
        switch self {
        case .ratings: return .RATING
        case .wishlist: return .WISHLIST
        case .custom(_, let tt, _, _): return tt
        }
    }
    public var pageLimit: Int {
        switch self {
        case .custom(_, _, _, let limit): return limit
        default: return 50
        }
    }
    public var freshnessMinutes: Int {
        switch self {
        case .custom(_, _, let m, _): return m
        default: return 86400
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
    
    private func register(id: UUID, key: String, spec: CollectionSpec, cont: AsyncStream<CollectionEvent>.Continuation, forceRefresh: Bool) async {
        ensureState(for: key)
        runs[key]!.listeners[id] = cont
        
        // Immediate snapshot from local store
        Task {
            let count: Int = try await MainActor.run {
                try Storage.withContext { ctx in
                    let cid = Storage.getKeyStore().integer(forKey: spec.idKey)
                    
                    let fd: FetchDescriptor<Tag>
                    if let tt = spec.tagType {
                        let raw = tt.getDatabaseName() // matches Tag.type optionality
                        fd = FetchDescriptor<Tag>(
                            predicate: #Predicate<Tag> {
                                $0.collection_id == cid && $0.type == raw
                            }
                        )
                    } else {
                        fd = FetchDescriptor<Tag>(
                            predicate: #Predicate<Tag> {
                                $0.collection_id == cid
                            }
                        )
                    }
                    
                    return try ctx.fetchCount(fd)
                }
            }
            cont.yield(.snapshot(count: count))
        }
        
        
        // Start a run if needed
        if forceRefresh || shouldStart(spec) { startIfNeeded(key: key, spec: spec, forceRefresh: forceRefresh) }
        
        cont.onTermination = { _ in Task { await self.removeListener(id: id, key: key) } }
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
        try await Preferabli.main.canWeContinue(needsToBeLoggedIn: true)
        
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
            
            // 2) Collect variant ids
            let allVariantIDsOnPage = tagDTOS.compactMap { $0.variant_id }
            
            // --- FIX START ---
            // Declare productDTOs as a 'let' constant.
            let productDTOs: [ProductDTO]
            
            if !allVariantIDsOnPage.isEmpty {
                // 3) Find which of these variants are *missing*
                let missingVariantIDs: [Int] = try await Storage.withBackgroundContext { ctx in
                    let predicate = #Predicate<Variant> { variant in
                        allVariantIDsOnPage.contains(variant.id)
                    }
                    let fetchDescriptor = FetchDescriptor<Variant>(predicate: predicate)
                    
                    let existingVariants = try ctx.fetch(fetchDescriptor)
                    let existingIDs = Set(existingVariants.map { $0.id })
                    let allIDs = Set(allVariantIDsOnPage)
                    
                    let missingIDs = allIDs.subtracting(existingIDs)
                    return Array(missingIDs)
                }
                
                // 4) Fetch products *only* for the missing variants
                if !missingVariantIDs.isEmpty {
                    // Assign the fetched products
                    productDTOs = try await Preferabli.main.api.getAlamo().get(APIEndpoints.products, sparams: ["variant_ids": missingVariantIDs])
                } else {
                    // Assign an empty array if no variants were missing
                    productDTOs = []
                }
                
            } else {
                // Assign an empty array if there were no variant IDs on the page
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
