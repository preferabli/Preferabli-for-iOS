//
//  ProfileHelper.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 12/2/25.
//

import Foundation
import SwiftData

public extension Notification.Name {
    static let didBuildTasteProfile = Notification.Name("Preferabli.didBuildTasteProfile")
}

@MainActor
final class ProfileHelper {

    private unowned let preferabli: Preferabli

    /// Dedupes concurrent getProfile calls per "owner" (user or customer).
    private var profileFetches: [Int: Task<Int, Error>] = [:]

    init(preferabli: Preferabli) {
        self.preferabli = preferabli
    }

    // MARK: - Public

    func isFetchingCurrentProfile() -> Bool {
        guard let key = try? currentProfileOwnerKey() else { return false }
        return profileFetches[key] != nil
    }

    public var isFetchingAnyProfile: Bool {
        !profileFetches.isEmpty
    }

    func getProfile(force_refresh: Bool = false) async throws -> Int {
        let key = try currentProfileOwnerKey()

        // Deduping: if an in-flight task exists, join it.
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

    // MARK: - Owner Resolution

    private func currentProfileOwnerKey() throws -> Int {
        if Preferabli.isCustomerLoggedIn() {
            let cid = PreferabliTools.getCustomerId()
            guard cid != 0 else {
                throw PreferabliException(type: .OtherError, message: "No customer id available.")
            }
            return cid
        } else if Preferabli.isPreferabliUserLoggedIn() {
            let uid = PreferabliTools.getPreferabliUserId()
            guard uid != 0 else {
                throw PreferabliException(type: .OtherError, message: "No user id available.")
            }
            return uid
        } else {
            throw PreferabliException(type: .InvalidAccessToken)
        }
    }

    // MARK: - Owner-Scoped Keys

    private func tasteKnownKey(owner: Int) -> String {
        "taste_profile_known_v1#\(owner)"
    }

    private func tasteShownKey(owner: Int) -> String {
        "taste_profile_built_message_shown_v1#\(owner)"
    }

    // MARK: - Local Validation

    /// Only allow id-only fast path if the Profile row exists locally.
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

    // MARK: - Core Fetch

    private func fetchAndPersistProfile(force_refresh: Bool) async throws -> Int {
        do {
            try await preferabli.canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event" : "get_profile"])

            let ks = Storage.getKeyStore()
            let owner = try currentProfileOwnerKey()

            // ---- PREVIOUS STATE SNAPSHOT (for transition detection) ----
            let wasKnown = ks.bool(forKey: tasteKnownKey(owner: owner))
            let previousHasTaste = ks.bool(forKey: "hasTasteProfile")
            let alreadyShown = ks.bool(forKey: tasteShownKey(owner: owner))

            let cachedProfileID = ks.integer(forKey: "profile_id")

            let minutesPassed =
                PreferabliTools.hasMinutesPassed(
                    minutes: 1,
                    startDate: ks.object(forKey: "lastCalledProfile") as? Date
                )

            // Keep existing semantics: if userHasTasteProfile() is false, we consider we need refresh.
            let needsRefresh =
                force_refresh ||
                minutesPassed ||
                !Preferabli.userHasTasteProfile() ||
                cachedProfileID <= 0 ||
                !isProfilePersistedLocally(profileID: cachedProfileID)

            // Fast path only if SwiftData agrees
            guard needsRefresh else {
                return cachedProfileID
            }

            // Network path: toggle loading state here.
            preferabli.loadState.isProfileLoading = true
            defer { preferabli.loadState.isProfileLoading = false }

            // ---- NETWORK: fetch profile ----
            let profileResponse: ProfileDTO = try await preferabli.api.getAlamo().get(
                Preferabli.isCustomerLoggedIn()
                ? APIEndpoints.customerProfile(
                    id: Preferabli.CHANNEL_ID,
                    and: PreferabliTools.getCustomerId()
                )
                : APIEndpoints.profile(id: PreferabliTools.getPreferabliUserId())
            )

            // ---- PERSIST: profile + profile styles, and decide which styles need fetching ----
            let result: (prefMapByStyleId: [Int: ProfileStyle], hasRecommendableStyle: Bool) =
            try Storage.withContext { ctx in
                let persistedProfile = try Storage.upsertProfile(from: profileResponse, in: ctx)

                var prefMapByStyleId: [Int: ProfileStyle] = [:]
                var hasRecommendableStyle: Bool = false

                for psJSON in profileResponse.preference_styles {
                    let ps = try Storage.upsertProfileStyle(from: psJSON, profile: persistedProfile, in: ctx)
                    let s  = try Storage.fetchById(Style.self, id: ps.style_id, in: ctx)

                    if (ps.recommend ?? false) { hasRecommendableStyle = true }

                    // If style isn't present (or force_refresh), mark it for fetching.
                    if force_refresh || s == nil {
                        prefMapByStyleId[ps.style_id] = ps
                    } else {
                        ps.style = s
                    }
                }

                try ctx.save()
                return (prefMapByStyleId, hasRecommendableStyle)
            }

            // ---- RESTORED FUNCTIONALITY (from older version): fetch missing StyleDTOs batched ----
            if !result.prefMapByStyleId.isEmpty {
                let allStyleIds = Array(result.prefMapByStyleId.keys)
                let chunkSize = 50

                var allStylesResp: [StyleDTO] = []
                var index = 0

                while index < allStyleIds.count {
                    let end = min(index + chunkSize, allStyleIds.count)
                    let chunk = Array(allStyleIds[index..<end])

                    let stylesRespChunk: [StyleDTO] = try await preferabli.api.getAlamo().get(
                        APIEndpoints.styles,
                        sparams: ["style_ids": chunk]
                    )

                    allStylesResp.append(contentsOf: stylesRespChunk)
                    index = end
                }

                try Storage.withContext { ctx in
                    for styleDTO in allStylesResp {
                        try Storage.upsertStyle(
                            from: styleDTO,
                            profile_style: result.prefMapByStyleId[styleDTO.id],
                            in: ctx
                        )
                    }
                    try ctx.save()
                }
            }

            // ---- METADATA ----
            let newHasTaste = !profileResponse.preference_styles.isEmpty
            let ratingsCount = await totalLocalRatingsCount()
            let hasMinimumRatings = ratingsCount >= 5
            let gatedHasTaste = previousHasTaste || (newHasTaste && hasMinimumRatings)

            ks.set(profileResponse.id, forKey: "profile_id")
            ks.set(Date(), forKey: "lastCalledProfile")
            ks.set(gatedHasTaste, forKey: "hasTasteProfile")
            ks.set(result.hasRecommendableStyle, forKey: "hasRecommendableStyle")
            ks.set(true, forKey: tasteKnownKey(owner: owner))

            try await preferabli.canWeContinue(needsToBeLoggedIn: true)

            // ---- TRANSITION DETECTION ----
            let didJustBuild =
                wasKnown &&
                previousHasTaste == false &&
                gatedHasTaste == true &&
                !alreadyShown

            if didJustBuild {
                ks.set(true, forKey: tasteShownKey(owner: owner))
                
                await preferabli.profileStatsCoordinator.invalidateAndRecomputeIfReady(timeout: 10)

                await MainActor.run {
                    NotificationCenter.default.post(name: .didBuildTasteProfile, object: nil)
                }
            }

            return profileResponse.id

        } catch {
            preferabli.handleError(error: error)
            throw error
        }
    }

    // MARK: - Ratings Gate

    private func totalLocalRatingsCount() async -> Int {
        let ks = Storage.getKeyStore()
        let ratingsCollectionId = ks.integer(forKey: BuiltInCollection.ratings.idKey)
        guard ratingsCollectionId > 0 else { return 0 }

        let rawRating = TagType.RATING.getDatabaseName()

        do {
            return try await Storage.withBackgroundContext { ctx in
                let fd = FetchDescriptor<Tag>(
                    predicate: #Predicate<Tag> {
                        $0.collection_id == ratingsCollectionId &&
                        $0.type == rawRating &&
                        $0.isTombstoned == false
                    }
                )
                return try ctx.fetchCount(fd)
            }
        } catch {
            return 0
        }
    }
    
