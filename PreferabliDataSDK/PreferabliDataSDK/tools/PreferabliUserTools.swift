//
//  PreferabliUserTools.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/10/16.
//  Copyright © 2023 RingIT, Inc. All rights reserved.
//

import Foundation
import SwiftData

/// Contains methods that help load ``PreferabliUser`` data.
internal class PreferabliUserTools {
    
    internal static var sharedInstance = PreferabliUserTools()
    
    // MARK: - Purchase History
    
    /// Returns all Products that appear in any "purchase" UserCollection.
    /// Triggers a refresh if needed; otherwise returns cached results.
    internal func getPurchaseHistory(
        priority: Operation.QueuePriority,
        forceRefresh: Bool,
        lock_to_integration: Bool
    ) async throws -> [Product] {

        let ks = PreferabliTools.getKeyStore()

        // Refresh now if needed
        if forceRefresh || !ks.bool(forKey: "hasLoadedPurchaseHistory") {
            try await getPurchaseHistoryFromAPI(priority: priority, forceRefresh: forceRefresh)
        } else if PreferabliTools.hasMinutesPassed(
            minutes: 5,
            startDate: ks.object(forKey: "lastCalledPurchaseHistory") as? Date
        ) {
            // Opportunistic background refresh
            PreferabliTools.startNewAsyncWorkThread(priority: .low) { [weak self] in
                guard let self else { return }
                do { try await self.getPurchaseHistoryFromAPI(priority: .low, forceRefresh: false) }
                catch { if Preferabli.loggingEnabled { print(error) } }
            }
        }

        // Read from SwiftData
        return try await Storage.withContext { ctx in
            // 1) Find "purchase" user collections
            let fdUC = FetchDescriptor<UserCollection>(predicate: #Predicate<UserCollection> {
                $0.relationship_type == "purchase"
            })
            let userCollections = try ctx.fetch(fdUC)

            // 2) Filter to collections (optionally lock to current integration/channel)
            let currentChannel = ks.integer(forKey: "CHANNEL_ID")
            let collections: [Collection] = userCollections.compactMap { $0.collection }.filter { c in
                guard lock_to_integration else { return true }
                return (c.channel_id ?? 0) == currentChannel
            }

            guard !collections.isEmpty else { return [] }

            // 3) Gather product ids that have ANY variant with ANY tag whose collection_id is in our set
            var productIds = Set<Int>()
            for coll in collections {
                let targetId = coll.id
                let fdTags = FetchDescriptor<Tag>(predicate: #Predicate<Tag> {
                    ($0.collection_id ?? -1) == targetId
                })
                let tagsForCollection = try ctx.fetch(fdTags)

                // Prefer direct product_id when available, else walk variant → product
                for t in tagsForCollection {
                    if let pid = t.product_id, pid != 0 {
                        productIds.insert(pid)
                    } else if let pid = t.variant?.product?.id, pid != 0 {
                        productIds.insert(pid)
                    }
                }
            }

            guard !productIds.isEmpty else { return [] }

