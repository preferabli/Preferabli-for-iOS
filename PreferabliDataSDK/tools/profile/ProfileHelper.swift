//
//  ProfileHelper.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 12/2/25.
//

import Foundation
import SwiftData

@MainActor
final class ProfileHelper {

    private unowned let preferabli: Preferabli
    /// Dedupes concurrent getProfile calls per "owner" (user or customer).
    private var profileFetches: [Int: Task<Int, Error>] = [:]

    init(preferabli: Preferabli) {
        self.preferabli = preferabli
    }

    // MARK: - Public entry point

    func getProfile(force_refresh: Bool = false) async throws -> Int {
        let key = try currentProfileOwnerKey()

        if !force_refresh, let inflight = profileFetches[key] {
            return try await inflight.value
        }

        let task = Task<Int, Error> { [weak self] in
            guard let self else {
                throw PreferabliException(
                    type: .OtherError,
                    message: "Preferabli deallocated while fetching profile."
                )
            }
            return try await self.fetchAndPersistProfile(force_refresh: force_refresh)
        }

        profileFetches[key] = task

        do {
            let result = try await task.value
            profileFetches[key] = nil
            return result
        } catch {
            profileFetches[key] = nil
            throw error
        }
    }

    // MARK: - Private helpers

    private func currentProfileOwnerKey() throws -> Int {
        if Preferabli.isCustomerLoggedIn() {
            let cid = PreferabliTools.getCustomerId()
            guard cid != 0 else {
                throw PreferabliException(type: .OtherError, message: "No customer id available for profile fetch.")
            }
            return cid
        } else if Preferabli.isPreferabliUserLoggedIn() {
            let uid = PreferabliTools.getPreferabliUserId()
            guard uid != 0 else {
                throw PreferabliException(type: .OtherError, message: "No user id available for profile fetch.")
            }
            return uid
        } else {
            throw PreferabliException(type: .InvalidAccessToken)
        }
    }

    private func fetchAndPersistProfile(force_refresh: Bool) async throws -> Int {
        do {
            try await preferabli.canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event" : "get_profile"])

            let needsRefresh = force_refresh || PreferabliTools.hasMinutesPassed(
                minutes: 1,
                startDate: Storage.getKeyStore().object(forKey: "lastCalledProfile") as? Date
            ) || !Preferabli.userHasTasteProfile()

            guard needsRefresh else {
                return Storage.getKeyStore().integer(forKey: "profile_id")
            }

            // 1) Fetch profile from API
            let profileResponse: ProfileDTO = try await preferabli.api.getAlamo().get(
                Preferabli.isCustomerLoggedIn()
                ? APIEndpoints.customerProfile(id: Preferabli.CHANNEL_ID,
                                               and: PreferabliTools.getCustomerId())
                : APIEndpoints.profile(id: PreferabliTools.getPreferabliUserId())
            )

            let result: ([Int: ProfileStyle], Bool) = try Storage.withContext { ctx in
                let persistedProfile = try Storage.upsertProfile(from: profileResponse, in: ctx)
                var prefMapByStyleId: [Int: ProfileStyle] = [:]

                var hasRecommendableStyle: Bool = false
                for psJSON in profileResponse.preference_styles {
                    let ps = try Storage.upsertProfileStyle(from: psJSON, profile: persistedProfile, in: ctx)
                    let s = try Storage.fetchById(Style.self, id: ps.style_id, in: ctx)
                    
                    if (ps.recommend ?? false) { hasRecommendableStyle = true }

                    if force_refresh || s == nil {
                        prefMapByStyleId[ps.style_id] = ps
                    } else {
                        ps.style = s
                    }
                }

                try ctx.save()
                
                // 3. Return them together as a tuple
                return (prefMapByStyleId, hasRecommendableStyle)
            }
            
            let prefMapByStyleId = result.0

            // 3) Fetch missing StyleDTOs batched
            if !prefMapByStyleId.isEmpty {
                let allStyleIds = Array(prefMapByStyleId.keys)
                let chunkSize   = 50

                var allStylesResp: [StyleDTO] = []
                var index = 0

                while index < allStyleIds.count {
                    let end   = min(index + chunkSize, allStyleIds.count)
                    let chunk = Array(allStyleIds[index..<end])

                    let stylesRespChunk: [StyleDTO] = try await preferabli.api.getAlamo().get(
                        APIEndpoints.styles,
                        sparams: ["style_ids": chunk]
                    )

                    allStylesResp.append(contentsOf: stylesRespChunk)
                    index = end
                }

                try Storage.withContext { ctx in
                    for styleDict in allStylesResp {
                        try Storage.upsertStyle(
                            from: styleDict,
                            profile_style: prefMapByStyleId[styleDict.id],
                            in: ctx
                        )
                    }
                    try ctx.save()
                }
            }
            
            

            // 4) Persist metadata
            Storage.getKeyStore().set(profileResponse.id, forKey: "profile_id")
            Storage.getKeyStore().set(Date(), forKey: "lastCalledProfile")
            Storage.getKeyStore().set(!profileResponse.preference_styles.isEmpty, forKey: "hasTasteProfile")
            Storage.getKeyStore().set(result.1, forKey: "hasRecommendableStyle")

            try await preferabli.canWeContinue(needsToBeLoggedIn: true)
            return profileResponse.id

        } catch {
            preferabli.handleError(error: error)
            throw error
        }
    }
}