    // MARK: - Taste Gate Recompute (local-only)

    private func localHasAnyPreferenceStyles(profileID: Int) async -> Bool {
        guard profileID > 0 else { return false }

        do {
            return try await Storage.withBackgroundContext { ctx in
                // If you have a ProfileStyle model, this is the most direct:
                var fd = FetchDescriptor<ProfileStyle>(
                    predicate: #Predicate<ProfileStyle> { $0.profile?.id == profileID }
                )
                fd.fetchLimit = 1
                return try ctx.fetch(fd).first != nil
            }
        } catch {
            return false
        }
    }

    /// Call this after ratings load completes to resolve the ">= 5 ratings" gate.
    /// Monotonic: will only ever flip hasTasteProfile false -> true.
    public func recomputeHasTasteProfileGateIfPossible() async {
        let ks = Storage.getKeyStore()

        // Already true? nothing to do.
        if ks.bool(forKey: "hasTasteProfile") { return }

        // Need a profile id, and the profile must indicate "taste exists" (styles present)
        let profileID = ks.integer(forKey: "profile_id")
        guard profileID > 0 else { return }

        let hasAnyStyles = await localHasAnyPreferenceStyles(profileID: profileID)
        guard hasAnyStyles else { return }

        // Now check ratings gate
        let ratingsCount = await totalLocalRatingsCount()
        guard ratingsCount >= 5 else { return }

        ks.set(true, forKey: "hasTasteProfile")

        // If you want to reuse your "did build" notification logic, you can optionally
        // post here too (but be careful about your "shown" gating keys / owner keys).
    }
}