            // 4) Fetch those products
            let fdProducts = FetchDescriptor<Product>(predicate: #Predicate<Product> {
                productIds.contains($0.id)
            })
            return try ctx.fetch(fdProducts)
        }
    }

    /// Refresh purchase-history content by (re)loading the user's "purchase" collections and their tags/products.
    private func getPurchaseHistoryFromAPI(
        priority: Operation.QueuePriority,
        forceRefresh: Bool
    ) async throws {
        // 1) Load (or refresh) the user's "purchase" collections
        let purchaseCollections = try await getUserCollections(
            forceRefresh: forceRefresh,
            relationship_type: "purchase"
        ).compactMap { $0.collection }

        // 2) For each collection, refresh tags/products concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for coll in purchaseCollections {
                if PreferabliTools.isLoggedOutOrLoggingOut() { continue }
                group.addTask {
                    try await LoadCollectionTools.sharedInstance.loadCollectionViaTags(
                        priority: priority,
                        force_refresh: forceRefresh,
                        collection_id: coll.id
                    )
                }
            }
            try await group.waitForAll()
        }

        if PreferabliTools.isLoggedOutOrLoggingOut() { return }

        let ks = PreferabliTools.getKeyStore()
        ks.set(Date(), forKey: "lastCalledPurchaseHistory")
        ks.set(true,   forKey: "hasLoadedPurchaseHistory")
    }

    // MARK: - User Collections (by relationship), with optional refresh

    internal func getUserCollections(
        forceRefresh: Bool,
        relationship_type: String
    ) async throws -> [UserCollection] {
        let ks = PreferabliTools.getKeyStore()

        if forceRefresh || !ks.bool(forKey: "hasLoadedUserCollections") {
            try await getUserCollections() // full refresh
        } else if PreferabliTools.hasMinutesPassed(
            minutes: 5,
            startDate: ks.object(forKey: "lastCalledUserCollections") as? Date
        ) {
            // Opportunistic background refresh
            PreferabliTools.startNewAsyncWorkThread(priority: .low) { [weak self] in
                guard let self else { return }
                do { try await self.getUserCollections() }
                catch { if Preferabli.loggingEnabled { print(error) } }
            }
        }

        // Return from SwiftData
        return try await Storage.withContext { ctx in
            let fd = FetchDescriptor<UserCollection>(predicate: #Predicate<UserCollection> {
                $0.relationship_type == relationship_type
            })
            return try ctx.fetch(fd)
        }
    }

    // MARK: - Full refresh of all user collections (SwiftData)

    private func getUserCollections() async throws {
        // Snapshot existing ids to clean up later
        let existingIds: [Int] = try await Storage.withContext { ctx in
            try ctx.fetch(FetchDescriptor<UserCollection>()).map { $0.id }
        }

        var keepIds = Set<Int>()
        var offset = 0
        let limit = 50

        // Pull pages in batches of 5, concurrently
        pageLoop: while true {
            if PreferabliTools.isLoggedOutOrLoggingOut() { return }

            // Launch up to 5 pages
            let batchOffsets = (0..<5).map { offset + ($0 * limit) }
            offset += (limit * 5)

            let pageIdLists: [[Int]] = try await withThrowingTaskGroup(of: [Int].self) { group in
                for pageOffset in batchOffsets {
                    group.addTask { try await self.fetchUserCollectionsPage(offset: pageOffset, limit: limit) }
                }

                var results: [[Int]] = []
                for try await ids in group { results.append(ids) }
                return results
            }

            // Merge ids and decide whether we've reached the end
            var totalFetchedThisBatch = 0
            for ids in pageIdLists {
                keepIds.formUnion(ids)
                totalFetchedThisBatch += ids.count
            }

            // If we fetched fewer than 5 pages worth, we've reached the end
            if totalFetchedThisBatch < (limit * 5) { break pageLoop }
        }

        if PreferabliTools.isLoggedOutOrLoggingOut() { return }

        // Delete UserCollections that are no longer present
        try await Storage.withContext { ctx in
            // Fetch all again to delete missing ones
            let all = try ctx.fetch(FetchDescriptor<UserCollection>())
            for uc in all where !keepIds.contains(uc.id) {
                ctx.delete(uc)
            }
            try ctx.save()
        }

        // Flags
        let ks = PreferabliTools.getKeyStore()
        ks.set(Date(), forKey: "lastCalledUserCollections")
        ks.set(true,   forKey: "hasLoadedUserCollections")
    }

    // MARK: - Single page fetch/upsert

    private func fetchUserCollectionsPage(offset: Int, limit: Int) async throws -> [Int] {
        // GET user collections page
        var resp = try Preferabli.api.getAlamo().get(
            APIEndpoints.userCollections(id: PreferabliTools.getPreferabliUserId()),
            params: ["offset": offset, "limit": limit]
        )
        resp = try await APIService.continueOrThrowPreferabliException(response: resp)

        guard let dicts = try APIService
            .continueOrThrowJSONException(data: resp.data!) as? [[String: Any]] else {
            return []
        }

        // Upsert to SwiftData (single pass)
        return try await Storage.withContext { ctx in
            var pageIds: [Int] = []
            pageIds.reserveCapacity(dicts.count)

            for d in dicts {
                let uc = try Storage.upsertUserCollection(from: d, in: ctx)
                pageIds.append(uc.id)
            }
            try ctx.save()
            return pageIds
        }
    }
}
