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

    public func isFetchingCurrentProfile() -> Bool {
        guard let key = try? currentProfileOwnerKey() else { return false }
        return profileFetches[key] != nil
    }

    /// Optional: true if *any* owner fetch is running (useful for debugging)
    public var isFetchingAnyProfile: Bool {
        !profileFetches.isEmpty
    }

    init(preferabli: Preferabli) {
        self.preferabli = preferabli
    }

    // MARK: - Public entry point

    func getProfile(force_refresh: Bool = false) async throws -> Int {
        let key = try currentProfileOwnerKey()

        // ✅ Deduping: if an in-flight task exists, join it.
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
        defer { profileFetches[key] = nil }

        return try await task.value
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

    /// ✅ Fix C: only allow id-only fast path if the Profile row exists locally.
    /// NOTE: We intentionally do NOT require profile_styles to be non-empty,
    /// because a new user can have a valid Profile with zero styles.
    private func isProfilePersistedLocally(profileID: Int) -> Bool {
        guard profileID > 0 else { return false }
        do {
            return try Storage.withContext { ctx in
                var fd = FetchDescriptor<Profile>(
                    predicate: Profile.predicate(forID: profileID)
                )
                fd.fetchLimit = 1
                return try ctx.fetch(fd).first != nil
            }
        } catch {
            return false
        }
    }

    private func fetchAndPersistProfile(force_refresh: Bool) async throws -> Int {
        do {
            try await preferabli.canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event" : "get_profile"])

            let ks = Storage.getKeyStore()

            let cachedProfileID = ks.integer(forKey: "profile_id")

            // Existing freshness logic
            let minutesPassed =
                PreferabliTools.hasMinutesPassed(
                    minutes: 1,
                    startDate: ks.object(forKey: "lastCalledProfile") as? Date
                )

            // We keep your semantics: if userHasTasteProfile() is false, we consider we need refresh.
            // (Even if the Profile exists locally, the flags indicate we haven't loaded/confirmed taste state.)
            let needsRefresh =
                force_refresh ||
                minutesPassed ||
                !Preferabli.userHasTasteProfile() ||
                cachedProfileID <= 0 ||
                !isProfilePersistedLocally(profileID: cachedProfileID)

            // ✅ Fast path ONLY if SwiftData agrees (Fix C)
            guard needsRefresh else {
                return cachedProfileID
            }

            // ✅ Network path only: toggle loading state here (Option B).
            preferabli.loadState.isProfileLoading = true
            defer { preferabli.loadState.isProfileLoading = false }

            // 1) Fetch profile from API
            let profileResponse: ProfileDTO = try await preferabli.api.getAlamo().get(
                Preferabli.isCustomerLoggedIn()
                ? APIEndpoints.customerProfile(
                    id: Preferabli.CHANNEL_ID,
                    and: PreferabliTools.getCustomerId()
                )
                : APIEndpoints.profile(id: PreferabliTools.getPreferabliUserId())
            )

            // 2) Persist profile + determine which styles need fetching
            let result: (prefMapByStyleId: [Int: ProfileStyle], hasRecommendableStyle: Bool) =
            try Storage.withContext { ctx in
                let persistedProfile = try Storage.upsertProfile(from: profileResponse, in: ctx)

                var prefMapByStyleId: [Int: ProfileStyle] = [:]
                var hasRecommendableStyle: Bool = false

                for psJSON in profileResponse.preference_styles {
                    let ps = try Storage.upsertProfileStyle(from: psJSON, profile: persistedProfile, in: ctx)
                    let s  = try Storage.fetchById(Style.self, id: ps.style_id, in: ctx)

                    if (ps.recommend ?? false) { hasRecommendableStyle = true }

                    if force_refresh || s == nil {
                        prefMapByStyleId[ps.style_id] = ps
                    } else {
                        ps.style = s
                    }
                }

                try ctx.save()
                return (prefMapByStyleId, hasRecommendableStyle)
            }

            // 3) Fetch missing StyleDTOs batched
            if !result.prefMapByStyleId.isEmpty {
                let allStyleIds = Array(result.prefMapByStyleId.keys)
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
                            profile_style: result.prefMapByStyleId[styleDict.id],
                            in: ctx
                        )
                    }
                    try ctx.save()
                }
            }

            // 4) Persist metadata
            ks.set(profileResponse.id, forKey: "profile_id")
            ks.set(Date(), forKey: "lastCalledProfile")
            ks.set(!profileResponse.preference_styles.isEmpty, forKey: "hasTasteProfile")
            ks.set(result.hasRecommendableStyle, forKey: "hasRecommendableStyle")

            try await preferabli.canWeContinue(needsToBeLoggedIn: true)
            return profileResponse.id

        } catch {
            preferabli.handleError(error: error)
            throw error
        }
    }
}
