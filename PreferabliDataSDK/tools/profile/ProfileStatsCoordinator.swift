//
//  ProfileStatsCoordinator.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 12/23/25.
//

import Foundation
import SwiftData

public actor ProfileStatsCoordinator {

    private unowned let preferabli: Preferabli

    /// Dedupes concurrent recompute calls per profile owner.
    private var recomputeTasks: [Int: Task<Void, Never>] = [:]

    public init(preferabli: Preferabli) {
        self.preferabli = preferabli
    }

    // MARK: - Public API

    /// Mark stats as needing recompute (cheap).
    public func invalidate() async {
        do {
            let key = try currentProfileOwnerKey()
            setDirty(true, ownerKey: key)
        } catch {
            // ignore (not logged in yet)
        }
    }

    /// Convenience: invalidate + attempt recompute if inputs are ready.
    public func invalidateAndRecomputeIfReady(timeout: TimeInterval = 10) async {
        await invalidate()
        await recomputeIfReady(timeout: timeout)
    }

    /// For screens that REQUIRE stats: ensure all inputs are loaded and recompute if dirty.
    ///
    /// This is your "all-or-nothing" entry point for analytics UI.
    public func ensureStatsReady(
        forceRefreshProfile: Bool = false,
        forceRefreshRatings: Bool = false,
        timeout: TimeInterval = 10
    ) async {
        do {
            let ownerKey = try currentProfileOwnerKey()

            // 1) Ensure profile exists locally (profile-only fetch)
            _ = try await preferabli.profileHelper.getProfile(force_refresh: forceRefreshProfile)

            // Profile changed => dirty
            setDirty(true, ownerKey: ownerKey)

            // 2) Ensure ratings are loaded (stats dependency)
            if forceRefreshRatings {
                await CollectionLoader.shared.forceRefresh(BuiltInCollection.ratings)
            }
            await CollectionLoader.shared.ensureLoaded(BuiltInCollection.ratings, timeout: timeout)

            // 3) Recompute (deduped)
            await recomputeForced(ownerKey: ownerKey)
        } catch {
            // If not logged in or anything else, just no-op.
            // Stats UI can show empty state / fallback.
        }
    }
    
    private func recomputeForced(ownerKey: Int) async {
        // Dedup per owner
        if let t = recomputeTasks[ownerKey] {
            await t.value
            return
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.recomputeFromLocal()
            await self.setDirty(false, ownerKey: ownerKey)
        }

        recomputeTasks[ownerKey] = task
        await task.value
        recomputeTasks[ownerKey] = nil
    }


    /// Called from background hooks (startup, ratings warm done, etc).
    /// Only recomputes if:
    /// - dirty
    /// - profile present
    /// - ratings present (loaded enough)
    public func recomputeIfReady(timeout: TimeInterval = 10) async {
        do {
            let ownerKey = try currentProfileOwnerKey()
            await recomputeIfReady(ownerKey: ownerKey, timeout: timeout)
        } catch {
            // ignore
        }
    }

    // MARK: - Internals

    private func recomputeIfReady(ownerKey: Int, timeout: TimeInterval) async {
        // 0) If not dirty, skip.
        guard isDirty(ownerKey: ownerKey) else { return }

        // 1) Inputs ready?
        guard await inputsReadyForStats(timeout: timeout) else { return }

        // 2) Dedup recompute per owner.
        if let t = recomputeTasks[ownerKey] {
            await t.value
            return
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.recomputeFromLocal()
            await self.setDirty(false, ownerKey: ownerKey)
        }

        recomputeTasks[ownerKey] = task
        await task.value
        recomputeTasks[ownerKey] = nil
    }

    /// Checks if we have enough local data to compute stats.
    /// (We do not force loads here unless ensureStatsReady is used.)
    private func inputsReadyForStats(timeout: TimeInterval) async -> Bool {
        // Profile ready?
        let hasProfileId = Storage.getKeyStore().integer(forKey: "profile_id") > 0
        let hasProfileCall = Storage.getKeyStore().object(forKey: "lastCalledProfile") as? Date != nil
        let hasProfile = Storage.getKeyStore().bool(forKey: "hasTasteProfile")
        
        guard hasProfileId && hasProfileCall && hasProfile else { return false }

        // Ratings ready?
        let ratingsCid = Storage.getKeyStore().integer(forKey: BuiltInCollection.ratings.idKey)
        guard ratingsCid > 0 else { return false }

        let statusKey = "hasLoaded\(BuiltInCollection.ratings.namespace)#\(ratingsCid)"
        let hasRatingsLoaded = Storage.getKeyStore().bool(forKey: statusKey)
        guard hasRatingsLoaded else { return false }

        // Optionally also ensure it isn't stale (your call). For stats, "loaded at all" is usually enough.
        // If you want to require freshness, uncomment:
        //
        // let timeKey = "lastCalled\(BuiltInCollection.ratings.namespace)#\(ratingsCid)"
        // let lastCalled = Storage.getKeyStore().object(forKey: timeKey) as? Date
        // let stale = PreferabliTools.hasMinutesPassed(minutes: BuiltInCollection.ratings.freshnessMinutes, startDate: lastCalled)
        // if stale { return false }

        // Confirm Profile row exists (cheap fetch)
        let profileExists: Bool = (try? await Storage.withBackgroundContext { ctx in
            var fd = FetchDescriptor<Profile>()
            fd.fetchLimit = 1
            return (try ctx.fetch(fd).first != nil)
        }) ?? false

        return profileExists
    }

    // MARK: - Actual recompute implementation (moved OUT of ProfileHelper)

    private func recomputeFromLocal() async {
        do {
            let (
                profileInput,
                prefInputs,
                ratingsCountInput,
                ratingSamples
            ): (
                ProfileAnalytics.ProfileInput,
                [ProfileAnalytics.PreferenceStyleInput],
                ProfileAnalytics.RatingsCountInput,
                [ProfileAnalytics.RatingRegionSample]
            ) = try await Storage.withBackgroundContext { ctx in

                // 1) Fetch Profile
                var profileFD = FetchDescriptor<Profile>()
                profileFD.fetchLimit = 1

                guard let profile = try ctx.fetch(profileFD).first else {
                    return (
                        ProfileAnalytics.ProfileInput(),
                        [],
                        ProfileAnalytics.RatingsCountInput(counts: [:]),
                        []
                    )
                }

                // 2) ProfileInput
                let profileInput = ProfileAnalytics.ProfileInput(from: profile)

                // 3) PreferenceStyleInput list (include cat/sub/type)
                let prefInputs: [ProfileAnalytics.PreferenceStyleInput] =
                    profile.profile_styles.compactMap { ps in
                        guard let kind = ps.analyticsKind(),
                              let style = ps.style
                        else { return nil }

                        let cat = style.getProductCategory()?.getCategoryName()
                        let sub = style.getProductSubcategory()?.getSubcategoryName()
                        let typ = style.getProductType()?.getTypeName()

                        return .init(
                            kind: kind,
                            rating: ps.rating,
                            orderRecommend: ps.order_recommend,
                            isAppealing: ps.isAppealing(),
                            isUnappealing: ps.isUnappealing(),
                            styleId: ps.style_id,
                            styleName: style.name,
                            styleImageURL: style.getImage(width: 400, height: 400),
                            productCategory: cat,
                            productSubcategory: sub,
                            productType: typ
                        )
                    }

                // 4) Ratings tags
                let ratingsCollectionId = Storage.getKeyStore().integer(forKey: BuiltInCollection.ratings.idKey)
                guard ratingsCollectionId > 0 else {
                    return (profileInput, prefInputs, .init(counts: [:]), [])
                }

                let rawRating = TagType.RATING.getDatabaseName()

                let tagsFD = FetchDescriptor<Tag>(
                    predicate: #Predicate<Tag> {
                        $0.collection_id == ratingsCollectionId &&
                        $0.type == rawRating &&
                        $0.isTombstoned == false
                    }
                )

                let ratingTags = (try? ctx.fetch(tagsFD)) ?? []

                // 5) ratingCount per kind + region samples
                var counts: [ProfileProductKind: Int] = [:]
                counts.reserveCapacity(ProfileProductKind.allCases.count)

                var samples: [ProfileAnalytics.RatingRegionSample] = []
                samples.reserveCapacity(ratingTags.count)

                for t in ratingTags {
                    let product = t.variant.product

                    guard let kind = product.analyticsKind() else { continue }
                    counts[kind, default: 0] += 1

                    guard let regionRaw = product.region,
                          !regionRaw.localizedCaseInsensitiveContains("info"),
                          !regionRaw.isEmptyOrWhitespace()
                    else { continue }

                    let isAppealing: Bool = {
                        guard let lvl = t.rating_level else { return false }
                        return lvl == .LOVE || lvl == .LIKE
                    }()

                    samples.append(.init(
                        kind: kind,
                        region: regionRaw,
                        isAppealing: isAppealing,
                        countryCode: product.country_code,
                        lat: product.brand_lat,
                        lon: product.brand_lon
                    ))
                }

                let ratingsCountInput = ProfileAnalytics.RatingsCountInput(counts: counts)
                return (profileInput, prefInputs, ratingsCountInput, samples)
            }

            // 6) Persist computed stats
            ProfileAnalytics.recomputeAndStoreStats(
                profile: profileInput,
                preferenceStyles: prefInputs,
                ratings: ratingsCountInput,
                ratingSamples: ratingSamples
            )

        } catch {
            await MainActor.run {
                Preferabli.main.handleError(error: error)
            }
        }
    }

    // MARK: - Owner identity + dirty flag

    private func currentProfileOwnerKey() throws -> Int {
        if Preferabli.isCustomerLoggedIn() {
            let cid = PreferabliTools.getCustomerId()
            guard cid != 0 else {
                throw PreferabliException(type: .OtherError, message: "No customer id available for stats.")
            }
            return cid
        } else if Preferabli.isPreferabliUserLoggedIn() {
            let uid = PreferabliTools.getPreferabliUserId()
            guard uid != 0 else {
                throw PreferabliException(type: .OtherError, message: "No user id available for stats.")
            }
            return uid
        } else {
            throw PreferabliException(type: .InvalidAccessToken)
        }
    }

    private func dirtyKey(ownerKey: Int) -> String {
        "profile_stats_dirty#\(ownerKey)"
    }

    private func isDirty(ownerKey: Int) -> Bool {
        Storage.getKeyStore().bool(forKey: dirtyKey(ownerKey: ownerKey))
    }

    private func setDirty(_ value: Bool, ownerKey: Int) {
        Storage.getKeyStore().set(value, forKey: dirtyKey(ownerKey: ownerKey))
    }
}
