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

        // If a fetch is already running for this profile owner and we're not forcing refresh,
        // just join that Task.
        if !force_refresh, let inflight = profileFetches[key] {
            return try await inflight.value
        }

        // Start a new Task, store it in the map so other callers can join.
        let task = Task<Int, Error> { [weak self] in
            guard let self else {
                throw PreferabliException(
                    type: .OtherError,
                    message: "Preferabli deallocated while fetching profile."
                )
            }
            return try await self.fetchProfileAndRecomputeAnalytics(force_refresh: force_refresh)
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

    /// Unique key per "profile owner" (either customer or user).
    private func currentProfileOwnerKey() throws -> Int {
        if Preferabli.isCustomerLoggedIn() {
            let cid = PreferabliTools.getCustomerId()
            guard cid != 0 else {
                throw PreferabliException(
                    type: .OtherError,
                    message: "No customer id available for profile fetch."
                )
            }
            return cid
        } else if Preferabli.isPreferabliUserLoggedIn() {
            let uid = PreferabliTools.getPreferabliUserId()
            guard uid != 0 else {
                throw PreferabliException(
                    type: .OtherError,
                    message: "No user id available for profile fetch."
                )
            }
            return uid
        } else {
            throw PreferabliException(type: .InvalidAccessToken)
        }
    }

    /// Actual implementation of fetching/upserting profile & styles and recomputing analytics.
    private func fetchProfileAndRecomputeAnalytics(force_refresh: Bool) async throws -> Int {
        do {
            try await preferabli.canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event" : "get_profile"])

            let needsRefresh = force_refresh || PreferabliTools.hasMinutesPassed(
                minutes: 5,
                startDate: Storage.getKeyStore().object(forKey: "lastCalledProfile") as? Date
            )

            // If we don't need a fresh API call, just return the cached id.
            guard needsRefresh else {
                return Storage.getKeyStore().integer(forKey: "profile_id")
            }

            // Fetch profile from API (customer or user)
            let profileResponse: ProfileDTO = try await preferabli.api.getAlamo().get(
                Preferabli.isCustomerLoggedIn()
                ? APIEndpoints.customerProfile(id: Preferabli.CHANNEL_ID,
                                               and: PreferabliTools.getCustomerId())
                : APIEndpoints.profile(id: PreferabliTools.getPreferabliUserId())
            )

            // 1️⃣ Upsert Profile + ProfileStyles, track which styles need a full StyleDTO fetch.
            let prefMapByStyleId: [Int: ProfileStyle] = try Storage.withContext { ctx in
                let persistedProfile = try Storage.upsertProfile(from: profileResponse, in: ctx)

                var prefMapByStyleId: [Int: ProfileStyle] = [:]

                for psJSON in profileResponse.preference_styles {
                    let ps = try Storage.upsertProfileStyle(from: psJSON,
                                                            profile: persistedProfile,
                                                            in: ctx)
                    let s  = try Storage.fetchById(Style.self, id: ps.style_id, in: ctx)

                    if force_refresh || s == nil {
                        prefMapByStyleId[ps.style_id] = ps
                    } else {
                        ps.style = s
                    }
                }

                try ctx.save()
                return prefMapByStyleId
            }

            // 2️⃣ Fetch missing StyleDTOs from API (batched), if any.
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

                // Persist styles and attach to ProfileStyles
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

            // 3️⃣ ALWAYS recompute analytics from whatever is persisted now.
            try Storage.withContext { ctx in
                guard let persistedProfile: Profile = try? Storage.fetchById(
                    Profile.self,
                    id: profileResponse.id,
                    in: ctx
                ) else {
                    return
                }

                let profileInput = ProfileAnalytics.ProfileInput(from: persistedProfile)

                let preferenceInputs: [ProfileAnalytics.PreferenceStyleInput] =
                    persistedProfile.profile_styles.compactMap { ps in
                        guard let kind = ps.analyticsKind() else { return nil }

                        return ProfileAnalytics.PreferenceStyleInput(
                            kind: kind,
                            rating: ps.rating,
                            orderRecommend: ps.order_recommend,
                            isAppealing: ps.isAppealing(),
                            isUnappealing: ps.isUnappealing(),
                            styleId: ps.style_id,
                            styleName: ps.style?.name,
                            styleImageURL: ps.style?.getImage(width: 300, height: 300)
                        )
                    }

                ProfileAnalytics.recomputeAndStoreStats(
                    profile: profileInput,
                    preferenceStyles: preferenceInputs
                )

                try ctx.save()
            }

            Storage.getKeyStore().set(profileResponse.id, forKey: "profile_id")
            Storage.getKeyStore().set(Date(), forKey: "lastCalledProfile")

            try await preferabli.canWeContinue(needsToBeLoggedIn: true)

            return profileResponse.id

        } catch {
            preferabli.handleError(error: error)
            throw error
        }
    }
}
