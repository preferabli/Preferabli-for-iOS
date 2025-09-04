//
//  LoadCollectionTools.swift
//  Preferabli
//
//  Updated to SwiftData + Storage.withContext pattern, async/await
//

import Foundation
import SwiftData

/// Contains methods that help load `Collection`s.
internal final class LoadCollectionTools {

    internal static let sharedInstance = LoadCollectionTools()

    // MARK: Public entry points

    /// Top-level orchestrator that ensures a collection is loaded via Tags.
    /// Triggers a background refresh if stale; otherwise no-ops.
    internal func loadCollectionViaTags(
        priority: Operation.QueuePriority,
        force_refresh: Bool,
        collection_id: Int
    ) async throws {
        let ks = PreferabliTools.getKeyStore()

        if force_refresh || !ks.bool(forKey: "hasLoaded\(collection_id)") {
            try await loadCollectionViaTags(priority: priority, collectionId: collection_id)
        } else if PreferabliTools.hasMinutesPassed(
            minutes: 5,
            startDate: ks.object(forKey: "lastCalled\(collection_id)") as? Date
        ) {
            // Fire-and-forget refresh (does not block caller)
            PreferabliTools.startNewAsyncWorkThread(priority: .low) { [weak self] in
                do {
                    try await self?.loadCollectionViaTags(priority: .low, collectionId: collection_id)
                } catch {
                    if Preferabli.loggingEnabled { print(error) }
                }
            }
        }
    }

    /// Same behavior as the legacy private version, but async and using Storage.withContext.
    private func loadCollectionViaTags(
        priority: Operation.QueuePriority,
        collectionId: Int
    ) async throws {

        // 1) Snapshot currently-linked (non-dirty) tags for this collection
        let oldTags: [Tag] = try await Storage.withContext { ctx in
            var fd = FetchDescriptor<Tag>(predicate: #Predicate<Tag> {
                ($0.collection_id ?? 0) == collectionId
            })
            return try ctx.fetch(fd)
        }

        // 2) Ensure the Collection exists (or fetch it)
        let collection = try await getCollection(forceRefresh: false, collectionId: collectionId)

        // 3) Early exit if logout is in-flight
        if PreferabliTools.isLoggedOutOrLoggingOut() { return }

        // 4) Pull latest tags/products and get the fresh tag ids
        let freshTagIds: [Int] = try await getTagsAndProducts(collection: collection, priority: priority)

        // 5) Any previously linked tag not present now gets unlinked
        try await Storage.withContext { ctx in
            if !freshTagIds.isEmpty {
                let keep = Set(freshTagIds)
                for tag in oldTags where !keep.contains(tag.id) {
                    tag.collection_id = 0
                }
                try ctx.save()
            }
        }

