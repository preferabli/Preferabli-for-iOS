//
//  AppConfigLoader.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 3/23/26.
//

import SwiftUI
import Foundation

@MainActor
public final class ForceUpdateState: ObservableObject {
    @Published public internal(set) var isRequired = false
    @Published public internal(set) var message = "A new version of the app is required."
    @Published public internal(set) var updateURL: URL?
}

@MainActor
final class AppConfigLoader {
    private enum Keys {
        static let lastCalledConfig = "lastCalledConfig"
        static let shouldUpdate = "shouldUpdate"
        static let shouldUpdateMessage = "shouldUpdateMessage"
        static let shouldUpdateURL = "shouldUpdateURL"
    }

    private unowned let preferabli: Preferabli
    private let updateState: ForceUpdateState

    init(preferabli: Preferabli, updateState: ForceUpdateState) {
        self.preferabli = preferabli
        self.updateState = updateState
    }

    func refreshIfNeeded(force: Bool = false) async {
        let ks = Storage.getKeyStore()
        let last = ks.object(forKey: Keys.lastCalledConfig) as? Date
        let needsRefresh = force || last == nil || PreferabliTools.hasMinutesPassed(minutes: 60, startDate: last)

        if !needsRefresh {
            await loadCached()
            return
        }

        do {
            // Keep config loading aligned with the rest of the SDK API surface.
            // This waits until startup has created the anonymous session and loaded
            // integration/channel state before the config request is allowed to run.
            try await preferabli.canWeContinue(needsToBeLoggedIn: false)
        } catch {
            await MainActor.run {
                preferabli.handleError(error: error)
            }
            await loadCached()
            return
        }

        await refresh()
    }

    private func refresh() async {
        do {
            let buildInt = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
            let platform = Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE") ?? "ios"

            let dto: AppConfigDTO = try await preferabli.api
                .getAlamo(requiresAccessToken: false)
                .get(APIEndpoints.config, sparams: [
                    "version": buildInt,
                    "platform": platform
                ])

            let shouldUpdate = dto.should_update
            let ks = Storage.getKeyStore()
            ks.set(Date(), forKey: Keys.lastCalledConfig)
            ks.set(shouldUpdate?.display ?? false, forKey: Keys.shouldUpdate)
            ks.set(shouldUpdate?.message, forKey: Keys.shouldUpdateMessage)
            ks.set(shouldUpdate?.url, forKey: Keys.shouldUpdateURL)

            await MainActor.run {
                updateState.isRequired = shouldUpdate?.display ?? false
                updateState.message = shouldUpdate?.message ?? "A new version of the app is required."
                updateState.updateURL = shouldUpdate?.url.flatMap(URL.init(string:))
            }
        } catch {
            await MainActor.run {
                preferabli.handleError(error: error)
            }
            await loadCached()
        }
    }

    private func loadCached() async {
        let ks = Storage.getKeyStore()
        await MainActor.run {
            updateState.isRequired = ks.bool(forKey: Keys.shouldUpdate)
            updateState.message = ks.string(forKey: Keys.shouldUpdateMessage)
                ?? "A new version of the app is required."
            updateState.updateURL = ks.string(forKey: Keys.shouldUpdateURL)
                .flatMap(URL.init(string:))
        }
    }
}
