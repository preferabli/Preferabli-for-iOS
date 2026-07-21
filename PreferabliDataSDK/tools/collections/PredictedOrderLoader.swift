//
//  PredictedOrderLoader.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 7/13/26.
//

import Foundation
import SwiftData

public actor PredictedOrderLoader {

    public static let shared = PredictedOrderLoader()

    private let pageLimit = 100
    
    private struct PredictedOrderingItem: Sendable {
        let groupID: Int
        let orderingDTO: CollectionOrderDTO
    }

    private init() {}

    @discardableResult
    public func load(
        collectionId: Int
    ) async throws -> Int {
        let totalOrderingCount = try await sourceOrderingCount(
            collectionId: collectionId
        )

        guard totalOrderingCount > 0 else {
            throw PreferabliException(
                type: .BadData,
                message: "Cannot predict an empty collection.",
                code: 765
            )
        }

        var offset = 0
        var predictedVersionID: Int?
        var receivedOrderingCount = 0

        while offset < totalOrderingCount {
            let payload: SParams = [
                "collection_id": collectionId,
                "fast_method": true,
                "user_ids": [
                    PreferabliTools.getPreferabliUserId()
                ],
                "precedence": false,
                "offset": offset,
                "limit": pageLimit
            ]

            let versionDTO: CollectionVersionDTO =
                try await Preferabli.main.api
                    .getAlamo()
                    .get(
                        APIEndpoints.predictOrder,
                        sparams: payload
                    )

            let pageItems = predictedOrderingItems(
                from: versionDTO
            )

            let versionID = try await persistPage(
                versionDTO: versionDTO,
                collectionId: collectionId,
                orderingItems: pageItems
            )

            if let existingID = predictedVersionID,
               existingID != versionID {
                throw PreferabliException(
                    type: .BadData,
                    message: "Predict order returned multiple version IDs.",
                    code: 766
                )
            }

            predictedVersionID = versionID

            let pageCount = pageItems.count

            guard pageCount > 0 else {
                break
            }

            receivedOrderingCount += pageCount
            offset += pageCount

            // A successful page containing fewer items than requested is the final page.
            if pageCount < pageLimit {
                break
            }

            if receivedOrderingCount >= totalOrderingCount {
                break
            }
        }

        guard let predictedVersionID else {
            throw PreferabliException(
                type: .BadData,
                message: "Predict order returned no collection version.",
                code: 767
            )
        }

        guard receivedOrderingCount > 0 else {
            throw PreferabliException(
                type: .BadData,
                message: "Predict order returned no collection orderings.",
                code: 768
            )
        }

        return predictedVersionID
    }
    
    private func sourceOrderingCount(
        collectionId: Int
    ) async throws -> Int {
        try await Storage.withBackgroundContext { ctx in
            guard let collection = try Storage.fetchById(
                Collection.self,
                id: collectionId,
                in: ctx
            ) else {
                throw PreferabliException(
                    type: .BadSwiftData,
                    message: "Collection \(collectionId) was not found.",
                    code: 769
                )
            }

            guard let sourceVersion = collection.versions.sorted(
                by: { lhs, rhs in
                    let lhsOrder = lhs.order ?? Int.max
                    let rhsOrder = rhs.order ?? Int.max

                    if lhsOrder != rhsOrder {
                        return lhsOrder < rhsOrder
                    }

                    if lhs.created_at != rhs.created_at {
                        return lhs.created_at < rhs.created_at
                    }

                    return lhs.id < rhs.id
                }
            ).first else {
                throw PreferabliException(
                    type: .BadSwiftData,
                    message: "Collection \(collectionId) has no source version.",
                    code: 770
                )
            }

            let groups = CollectionGroup.sortGroups(
                groups: Array(sourceVersion.groups)
            )

            let groupTotal = groups.reduce(into: 0) {
                total,
                group in

                total += group.orderings_count
                    ?? group.orderings.count
            }

            if groupTotal > 0 {
                return groupTotal
            }

            return collection.product_count ?? 0
        }
    }
    
    private func predictedOrderingItems(
        from versionDTO: CollectionVersionDTO
    ) -> [PredictedOrderingItem] {
        (versionDTO.groups ?? []).flatMap { groupDTO in
            (groupDTO.orderings ?? []).map { orderingDTO in
                PredictedOrderingItem(
                    groupID: groupDTO.id,
                    orderingDTO: orderingDTO
                )
            }
        }
    }
    
    private func persistPage(
        versionDTO: CollectionVersionDTO,
        collectionId: Int,
        orderingItems: [PredictedOrderingItem]
    ) async throws -> Int {

        // 1. Persist the predicted version and its groups first.
        let predictedVersionID: Int = try await Storage.withBackgroundContext { ctx in
            guard let collection = try Storage.fetchById(
                Collection.self,
                id: collectionId,
                in: ctx
            ) else {
                throw PreferabliException(
                    type: .BadSwiftData,
                    message: "Collection \(collectionId) was not found while saving predicted order.",
                    code: 771
                )
            }

            let version = try Storage.upsertCollectionVersion(
                from: versionDTO,
                collection: collection,
                in: ctx
            )

            try ctx.save()
            return version.id
        }

        // The API may return the version/groups before returning any orderings.
        guard !orderingItems.isEmpty else {
            return predictedVersionID
        }

        // 2. Fetch the tags referenced by this ordering page.
        let tagIDs = Array(
            Set(
                orderingItems.map {
                    $0.orderingDTO.tag_id
                }
            )
        )

        let tagDTOs: [TagDTO]

        if tagIDs.isEmpty {
            tagDTOs = []
        } else {
            tagDTOs = try await Preferabli.main.api
                .getAlamo()
                .get(
                    APIEndpoints.tags(id: collectionId),
                    sparams: [
                        "tag_ids": tagIDs
                    ]
                )
        }

        // 3. Determine which associated variants are missing locally.
        let variantIDs = Array(
            Set(
                tagDTOs.map {
                    $0.variant_id
                }
            )
        )

        let missingVariantIDs: [Int]

        if variantIDs.isEmpty {
            missingVariantIDs = []
        } else {
            missingVariantIDs = try await Storage.withBackgroundContext { ctx in
                try Storage.missingVariantIds(
                    from: variantIDs,
                    in: ctx
                )
            }
        }

        // 4. Fetch products. Product upsert will also establish variants.
        let productDTOs: [ProductDTO]

        if missingVariantIDs.isEmpty {
            productDTOs = []
        } else {
            productDTOs = try await Preferabli.main.api
                .getAlamo()
                .get(
                    APIEndpoints.products,
                    sparams: [
                        "variant_ids": missingVariantIDs
                    ]
                )
        }

        // 5. Persist products -> tags -> orderings.
        let errors: [PreferabliException] =
            try await Storage.withBackgroundContext { ctx in
                var localErrors: [PreferabliException] = []

                for productDTO in productDTOs {
                    _ = try Storage.upsertProduct(
                        from: productDTO,
                        in: ctx
                    )
                }

                var tagsByID: [Int: Tag] = [:]
                tagsByID.reserveCapacity(tagDTOs.count)

                for tagDTO in tagDTOs {
                    guard let variant = try Storage.fetchById(
                        Variant.self,
                        id: tagDTO.variant_id,
                        in: ctx
                    ) else {
                        localErrors.append(
                            PreferabliException(
                                type: .BadSwiftData,
                                message:
                                    "Could not save predicted tag \(tagDTO.id) because Variant \(tagDTO.variant_id) was not found.",
                                code: 772
                            )
                        )
                        continue
                    }

                    let tag = try Storage.upsertTag(
                        from: tagDTO,
                        variant: variant,
                        in: ctx
                    )

                    tagsByID[tag.id] = tag
                }

                for item in orderingItems {
                    let orderingDTO = item.orderingDTO

                    guard let group = try Storage.fetchById(
                        CollectionGroup.self,
                        id: item.groupID,
                        in: ctx
                    ) else {
                        localErrors.append(
                            PreferabliException(
                                type: .BadSwiftData,
                                message:
                                    "Could not save predicted ordering \(orderingDTO.id) because Group \(item.groupID) was not found.",
                                code: 773
                            )
                        )
                        continue
                    }

                    guard group.version.id == predictedVersionID else {
                        localErrors.append(
                            PreferabliException(
                                type: .BadSwiftData,
                                message:
                                    "Predicted Group \(item.groupID) does not belong to Version \(predictedVersionID).",
                                code: 774
                            )
                        )
                        continue
                    }

                    let tag: Tag?

                    if let pageTag = tagsByID[orderingDTO.tag_id] {
                        tag = pageTag
                    } else {
                        tag = try Storage.fetchById(
                            Tag.self,
                            id: orderingDTO.tag_id,
                            in: ctx
                        )
                    }

                    guard let tag else {
                        localErrors.append(
                            PreferabliException(
                                type: .BadSwiftData,
                                message:
                                    "Could not save predicted ordering \(orderingDTO.id) because Tag \(orderingDTO.tag_id) was not found.",
                                code: 775
                            )
                        )
                        continue
                    }

                    _ = try Storage.upsertCollectionOrder(
                        from: orderingDTO,
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
                for error in errors {
                    Preferabli.main.handleError(error: error)
                }
            }
        }

        return predictedVersionID
    }
}