        // 6) Touch freshness flags
        let ks = PreferabliTools.getKeyStore()
        ks.set(Date(), forKey: "lastCalled\(collectionId)")
        ks.set(true,   forKey: "hasLoaded\(collectionId)")
    }

    // MARK: Core helpers

    /// Fetch (and optionally refresh) a `Collection` from API into SwiftData, then return it.
    internal func getCollection(
        forceRefresh: Bool,
        collectionId: Int
    ) async throws -> Collection {
        // Try local first
        if !forceRefresh, let local = try await Storage.withContext({ ctx in
            try Storage.fetchById(Collection.self, id: collectionId, in: ctx)
        }) {
            return local
        }

        // Fetch from API
        var resp = try Preferabli.api.getAlamo().get(APIEndpoints.collection(id: collectionId))
        resp = try await APIService.continueOrThrowPreferabliException(response: resp)
        PreferabliTools.saveCollectionEtag(response: resp, collectionId: collectionId)

        guard let dict = try APIService.continueOrThrowJSONException(data: resp.data!) as? [String: Any] else {
            throw PreferabliException(type: .MappingNotFound)
        }

        // Upsert into SwiftData
        return try await Storage.withContext { ctx in
            let c = try Storage.upsertCollection(from: dict, in: ctx)
            try ctx.save()
            return c
        }
    }

    /// Fetches tags and their backing products for a collection, upserts everything,
    /// and returns the set of Tag ids we now know about.
    internal func getTagsAndProducts(
        collection: Collection,
        priority: Operation.QueuePriority
    ) async throws -> [Int] {

        if PreferabliTools.isLoggedOutOrLoggingOut() { return [] }

        let collectionId = collection.id
        let total = max(collection.product_count ?? 0, 0)
        let pageSize = 50

        struct PageResult {
            let tagDicts: [[String: Any]]
            let productDicts: [[String: Any]]
        }

        // 1) Page network in parallel
        let pageOffsets = stride(from: 0, through: total, by: pageSize).map { $0 }

        let pageResults: [PageResult] = try await withThrowingTaskGroup(of: PageResult?.self) { group in
            for off in pageOffsets {
                group.addTask {
                    if PreferabliTools.isLoggedOutOrLoggingOut() { return nil }

                    // Fetch tags page
                    var tagsResp = try Preferabli.api.getAlamo().get(
                        APIEndpoints.tags(id: collectionId),
                        params: ["offset": off, "limit": pageSize]
                    )
                    tagsResp = try await APIService.continueOrThrowPreferabliException(response: tagsResp)

                    guard let tagDicts = try APIService
                        .continueOrThrowJSONException(data: tagsResp.data!) as? [[String: Any]],
                          !tagDicts.isEmpty
                    else { return PageResult(tagDicts: [], productDicts: []) }

                    // For these tags, fetch products by variant_ids (if any)
                    let variantIds: [Int] = tagDicts.compactMap { Storage.asInt($0["variant_id"]) }
                    var productDicts: [[String: Any]] = []

                    if !variantIds.isEmpty {
                        var prodResp = try Preferabli.api.getAlamo().get(
                            APIEndpoints.products,
                            params: ["variant_ids": variantIds]
                        )
                        prodResp = try await APIService.continueOrThrowPreferabliException(response: prodResp)
                        productDicts = (try APIService
                            .continueOrThrowJSONException(data: prodResp.data!) as? [[String: Any]]) ?? []
                    }

                    return PageResult(tagDicts: tagDicts, productDicts: productDicts)
                }
            }

            // Collect results
            var results: [PageResult] = []
            for try await r in group {
                if let r { results.append(r) }
            }
            return results
        }

        if PreferabliTools.isLoggedOutOrLoggingOut() { return [] }

        // 2) Apply to SwiftData (single main-actor pass)
        let tagIds: [Int] = try await Storage.withContext { ctx in
            var allTagIds: [Int] = []
            allTagIds.reserveCapacity(pageResults.reduce(0) { $0 + $1.tagDicts.count })

            // Upsert products first so Variant ids exist
            for page in pageResults where !page.productDicts.isEmpty {
                for pd in page.productDicts {
                    _ = try Storage.upsertProduct(from: pd, in: ctx)
                }
            }

            // Upsert tags + link to variants + mark location
            for page in pageResults where !page.tagDicts.isEmpty {
                for td in page.tagDicts {
                    let t = try Storage.upsertTag(from: td, in: ctx)
                    if !(t.isRating()) { t.location = collection.name }
                    if let vid = t.variant_id,
                       let v = try Storage.fetchById(Variant.self, id: vid, in: ctx) {
                        t.variant = v
                    }
                    allTagIds.append(t.id)
                }
            }

            try ctx.save()
            return allTagIds
        }

        return tagIds
    }

    /// Load a collection’s items by `CollectionOrder` (groups/orderings path).
    internal func loadCollectionViaOrderings(
        priority: Operation.QueuePriority,
        collection: Collection
    ) async throws {
        if PreferabliTools.isLoggedOutOrLoggingOut() { return }

        let collectionId = collection.id

        // Snapshot existing tags for this collection
        let oldTags: [Tag] = try await Storage.withContext { ctx in
            var fd = FetchDescriptor<Tag>(predicate: #Predicate<Tag> {
                ($0.collection_id ?? 0) == collectionId
            })
            return try ctx.fetch(fd)
        }

        // Choose first version (by order)
        guard let version = collection.versions.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) }).first else {
            throw PreferabliException(type: .DatabaseError)
        }

        // Fetch per-group pages concurrently (Swift concurrency)
        let groups = version.groups
        let pageSize = 50

        // Aggregate every tag id we encounter, so we can drop stale ones afterwards.
        var allTagIds = Set<Int>()
        try await withThrowingTaskGroup(of: [Int].self) { group in
            for g in groups {
                let maxCount = g.orderings_count ?? 0
                if maxCount <= 0 { continue }

                let offsets = stride(from: 0, through: maxCount, by: pageSize)
                for off in offsets {
                    group.addTask { [weak self] in
                        guard let self else { return [] }
                        return try await self.getGroupItems(
                            collection: collection,
                            versionId: version.id,
                            group: g,
                            limit: pageSize,
                            offset: off
                        )
                    }
                }
            }

            for try await ids in group {
                for id in ids { allTagIds.insert(id) }
            }
        }

        // Remove stale tags (not returned this cycle)
        try await Storage.withContext { ctx in
            let keep = allTagIds
            for tag in oldTags where !keep.contains(tag.id) {
                ctx.delete(tag)
            }
            try ctx.save()
        }

        // Flags
        let ks = PreferabliTools.getKeyStore()
        ks.set(Date(), forKey: "lastCalled\(collectionId)")
        ks.set(true,   forKey: "hasLoaded\(collectionId)")
    }

    /// Fetch a single "page" of group items (orderings -> tags -> products),
    /// upsert to SwiftData, and return the tag ids found.
    internal func getGroupItems(
        collection: Collection,
        versionId: Int,
        group: CollectionGroup,
        limit: Int,
        offset: Int
    ) async throws -> [Int] {
        if PreferabliTools.isLoggedOutOrLoggingOut() { return [] }

        let collectionId = collection.id

        // 1) Orderings for this page
        var ordersResp = try Preferabli.api.getAlamo().get(
            APIEndpoints.orderings(collectionId: collectionId, versionId: versionId, groupId: group.id),
            params: ["limit": limit, "offset": offset]
        )
        ordersResp = try await APIService.continueOrThrowPreferabliException(response: ordersResp)
        PreferabliTools.saveCollectionEtag(response: ordersResp, collectionId: collectionId)

        guard let orderingDicts = try APIService
            .continueOrThrowJSONException(data: ordersResp.data!) as? [[String: Any]],
              !orderingDicts.isEmpty
        else { return [] }

        // 2) Fetch tags for the orderings
        let tagIdsRequested: [Int] = orderingDicts.compactMap { Storage.asInt($0["tag_id"]) }
        var tagDicts: [[String: Any]] = []
        if !tagIdsRequested.isEmpty {
            var tagsResp = try Preferabli.api.getAlamo().get(
                APIEndpoints.tags(id: collectionId),
                params: ["tag_ids": tagIdsRequested]
            )
            tagsResp = try await APIService.continueOrThrowPreferabliException(response: tagsResp)
            PreferabliTools.saveCollectionEtag(response: tagsResp, collectionId: collectionId)
            tagDicts = (try APIService
                .continueOrThrowJSONException(data: tagsResp.data!) as? [[String: Any]]) ?? []
        }

        // 3) For those tags, fetch backing products (by variant_id)
        let variantIds: [Int] = tagDicts.compactMap { Storage.asInt($0["variant_id"]) }
        var productDicts: [[String: Any]] = []
        if !variantIds.isEmpty {
            var prodResp = try Preferabli.api.getAlamo().get(APIEndpoints.products,
                                                             params: ["variant_ids": variantIds])
            prodResp = try await APIService.continueOrThrowPreferabliException(response: prodResp)
            productDicts = (try APIService
                .continueOrThrowJSONException(data: prodResp.data!) as? [[String: Any]]) ?? []
        }

        // 4) Apply everything in one SwiftData pass; return tag ids discovered
        let tagIdsFound: [Int] = try await Storage.withContext { ctx in
            // Rehydrate local references in this context
            let localGroup = try Storage.fetchById(CollectionGroup.self, id: group.id, in: ctx)
                ?? { let g = CollectionGroup(id: group.id); ctx.insert(g); return g }()

            // Upsert orderings and attach group (tags wired later)
            var orders: [CollectionOrder] = []
            orders.reserveCapacity(orderingDicts.count)
            for od in orderingDicts {
                let o = try Storage.upsertCollectionOrder(from: od, in: ctx)
                o.group = localGroup
                orders.append(o)
            }

            // Upsert products so variants exist
            for pd in productDicts {
                _ = try Storage.upsertProduct(from: pd, in: ctx)
            }

            // Upsert tags, set location for non-ratings
            var pageTags: [Tag] = []
            pageTags.reserveCapacity(tagDicts.count)
            for td in tagDicts {
                let t = try Storage.upsertTag(from: td, in: ctx)
                if !(t.isRating()) { t.location = collection.name }
                pageTags.append(t)
            }

            // Wire orderings → tag objects
            for o in orders {
                if let t = try Storage.fetchById(Tag.self, id: o.tag_id, in: ctx) {
                    o.tag = t
                }
            }

            try ctx.save()
            return pageTags.map { $0.id }
        }

        return tagIdsFound
    }
}
