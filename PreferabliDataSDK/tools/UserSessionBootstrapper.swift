//
//  UserSessionBootstrapper.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/16/26.
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
final class UserSessionBootstrapper {

    // MARK: - State
    private var sessionBootstrapTask: Task<Void, Never>? = nil
    private var sessionBootstrappedOnce: Bool = false
    private var ratingsObserverTask: Task<Void, Never>? = nil

    // MARK: - Bootstrap loading refcount
    private var bootstrapRefCount: Int = 0

    // MARK: - Public API
    func bootstrapIfNeeded(
        preferabli: Preferabli,
        force: Bool = false
    ) async {
        guard Preferabli.isPreferabliUserLoggedIn() || Preferabli.isCustomerLoggedIn() else { return }

        if sessionBootstrappedOnce && !force { return }

        // Join if running
        if let t = sessionBootstrapTask {
            await t.value
            return
        }

        let t = Task { @MainActor [weak self, weak preferabli] in
            guard let self, let preferabli else { return }

            beginBootstrap(preferabli: preferabli)
            defer { endBootstrap(preferabli: preferabli) }

            // Ensure exactly one ratings observer at a time
            self.ratingsObserverTask?.cancel()
            let ratingsStream = await CollectionLoader.shared.observe(BuiltInCollection.ratings)

            self.ratingsObserverTask = Task { @MainActor [weak preferabli] in
                guard let preferabli else { return }

                for await event in ratingsStream {
                    if Task.isCancelled { break }

                    let next: Bool?
                    switch event {
                    case .started: next = true
                    case .done, .failed: next = false
                    default: next = nil
                    }
                    guard let next else { continue }

                    if preferabli.loadState.isRatingsLoading != next {
                        preferabli.loadState.isRatingsLoading = next
                    }
                }
            }
            
            await CollectionLoader.shared.setOnDone(BuiltInCollection.ratings) { [weak preferabli] event in
                guard let preferabli else { return }
                guard case .done = event else { return }
                await preferabli.profileHelper.recomputeHasTasteProfileGateIfPossible()
            }

            // Heavy work off-main
            
            // Affiliate state controls Explore routing, so sync it independently
            // from profile and collection bootstrap.
            let affiliateTask = Task { @MainActor [weak self, weak preferabli] in
                guard let self, let preferabli else { return }
                await self.refreshAffiliatesIfNeeded(preferabli: preferabli, force: force)
            }

            let localTicketTask = Task { @MainActor [weak preferabli] in
                guard let preferabli else { return false }
                guard Preferabli.isPreferabliUserLoggedIn() else { return true }
                do {
                    try await preferabli
                        .reconcileLocalTicketReservationsAfterAuthentication()
                    return true
                } catch {
                    return false
                }
            }

            do {
                await CollectionLoader.shared.ensureWarm(
                    BuiltInCollection.wishlist
                )

                await CollectionLoader.shared.ensureLoaded(
                    BuiltInCollection.ratings,
                    timeout: 10
                )

                await preferabli.profileHelper
                    .recomputeHasTasteProfileGateIfPossible()

                _ = try await preferabli.getProfile()

                await preferabli.profileStatsCoordinator.ensureStatsReady(
                    forceRefreshProfile: false,
                    forceRefreshRatings: false,
                    timeout: 10
                )

                Task(priority: .background) { [weak preferabli] in
                    guard let preferabli else { return }

                    await CellarWarmup.warmCellars(
                        preferabli: preferabli
                    )
                }

            } catch {
                // Silent by design.
            }

            await affiliateTask.value
            let didReconcileLocalTickets = await localTicketTask.value

            self.sessionBootstrappedOnce = didReconcileLocalTickets
            if didReconcileLocalTickets {
                PostLoginWarmupGate.markComplete()
            }
        }

        self.sessionBootstrapTask = t
        await t.value
        self.sessionBootstrapTask = nil
    }
    
