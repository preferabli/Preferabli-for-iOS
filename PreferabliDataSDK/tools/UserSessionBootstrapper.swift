//
//  UserSessionBootstrapper.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/16/26.
//

import Foundation
import SwiftUI

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

            // Heavy work off-main
            do {
                try await Task.detached(priority: .background) { [weak preferabli] in
                    guard let preferabli else { return }

                    // Keep your current warmups
                    await CollectionLoader.shared.ensureWarm(BuiltInCollection.wishlist)
                    await CollectionLoader.shared.ensureLoaded(BuiltInCollection.ratings, timeout: 10)

                    // Make sure profile exists locally (ProfileHelper Fix C makes this reliable)
                    _ = try await preferabli.getProfile()

                    // ✅ The key fix:
                    // Gate completion on the coordinator's "awaits recompute" method.
                    // This only returns after recomputeFromLocal() runs (if needed) and dirty is cleared.
                    await preferabli.profileStatsCoordinator.ensureStatsReady(
                        forceRefreshProfile: false,
                        forceRefreshRatings: false,
                        timeout: 10
                    )
                }.value

                self.sessionBootstrappedOnce = true

                // ✅ Only mark complete AFTER stats are ensured
                PostLoginWarmupGate.markComplete()

            } catch {
                // Silent by design
            }
        }

        self.sessionBootstrapTask = t
        await t.value
        self.sessionBootstrapTask = nil
    }

    /// Call on logout / user switch.
    func reset(preferabli: Preferabli) {
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

