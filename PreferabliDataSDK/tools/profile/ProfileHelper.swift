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

            // ---- PREVIOUS STATE SNAPSHOT ----
            let wasKnown = ks.bool(forKey: tasteKnownKey(owner: owner))
            let previousHasTaste = ks.bool(forKey: "hasTasteProfile")
            let alreadyShown = ks.bool(forKey: tasteShownKey(owner: owner))

            let cachedProfileID = ks.integer(forKey: "profile_id")

            let minutesPassed =
                PreferabliTools.hasMinutesPassed(
                    minutes: 1,
                    startDate: ks.object(forKey: "lastCalledProfile") as? Date
                )

            let needsRefresh =
                force_refresh ||
                minutesPassed ||
                !Preferabli.userHasTasteProfile() ||
                cachedProfileID <= 0 ||
                !isProfilePersistedLocally(profileID: cachedProfileID)

            guard needsRefresh else {
                return cachedProfileID
            }

            preferabli.loadState.isProfileLoading = true
            defer { preferabli.loadState.isProfileLoading = false }

            // ---- NETWORK ----
            let profileResponse: ProfileDTO = try await preferabli.api.getAlamo().get(
                Preferabli.isCustomerLoggedIn()
                ? APIEndpoints.customerProfile(
                    id: Preferabli.CHANNEL_ID,
                    and: PreferabliTools.getCustomerId()
                )
                : APIEndpoints.profile(id: PreferabliTools.getPreferabliUserId())
            )

            // ---- PERSIST ----
            let result: (prefMapByStyleId: [Int: ProfileStyle], hasRecommendableStyle: Bool) =
            try Storage.withContext { ctx in
                let persistedProfile = try Storage.upsertProfile(from: profileResponse, in: ctx)

                var prefMapByStyleId: [Int: ProfileStyle] = [:]
                var hasRecommendableStyle = false

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

            // ---- METADATA ----
            let newHasTaste = !profileResponse.preference_styles.isEmpty

            ks.set(profileResponse.id, forKey: "profile_id")
            ks.set(Date(), forKey: "lastCalledProfile")
            ks.set(newHasTaste, forKey: "hasTasteProfile")
            ks.set(result.hasRecommendableStyle, forKey: "hasRecommendableStyle")
            ks.set(true, forKey: tasteKnownKey(owner: owner))

            try await preferabli.canWeContinue(needsToBeLoggedIn: true)

            // ---- TRANSITION DETECTION ----
            let didJustBuild =
                wasKnown &&
                previousHasTaste == false &&
                newHasTaste == true &&
                !alreadyShown

            if didJustBuild {
                ks.set(true, forKey: tasteShownKey(owner: owner))

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
}