    private func refreshAffiliatesIfNeeded(
        preferabli: Preferabli,
        force: Bool
    ) async {
        guard AffiliateRefreshGate.shouldRefresh(force: force) else { return }

        let keyStore = Storage.getKeyStore()
        let pendingMigrationCodes =
            (keyStore.stringArray(
                forKey: "pendingAffiliateMigrationCodes"
            ) ?? [])
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter { !$0.isEmpty }
            .uniquedCaseInsensitive()

        if !pendingMigrationCodes.isEmpty {
            do {
                _ = try await preferabli.unlockAffiliates(
                    codes: pendingMigrationCodes
                )
                keyStore.removeObject(
                    forKey: "pendingAffiliateMigrationCodes"
                )
            } catch {
                // Do not replace the local anonymous codes with an incomplete
                // server response. Leave the gate and pending migration intact
                // so a later bootstrap can retry.
                return
            }
        }

        let localCodesBeforeRefresh = normalizedAffiliateCodes(
            keyStore.stringArray(forKey: "affiliateCodes") ?? []
        )

        do {
            let affiliateCodes = try await preferabli.getAffiliates()

            // The authenticated root can unlock an affiliate while this
            // server snapshot is in flight. If local state changed during the
            // request, preserve that newer state instead of replacing it with
            // a response that may have been captured before the unlock POST.
            let localCodesAfterRefresh = normalizedAffiliateCodes(
                keyStore.stringArray(forKey: "affiliateCodes") ?? []
            )
            let localStateChangedDuringRefresh =
                canonicalAffiliateCodes(localCodesAfterRefresh) !=
                canonicalAffiliateCodes(localCodesBeforeRefresh)

            let codesToPersist = localStateChangedDuringRefresh
                ? normalizedAffiliateCodes(
                    localCodesAfterRefresh + affiliateCodes
                )
                : normalizedAffiliateCodes(affiliateCodes)

            keyStore.set(
                codesToPersist,
                forKey: "affiliateCodes"
            )
            NotificationCenter.default.post(
                name: .preferabliAffiliateCodesDidChange,
                object: nil
            )

            AffiliateRefreshGate.markRefreshed()
        } catch {
            // Silent by design — affiliate loading should not block bootstrap.
        }
    }

    private func normalizedAffiliateCodes(_ codes: [String]) -> [String] {
        codes
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .uniquedCaseInsensitive()
    }

    private func canonicalAffiliateCodes(_ codes: [String]) -> [String] {
        normalizedAffiliateCodes(codes)
            .map { $0.lowercased() }
            .sorted()
    }

    /// Call on logout / user switch.
    func reset(preferabli: Preferabli) {
        AffiliateRefreshGate.reset()
        sessionBootstrappedOnce = false
        sessionBootstrapTask?.cancel()
        sessionBootstrapTask = nil
        ratingsObserverTask?.cancel()
        ratingsObserverTask = nil

        PostLoginWarmupGate.reset()   // ✅ boundary

        bootstrapRefCount = 0
        Task { @MainActor [weak preferabli] in
            guard let preferabli else { return }
            preferabli.loadState.isBootstrappingUserData = false
            preferabli.loadState.isRatingsLoading = false
        }
    }

    private func beginBootstrap(preferabli: Preferabli) {
        bootstrapRefCount += 1
        preferabli.loadState.isBootstrappingUserData = true
    }

    private func endBootstrap(preferabli: Preferabli) {
        bootstrapRefCount = max(0, bootstrapRefCount - 1)
        if bootstrapRefCount == 0 {
            preferabli.loadState.isBootstrappingUserData = false
        }
    }
}

public enum PostLoginWarmupGate {
    private static let key = "did_complete_post_login_warmup"

    public static func didComplete() -> Bool {
        Storage.getKeyStore().bool(forKey: key)
    }

    static func markComplete() {
        Storage.getKeyStore().set(true, forKey: key)
    }

    static func reset() {
        Storage.getKeyStore().set(false, forKey: key)
    }
}

public enum CellarWarmup {
    public static func warmCellars(preferabli: Preferabli) async {
        do {
            // 1) Sync user collections (source of truth)
            _ = try await preferabli.getUserCollections(force_refresh: false)

            // 2) Find cellar userCollections locally
            let cellarCollectionIds: [Int] = try await Storage.withBackgroundContext { ctx in
                var fd = FetchDescriptor<UserCollection>(
                    predicate: StorageFacade.QueriesNamespace().cellars()
                )
                fd.propertiesToFetch = [\.id, \.collection_id]
                let ucs = try ctx.fetch(fd)
                return Array(Set(ucs.compactMap { $0.collection_id }))
            }

            // 3) Warm each associated Collection via orderings
            for cid in cellarCollectionIds {
                let spec = FixedIDCollectionSpec(
                    collectionId: cid,
                    namespace: "cellar#\(cid)",
                    freshnessMinutes: 86400,
                    pageLimit: 50,
                    loadMode: .orderings
                )
                await CollectionLoader.shared.ensureWarm(spec)
            }
        } catch {
            // Silent by design (warmup)
            await MainActor.run { preferabli.handleError(error: error) } // optional
        }
    }
}

private enum AffiliateRefreshGate {
    static let key = "lastCalledAffiliates"
    static let maxDays = 60

    static func shouldRefresh(force: Bool) -> Bool {
        if force { return true }

        let ts = Storage.getKeyStore().double(forKey: key)
        let date = ts > 0 ? Date(timeIntervalSince1970: ts) : nil

        return PreferabliTools.hasDaysPassed(days: maxDays, startDate: date)
    }

    static func markRefreshed() {
        Storage.getKeyStore().set(Date().timeIntervalSince1970, forKey: key)
    }

    static func reset() {
        Storage.getKeyStore().removeObject(forKey: key)
    }
}
