//
//  Preferabli.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 5/20/20.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation
import UIKit
import Mixpanel
import Alamofire
import SwiftData
import SwiftUI

/// This is the primary class you will utilize to access the Preferabli Data SDK.
@MainActor
public class Preferabli {
    
    public let updateState = ForceUpdateState()
    private lazy var appConfigLoader = AppConfigLoader(preferabli: self, updateState: updateState)
    
    public func refreshAppConfigIfNeeded(force: Bool = false) async {
        await appConfigLoader.refreshIfNeeded(force: force)
    }
    
    @MainActor
    public final class PreferabliLoadState: ObservableObject {
        @Published public internal(set) var isProfileLoading: Bool = false
        @Published public internal(set) var isRatingsLoading: Bool = false
        @Published public internal(set) var isBootstrappingUserData: Bool = false
    }
    
    private static var _main: Preferabli?
    
    /// Use this instance to make Preferabli API calls.
    public static var main: Preferabli {
        guard let s = _main else { fatalError("Call Preferabli.initialize(_) first.") }
        return s
    }
    
    public static var storage: StorageFacade { StorageFacade() }
    public let loadState = PreferabliLoadState()
    private let sessionBootstrapper = UserSessionBootstrapper()
        
    public let loggingEnabled : Bool
    internal let api : APIService
    internal let hasBeenInitialized : Bool
    
    internal var startupThreadRunning = false
    internal lazy var profileHelper = ProfileHelper(preferabli: self)
    internal lazy var profileStatsCoordinator = ProfileStatsCoordinator(preferabli: self)
    
    /// The primary inventory id of your integration.
    public nonisolated static var PRIMARY_INVENTORY_ID : Int {
        Storage.getKeyStore().integer(forKey: "PRIMARY_INVENTORY_ID")
    }
    /// The channel id of your integration.
    public nonisolated static var CHANNEL_ID : Int {
        Storage.getKeyStore().integer(forKey: "CHANNEL_ID")
    }
    /// The  id of your integration.
    public nonisolated static var INTEGRATION_ID : Int {
        Storage.getKeyStore().integer(forKey: "INTEGRATION_ID")
    }
    /// The  id of the logged in user
    public nonisolated static var USER_ID : Int {
        Storage.getKeyStore().integer(forKey: "user_id")
    }
    
    private init(logging_enabled : Bool = false) {
        self.api = APIService()
        self.loggingEnabled = logging_enabled
        self.hasBeenInitialized = true
    }
    
    /// Call this in your App Delegate's didFinishLaunchingWithOptions with your supplied information. Contact us if you do not have your **client_interface** and/or **integration_id**.
    /// - Parameters:
    ///   - client_interface: your unique identifier - provided by Preferabli.
    ///   - integration_id: your integration id - provided by Preferabli. You may have more than one integration for different segments of your business (depending on how your account is set up).
    ///   - logging_enabled: pass true for full logging. Defaults to *false*.
    static public func initialize(
        client_interface: String,
        integration_id: Int,
        logging_enabled: Bool = false
    ) {
        Storage.getKeyStore().set(integration_id, forKey: "INTEGRATION_ID")
        Storage.getKeyStore().set(client_interface, forKey: "CLIENT_INTERFACE")
        Storage.getKeyStore().set(UIScreen.main.scale, forKey: "mainScale")
        
        guard _main == nil else { return }
        _main = Preferabli(logging_enabled: logging_enabled)
        
        Mixpanel.initialize(token: SDKConfig.mixpanelKey, trackAutomaticEvents: false, instanceName: "PreferabliDataSDK")
        Mixpanel.getInstance(name: "PreferabliDataSDK")?.registerSuperProperties([
            "CLIENT_INTERFACE": client_interface,
            "INTEGRATION_ID": integration_id
        ])
        
        PreferabliTools.addSDKProperties()
        
        // Small helper so we don’t repeat the logging gate everywhere.
        let log: @Sendable (String) -> Void = { msg in
            if logging_enabled { print(msg) }
        }
        
        let keyStore = Storage.getKeyStore()

        let savedBuildNumber = keyStore.integer(forKey: "lastDatabaseBuildNumber")

        let isBrandNewInstall = savedBuildNumber == 0

        if isBrandNewInstall {
            keyStore.set(Preferabli.appBuildNumber, forKey: "lastDatabaseBuildNumber")
        }
    }
    
    private func isInternal() -> Bool {
        return Preferabli.INTEGRATION_ID == -1
    }
    
    public static var appBuildNumber: Int {
        let raw = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return Int(raw) ?? 0
    }

    public var needsDatabaseUpgrade: Bool {
        let keyStore = Storage.getKeyStore()

        let savedBuildNumber = keyStore.integer(forKey: "lastDatabaseBuildNumber")
        let currentBuildNumber = Preferabli.appBuildNumber


        let buildNumberIncreased = savedBuildNumber != 0 && currentBuildNumber > savedBuildNumber

        return buildNumberIncreased
    }

    @discardableResult
    public func performDatabaseUpgradeIfNeeded() async throws -> Bool {
        let keyStore = Storage.getKeyStore()

        let currentBuildNumber = Preferabli.appBuildNumber
        let savedBuildNumber = keyStore.integer(forKey: "lastDatabaseBuildNumber")

        let buildNumberIncreased = savedBuildNumber != 0 && currentBuildNumber > savedBuildNumber

        let shouldUpgrade = buildNumberIncreased

        guard shouldUpgrade else {
            keyStore.set(currentBuildNumber, forKey: "lastDatabaseBuildNumber")
            return false
        }

        try await Storage.databaseUpgraded()

        keyStore.set(currentBuildNumber, forKey: "lastDatabaseBuildNumber")

        return true
    }

    public func performStartupActionsAfterStorageReady() async throws {
        try await handleStartupActions()

        let log: @Sendable (String) -> Void = { msg in
            if self.loggingEnabled { print(msg) }
        }

        PreferabliTools.detachedCancellableTask(priority: .background) {
            let ks = Storage.getKeyStore()
            let reindexKey = "didReindexSearchableContent_v\(await Preferabli.appBuildNumber)"

            if !ks.bool(forKey: reindexKey) {
                await Storage.reindexSearchableContent(batchSize: 250, log: log)
                ks.set(true, forKey: reindexKey)
            } else {
                log("Skipping reindex (already completed for \(reindexKey))")
            }
        }
    }
    
    private func handleStartupActions() async throws {
        defer { startupThreadRunning = false }
        startupThreadRunning = true
        try await createAnonymousSession(create_anonymous_user: isInternal())
        try await getIntegration()
        loadUserData()
    }
    
    internal func clearAllData() async throws {
        await api.clearUrlCache()
        await api.refreshDefaults()

        let keyStore = Storage.getKeyStore()

        let integrationID = keyStore.integer(forKey: "INTEGRATION_ID")
        let clientInterface = keyStore.string(forKey: "CLIENT_INTERFACE")
        let storeFile = keyStore.string(forKey: "swiftdata_store_filename")
        let mainScale = keyStore.double(forKey: "mainScale")
        let lastDatabaseBuildNumber = keyStore.integer(forKey: "lastDatabaseBuildNumber")
        let pendingStoreCleanupURLs = keyStore.stringArray(forKey: "PreferabliSDK.pendingStoreCleanupURLs")
        let activeStoreFilename = keyStore.string(forKey: "PreferabliSDK.activeStoreFilename")

        keyStore.removePersistentDomain(forName: "Preferabli")

        keyStore.set(integrationID, forKey: "INTEGRATION_ID")
        keyStore.set(clientInterface, forKey: "CLIENT_INTERFACE")
        keyStore.set(storeFile, forKey: "swiftdata_store_filename")
        keyStore.set(mainScale, forKey: "mainScale")
        keyStore.set(lastDatabaseBuildNumber, forKey: "lastDatabaseBuildNumber")
        if let pendingStoreCleanupURLs {
            keyStore.set(pendingStoreCleanupURLs, forKey: "PreferabliSDK.pendingStoreCleanupURLs")
        }
        if let activeStoreFilename {
            keyStore.set(activeStoreFilename, forKey: "PreferabliSDK.activeStoreFilename")
        }

        try await Storage.logoutReset()
    }
    
    public func bootstrapUserSessionIfNeeded(force: Bool = false) async {
        await sessionBootstrapper.bootstrapIfNeeded(preferabli: self, force: force)
    }
    
    private func loadUserData() {
        guard Preferabli.isPreferabliUserLoggedIn() || Preferabli.isCustomerLoggedIn() else { return }
        
        // Fire and forget is fine here; TasteView can await bootstrapUserSessionIfNeeded() too.
        Task { [weak self] in
            await self?.bootstrapUserSessionIfNeeded(force: false)
        }
    }
    
    private func createAnonymousSession(create_anonymous_user: Bool) async throws {
        // already have a token? nothing to do
        if !Storage.getKeyStore().string(forKey: "access_token").isEmptyOrWhitespace { return }
        
        // 1) Create anonymous session (no token required)
        let params: SParams = ["login_as_anonymous": true]
        
        let sessionDTO: SessionDTO = try await api.getAlamo(requiresAccessToken: false).post(APIEndpoints.sessions, sjson: params)
        await sessionDTO.saveSession()
        
        // 2) Optionally create an anonymous user (typed POST + DTO upsert)
        if create_anonymous_user {
            let createParams: SParams = ["anonymous": true]
            
            let user: PreferabliUserDTO = try await api.getAlamo().post(APIEndpoints.users, sjson: createParams)
            
            try await userUpdated(dto: user, doNotSave: true)
        }
    }
    
    public func refreshCurrentUserFromAPI() async throws {
        try await canWeContinue(needsToBeLoggedIn: true)

        let userID = PreferabliTools.getPreferabliUserId()
        guard userID != 0 else {
            throw PreferabliException(
                type: .InvalidAccessToken,
                message: "Cannot refresh current user because user_id is missing."
            )
        }

        let dto: PreferabliUserDTO = try await api
            .getAlamo()
            .get(APIEndpoints.user(id: userID))

        try userUpdated(dto: dto)
    }
    
    private struct IntegrationDTO: Decodable {} // payload unused; 2xx is all we need
    
    private func getIntegration() async throws {
        if !isInternal() {
            do {
                let integration_id = Preferabli.INTEGRATION_ID
                let _: IntegrationDTO = try await api.getAlamo()
                    .get(APIEndpoints.integration(id: integration_id))
                // success → no-op
            } catch {
                if let e = error as? PreferabliException, e.getCode() != 0 {
                    throw type(of: e).init(type: .InvalidIntegrationId)
                }
                throw error
            }
        } else {
            Storage.getKeyStore().set(-1, forKey: "CHANNEL_ID")
            Storage.getKeyStore().set(1, forKey: "PRIMARY_INVENTORY_ID")
        }
    }
    
    
    /// Will let you know if a Preferabli user is logged in or not. Most SDK installations will never use this.
    /// - Returns: bool
    static nonisolated public func isPreferabliUserLoggedIn() -> Bool {
        let accessToken = Storage.getKeyStore().string(forKey: "access_token")
        let email = Storage.getKeyStore().string(forKey: "email")
        let userId = PreferabliTools.getPreferabliUserId()
        return accessToken != nil && userId != 0 && !email.isEmptyOrWhitespace
    }
    
    static nonisolated public func userHasTasteProfile() -> Bool {
        return Storage.getKeyStore().bool(forKey: "hasTasteProfile")
    }
    
    static nonisolated public func userHasRecommendableStyle() -> Bool {
        return Storage.getKeyStore().bool(forKey: "hasRecommendableStyle")
    }
    
    /// Will let you know if a customer is logged in or not.
    /// - Returns: bool
    static nonisolated public func isCustomerLoggedIn() -> Bool {
        let accessToken = Storage.getKeyStore().string(forKey: "access_token")
        let customerId = PreferabliTools.getCustomerId()
        return accessToken != nil && customerId != 0
    }
    
    /// Get the Powered By Preferabli logo for use in your app.
    /// - Parameter light_background: pass true if you want the version suitable for a light background. Pass false for the dark background version.
    /// - Returns: Powered By Preferabli logo.
    static nonisolated public func getPoweredByPreferabliLogo(light_background : Bool) -> UIImage {
        return UIImage.init(named: light_background ? "powered_by_light_bg.png" : "powered_by_dark_bg.png", in: Bundle.init(for: Preferabli.self), compatibleWith: nil)!
    }
    
    internal func canWeContinue(needsToBeLoggedIn : Bool) async throws {
        let isLoggingOut = await PreferabliTools.isLoggingOut()
        
        if isLoggingOut { throw CancellationError() }
        
        if (!hasBeenInitialized) {
            throw PreferabliException.init(type: .InvalidClientInterface)
        } else if (!Storage.isKeyPresentInKeyStore(key: "access_token") && !startupThreadRunning) {
            try await handleStartupActions()
            try await canWeContinue(needsToBeLoggedIn: needsToBeLoggedIn)
        } else if (!Storage.isKeyPresentInKeyStore(key: "access_token")) {
            try await Task.sleep(for: .seconds(1))
            try await canWeContinue(needsToBeLoggedIn: needsToBeLoggedIn)
        } else if (!Storage.isKeyPresentInKeyStore(key: "CHANNEL_ID") && !startupThreadRunning) {
            try await handleStartupActions()
            try await canWeContinue(needsToBeLoggedIn: needsToBeLoggedIn)
        } else if (!Storage.isKeyPresentInKeyStore(key: "CHANNEL_ID")) {
            try await Task.sleep(for: .seconds(1))
            try await canWeContinue(needsToBeLoggedIn: needsToBeLoggedIn)
        } else if (needsToBeLoggedIn && !Preferabli.isPreferabliUserLoggedIn() && !Preferabli.isCustomerLoggedIn()) {
            throw PreferabliException.init(type: .InvalidAccessToken)
        } else if (needsToBeLoggedIn && isLoggingOut) {
            throw PreferabliException.init(type: .InvalidAccessToken)
        }
    }
    
    internal func handleError(error: Error) {
        // Prefer rich decoding/API context if available; otherwise wrap generically.
        let wrapped = PreferabliException.smartWrap(error)
        
        if loggingEnabled {
            let type  = wrapped.type
            let code  = wrapped.getCode()
            let msg   = wrapped.getMessage()
            
            print("⚠️ PreferabliException [\(type)] code=\(code)\n\(msg)")
        }
        
        Analytics.track([
            "event": "error",
            "type": String(describing: wrapped.type),
            "code": wrapped.getCode(),
            "message": wrapped.getMessage()
        ])
    }
    
    /// Starts the login / signup process for a Preferabli user by sending a magic link to the email provided. Most SDK installations will never use this.
    /// - Parameters:
    ///   - email: user's email address.
    public func authenticatePreferabliUser(email: String) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track( ["event" : "authenticate_user"])
            
            let params: SParams = [
                "email_address": email,
                "client_interface" : Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE") ?? ""
            ]
            
            var magicLinkResponse = try await api.getAlamo(requiresAccessToken: false).post(APIEndpoints.magicLink, json: params)
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    /// Finishes the login / signup process for a Preferabli user by confirming the OTP. Most SDK installations will never use this.
    /// - Parameters:
    ///   - otpCode: the OTP code that was sent to the user's email address.
    ///   - firstName: the user's first name
    ///   - lastName: the user's last name
    public func verifyPreferabliUser(otpCode: String, firstName: String? = nil, lastName: String? = nil) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)

            // Codes unlocked before authentication belong to the anonymous
            // session. Preserve them across the identity transition so they
            // can be attached to the newly authenticated account before its
            // affiliate bootstrap establishes server-authoritative state.
            let keyStore = Storage.getKeyStore()
            let anonymousAffiliateCodes = (
                (keyStore.stringArray(forKey: "affiliateCodes") ?? [])
                + (keyStore.stringArray(
                    forKey: "pendingAffiliateMigrationCodes"
                ) ?? [])
            )
                .map {
                    $0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                }
                .filter { !$0.isEmpty }
                .uniquedCaseInsensitive()

            if !anonymousAffiliateCodes.isEmpty {
                keyStore.set(
                    anonymousAffiliateCodes,
                    forKey: "pendingAffiliateMigrationCodes"
                )
            }
            
            Analytics.track( ["event" : "verify_user"])
            
            let params: SParams = [
                "token_magic_link": otpCode,
            ]
            
            var sessionDTO: SessionDTO = try await api.getAlamo(requiresAccessToken: false).post(APIEndpoints.sessions, sjson: params)
            await sessionDTO.saveSession()
            
            guard let user_id = sessionDTO.user_id else {
                throw PreferabliException.init(type: .OtherError, message: "No user_id in session object.")
            }
            
            var dto: PreferabliUserDTO = try await api.getAlamo().get(APIEndpoints.user(id: user_id))
            
            if (!firstName.isEmptyOrWhitespace || !lastName.isEmptyOrWhitespace) {
                let paramss2: SParams = [
                    "fname": firstName,
                    "lname": lastName
                ]
                
                dto = try await api.getAlamo().put(APIEndpoints.user(id: user_id), sjson: paramss2)
            }
            
            try await userUpdated(dto: dto)

            if !anonymousAffiliateCodes.isEmpty {
                do {
                    _ = try await unlockAffiliates(
                        codes: anonymousAffiliateCodes
                    )

                    keyStore.removeObject(
                        forKey: "pendingAffiliateMigrationCodes"
                    )

                    // Keep local consumers correct immediately. The subsequent
                    // authenticated bootstrap will refresh this from the server.
                    keyStore.set(
                        anonymousAffiliateCodes,
                        forKey: "affiliateCodes"
                    )
                } catch {
                    // Authentication succeeded. Keep the durable pending value
                    // and let authenticated bootstrap retry the migration.
                }
            }
            
            loadUserData()
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func updatePreferabliUser(firstName: String? = nil, lastName: String? = nil) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track( ["event" : "update_user"])
            
            if (!firstName.isEmptyOrWhitespace || !lastName.isEmptyOrWhitespace) {
                let params: SParams = [
                    "fname": firstName,
                    "lname": lastName
                ]
                
                let dto : PreferabliUserDTO = try await api.getAlamo().put(APIEndpoints.user(id: Preferabli.USER_ID), sjson: params)
                
                try await userUpdated(dto: dto)
                
                loadUserData()
            }
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func deletePreferabliUser() async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track( ["event" : "delete_user"])

            try await api.getAlamo().delete(APIEndpoints.user(id: Preferabli.USER_ID))
                                            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func bootstrapAnonymousIfNeeded() async throws {
        try await createAnonymousSession(create_anonymous_user: isInternal())
    }
    
    public func updateAvatar(
        image: Data? = nil,
        avatarId: Int? = nil,
        initialsBackgroundHex: String? = nil,
        initialsTextHex: String? = nil
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "update_avatar"])
            
            var params: SParams = [:]
            
            if let avatarId {
                // ✅ Selecting an existing media avatar (no upload)
                params["avatar_id"] = avatarId
            } else if let image {
                // ✅ Upload local/cropped image, then set avatar_id to uploaded media id
                let mediaResponse: MediaDTO = try await api.getAlamo().upload(APIEndpoints.postMedia, data: image)
                params["avatar_id"] = mediaResponse.id
            } else {
                // ✅ Initials avatar
                params["avatar_id"] = NSNull()
            }
            
            // ✅ Optional initials styling (you said you'll handle details server-side)
            if let initialsBackgroundHex {
                params["avatar_background_color_hex"] = initialsBackgroundHex   // TODO: confirm param name
            }
            if let initialsTextHex {
                params["avatar_text_color_hex"] = initialsTextHex       // TODO: confirm param name
            }
            
            let user : PreferabliUserDTO = try await api
                .getAlamo()
                .put(APIEndpoints.user(id: PreferabliTools.getPreferabliUserId()), sjson: params)
            
            try await userUpdated(dto: user)
            
            try await canWeContinue(needsToBeLoggedIn: true)
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    internal func userUpdated(dto: PreferabliUserDTO, doNotSave: Bool = false) throws {
        if doNotSave {
            Storage.getKeyStore().set(dto.id, forKey: "user_id")
            return
        }

        try Storage.withContext { ctx, save in
            let user = try Storage.upsertPreferabliUser(from: dto, in: ctx)
            try save()
            PreferabliTools.setUserProperties(user: user)
        }

        PreferabliTools.addSDKProperties()
    }
    
    /// Performs label recognition on a supplied image. Returns matches as an array of ``Product`` ids.
    /// - Parameters:
    ///   - image: label image you want to search for.
    public func labelRecognition(image: Data) async throws -> (ids: [Int], bestMatchID: Int?) {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "label_rec"])
            
            // 1. Upload and Get Results
            let mediaResponse: MediaDTO = try await api.getAlamo().upload(APIEndpoints.postMedia, data: image)
            let imageRecResponse: [LabelRecResultDTO] = try await api.getAlamo().get(APIEndpoints.imageRec, sparams: ["media_id": mediaResponse.id])
            
            // 2. Sort by Score (Descending) to simplify logic
            let sortedResults = imageRecResponse.sorted { $0.score > $1.score }
            
            // 3. Identify "Best Match" based on rules
            var bestMatchID: Int? = nil
            if let first = sortedResults.first, first.score > 70 {
                if sortedResults.count == 1 {
                    // Only one result and high confidence -> Winner
                    bestMatchID = first.product.id
                } else {
                    // Check if the gap to the runner-up is significant (> 20)
                    let second = sortedResults[1]
                    if (first.score - second.score) > 20 {
                        bestMatchID = first.product.id
                    }
                }
            }
            
            // 4. Persist Products and Collect IDs
            let productIds = try Storage.withContext { ctx, save in
                var productsToReturn = [Int]()
                
                // Upsert in sorted order to maintain relevance
                for imageRec in sortedResults {
                    let p = try Storage.upsertProduct(from: imageRec.product, in: ctx)
                    productsToReturn.append(p.id)
                }
                try save()
                return productsToReturn
            }
            
            // 5. Return both the list and the optional winner
            return (ids: productIds, bestMatchID: bestMatchID)
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func cancelReservation(
        reservation_id: Int
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track( ["event" : "cancel_reservation"])

            let response = try await api.getAlamo().delete(APIEndpoints.reservation(id: reservation_id) + "?cancellation_reason=Customer%20requested%20cancellation")
            
            let body: [ReservationDTO] = try await api.getAlamo().get(APIEndpoints.reservations)
            
            try await Storage.withBackgroundContext { ctx, save in
                for dto in body {
                    try Storage.upsertReservation(from: dto, in: ctx)
                }
                
                try save()
            }
                        
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func alternativeTime(
        reservation_id: Int,
        time: String
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track( ["event" : "alternative_time"])
            
            var dictionary: SParams = [
                "time": time
            ]

            let response = try await api.getAlamo().put(APIEndpoints.alternativeTimes(id: reservation_id), sjson: dictionary)
            
            let body: [ReservationDTO] = try await api.getAlamo().get(APIEndpoints.reservations)
            
            try await Storage.withBackgroundContext { ctx, save in
                for dto in body {
                    try Storage.upsertReservation(from: dto, in: ctx)
                }
                
                try save()
            }
                        
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func updateReservation(
        reservation_id: Int,
        date : String?,
        time : String?,
        guest_count : Int?,
        specific_requests : String?
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track( ["event" : "update_reservation"])
            
            var dictionary = SParams()

            // Optional fields
            
            if let date {
                dictionary["date"] = date
            }
            
            if let time {
                dictionary["time"] = time
            }
            
            if let guest_count {
                dictionary["guest_count"] = guest_count
            }
            
            if let specific_requests {
                dictionary["specific_requests"] = specific_requests
            }

            try await api.getAlamo().put(APIEndpoints.reservation(id: reservation_id), sjson: dictionary)

            let body: [ReservationDTO] = try await api.getAlamo().get(APIEndpoints.reservations)
            
            try await Storage.withBackgroundContext { ctx, save in
                for dto in body {
                    try Storage.upsertReservation(from: dto, in: ctx)
                }
                
                try save()
            }
                        
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func updateInternalReservation(
        reservation_id: Int,
        date: String,
        requested_times: [String],
        guests: [[String: Any]]
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "update_internal_reservation"])
            
            var guestParams = [SParams]()
            for guest in guests {
                let guestParam: SParams = [
                    "price_id": guest["price_id"] as! Int,
                    "quantity": guest["quantity"] as! Int
                ]
                guestParams.append(guestParam)
            }

            var dictionary: SParams = [
                "date": date,
                "requested_times": requested_times,
                "guests": guestParams,
            ]

            try await api.getAlamo().put(APIEndpoints.reservation(id: reservation_id), sjson: dictionary)

            let body: [ReservationDTO] = try await api
                .getAlamo()
                .get(APIEndpoints.reservations)

            try await Storage.withBackgroundContext { ctx, save in
                for dto in body {
                    try Storage.upsertReservation(from: dto, in: ctx)
                }
                try save()
            }

        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func createInternalReservation(
        experience_id: Int,
        hubspot_deal_id: String,
        date: String,
        requested_times: [String],
        guests: [[String: Any]],
        payment_method_id: String? = nil
    ) async throws -> Int {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "create_internal_reservation"])
            
            var guestParams = [SParams]()
            for guest in guests {
                let guestParam: SParams = [
                    "price_id": guest["price_id"] as! Int,
                    "quantity": guest["quantity"] as! Int
                ]
                guestParams.append(guestParam)
            }

            var dictionary: SParams = [
                "date": date,
                "requested_times": requested_times,
                "guests": guestParams,
                "reservation_source": Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE"),
                "hubspot_deal_id": hubspot_deal_id
            ]
            
            if let payment_method_id {
                dictionary["payment_method_id"] = payment_method_id
            }

            let response: InternalReservationResponseDTO = try await api
                .getAlamo()
                .post(APIEndpoints.internalReservations(id: experience_id), sjson: dictionary)

            let body: [ReservationDTO] = try await api
                .getAlamo()
                .get(APIEndpoints.reservations)

            try await Storage.withBackgroundContext { ctx, save in
                for dto in body {
                    try Storage.upsertReservation(from: dto, in: ctx)
                }
                try save()
            }

            return response.id

        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func createAnyroadReservation(
        experience_id: Int,
        hubspot_deal_id: String,
        date: String,
        time: String?,
        guest_count : Int,
        modification_link : String?,
        booking_confirmation_ref : String?,
        unit_price : Int?,
        total_price : Int?,
        specific_requests : String?,
        cancellation_policy : String?,
        confirmation_message : String?
    ) async throws -> Int {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "create_anyroad_reservation"])
            
            var dictionary: SParams = [
                "date": date,
                "guest_count": guest_count,
                "reservation_source": Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE"),
                "hubspot_deal_id": hubspot_deal_id
            ]
            
            if let time {
                dictionary["requested_times"] = [time]
            }
            
            if let modification_link {
                dictionary["modification_link"] = modification_link
            }

            if let booking_confirmation_ref {
                dictionary["booking_confirmation_ref"] = booking_confirmation_ref
            }

            if let unit_price {
                dictionary["unit_price"] = unit_price
            }

            if let total_price {
                dictionary["total_price"] = total_price
            }

            if let specific_requests {
                dictionary["specific_requests"] = specific_requests
            }

            if let cancellation_policy {
                dictionary["cancellation_policy"] = cancellation_policy
            }

            if let confirmation_message {
                dictionary["confirmation_message"] = confirmation_message
            }

            let response: InternalReservationResponseDTO = try await api
                .getAlamo()
                .post(APIEndpoints.internalReservations(id: experience_id), sjson: dictionary)

            let body: [ReservationDTO] = try await api
                .getAlamo()
                .get(APIEndpoints.reservations)

            try await Storage.withBackgroundContext { ctx, save in
                for dto in body {
                    try Storage.upsertReservation(from: dto, in: ctx)
                }
                try save()
            }

            return response.id

        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func createExternalReservation(
        experience_id : Int,
        hubspot_deal_id : String,
        date : String,
        time : String?,
        guest_count : Int,
        modification_link : String?,
        booking_confirmation_ref : String?,
        unit_price : Int?,
        total_price : Int?,
        specific_requests : String?,
        cancellation_policy : String?,
        confirmation_message : String?
    ) async throws -> Int {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track( ["event" : "create_reservation"])
            
            var dictionary: SParams = [
                "reservation_source": Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE"),
                "experience_id": experience_id,
                "hubspot_deal_id": hubspot_deal_id,
                "date": date,
                "guest_count": guest_count
            ]

            // Optional fields
            if let modification_link {
                dictionary["modification_link"] = modification_link
            }
            
            if let time {
                dictionary["time"] = time
            }

            if let booking_confirmation_ref {
                dictionary["booking_confirmation_ref"] = booking_confirmation_ref
            }

            if let unit_price {
                dictionary["unit_price"] = unit_price
            }

            if let total_price {
                dictionary["total_price"] = total_price
            }

            if let specific_requests {
                dictionary["specific_requests"] = specific_requests
            }

            if let cancellation_policy {
                dictionary["cancellation_policy"] = cancellation_policy
            }

            if let confirmation_message {
                dictionary["confirmation_message"] = confirmation_message
            }

            let response : ReservationResponseDTO = try await api.getAlamo().post(APIEndpoints.externalReservations(id: experience_id), sjson: dictionary)
            
            let body: [ReservationDTO] = try await api.getAlamo().get(APIEndpoints.reservations)
            
            try await Storage.withBackgroundContext { ctx, save in
                for dto in body {
                    try Storage.upsertReservation(from: dto, in: ctx)
                }
                
                try save()
            }
            
            return response.reservation_request_id
                        
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func createHubspotDeal(
        experience_id : Int
    ) async throws -> String {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track( ["event" : "create_hubspot_deal"])
            
            var dictionary: SParams = ["experience_id" : experience_id]

            let response : HubspotResponseDTO = try await api.getAlamo().post(APIEndpoints.hubspotDeal, sjson: dictionary)
            
            return response.hubspot_deal_id
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func unlockAffiliates(
        codes: [String]
    ) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "unlock_affiliate"])

            let dictionary: SParams = ["codes": codes]
            
            let affiliateArray: [AffiliateDTO]

            if Preferabli.isPreferabliUserLoggedIn() {
                affiliateArray = try await api.getAlamo().post(
                    APIEndpoints.affiliates,
                    sjson: dictionary
                )
            } else {
                affiliateArray = try await api.getAlamo().get(
                    APIEndpoints.affiliateCodes,
                    sparams: dictionary
                )
            }
            
            

            
            let ids : [Int] = try await Storage.withBackgroundContext { ctx, save in
                var idsToReturn = [Int]()
                for affiliateDTO in affiliateArray {
                    try Storage.upsertAffiliate(from: affiliateDTO, in: ctx)
                    idsToReturn.append(Int(affiliateDTO.id))
                }

                try save()
                return idsToReturn
            }

            if affiliateArray.isEmpty {
                throw PreferabliException.init(type: .BadData, message: "No affiliate(s) found.", code: 404)
            }
            
            return ids

        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getAffiliates() async throws -> [String] {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "get_affiliates"])

            let response: [AffiliateDTO] = try await api
                .getAlamo()
                .get(APIEndpoints.affiliates)

            try await Storage.withBackgroundContext { ctx, save in
                for affiliateDTO in response {
                    try Storage.upsertAffiliate(
                        from: affiliateDTO,
                        in: ctx
                    )
                }

                try save()
            }

            return response
                .compactMap(\.affiliate_code)
                .map {
                    $0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                }
                .filter { !$0.isEmpty }
                .uniquedCaseInsensitive()

        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func createStripePaymentIntent(
        first_name: String,
        last_name: String,
        email: String
    ) async throws -> StripeResponseDTO {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "create_stripe_payment_intent"])

            let dictionary: SParams = [
                "first_name": first_name,
                "last_name": last_name,
                "email": email
            ]

            let response: StripeResponseDTO = try await api
                .getAlamo()
                .post(APIEndpoints.stripePaymentIntent, sjson: dictionary)

            return response

        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    
    public func getStripePaymentMethod(
        intent_id: String
    ) async throws -> StripeMethodResponseDTO {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "get_stripe_payment_method"])

            let response: StripeMethodResponseDTO = try await api
                .getAlamo()
                .get(APIEndpoints.stripePaymentMethod(id: intent_id))

            return response

        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func searchVenues(
        query : String,
        market_trait_ids : [Int]? = nil,
    ) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track( ["event" : "search_venues"])
            
            var dictionary: SParams = ["search" : query , "search_types" : ["venues"], "has_market_id" : true]
            if let market_trait_ids = market_trait_ids {
                dictionary["market_trait_ids"] = market_trait_ids
            }
            
            let searchResponse : VenueSearchResponseDTO = try await api.getAlamo().get(APIEndpoints.search, sparams: dictionary)
            
            let venueIds = try await Storage.withBackgroundContext { ctx, save in
                var venuesToReturn = [Int]()
                
                for vd in searchResponse.venues {
                    if let v = try Storage.upsertVenue(from: vd, in: ctx) {
                        venuesToReturn.append(v.id)
                    }
                }
                try save()
                return venuesToReturn
            }
            
            return venueIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    
    /// Search for a ``Product``.
    /// - Parameters:
    ///   - query: your search query.
    ///   - lock_to_integration: pass true if you only want to draw results from your integration. Defaults to *false*.
    ///   - product_categories: pass any ``ProductCategory`` that you would like the results to conform to. Pass *nil* for all results. Defaults to *nil*.
    ///   - product_types: pass any ``ProductType`` that you would like the results to conform to. Pass *nil* for all results. Defaults to *nil*.
    public func searchProducts(
        query : String,
        lock_to_integration : Bool = false,
        product_categories : [ProductCategory]?,
        product_subcategories : [ProductSubcategory]?,
        product_types : [ProductType]?
    ) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track( ["event" : "search_products"])
            
            var dictionary: SParams = ["search" : query , "search_types" : ["products"]]
            if lock_to_integration {
                dictionary["channel_id"] = Preferabli.CHANNEL_ID
                dictionary["search_types"] = ["tags"]
            }
            if let product_categories = product_categories {
                var categories = [String]()
                for c in product_categories { categories.append(c.getCategoryName()) }
                if !categories.isEmpty { dictionary["product_categories"] = categories }
            }
            if let product_subcategories = product_subcategories {
                var sub_categories = [String]()
                for c in product_subcategories { sub_categories.append(c.getSubcategoryName()) }
                if !sub_categories.isEmpty { dictionary["product_subcategories"] = sub_categories }
            }
            if let product_types = product_types {
                var types = [String]()
                for t in product_types { types.append(t.getTypeName()) }
                if !types.isEmpty { dictionary["product_types"] = types }
            }
            
            var searchResponse : ProductSearchResponseDTO = try await api.getAlamo().get(APIEndpoints.search, sparams: dictionary)
            
            // Upsert Products
            let productIds = try Storage.withContext { ctx, save in
                var productsToReturn = [Int]()
                
                for pd in searchResponse.products {
                    let p = try Storage.upsertProduct(from: pd, in: ctx)
                    productsToReturn.append(p.id)
                }
                try save()
                return productsToReturn
            }
            
            return productIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func searchExperiences(
        query : String
    ) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track( ["event" : "search_experiences"])
            
            let searchResponse : [ExperienceDTO] = try await api.getAlamo().get(APIEndpoints.searchExperiences(query: query))
            
            let needsVenues = try await Storage.withBackgroundContext { ctx, save in
                var needsVenues = [Int]()

                for expDTO in searchResponse {
                    if let venueId = expDTO.preferabli_venue_id {
                        guard let venue = try Storage.fetchById(Venue.self, id: venueId, in: ctx) else {
                            needsVenues.append(venueId)
                            continue
                        }
                    }
                }

                return needsVenues
            }

            let uniqueVenueIDs = Array(Set(needsVenues))

            var venueResponses = [VenueDTO]()
            for venueId in uniqueVenueIDs {
                let body: VenueDTO = try await api.getAlamo().get(APIEndpoints.venue(id: venueId))
                venueResponses.append(body)
            }
            
            let venueResponsesFinal = venueResponses
            let experienceIds = try await Storage.withBackgroundContext { ctx, save in
                var experienceIds = [Int]()

                for venueResponse in venueResponsesFinal {
                    try Storage.upsertVenue(from: venueResponse, in: ctx)
                }

                try save()

                for expDTO in searchResponse {
                    guard let venueId = expDTO.preferabli_venue_id,
                          let venue = try Storage.fetchById(Venue.self, id: venueId, in: ctx)
                    else {
                        continue
                    }

                    let experience = try Storage.upsertExperience(from: expDTO, venue: venue, in: ctx)
                    experienceIds.append(experience.id)
                }

                try save()

                return experienceIds
            }
            
            return experienceIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func saveSearch(query : String) throws {
        if (query.isEmptyOrWhitespace()) {
            return
        }
        do {
            try Storage.withContext { ctx, save in
                let predicate = #Predicate<Search> { $0.text == query }
                var descriptor = FetchDescriptor<Search>(predicate: predicate)
                descriptor.fetchLimit = 1
                
                let searchRecord: Search
                
                if let existing = try ctx.fetch(descriptor).first {
                    searchRecord = existing
                } else {
                    let new = Search(
                        count: 0,
                        last_searched: Date(),
                        text: query
                    )
                    ctx.insert(new)
                    searchRecord = new
                }
                
                searchRecord.count += 1
                searchRecord.last_searched = Date()
                
                try save()
            }
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    /// Get all the questions and choices needed to run a Guided Rec. Present the questions to the user, then pass the answers to ``Preferabli/getGuidedRecResults(guided_rec_id:selected_choice_ids:price_min:price_max:collection_id:include_merchant_links:onCompletion:onFailure:)`` to get results.
    /// - Parameters:
    ///   - guided_rec_id: id of the Guided Rec you wish to run. See ``GuidedRec`` for all the default Guided Rec options. Defaults to ``GuidedRec/WINE_DEFAULT``.
    public func getGuidedRec(guided_rec_id: Int = GuidedRecQuizDTO.WINE_DEFAULT) async throws -> GuidedRecQuizDTO {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track( ["event" : "get_guided_rec"])
            
            let guidedRecQuiz : GuidedRecQuizDTO = try await api.getAlamo().get(APIEndpoints.guidedRec(id: guided_rec_id))
            return guidedRecQuiz
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    /// Get Guided Rec results based on the selected ``GuidedRecChoice``.
    /// - Parameters:
    ///   - guided_rec_id: id of the Guided Rec you wish to run.
    ///   - selected_choice_ids: an array of selected ``GuidedRecChoice`` ids.
    ///   - price_min: pass if you want to lock results to a minimum price. Defaults to *nil*.
    ///   - price_max: pass if you want to lock results to a maximum price. Defaults to *nil*.
    ///   - collection_id: the id of a specific ``Collection`` that you want to draw results from. Defaults to ``PRIMARY_INVENTORY_ID``. Pass *nil* for results from anywhere.
    public func getGuidedRecResults(
        guided_rec_id: Int,
        selected_choice_ids: [Int],
        price_min: Int? = nil,
        price_max: Int? = nil,
        collection_id: Int? = Preferabli.PRIMARY_INVENTORY_ID
    ) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event" : "get_guided_rec_results"])
            
            var payload: SParams = [
                "limit": 8,
                "sort_by": "preference",
                "questionnaire_id": guided_rec_id,
                "offset": 0,
                "questionnaire_choice_ids": selected_choice_ids
            ]
            
            var filters = [SParams]()
            if let price_min { filters.append(["key": "price_min", "value": price_min]) }
            if let price_max { filters.append(["key": "price_max", "value": price_max]) }
            payload["filters"] = filters
            
            var recResponse: GuidedRecResponseDTO = try await api
                .getAlamo()
                .post(
                    collection_id == nil
                    ? APIEndpoints.guidedRecResults()
                    : APIEndpoints.guidedRecResults(id: collection_id!),
                    sjson: payload
                )
            
            // 1) Gather variant_ids + predicted rating map
            var variantIds = [Int]()
            var predictedByVariant = [Int: Int]() // variant_id -> formatted_predict_rating
            
            for type in recResponse.types {
                for r in type.results {
                    if let vid = r.variant_id {
                        variantIds.append(vid)
                        if let wili = r.formatted_predict_rating {
                            predictedByVariant[vid] = wili
                        }
                    }
                }
            }
            
            guard !variantIds.isEmpty else { return [] }
            
            // 2) Figure out which variants are missing (on main context)
            let missingVariantIds: [Int] = try Storage.withContext { ctx, save in
                try Storage.missingVariantIds(from: variantIds, in: ctx)
            }
            
            // 3) Fetch products only for missing variants
            let productDTOs: [ProductDTO]
            if missingVariantIds.isEmpty {
                productDTOs = []
            } else {
                productDTOs = try await api.getAlamo().get(
                    APIEndpoints.products,
                    sparams: ["variant_ids": missingVariantIds]
                )
            }
            
            // 4) Upsert missing products + attach preference data for *all* variants
            //    and build ordered productIds (by variant order).
            let productIds: [Int] = try Storage.withContext { ctx, save in
                // 4a) Upsert missing products
                for pd in productDTOs {
                    _ = try Storage.upsertProduct(from: pd, in: ctx)
                }
                
                // 4b) For each variant in original order, attach preference_data
                //     and collect product.id (deduped, in rec order)
                var ids: [Int] = []
                var seen = Set<Int>()
                
                for vid in variantIds {
                    guard let variant = try Storage.fetchById(Variant.self, id: vid, in: ctx) else {
                        continue
                    }
                    let product = variant.product
                    
                    if let rating = predictedByVariant[vid] {
                        let preferenceDataDTO = PreferenceDataDTO(
                            formatted_predict_rating: rating
                        )
                        try Storage.upsertPreferenceData(from: preferenceDataDTO, for: product, in: ctx)
                    }
                    
                    if !seen.contains(product.id) {
                        seen.insert(product.id)
                        ids.append(product.id)
                    }
                }
                
                try save()
                return ids
            }
            
            return productIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    /// Creates a preference-predicted version of a collection and persists it.
    ///
    /// - Parameter collectionId: The source collection whose products should be
    ///   ordered using the current user's preference profile.
    /// - Returns: The ID of the newly generated collection version.
    @discardableResult
    public func predictOrder(
        collectionId: Int
    ) async throws -> Int {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)

            Analytics.track([
                "event": "predict_collection_order",
                "collection_id": collectionId
            ])

            return try await PredictedOrderLoader.shared.load(
                collectionId: collectionId
            )
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getQueryResults(
        queryItems: [URLQueryItem]
    ) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "get_query_results"])

            var components = URLComponents(string: APIEndpoints.baseUrl + "query")
            components?.queryItems = queryItems

            guard let endpoint = components?.url?.absoluteString else {
                throw PreferabliException(
                    type: .APIError,
                    message: "Unable to build query endpoint.",
                    code: 0
                )
            }

            let recResponse: GuidedRecResponseDTO = try await api
                .getAlamo()
                .get(endpoint)

            var variantIds = [Int]()
            var predictedByVariant = [Int: Int]()

            for type in recResponse.types {
                for r in type.results {
                    if let vid = r.variant_id {
                        variantIds.append(vid)

                        if let wili = r.formatted_predict_rating {
                            predictedByVariant[vid] = wili
                        }
                    }
                }
            }

            guard !variantIds.isEmpty else { return [] }

            let missingVariantIds: [Int] = try Storage.withContext { ctx, save in
                try Storage.missingVariantIds(from: variantIds, in: ctx)
            }

            let productDTOs: [ProductDTO]

            if missingVariantIds.isEmpty {
                productDTOs = []
            } else {
                productDTOs = try await api.getAlamo().get(
                    APIEndpoints.products,
                    sparams: ["variant_ids": missingVariantIds]
                )
            }

            let productIds: [Int] = try Storage.withContext { ctx, save in
                for pd in productDTOs {
                    _ = try Storage.upsertProduct(from: pd, in: ctx)
                }

                var ids: [Int] = []
                var seen = Set<Int>()

                for vid in variantIds {
                    guard let variant = try Storage.fetchById(Variant.self, id: vid, in: ctx) else {
                        continue
                    }

                    let product = variant.product

                    if let rating = predictedByVariant[vid] {
                        let preferenceDataDTO = PreferenceDataDTO(
                            formatted_predict_rating: rating
                        )
                        try Storage.upsertPreferenceData(from: preferenceDataDTO, for: product, in: ctx)
                    }

                    if !seen.contains(product.id) {
                        seen.insert(product.id)
                        ids.append(product.id)
                    }
                }

                try save()
                return ids
            }

            return productIds
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getScripts() async throws -> [String : String] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track( ["event" : "get_scripts"])
            
            let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            let buildInt = Int(buildNumber)
            
            var params: SParams = [
                "platform": Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE"),
                "version" : buildInt
            ]
            
            let scripts = try await api.getAlamo().getText(APIEndpoints.scripts, sparams: params)
            return PreferabliTools.splitCombinedScriptsToDictionary(from: scripts)
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getFoodCategories(style_id : Int? = nil) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "get_food_categories"])
            
            var params: SParams = [
                "limit": 9999
            ]
            if style_id != nil {
                params["style_id"] = style_id
            }
            
            let body: [FoodCategoryDTO] = try await api.getAlamo().get(APIEndpoints.foodCategories, sparams: params)
            
            let foodIds = try Storage.withContext { ctx, save in
                
                var foodIds: [Int] = []
                
                for food in body {
                    let food = try Storage.upsertFoodCategory(from: food, in: ctx)
                    foodIds.append(food.id)
                }
                
                try save()
                
                return foodIds
            }
            
            return foodIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getUserCollections(force_refresh: Bool = false) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "get_user_collections"])
            
            let ks = Storage.getKeyStore()
            
            // ✅ Gate: only call API once per 60 minutes unless force_refresh
            //            let needsRefresh: Bool = {
            //                if force_refresh { return true }
            //                let last = ks.object(forKey: "lastCalledUserCollections") as? Date
            //                return PreferabliTools.hasMinutesPassed(minutes: 60, startDate: last)
            //            }()
            let needsRefresh = true
            
            // ✅ Fast path: return local if not stale AND we’ve loaded before
            if !needsRefresh, ks.bool(forKey: "hasLoadedUserCollections") {
                let localIds: [Int] = try await Storage.withBackgroundContext { ctx, save in
                    var fd = FetchDescriptor<UserCollection>(
                        predicate: StorageFacade.QueriesNamespace().cellars()
                    )
                    fd.propertiesToFetch = [\.id]
                    let ucs = try ctx.fetch(fd)
                    return ucs.map { $0.id }
                }
                if !localIds.isEmpty { return localIds }
                // If empty (edge case), fall through to refresh.
            }
            
            // ✅ Network: API is source of truth
            let params: SParams = ["limit": 9999, "offset": 0]
            let body: [UserCollectionDTO] = try await api.getAlamo()
                .get(APIEndpoints.userCollections(id: PreferabliTools.getPreferabliUserId()), sparams: params)
            
            let apiIds = Set(body.map { $0.id })
            
            let ids: [Int] = try await Storage.withBackgroundContext { ctx, save in
                // 1) Upsert all from API
                var out: [Int] = []
                out.reserveCapacity(body.count)
                
                for dto in body {
                    let uc = try Storage.upsertUserCollection(from: dto, in: ctx)
                    out.append(uc.id)
                }
                
                // 2) ✅ Remove anything local that is missing from API (source of truth)
                var fd = FetchDescriptor<UserCollection>(
                    predicate: StorageFacade.QueriesNamespace().cellars()
                )
                fd.propertiesToFetch = [\.id]
                let localAll = try ctx.fetch(fd)
                for local in localAll where !apiIds.contains(local.id) {
                    ctx.delete(local)
                }
                
                try save()
                return out
            }
            
            ks.set(Date(), forKey: "lastCalledUserCollections")
            ks.set(true, forKey: "hasLoadedUserCollections")
            
            let cellarIDs: [Int] = body
                .filter { ($0.relationship_type ?? "") == "mycellar" }
                .compactMap { $0.collection_id }
            
            Storage.saveCellarCollectionIDs(cellarIDs)
            
            if let first : Int = (body
                .filter { ($0.relationship_type ?? "") == "skip" }
                .compactMap { $0.collection_id }).first {
                ks.set(first, forKey: "skips_id")
            }
            
            return ids
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getAvatars() async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "get_avatars"])
            
            let body: [MediaDTO] = try await api.getAlamo().get(APIEndpoints.avatars)
            
            let mediaIds = try Storage.withContext { ctx, save in
                
                var mediaIds: [Int] = []
                
                for media in body {
                    let media = try Storage.upsertMedia(from: media, in: ctx)
                    mediaIds.append(media.id)
                }
                
                try save()
                
                return mediaIds
            }
            
            return mediaIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getStylesToTry(category : ProductCategory, type : ProductType?) async throws -> [Int]
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "styles_to_try"])
            
            var params: SParams = [
                "collection_id": Preferabli.PRIMARY_INVENTORY_ID,
                "user_id":  PreferabliTools.getPreferabliUserId(),
                "product_category": category.getCategoryName(),
                "limit": 10,
            ]
            
            if let type {
                params["product_type"] = type.getTypeName()
            }
            
            let body: [StyleDTO] = try await api.getAlamo().get(APIEndpoints.stylesToTry, sparams: params)
            
            let styleIds = try Storage.withContext { ctx, save in
                var styleIds = [Int]()
                for styleDTO in body {
                    let style = try Storage.upsertStyle(from: styleDTO, in: ctx)
                    styleIds.append(style.id)
                }
                try save()
                return styleIds
            }
            
            try await canWeContinue(needsToBeLoggedIn: false)
            
            return styleIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getStylesToTryRecommendations(category : ProductCategory, type : ProductType?, style_id : Int) async throws -> [Int]
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "styles_to_try_recs"])
            
            var params: SParams = [
                "collection_id": Preferabli.PRIMARY_INVENTORY_ID,
                "user_id":  PreferabliTools.getPreferabliUserId(),
                "style_ids[]": style_id,
                "limit": 10,
                "product_category": category.getCategoryName(),
            ]
            
            if let type {
                params["product_type"] = type.getTypeName()
            }
            
            let body: [StyleRecResponseDTO] = try await api.getAlamo().get(APIEndpoints.stylesToTryRecs, sparams: params)
            
            let productIDs = try Storage.withContext { ctx, save in
                var productIDs = [Int]()
                
                if let first = body.first {
                    for item in body.first!.products {
                        let product = try Storage.upsertProduct(from: item, in: ctx)
                        productIDs.append(product.id)
                    }
                    
                    try save()
                }
                
                return productIDs
            }
            
            
            try await canWeContinue(needsToBeLoggedIn: false)
            
            return productIDs
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getStyleSuggestions(product_category: ProductCategory?, product_subcategory: ProductSubcategory?, product_type: ProductType?,style_id : Int, conflict : Bool) async throws -> [Int]
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "style_suggestions"])
            
            var params: SParams = [
                "collection_id": Preferabli.PRIMARY_INVENTORY_ID,
                "user_id":  PreferabliTools.getPreferabliUserId(),
                "style_id": style_id,
                "mode": conflict ? "ambiguous" : "low_experience",
                "product_category": product_category?.getCategoryName(),
            ]
            
            if let product_type {
                params["type"] = product_type.getTypeName()
            }
            
            let body: [StyleRecResponseDTO] = try await api.getAlamo().get(APIEndpoints.styleSuggestions, sparams: params)
            
            let productIDs = try Storage.withContext { ctx, save in
                var productIDs = [Int]()
                
                if let first = body.first {
                    for item in body.first!.products {
                        let product = try Storage.upsertProduct(from: item, in: ctx)
                        productIDs.append(product.id)
                    }
                    
                    try save()
                }
                
                try save()
                
                return productIDs
            }
            
            
            try await canWeContinue(needsToBeLoggedIn: false)
            
            return productIDs
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    /// Get a Similar Tasting Products recommendation. Start with a ``Product``, get similar tasting results. This function will return personalized results if a user is logged in.
    /// - Parameters:
    ///   - product_id: id of the starting ``Product``.  Only pass a Preferabli product id. If necessary, call ``Preferabli/getPreferabliProductId(merchant_product_id:merchant_variant_id:onCompletion:onFailure:)`` to convert your product id into a Preferabli product id.
    ///   - year: year of the ``Variant`` that you want to get results on. Defaults to ``Variant/CURRENT_VARIANT_YEAR``.
    ///   - collection_id: the id of a specific ``Collection`` that you want to draw results from. Defaults to ``PRIMARY_INVENTORY_ID``.
    /// - Returns:
    ///     - An array of Product IDs to use in a ``ProductsQuery``.
    public func similarTastingProducts(product_id : Int, year : Int = Variant.CURRENT_VARIANT_YEAR, collection_id: @autoclosure () -> Int = Preferabli.PRIMARY_INVENTORY_ID) async throws -> [Int]
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "lttt"])
            
            let cid = collection_id()
            
            var params: SParams = [
                "product_id": product_id,
                "year": year,
                "collection_id": cid
            ]
            if Preferabli.isPreferabliUserLoggedIn() {
                params["user_id"] = PreferabliTools.getPreferabliUserId()
            } else if Preferabli.isCustomerLoggedIn() {
                params["channel_customer_id"] = PreferabliTools.getCustomerId()
            }
            
            let body: LTTTResponseDTO = try await api.getAlamo().get(APIEndpoints.lttt, sparams: params)
            
            let productIDs = try Storage.withContext { ctx, save in
                var productIDs = [Int]()
                
                for item in body.results {
                    let product = try Storage.upsertProduct(from: item.product, in: ctx)
                    
                    if let rating = item.formatted_predict_rating {
                        let preferenceDataDTO = PreferenceDataDTO(formatted_predict_rating: rating)
                        try Storage.upsertPreferenceData(from: preferenceDataDTO, for: product, in: ctx)
                    }
                    
                    productIDs.append(product.id)
                }
                
                try save()
                
                return productIDs
            }
            
            return productIDs
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func productsForFood(
        recipeId: Int,
        product_categories: [ProductCategory]? = nil,
        product_subcategories: [ProductSubcategory]? = nil,
        product_types: [ProductType]? = nil
    ) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)

            Analytics.track(["event": "flttt"])

            var params: SParams = [
                "recipe_id": recipeId,
                "collection_id": Preferabli.PRIMARY_INVENTORY_ID
            ]

            if let product_categories {
                let categories = product_categories.map { $0.getCategoryName() }
                if !categories.isEmpty {
                    params["product_categories"] = categories
                }
            }

            if let product_subcategories {
                let subcategories = product_subcategories.map { $0.getSubcategoryName() }
                if !subcategories.isEmpty {
                    params["product_subcategories"] = subcategories
                }
            }

            if let product_types {
                let types = product_types.map { $0.getTypeName() }
                if !types.isEmpty {
                    params["types"] = types
                }
            }

            if Preferabli.isPreferabliUserLoggedIn() {
                params["user_id"] = PreferabliTools.getPreferabliUserId()
            } else if Preferabli.isCustomerLoggedIn() {
                params["channel_customer_id"] = PreferabliTools.getCustomerId()
            }

            let body: FLTTTResponseDTO = try await api.getAlamo().get(
                APIEndpoints.flttt,
                sparams: params
            )

            let productIDs = try Storage.withContext { ctx, save in
                var productIDs = [Int]()

                for item in body.products {
                    let product = try Storage.upsertProduct(from: item, in: ctx)
                    productIDs.append(product.id)
                }

                try save()
                return productIDs
            }

            return productIDs

        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func recipesForProduct(forceRefresh: Bool = false, productId: Int) async throws -> [Int]
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "recipes_for_product"])
            
            let recipeIdsFirst = try await Storage.withContext { ctx, save in
                guard let product = try Storage.fetchById(Product.self, id: productId, in: ctx) else {
                    throw PreferabliException.init(type: .BadSwiftData, message: "Product not found.", code: 404)
                }
                
                if (!(product.recommendable ?? false)) {
                    throw PreferabliException.init(type: .APIError, message: "Product not recommendable.", code: 404)
                }
                
                if !forceRefresh && !product.recipes.isEmpty {
                    return product.recipes
                        .sorted { $0.order < $1.order }
                        .map { $0.recipe.id }
                } else {
                    return []
                }
            }
            
            if !recipeIdsFirst.isEmpty {
                return recipeIdsFirst
            }
            
            var params: SParams = [
                "product_id": productId,
                "year": Variant.CURRENT_VARIANT_YEAR
            ]
            
            let body: [RecipesResponseDTO] = try await api.getAlamo().get(APIEndpoints.recipesForProducts, sparams: params)
            
            let recipeIds = try await Storage.withContext { ctx, save in
                guard let product = try Storage.fetchById(Product.self, id: productId, in: ctx) else {
                    throw PreferabliException.init(type: .BadSwiftData, message: "Product not found.", code: 404)
                }
                
                guard let first = body.first else {
                    throw PreferabliException.init(type: .BadData, message: "Proper product / recipe data not returned.", code: 659)
                }
                
                product.recipes.removeAll()
                
                var recipeIds = [Int]()
                
                var order = 0
                for item in first.recipes {
                    let recipe = try Storage.upsertRecipe(from: item, in: ctx)
                    let productRecipe = try Storage.upsertProductRecipe(order: order, recipe: recipe, product: product, in: ctx)
                    product.recipes.append(productRecipe)
                    recipeIds.append(recipe.id)
                    order = order + 1
                }
                
                try save()
                
                return recipeIds
            }
            
            return recipeIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getShareQRCode(shareLink : String, width : Int, tint : Color, background : Color = .white) async throws -> Data
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "share_product_qr"])
            
            let hex = tint.toHex()
            let bgHex = background.toHex()
            
            let params: SParams = ["background_color" : bgHex, "frame_name" : "no-frame", "qr_code_text" : shareLink, "image_format" : "PNG", "image_width" : width, "qr_code_logo" : "no-logo", "foreground_color" : "#000000", "marker_left_inner_color" : "#000000", "marker_left_outer_color" : hex, "marker_right_inner_color" : "#000000", "marker_right_outer_color" : hex, "marker_bottom_inner_color" : "#000000", "marker_bottom_outer_color" : hex, "marker_left_template" : "version11", "marker_right_template" : "version11", "marker_bottom_template" : "version11"]
            
            let body = try await api.getAlamo().get(APIEndpoints.qrCode, sparams: params)
            
            guard let data = body.data else {
                throw PreferabliException.init(type: .APIError, message: "QR code data is bad.")
            }
            
            return data
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    /// Get product details like a taste profile and food pairings.
    /// - Parameters:
    ///   - force_refresh: if you want to force a refresh of the data
    ///   - product_id: id of the starting ``Product``.  Only pass a Preferabli product id. If necessary, call ``Preferabli/getPreferabliProductId(merchant_product_id:merchant_variant_id:onCompletion:onFailure:)`` to convert your product id into a Preferabli product id.
    ///   - year: year of the ``Variant`` that you want to get results on. Defaults to ``Variant/CURRENT_VARIANT_YEAR``.
    ///   - pairings_only: pass TRUE if you only want to refresh food pairings.
    /// - Returns:
    ///     - A product ID to use in ``ProductsQuery``.
    public func getProductProfile(force_refresh : Bool = false, product_id : Int, year : Int = Variant.CURRENT_VARIANT_YEAR, pairings_only : Bool = false) async throws -> Int
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "product_profile"])
            
            var needsRefresh = false
            
            // --- 1. READ PHASE ---
            // Use a short-lived context just to check timestamps
            try Storage.withContext { ctx, save in
                guard let product = try Storage.fetchById(Product.self, id: product_id, in: ctx) else {
                    throw PreferabliException.init(type: .BadSwiftData, message: "Product not found.", code: 404)
                }
                
                let profile = product.profile
                needsRefresh = (force_refresh || PreferabliTools.hasMinutesPassed(minutes: 60, startDate: profile?.refreshed_at))
            }
            
            // --- 2. NETWORK PHASE ---
            // Only run if we actually need to refresh
            if needsRefresh {
                // Make the API call *outside* of any ModelContext
                let body: ProductProfileDTO = try await api.getAlamo().get(APIEndpoints.productProfileData(id: product_id, year: year))
                
                // --- 3. WRITE PHASE ---
                // Open a new, clean context *just* for writing
                try Storage.withContext { ctx, save in
                    guard let product = try Storage.fetchById(Product.self, id: product_id, in: ctx) else {
                        throw PreferabliException.init(type: .BadSwiftData, message: "Product not found.", code: 404)
                    }
                    
                    // Now we call upsert with a guaranteed-valid product and context
                    let profile = try Storage.upsertProductProfile(from: body, for: product, in: ctx)
                    
                    // Save the write context
                    try save()
                }
            }
            
            return product_id
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func favoriteVenue(venueId : Int) async throws
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            
            Analytics.track(["event": "favorite_venue"])
            
            _ = try await api.getAlamo().postNoBody(APIEndpoints.favoriteVenue(id: PreferabliTools.getPreferabliUserId(), venueId: venueId))
            
            try await Storage.withBackgroundContext { ctx, save in
                guard let user = try Storage.fetchById(PreferabliUser.self, id: PreferabliTools.getPreferabliUserId(), in: ctx) else {
                    return
                }
                
                var favorites = user.favorite_venue_ids ?? []
                favorites.append(venueId)
                user.favorite_venue_ids = favorites
                
                try save()
            }
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func favoriteExperience(experienceId : Int) async throws
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            
            Analytics.track(["event": "favorite_experience"])
            
            _ = try await api.getAlamo().postNoBody(APIEndpoints.favoriteExperience(id: PreferabliTools.getPreferabliUserId(), experienceId: experienceId))
            
            try await Storage.withBackgroundContext { ctx, save in
                guard let user = try Storage.fetchById(PreferabliUser.self, id: PreferabliTools.getPreferabliUserId(), in: ctx) else {
                    return
                }
                
                var favorites = user.favorite_experience_ids ?? []
                favorites.append(experienceId)
                user.favorite_experience_ids = favorites
                
                try save()
            }
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func favoriteExperienceOnServerOnly(experienceId: Int) async throws {
        try await canWeContinue(needsToBeLoggedIn: true)

        Analytics.track(["event": "favorite_experience"])

        _ = try await api.getAlamo().postNoBody(
            APIEndpoints.favoriteExperience(
                id: PreferabliTools.getPreferabliUserId(),
                experienceId: experienceId
            )
        )
    }

    public func unfavoriteExperienceOnServerOnly(experienceId: Int) async throws {
        try await canWeContinue(needsToBeLoggedIn: true)

        Analytics.track(["event": "unfavorite_experience"])

        _ = try await api.getAlamo().delete(
            APIEndpoints.favoriteExperience(
                id: PreferabliTools.getPreferabliUserId(),
                experienceId: experienceId
            )
        )
    }
    
    public func unfavoriteVenue(venueId : Int) async throws
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            
            Analytics.track(["event": "unfavorite_venue"])
            
            _ = try await api.getAlamo().delete(APIEndpoints.favoriteVenue(id: PreferabliTools.getPreferabliUserId(), venueId: venueId))
            
            try await Storage.withBackgroundContext { ctx, save in
                guard let user = try Storage.fetchById(PreferabliUser.self, id: PreferabliTools.getPreferabliUserId(), in: ctx) else {
                    return
                }
                
                var favorites = user.favorite_venue_ids ?? []
                favorites.removeAll { $0 == venueId }
                user.favorite_venue_ids = favorites
                
                try save()
            }
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func unfavoriteExperience(experienceId : Int) async throws
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            
            Analytics.track(["event": "unfavorite_experience"])
            
            _ = try await api.getAlamo().delete(APIEndpoints.favoriteExperience(id: PreferabliTools.getPreferabliUserId(), experienceId: experienceId))
            
            try await Storage.withBackgroundContext { ctx, save in
                guard let user = try Storage.fetchById(PreferabliUser.self, id: PreferabliTools.getPreferabliUserId(), in: ctx) else {
                    return
                }
                
                var favorites = user.favorite_experience_ids ?? []
                favorites.removeAll { $0 == experienceId }
                user.favorite_experience_ids = favorites
                
                try save()
            }
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getChannels(force_refresh : Bool = false) async throws -> [Int]
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "get_channels"])
            
            let body: [ChannelDTO] = try await api.getAlamo().get(APIEndpoints.channels)
            
            // --- 3. WRITE PHASE ---
            // Open a new, clean context *just* for writing
            let channelIds = try await Storage.withBackgroundContext { ctx, save in
                var channelIds = [Int]()
                for channelDTO in body {
                    let channel = try Storage.upsertChannel(from: channelDTO, in: ctx)
                    channelIds.append(channel.id)
                }
                // Save the write context
                try save()
                return channelIds
            }
            
            return channelIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getVenues(market_id: Int) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)

            Analytics.track(["event": "get_venues"])

            let params: SParams = [
                "limit": 9999,
                "offset": 0,
                "include_submarket_venues": true
            ]

            let body: [VenueDTO] = try await api.getAlamo().get(
                APIEndpoints.venues(id: market_id),
                sparams: params
            )

            let venueIds: [Int] = try await Storage.withBackgroundContext { ctx, save in
                guard let market = try Storage.fetchById(Market.self, id: market_id, in: ctx) else {
                    throw PreferabliException(
                        type: .BadSwiftData,
                        message: "Could not get venues due to lack of a market. This should never happen.",
                        code: 659
                    )
                }

                let keepVenueIDs = Set(body.map(\.id))

                try Storage.deleteVenuesNotInBatch(
                    keepVenueIDs,
                    rootMarket: market,
                    in: ctx
                )

                let batch = try Storage.VenueUpsertBatch(
                    venueDTOs: body,
                    market: market,
                    in: ctx
                )

                var venueIds: [Int] = []
                venueIds.reserveCapacity(body.count)

                for dto in body {
                    if let venue = try Storage.upsertVenue(from: dto, market: market, batch: batch, in: ctx) {
                        venueIds.append(venue.id)
                    }
                }

                try save()
                return venueIds
            }

            return venueIds

        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getExperiences(market_id: Int) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "get_experiences"])
            
            let params: SParams = ["limit": 9999, "offset": 0]
            let body: [ExperienceDTO] = try await api.getAlamo().get(APIEndpoints.experiences(marketId: market_id), sparams: params)
            
            let experienceIds: [Int] = try await Storage.withBackgroundContext { ctx, save in
                var experienceIds: [Int] = []
                experienceIds.reserveCapacity(body.count)

                for experienceDTO in body {
                    guard
                        let preferabli_venue_id = experienceDTO.preferabli_venue_id,
                        let venue = try Storage.fetchById(Venue.self, id: preferabli_venue_id, in: ctx)
                    else {
                        continue
                    }

                    let experience = try Storage.upsertExperience(from: experienceDTO, venue: venue, in: ctx)
                    experienceIds.append(experience.id)
                }

                if let market = try Storage.fetchById(Market.self, id: market_id, in: ctx) {
                    try Storage.tombstoneExperiencesNotInSet(
                        Set(experienceIds),
                        rootMarket: market,
                        in: ctx
                    )
                }

                try save()
                return experienceIds
            }
            
            return experienceIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getCTAPages(
        force_refresh: Bool = false
    ) async throws -> [Int] {
        let api = self.api
        let loggingEnabled = self.loggingEnabled // (unused for now, but left intact)
        
        return try await BucketsLoader.shared.run { [weak self] in
            guard let self else { return [] }
            
            do {
                try await self.canWeContinue(needsToBeLoggedIn: false)
                Analytics.track(["event": "get_cta_pages"])
                                
                // Only short-circuit for the *general* (unscoped) load
                if !force_refresh,
                   Storage.getKeyStore().bool(forKey: "hasLoadedCTAPages") {
                    
                    let localIds: [Int] = try await Storage.withBackgroundContext { ctx, save in
                        let pages = try ctx.fetch(FetchDescriptor<CTAPage>())
                        return pages.filter { !$0.isTombstoned }.map { $0.id }
                    }
                    
                    if !localIds.isEmpty { return localIds }
                }
                
                var params: SParams = ["domain": "tastefuli-v3"]
                
                let body: [CTAPageDTO] = try await api
                    .getAlamo()
                    .get(APIEndpoints.ctaPages, sparams: params)
                
                let dtoIds: [Int] = try await Storage.withBackgroundContext { ctx, save in
                    let ids = try Storage.upsertCTAPagesSourceOfTruth(
                        from: body,
                        in: ctx
                    )
                    try save()
                    return ids
                }
                
                Storage.getKeyStore().set(true, forKey: "hasLoadedCTAPages")
                
                return dtoIds
                
            } catch {
                await MainActor.run {
                    self.handleError(error: error)
                }
                throw error
            }
        }
    }
    
    public func getMarkets(force_refresh: Bool = false) async throws -> [Int] {
        let api = self.api
        let loggingEnabled = self.loggingEnabled // if needed later
        
        return try await MarketsLoader.shared.run { [weak self] in
            guard let self else { return [] }
            
            do {
                try await self.canWeContinue(needsToBeLoggedIn: false)
                Analytics.track(["event": "get_markets"])
                
                if !force_refresh, Storage.getKeyStore().bool(forKey: "hasLoadedMarkets") {
                    let localIds: [Int] = try await Storage.withBackgroundContext { ctx, save in
                        let markets = try ctx.fetch(FetchDescriptor<Market>())
                        return markets.map { $0.id }
                    }
                    if !localIds.isEmpty { return localIds }
                }
                
                let body: [MarketDTO] = try await api.getAlamo().get(APIEndpoints.markets)
                
                let dtoIds: [Int] = {
                    var out: [Int] = []
                    func walk(_ m: MarketDTO) {
                        out.append(m.id)
                        if let submarkets = m.submarkets {
                            for c in submarkets { walk(c) }
                        }
                    }
                    for m in body { walk(m) }
                    return out
                }()
                
                try await Storage.withBackgroundContext { ctx, save in
                    _ = try Storage.upsertMarketsSourceOfTruth(from: body, in: ctx)
                    try save()
                }
                
                Storage.getKeyStore().set(true, forKey: "hasLoadedMarkets")
                return dtoIds
                
            } catch {
                await MainActor.run {
                    self.handleError(error: error)
                }
                throw error
            }
        }
    }
    
    public func getRecipes(force_refresh: Bool = false) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "get_recipes"])
            
            if !force_refresh, Storage.getKeyStore().bool(forKey: "hasLoadedRecipes") {
                let localIds: [Int] = try await Storage.withBackgroundContext { ctx, save in
                    let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
                    return recipes.map { $0.id }
                }
                if !localIds.isEmpty { return localIds }
            }
            
            let body: [RecipeDTO] = try await api.getAlamo().get(APIEndpoints.recipes)
            
            let recipeIds : [Int] = try await Storage.withBackgroundContext { ctx, save in
                var recipeIds : [Int] = []
                for recipe in body {
                    let recipeActual = try Storage.upsertRecipe(from: recipe, in: ctx)
                    recipeIds.append(recipeActual.id)
                }
                try save()
                
                return recipeIds
            }
            
            Storage.getKeyStore().set(true, forKey: "hasLoadedRecipes")
            return recipeIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getRecipeGroups(force_refresh: Bool = false) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "get_recipe_groups"])
            
            if !force_refresh, Storage.getKeyStore().bool(forKey: "hasLoadedRecipeGroups") {
                let localIds: [Int] = try await Storage.withBackgroundContext { ctx, save in
                    let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
                    return recipes.map { $0.id }
                }
                if !localIds.isEmpty { return localIds }
            }
            
            let body: [RecipeGroupDTO] = try await api.getAlamo().get(APIEndpoints.recipeGroups)
            
            let recipeGroupIds : [Int] = try await Storage.withBackgroundContext { ctx, save in
                var recipeGroupIds : [Int] = []
                for recipeGroup in body {
                    let recipeActual = try Storage.upsertRecipeGroup(from: recipeGroup, in: ctx)
                    recipeGroupIds.append(recipeActual.id)
                }
                try save()
                
                return recipeGroupIds
            }
            
            Storage.getKeyStore().set(true, forKey: "hasLoadedRecipeGroups")
            return recipeGroupIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    
    /// Get product details like a taste profile and food pairings.
    /// - Parameters:
    ///   - force_refresh: if you want to force a refresh of the data
    ///   - product_id: id of the starting ``Product``.  Only pass a Preferabli product id. If necessary, call ``Preferabli/getPreferabliProductId(merchant_product_id:merchant_variant_id:onCompletion:onFailure:)`` to convert your product id into a Preferabli product id.
    /// - Returns:
    ///     - A product ID to use in ``ProductsQuery``.
    public func getProduct(force_refresh : Bool = false, product_id : Int) async throws -> Int
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "product_refresh"])
            
            var needsRefresh = true
            
            if (!force_refresh) {
                try Storage.withContext { ctx, save in
                    if let product = try Storage.fetchById(Product.self, id: product_id, in: ctx) {
                        
                        needsRefresh = PreferabliTools.hasMinutesPassed(minutes: 60, startDate: Storage.getKeyStore().object(forKey: "lastCalledProduct\(product_id)") as? Date)
                    }
                }
            }
            
            if needsRefresh {
                let body: ProductDTO = try await api.getAlamo().get(APIEndpoints.product(id: product_id))
                
                try Storage.withContext { ctx, save in
                    try Storage.upsertProduct(from: body, in: ctx)
                    
                    try save()
                    
                    Storage.getKeyStore().set(Date(), forKey: "lastCalledProduct\(product_id)")
                }
            }
            
            return product_id
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getProduct(force_refresh : Bool = false, productHash : String) async throws
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "product_refresh"])
            
            var needsRefresh = true
            
            if (!force_refresh) {
                try Storage.withContext { ctx, save in
                    
                    let fd = FetchDescriptor<Product>(
                        predicate: #Predicate<Product> {
                            $0.product_hash == productHash
                        }
                    )

                    let results = try ctx.fetch(fd)
                    
                    if let product = results.first {
                        needsRefresh = PreferabliTools.hasMinutesPassed(minutes: 60, startDate: Storage.getKeyStore().object(forKey: "lastCalledProduct\(product.id)") as? Date)
                    }
                }
            }
            
            if needsRefresh {
                let body: [ProductDTO] = try await api.getAlamo().get(APIEndpoints.products, sparams: ["hashes" : [productHash]])
                
                try Storage.withContext { ctx, save in
                    if let first = body.first {
                        try Storage.upsertProduct(from: first, in: ctx)
                        
                        try save()
                        
                        Storage.getKeyStore().set(Date(), forKey: "lastCalledProduct\(first.id)")
                    }
                }
            }
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getExperience(force_refresh : Bool = false, venue_id : Int, experience_id : Int) async throws -> Int
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "experience_refresh"])
            
            var needsRefresh = true
            var needsVenue = true
            
                try Storage.withContext { ctx, save in
                    if let venue = try Storage.fetchById(Venue.self, id: venue_id, in: ctx) {
                        needsVenue = false
                    }
                    if let experience = try Storage.fetchById(Experience.self, id: experience_id, in: ctx) {
                        needsRefresh = PreferabliTools.hasMinutesPassed(minutes: 60, startDate: Storage.getKeyStore().object(forKey: "lastCalledExperience\(experience_id)") as? Date) || force_refresh
                    }
                }
            
            if needsVenue {
                let body: VenueDTO = try await api.getAlamo().get(APIEndpoints.venue(id: venue_id))
                
                try Storage.withContext { ctx, save in
                    try Storage.upsertVenue(from: body, in: ctx)
                    
                    try save()
                }
            }
            
            if needsRefresh {
                
                let experienceDTO: ExperienceDTO = try await api.getAlamo().get(APIEndpoints.experience(id: experience_id))
                
                try await Storage.withBackgroundContext { ctx, save in
                        
                        guard let preferabli_venue_id =  experienceDTO.preferabli_venue_id, let venue = try Storage.fetchById(Venue.self, id: preferabli_venue_id, in: ctx) else {
                            return
                        }
                        
                        try Storage.upsertExperience(from: experienceDTO, venue: venue, in: ctx)

                    try save()
                    
                    Storage.getKeyStore().set(Date(), forKey: "lastCalledExperience\(experience_id)")
                }
            }
            
            return experience_id
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getVenue(force_refresh : Bool = false, venue_id : Int) async throws -> Int
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "venue_refresh"])
            
            var needsRefresh = true
            
            if (!force_refresh) {
                try Storage.withContext { ctx, save in
                    if let venue = try Storage.fetchById(Venue.self, id: venue_id, in: ctx) {
                        needsRefresh = PreferabliTools.hasMinutesPassed(minutes: 60, startDate: Storage.getKeyStore().object(forKey: "lastCalledVenue\(venue_id)") as? Date)
                    }
                }
            }
            
            if needsRefresh {
                let body: VenueDTO = try await api.getAlamo().get(APIEndpoints.venue(id: venue_id))
                
                try Storage.withContext { ctx, save in
                    try Storage.upsertVenue(from: body, in: ctx)
                    
                    try save()
                    
                    Storage.getKeyStore().set(Date(), forKey: "lastCalledVenue\(venue_id)")
                }
            }
            
            return venue_id
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getReservations() async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            
            Analytics.track(["event": "reservations_refresh"])
            
            var needsRefresh = true
            
            
            let body: [ReservationDTO] = try await api.getAlamo().get(APIEndpoints.reservations)
            
            let reservationIds = try Storage.withContext { ctx, save in
                var ids = [Int]()
                for dto in body {
                    let reservation = try Storage.upsertReservation(from: dto, in: ctx)
                    ids.append(reservation.id)
                }
                
                try save()
                
                return ids
            }
            
            return reservationIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getExperiences(force_refresh: Bool = false, venue_id: Int) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "experiences_refresh"])
            
            var needsRefresh = true
            
            if !force_refresh {
                try Storage.withContext { ctx, save in
                    if try Storage.fetchById(Venue.self, id: venue_id, in: ctx) != nil {
                        needsRefresh = PreferabliTools.hasMinutesPassed(
                            minutes: 60,
                            startDate: Storage.getKeyStore().object(forKey: "lastCalledVenueExperiences\(venue_id)") as? Date
                        )
                    }
                }
            }
            
            var experienceIds = [Int]()
            if needsRefresh {
                
                let params: SParams = ["limit": 9999, "offset": 0]
                let body: [ExperienceDTO] = try await api.getAlamo().get(APIEndpoints.experiences(id: venue_id), sparams: params)
                
                experienceIds = try await Storage.withBackgroundContext { ctx, save in
                    var experienceIds: [Int] = []
                    experienceIds.reserveCapacity(body.count)
                    
                    for experienceDTO in body {
                        
                        guard let preferabli_venue_id =  experienceDTO.preferabli_venue_id, let venue = try Storage.fetchById(Venue.self, id: preferabli_venue_id, in: ctx) else {
                            continue
                        }
                        
                        let experience = try Storage.upsertExperience(from: experienceDTO, venue: venue, in: ctx)
                        experienceIds.append(experience.id)
                    }
                    
                    try Storage.tombstoneExperiencesNotInSet(
                        Set(experienceIds),
                        scopeVenueId: venue_id,
                        in: ctx
                    )

                    try save()
                    return experienceIds
                }
            }
            
            return experienceIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func addBalloonTicket(booking_code: String) async throws -> String {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "add_balloon_ticket"])

            let params: SParams = ["search": booking_code]
            let body : BalloonResponseDTO = try await api.getAlamo().get(APIEndpoints.balloonBooking, sparams: params)
            
            let reservationId = try Storage.withContext { ctx, save in
                let reservation = try Storage.upsertBalloonReservation(from: body.booking, in: ctx)
                try save()
                return reservation.id
            }
            
            return reservationId
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func completeSafetyBrief(
        email: String,
        firstname: String,
        lastname: String,
        phone: String,
        marketing_sign_up_requested: String,
        booking_id: String,
        date_of_birth: String
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)

            Analytics.track([
                "event": "complete_safety_brief",
                "booking_id": booking_id
            ])

            let params: SParams = [
                "email": email,
                "firstname": firstname,
                "lastname": lastname,
                "phone": phone,
                "completed_safety_brief": true,
                "marketing_sign_up_requested": marketing_sign_up_requested,
                "completed_safety_brief_platform": Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE"),
                "booking_id": booking_id,
                "date_of_birth": date_of_birth
            ]

            try await api.getAlamo().post(APIEndpoints.completeSafetyBrief, sjson: params)

            try await Storage.withBackgroundContext { ctx, save in
                guard let reservation = try Storage.fetchById(BalloonReservation.self, id: booking_id, in: ctx) else {
                    return
                }
                
                reservation.completed_safety_brief = true
                
                try save()
            }

        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    /// Get help finding out where a ``Product`` is in stock.
    /// - Parameters:
    ///   - product_id: id of the starting ``Product``.  Only pass a Preferabli product id. If necessary, call ``Preferabli/getPreferabliProductId(merchant_product_id:merchant_variant_id:onCompletion:onFailure:)`` to convert your product id into a Preferabli product id.
    ///   - fulfill_sort: pass ``FulfillSort`` for sorting & filtering options. If sorting by distance, ``Location`` MUST be present!
    ///   - append_nonconforming_results: pass true if you want results that *DO NOT* conform to all filtering & sorting parameters to be returned. Useful so that something is returned even if the user's filter parameters are too narrow. All results that do not conform contain nonconforming_result = true within. Defaults to *true*.
    ///   - lock_to_integration: pass true if you only want to draw results from your integration. Defaults to *false*.
    public func whereToBuy(product_id : Int, fulfill_sort : FulfillSort = FulfillSort.init(), append_nonconforming_results : Bool = true, lock_to_integration : Bool = false) async throws -> WhereToBuyDTO {
        
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track( ["event" : "where_to_buy"])
            
            var sort_by = "nearest_first"
            if (fulfill_sort.type == .DISTANCE && fulfill_sort.ascending) {
                sort_by = "nearest_first"
            } else if (fulfill_sort.type == .DISTANCE) {
                sort_by = "furthest_first"
            } else if (fulfill_sort.ascending){
                sort_by = "price_asc"
            } else {
                sort_by = "price_desc"
            }
            
            var params : SParams = ["product_id" : product_id, "sort_by" : sort_by, "merge_products" : true, "in-person" : fulfill_sort.include_in_person, "pickup" : fulfill_sort.include_pickup, "local_delivery" : fulfill_sort.include_delivery, "standard_shipping" : fulfill_sort.include_shipping, "append_nonconforming_results" : append_nonconforming_results, "limit" : 1000, "offset" : 0, "distance_miles" : fulfill_sort.distance_miles]
            
            if (fulfill_sort.type == .DISTANCE && fulfill_sort.location == nil) {
                throw PreferabliException.init(type: .OtherError, message: "Sort by distance requires a location.")
            } else if let location = fulfill_sort.location {
                if (location.zip_code.isEmptyOrWhitespace) {
                    params["lat"] = location.latitude
                    params["long"] = location.longitude
                } else {
                    params["zip_code"] = location.zip_code
                }
            } else {
                params["in_stock_anywhere"] = true
            }
            
            if (lock_to_integration) {
                var channelIds = Array<Int>()
                channelIds.append(Preferabli.CHANNEL_ID)
                params["channel_ids"] = channelIds
            }
            
            if (fulfill_sort.variant_year != Variant.NON_VARIANT) {
                var years = Array<Int>()
                years.append(fulfill_sort.variant_year)
                params["years"] = years
            }
            
            let marketplaceResponse : [WhereToBuyDTO] = try await api.getAlamo().get(APIEndpoints.whereToBuy, sparams: params)
            
            guard let result = marketplaceResponse.first else {
                throw PreferabliException.init(type: .BadData, message: "No Where to Buy data passed!", code: 765)
            }
            
            if ((result.lookup_results?.isEmpty ?? true) && (result.venue_results?.isEmpty ?? true)) {
                throw PreferabliException.init(type: .APIError, message: "No Where to Buy data passed!", code: 765)
            }
            
            return result
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    /// Create a brand new "mycellar" collection and attach it to the current user.
    /// Mirrors the legacy UIKit flow:
    /// 1) optional media upload
    /// 2) POST collection
    /// 3) POST user-collection relationship (relationship_type = "mycellar")
    /// 4) upsert Collection + UserCollection locally
    /// - Returns: the created Collection id
    public func createCellar(
        name: String,
        image: Data? = nil
    ) async throws -> Int {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "create_cellar"])
            
            var payload: SParams = [
                "name": name,
                "public": false,
                "start_date": PreferabliTools.getAPIDateFormatter().string(from: Date()),
                "end_date": PreferabliTools.getAPIDateFormatter().string(from: Date()),
                "is_blind": false,
                "display_price": true,
                "display_time": false,
                "display_quantity": true,
                "display_bin": true,
                "display_group_headings": true,
                "published": true,
                "order": 1,
                "timezone": TimeZone.current.identifier,
                "location_based_recs": true,
                "traits": [10],
                "default_group_name": "Cellar Group"
            ]
            
            // --- Optional image upload -> primary_image_id ---
            if let image {
                let mediaResponse: MediaDTO = try await api.getAlamo().upload(APIEndpoints.postMedia, data: image)
                payload["primary_image_id"] = mediaResponse.id
            }
            
            // --- 1) Create the collection ---
            let collectionDTO: CollectionDTO = try await api
                .getAlamo()
                .post(APIEndpoints.collections, sjson: payload)
            
            let collectionId = collectionDTO.id
            
            // --- 2) Create the user relationship (mycellar) ---
            let relPayload: SParams = [
                "collection_id": collectionId,
                "relationship_type": "mycellar",
                "is_admin": true,
                "is_editor": true,
                "is_viewer": true,
                "user_id": PreferabliTools.getPreferabliUserId()
            ]
            
            // Your getUserCollections() uses APIEndpoints.userCollections(id: userId) for GET.
            // We assume POST to the same endpoint is correct (like legacy APIEndpoints.userCollections()).
            let userCollectionDTO: UserCollectionDTO = try await api
                .getAlamo()
                .post(APIEndpoints.userCollections(id: PreferabliTools.getPreferabliUserId()), sjson: relPayload)
            
            // --- 3) Upsert locally ---
            try Storage.withContext { ctx, save in
                _ = try Storage.upsertCollection(from: collectionDTO, in: ctx)
                _ = try Storage.upsertUserCollection(from: userCollectionDTO, in: ctx)
                try save()
            }
            
            
            var ids = Storage.loadCellarCollectionIDSetCached()
            if !ids.contains(collectionId) { ids.insert(collectionId) }
            Storage.saveCellarCollectionIDs(Array(ids))
            
            
            try await canWeContinue(needsToBeLoggedIn: true)
            
            return collectionId
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func editCellar(collectionId: Int,
                           name: String,
                           image: Data? = nil,
                           removeImage: Bool
    ) async throws -> Int {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "edit_cellar"])
            
            var payload: SParams = [
                "name": name
            ]
            
            // --- Optional image upload -> primary_image_id ---
            if let image {
                let mediaResponse: MediaDTO = try await api.getAlamo().upload(APIEndpoints.postMedia, data: image)
                payload["primary_image_id"] = mediaResponse.id
            } else if (removeImage) {
                payload["primary_image_id"] = NSNull()
            }
            
            // --- 1) Create the collection ---
            let collectionDTO: CollectionDTO = try await api
                .getAlamo()
                .put(APIEndpoints.collection(id: collectionId), sjson: payload)
            
            try Storage.withContext { ctx, save in
                _ = try Storage.upsertCollection(from: collectionDTO, in: ctx)
                try save()
            }
            
            try await canWeContinue(needsToBeLoggedIn: true)
            
            return collectionId
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func deleteCellar(userCollectionId: Int
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "delete_cellar"])
            
            _ = try await api
                .getAlamo()
                .delete(APIEndpoints.userCollection(id: PreferabliTools.getPreferabliUserId(), userCollectionId: userCollectionId))
            
            try Storage.withContext { ctx, save in
                guard let userCollection = try Storage.fetchById(UserCollection.self, id: userCollectionId, in: ctx) else {
                    return
                }
                
                ctx.delete(userCollection)
                
                try save()
            }
            
            try await canWeContinue(needsToBeLoggedIn: true)
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func deleteOrdering(collectionId: Int,
                               versionId: Int,
                               groupId: Int,
                               orderingId: Int
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "delete_ordering"])
            
            _ = try await api
                .getAlamo()
                .delete(APIEndpoints.ordering(collectionId: collectionId, versionId: versionId, groupId: groupId, orderingId: orderingId))
            
            try Storage.withContext { ctx, save in
                guard let ordering = try Storage.fetchById(CollectionOrder.self, id: orderingId, in: ctx) else {
                    return
                }
                ctx.delete(ordering)
                
                if let collection = try Storage.fetchById(Collection.self, id: collectionId, in: ctx) {
                    collection.product_count = max(0, (collection.product_count ?? 0) - 1)
                    collection.updated_at = Date()
                }
                
                try save()
            }
            
            try await canWeContinue(needsToBeLoggedIn: true)
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    /// Get the Preference Profile of the customer. Customer must be logged in to run this call.
    /// - Parameters:
    ///   - force_refresh: pass true if you want to force a refresh from the API and wait for the results to return. Otherwise, the call will load locally if available and run a background refresh only if one has not been initiated in the past 5 minutes. Defaults to *false*.
    /// Get the Preference Profile of the customer (or user).
    /// This now delegates to ProfileHelper, which handles deduping and analytics.
    public func getProfile(force_refresh: Bool = false) async throws -> Int {
        try await profileHelper.getProfile(force_refresh: force_refresh)
    }
    
    /// Ensures Taste Profile Statistics are computed and ready for UI consumption.
    ///
    /// This is the "all-or-nothing" entry point for analytics screens:
    /// it will ensure the profile exists locally, ensure ratings are loaded if needed,
    /// and recompute/store analytics from local SwiftData.
    ///
    /// - Parameters:
    ///   - force_refresh_profile: Force refresh the profile from network.
    ///   - force_refresh_ratings: Force refresh the ratings collection from network.
    ///   - timeout: How long we’ll wait for ratings load when required.
    @MainActor
    public func ensureProfileStatisticsReady(
        force_refresh_profile: Bool = false,
        force_refresh_ratings: Bool = false,
        timeout: TimeInterval = 10
    ) async {
        await profileStatsCoordinator.ensureStatsReady(
            forceRefreshProfile: force_refresh_profile,
            forceRefreshRatings: force_refresh_ratings,
            timeout: timeout
        )
    }
    
    /// Convenience: returns stats after ensuring they are ready.
    @MainActor
    public func getProfileStatistics(
        force_refresh_profile: Bool = false,
        force_refresh_ratings: Bool = false,
        timeout: TimeInterval = 10
    ) async -> ProfileStatistics? {
        await ensureProfileStatisticsReady(
            force_refresh_profile: force_refresh_profile,
            force_refresh_ratings: force_refresh_ratings,
            timeout: timeout
        )
        return ProfileAnalytics.loadStats()
    }
    
    /// Get a personalized, preference based recommendation for a customer.
    /// - Parameters:
    ///   - product_category: pass a ``ProductCategory`` that you would like the results to conform to.
    ///   - product_type: pass a ``ProductType`` that you would like the results to conform to. Pass ``ProductType/OTHER`` if ``ProductCategory`` is not set  to ``ProductCategory/WINE``. If ``ProductCategory/WINE`` is passed, a type of wine *must* be passed here.
    ///   - collection_id: the id of a specific ``Collection`` that you want to draw results from. Defaults to ``PRIMARY_INVENTORY_ID``. Pass *nil* for results from anywhere.
    ///   - price_min: pass if you want to lock results to a minimum price. Defaults to *nil*.
    ///   - price_max: pass if you want to lock results to a maximum price. Defaults to *nil*.
    ///   - style_ids: an array of ``Style`` ids that you want to constrain results to. Get available styles from ``getProfile(force_refresh:onCompletion:onFailure:)``. Defaults to *nil*.
    public func getRecommendations(
        product_category: ProductCategory?,
        product_subcategory: ProductSubcategory?,
        product_type: ProductType?,
        price_min: Int?,
        price_max: Int?,
        collection_id: Int? = PRIMARY_INVENTORY_ID,
        style_ids: [Int]?
    ) async throws -> [Int] {
        do {
            guard let product_category else {
                throw PreferabliException.init(type: .BadSwiftData, message: "No Product Category passed!", code: 700)
            }
            
            
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event" : "get_recs"])
            
            // 1) Build constraints
            var constraints = [SParams]()
            
            if Preferabli.isCustomerLoggedIn() {
                constraints.append([
                    "type"   : "channel_customer_ids",
                    "values" : [PreferabliTools.getCustomerId()]
                ])
            } else {
                constraints.append([
                    "type"   : "user_ids",
                    "values" : [PreferabliTools.getPreferabliUserId()]
                ])
            }
            
            constraints.append(["type": "collection_ids", "values": [collection_id]])
            if let pt = product_type {
                constraints.append(["type": "types", "values": [pt.getTypeName()]])
            }
            constraints.append(["type": "product_categories", "values": [product_category.getCategoryName()]])
            constraints.append(["type": "precedence",          "values": false])
            constraints.append(["type": "single_style",        "values": true])
            constraints.append(["type": "rated_wines",         "values": "ignore"])
            
            if let style_ids, !style_ids.isEmpty {
                constraints.append(["type": "style_ids", "values": style_ids])
            }
            
            if let price_min { constraints.append(["type": "price_min", "values": price_min]) }
            if let price_max { constraints.append(["type": "price_max", "values": price_max]) }
            
            let payload: SParams = ["constraints": constraints]
            
            var recResponse: RecResponseDTO = try await api
                .getAlamo()
                .post(APIEndpoints.getRec, sjson: payload)
            
            let results = recResponse.results
            
            if (collection_id != Preferabli.PRIMARY_INVENTORY_ID && recResponse.message?.containsIgnoreCase("collection constraint") ?? false) {
                throw PreferabliException(
                    type: .APIError,
                    message: "No products that fit this rec in this inventory.",
                    code: 610
                )
            }
            
            // 2) Collect variant ids + prediction metadata (all local, immutable)
            let variantIds: [Int] = results.map { $0.variant_id }
            
            let predictedByVariant: [Int: (rating: Int?, code: Int?)] = {
                var tmp: [Int: (Int?, Int?)] = [:]
                for r in results {
                    tmp[r.variant_id] = (r.formatted_predict_rating, r.confidence_code)
                }
                return tmp
            }()
            
            guard !variantIds.isEmpty else {
                try await canWeContinue(needsToBeLoggedIn: true)
                return []
            }
            
            // 3) Figure out missing variants in a BACKGROUND context
            let missingVariantIds: [Int] = try await Storage.withBackgroundContext { ctx, save in
                try Storage.missingVariantIds(from: variantIds, in: ctx)
            }
            
            // 4) Fetch products only for missing variants
            let productDTOs: [ProductDTO]
            if missingVariantIds.isEmpty {
                productDTOs = []
            } else {
                productDTOs = try await api.getAlamo().get(
                    APIEndpoints.products,
                    sparams: ["variant_ids": missingVariantIds]
                )
            }
            
            // 5) Upsert missing products + attach PreferenceData + build ordered productIds
            let productIds: [Int] = try await Storage.withBackgroundContext { ctx, save in
                // 5a) Upsert missing products
                for pd in productDTOs {
                    _ = try Storage.upsertProduct(from: pd, in: ctx)
                }
                
                // 5b) Attach preference_data and collect product IDs
                var ids: [Int] = []
                var seen = Set<Int>()
                
                for vid in variantIds {
                    guard let variant = try Storage.fetchById(Variant.self, id: vid, in: ctx) else {
                        continue
                    }
                    let product = variant.product
                    
                    if let prediction = predictedByVariant[variant.id] {
                        let preferenceDataDTO = PreferenceDataDTO(
                            confidence_code: prediction.code,
                            formatted_predict_rating: prediction.rating
                        )
                        try Storage.upsertPreferenceData(from: preferenceDataDTO, for: product, in: ctx)
                    }
                    
                    if seen.insert(product.id).inserted {
                        ids.append(product.id)
                    }
                }
                
                try save()
                return ids
            }
            
            
            try await canWeContinue(needsToBeLoggedIn: true)
            return productIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func addToCellar(
        product_id: Int,
        year: Int,
        cellar_id: Int,
        group_id: Int
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track(["event": "add_to_cellar"])
            
            // 1) Create the Tag first (this is the “membership” in the cellar collection).
            let tagId = try await createOrEditTagActual(
                product_id: product_id,
                year: year,
                collection_id: cellar_id,
                value: nil,
                tag_type: .COLLECTION,
                location: nil,
                notes: nil,
                price: nil,
                quantity: nil,
                format_ml: nil
            )
            
            // 2) Resolve version_id + compute next order for this group
            //    (Ensure we have the cellar collection + versions/groups locally)
            let resolved: (versionId: Int, nextOrder: Int) = try await {
                // Helper: pick “current” version (highest order, fallback to newest timestamp)
                func pickVersionId(_ versions: [CollectionVersion]) -> Int? {
                    if versions.isEmpty { return nil }
                    // Prefer explicit order
                    let byOrder = versions.sorted { ($0.order ?? Int.min) < ($1.order ?? Int.min) }
                    if let last = byOrder.last, last.id != 0 { return last.id }
                    // Fallback: updated_at
                    let byUpdated = versions.sorted { ($0.updated_at) < ($1.updated_at) }
                    return byUpdated.last?.id
                }
                
                // Try local first
                if let local = try Storage.withContext({ ctx, save -> (Int, Int)? in
                    guard let collection = try Storage.fetchById(Collection.self, id: cellar_id, in: ctx) else { return nil }
                    guard let versionId = pickVersionId(collection.versions) else { return nil }
                    guard let group = try Storage.fetchById(CollectionGroup.self, id: group_id, in: ctx) else { return nil }
                    // Ensure the group is actually in that version (defensive)
                    if group.version.id != versionId { return nil }
                    
                    let maxOrder = group.orderings.map(\.order).max() ?? -1
                    return (versionId, maxOrder + 1)
                }) {
                    return local
                }
                
                // Network fallback: fetch collection, upsert versions/groups, then recompute
                let dto: CollectionDTO = try await api.getAlamo().get(APIEndpoints.collection(id: cellar_id))
                _ = try Storage.withContext { ctx, save in
                    _ = try Storage.upsertCollection(from: dto, in: ctx)
                    try save()
                }
                
                guard let after = try Storage.withContext({ ctx, save -> (Int, Int)? in
                    guard let collection = try Storage.fetchById(Collection.self, id: cellar_id, in: ctx) else { return nil }
                    guard let versionId = pickVersionId(collection.versions) else { return nil }
                    guard let group = try Storage.fetchById(CollectionGroup.self, id: group_id, in: ctx) else { return nil }
                    if group.version.id != versionId { return nil }
                    
                    let maxOrder = group.orderings.map(\.order).max() ?? -1
                    return (versionId, maxOrder + 1)
                }) else {
                    throw PreferabliException(
                        type: .BadSwiftData,
                        message: "Could not resolve collection version/group for cellar add.",
                        code: 600
                    )
                }
                
                return after
            }()
            
            // 3) Create the ordering on the server (links Tag <-> Group, sets order)
            let orderingPayload: SParams = [
                "tag_id": tagId,
                "order": resolved.nextOrder
            ]
            
            // Expecting a single ordering back
            let orderingDTO: CollectionOrderDTO = try await api.getAlamo().post(
                APIEndpoints.orderings(collectionId: cellar_id, versionId: resolved.versionId, groupId: group_id),
                sjson: orderingPayload
            )
            
            // 4) Upsert ordering locally and link relationships (Group <-> Order <-> Tag)
            try Storage.withContext { ctx, save in
                guard
                    let group = try Storage.fetchById(CollectionGroup.self, id: group_id, in: ctx),
                    let tag   = try Storage.fetchById(Tag.self, id: tagId, in: ctx),
                    let collection = try Storage.fetchById(Collection.self, id: cellar_id, in: ctx)
                        
                else {
                    throw PreferabliException(
                        type: .BadSwiftData,
                        message: "Could not finalize cellar add due to missing Group/Tag in local DB.",
                        code: 600
                    )
                }
                
                _ = try Storage.upsertCollectionOrder(from: orderingDTO, group: group, tag: tag, in: ctx)
                
                // Keep product cached relationships consistent (cellar tag affects cachedCellar)
                tag.variant.product.updateCachedRelationships()
                
                group.orderings_count = (group.orderings_count ?? 0) + 1
                group.updated_at = Date()
                
                collection.product_count = (collection.product_count ?? 0) + 1
                collection.updated_at = Date()
                
                try save()
            }
            
            try await canWeContinue(needsToBeLoggedIn: true)
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func skipProduct(product_id : Int) async throws {
        Analytics.track( ["event" : "skip_product"])
        try await createOrEditTagActual(product_id: product_id, year: Variant.CURRENT_VARIANT_YEAR, collection_id: Storage.getKeyStore().integer(forKey: "skips_id"), value: nil, tag_type: .SKIPPED, location: nil, notes: nil, price: nil, quantity: nil, format_ml: nil)
    }
    
    /// Rate a ``Product``. Creates a ``Tag`` of type ``TagType/RATING`` which is returned within the relevant product ``Variant``. User must be logged in to run this call.
    /// - Parameters:
    ///   - product_id: id of the starting ``Product``.  Only pass a Preferabli product id. If necessary, call ``Preferabli/getPreferabliProductId(merchant_product_id:merchant_variant_id:onCompletion:onFailure:)`` to convert your product id into a Preferabli product id.
    ///   - year: year of the ``Variant`` that you want to rate. Can use ``Variant/CURRENT_VARIANT_YEAR`` if you want to rate the latest variant, or ``Variant/NON_VARIANT`` if the product is not vintaged.
    ///   - rating: pass one of ``RatingLevel/LOVE``, ``RatingLevel/LIKE``, ``RatingLevel/SOSO``, ``RatingLevel/DISLIKE``.
    ///   - location: location where the rating occurred. Defaults to *nil*.
    ///   - notes: any notes to go along with the rating. Defaults to *nil*.
    ///   - price: price of the product rated. Defaults to *nil*.
    ///   - quantity: quantity purchased of the product rated. Defaults to *nil*.
    ///   - format_ml: size of the product rated. Defaults to *nil*.
    public func rateProduct(product_id : Int, year : Int, rating : RatingLevel, occasion : String? = nil, location : String? = nil, notes : String? = nil, price : Decimal? = nil, format_ml : Int? = nil) async throws {
        Analytics.track( ["event" : "rate_product"])
        try await createOrEditTagActual(product_id: product_id, year: year, collection_id: Storage.getKeyStore().integer(forKey: "ratings_id"), value: rating.getValue(), tag_type: .RATING, occasion: occasion, location: location, notes: notes, price: price, quantity: nil, format_ml: format_ml)
    }
    
    /// Toggles the wishlist status of a ``Product``. Creates a ``Tag`` of type ``TagType/WISHLIST`` if none already exists. Deletes the wishlist tag if it already does. User must be logged in to run this call.
    /// - Parameters:
    ///   - product_id: id of the starting ``Product``.  Only pass a Preferabli product id. If necessary, call ``Preferabli/getPreferabliProductId(merchant_product_id:merchant_variant_id:onCompletion:onFailure:)`` to convert your product id into a Preferabli product id.
    public func toggleProductOnWishlist(product_id : Int) async throws {
        Analytics.track( ["event" : "wishlist_product"])
        
        var existingTagId : Int?
        try Storage.withContext { ctx, save in
            let product = try Storage.fetchById(Product.self, id: product_id, in: ctx)
            existingTagId = product?.cachedWishlist?.id
            product?.cachedWishlist?.isTombstoned = true
            product?.cachedWishlist = nil
            try save()
        }
        
        if let existingTagId = existingTagId {
            try await deleteTag(tag_id: existingTagId)
        } else {
            try await createOrEditTagActual(product_id: product_id, year: Variant.CURRENT_VARIANT_YEAR, collection_id: Storage.getKeyStore().integer(forKey: "wishlist_id"), value: nil, tag_type: .WISHLIST, location: nil, notes: nil, price: nil, quantity: nil, format_ml: nil)
        }
    }
    
    @discardableResult
    public func submitProduct(
        name: String? = nil,
        image: Data? = nil,
        category: ProductCategory,
        subcategory: ProductSubcategory? = nil,
        type: ProductType? = nil,
        onTempProductSaved: ((Int) -> Void)? = nil
    ) async throws -> Int {

        Analytics.track(["event": "submit_product"])

        try await canWeContinue(needsToBeLoggedIn: false)

        let tempProductId = Storage.generateRandomLongId()
        let tempVariantId = Storage.generateRandomLongId()

        try Storage.withContext { ctx, save in
            let productDTO = ProductDTO(
                id: tempProductId,
                name: name,
                category: category.getCategoryName(),
                subcategory: subcategory?.getSubcategoryName(),
                type: type?.getTypeName()
            )

            let product = try Storage.upsertProduct(from: productDTO, in: ctx)
            product.temporaryImage = image
            product.temporaryName = name

            let variantDTO = VariantDTO(
                id: tempVariantId,
                created_at: Date(),
                updated_at: Date(),
                num_dollar_signs: nil,
                price: nil,
                recommendable: false,
                year: Variant.CURRENT_VARIANT_YEAR,
                primary_image: nil,
                product_id: tempProductId
            )

            _ = try Storage.upsertVariant(from: variantDTO, product: product, in: ctx)

            try save()
        }

        if let onTempProductSaved {
            await MainActor.run {
                onTempProductSaved(tempProductId)
            }
        }

        let payload: SParams = [
            "name": name,
            "category": category.getCategoryName(),
            "subcategory": subcategory?.getSubcategoryName(),
            "type": type?.getTypeName()
        ]

        var variantPayload: SParams = [
            "year": Variant.CURRENT_VARIANT_YEAR
        ]

        if let image {
            let mediaResponse: MediaDTO = try await api.getAlamo().upload(APIEndpoints.postMedia, data: image)
            variantPayload["image_ids"] = [mediaResponse.id]
            variantPayload["primary_image_id"] = mediaResponse.id
        }

        let productDTO: ProductDTO = try await api.getAlamo().post(APIEndpoints.products, sjson: payload)
        let variantDTO: VariantDTO = try await api.getAlamo().post(APIEndpoints.variants(product_id: productDTO.id), sjson: variantPayload)

        try Storage.withContext { ctx, save in
            let product = try Storage.upsertProduct(from: productDTO, tempProductId: tempProductId, in: ctx)
            _ = try Storage.upsertVariant(from: variantDTO, product: product, in: ctx)
            try save()
        }

        return productDTO.id
    }
    
    private func createOrEditTagActual(
        tag_id: Int? = nil,
        product_id: Int,
        year: Int,
        collection_id: Int,
        value: String? = nil,
        tag_type: TagType?,
        occasion: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        price: Decimal? = nil,
        quantity: Int? = nil,
        format_ml: Int? = nil,
        bin: String? = nil,
        tagged_in_collection_id: Int? = nil
    ) async throws -> Int {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            
            let tempTagId = tag_id ?? Storage.generateRandomLongId()
            let tempVariantId = Storage.generateRandomLongId()
            var needsRefresh = false
            
            try Storage.withContext { ctx, save in
                let product = try Storage.fetchById(Product.self, id: product_id, in: ctx)
                guard let product = product else {
                    needsRefresh = true
                    return
                }
                
                let variant: Variant
                if let v = try Storage.fetchVariant(productId: product_id, year: year, in: ctx) {
                    variant = v
                } else {
                    // Create a temp variant with the correct year. The API-created real variant
                    // can later promote/replace this temp variant by matching product/year.
                    let variantDTO = VariantDTO(
                        id: tempVariantId,
                        created_at: Date(),
                        updated_at: Date(),
                        num_dollar_signs: nil,
                        price: nil,
                        recommendable: false,
                        year: year,
                        primary_image: nil,
                        product_id: product_id
                    )
                    variant = try Storage.upsertVariant(from: variantDTO, product: product, in: ctx)
                    needsRefresh = true
                }

                let tagDTO = TagDTO(
                    id: tempTagId,
                    collection_id: collection_id,
                    comment: notes,
                    created_at: Date(),
                    location: location,
                    badge: nil,
                    tagged_in_collection_id: tagged_in_collection_id,
                    tagged_in_channel_id: nil,
                    tagged_in_channel_name: nil,
                    type: tag_type?.getDatabaseName(),
                    updated_at: Date(),
                    user_id: PreferabliTools.getPreferabliUserId(),
                    value: value,
                    bin: bin,
                    occasion: occasion,
                    variant_id: variant.id,
                    quantity: quantity,
                    format_ml: format_ml,
                    price: price,
                    customer_id: PreferabliTools.getCustomerId()
                )

                _ = try Storage.upsertTag(from: tagDTO, variant: variant, in: ctx)

                // Avoid product.updateCachedRelationships() here because it walks
                // product.variants -> variant.tags and can fault a stale relationship graph.
                switch tag_type {
                case .RATING:
                    product.cachedMostRecentRating = try Storage.fetchById(Tag.self, id: tempTagId, in: ctx)
                case .WISHLIST:
                    product.cachedWishlist = try Storage.fetchById(Tag.self, id: tempTagId, in: ctx)
                case .COLLECTION:
                    product.cachedCellar = try Storage.fetchById(Tag.self, id: tempTagId, in: ctx)
                default:
                    break
                }

                try save()
            }
            
            let payload: SParams = [
                "type"         : tag_type?.getDatabaseName(),
                "location"     : location,
                "comment"      : notes,
                "value"        : value,
                "year"         : year,
                "product_id"   : product_id,
                "price"        : price,
                "quantity"     : quantity,
                "format_ml"    : format_ml,
                "user_id"    : PreferabliTools.getPreferabliUserId(),
                "collection_id": collection_id
            ]
            
            // POST the tag to the right endpoint
            let tagDTO: TagDTO
            if Preferabli.isPreferabliUserLoggedIn() {
                if let tag_id = tag_id {
                    tagDTO = try await api.getAlamo().put(APIEndpoints.tag(collectionId: collection_id, tagId: tag_id), sjson: payload)
                } else {
                    tagDTO = try await api.getAlamo().post(APIEndpoints.tags(id: collection_id), sjson: payload)
                }
            } else {
                // must be customer
                tagDTO = try await api.getAlamo().post(APIEndpoints.customerTags(id: Preferabli.CHANNEL_ID, and: PreferabliTools.getCustomerId()), sjson: payload)
            }
            
            // we don't have the product. refresh.
            var productDTO: ProductDTO?
            if needsRefresh {
                // this call needs to happen AFTER creating the tag because a new variant is created in that call if necessary.
                // if this call ever fails after creating the tag, we may end up with a duplicate rating. should happen very rarely.
                productDTO = try await api.getAlamo().get(APIEndpoints.product(id: product_id))
            }
            
            // now we upsert the tag
            let tag_id: Int = try Storage.withContext { ctx, save in
                
                let product : Product?
                if let productDTO = productDTO {
                    product = try Storage.upsertProduct(from: productDTO, in: ctx)
                } else {
                    product = try Storage.fetchById(Product.self, id: product_id, in: ctx)
                }
                
                guard let product = product else {
                    throw PreferabliException.init(type: .BadSwiftData, message: "Could not add new tag due to database error involving Product. This should never happen.", code: 600)
                }
                
                guard let variant = try Storage.fetchById(Variant.self, id: tagDTO.variant_id, in: ctx) else {
                    throw PreferabliException.init(type: .BadSwiftData, message: "Could not add new tag due to database error involving Variant. This should never happen.", code: 600)
                }
                
                let tag = try Storage.upsertTag(from: tagDTO, variant: variant, tempTagId: tempTagId, in: ctx)
                
                try save()
                
                return tag.id
            }
            
            try await canWeContinue(needsToBeLoggedIn: true)
            
            if (tag_type == .RATING) {
                await profileStatsCoordinator.invalidateAndRecomputeIfReady()
                
                PreferabliTools.detachedCancellableTask { [weak self] in
                    try await self?.profileHelper.getProfile(force_refresh: false)
                }
            }
            
            return tag_id
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    
    /// Delete the specified ``Tag``.
    /// - Parameters:
    ///   - tag_id: id of the ``Tag`` you want to delete.
    public func deleteTag(tag_id: Int) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            Analytics.track( ["event" : "delete_tag"])
            
            try Storage.withContext { ctx, save in
                let tag = try Storage.fetchById(Tag.self, id: tag_id, in: ctx)
                tag?.isTombstoned = true
                tag?.variant.product.updateCachedRelationships()
                try save()
            }
            
            do {
                if Preferabli.isCustomerLoggedIn() {
                    try await api.getAlamo()
                        .delete(APIEndpoints.customerTag(id: Preferabli.CHANNEL_ID,
                                                         customerId: PreferabliTools.getCustomerId(),
                                                         tagId: tag_id))
                } else {
                    try await api.getAlamo()
                        .delete(APIEndpoints.userTag(id: PreferabliTools.getPreferabliUserId(),
                                                     tagId: tag_id))
                }
                
            } catch {
                // catch here to UNDELETE if for some reason the call fails...
                // we also need to figure out a way to run these with no network...
                try await Storage.withContext { ctx, save in
                    guard let tag = try Storage.fetchById(Tag.self, id: tag_id, in: ctx), tag.product_id != nil else {
                        throw PreferabliException(type: .DatabaseError)
                    }
                    tag.isTombstoned = false
                    tag.variant.product.updateCachedRelationships()
                    try save()
                    throw error
                }
            }
            
            await profileStatsCoordinator.invalidateAndRecomputeIfReady()
            
            try await canWeContinue(needsToBeLoggedIn: true)
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    /// Get a customer's preference data for a given ``Product``.
    /// - Parameters:
    ///   - force_refresh: if you want to force a refresh of the data
    ///   - product_id: id of the starting ``Product``.
    ///   - year: year of the ``Variant`` that you want to get results on. Defaults to ``Variant/CURRENT_VARIANT_YEAR``.
    /// - Returns:
    ///     - A product ID to use in ``ProductsQuery``.
    public func getPreferenceData(force_refresh : Bool = false, product_id : Int, year : Int = Variant.CURRENT_VARIANT_YEAR) async throws -> Int {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            
            Analytics.track( ["event" : "get_preferabli_score"])
            
            let needsRefresh = try await Storage.withContext { ctx, save in
                var needsRefresh = false
                guard let product = try Storage.fetchById(Product.self, id: product_id, in: ctx) else {
                    throw PreferabliException.init(type: .BadSwiftData, message: "Product not found.", code: 404)
                }
                
                if (!(product.recommendable ?? false)) {
                    let dto = PreferenceDataDTO.init(title: "maybe")
                    try Storage.upsertPreferenceData(from: dto, for: product, in: ctx)
                    try save()
                    needsRefresh = false
                } else {
                    let preference_data = product.preference_data
                    needsRefresh = (force_refresh || PreferabliTools.hasMinutesPassed(minutes: 10, startDate: preference_data?.refreshed_at))
                }
                
                return needsRefresh
            }
            
            if needsRefresh {
                let preferenceResponse : PreferenceDataDTO
                var params = ["product_id" : product_id, "year" : year] as SParams
                if (Preferabli.isCustomerLoggedIn()) {
                    params["channel_customer_id"] = PreferabliTools.getCustomerId()
                    params["third_person_response"] = 1
                    preferenceResponse = try await api.getAlamo().get(APIEndpoints.preferenceData, sparams: params)
                } else {
                    params["user_id"] = PreferabliTools.getPreferabliUserId()
                    preferenceResponse = try await api.getAlamo().get(APIEndpoints.preferenceData, sparams: params)
                }
                
                try await Storage.withContext { ctx, save in
                    guard let product = try Storage.fetchById(Product.self, id: product_id, in: ctx) else {
                        throw PreferabliException.init(type: .BadSwiftData, message: "Product not found.", code: 404)
                    }
                    
                    try Storage.upsertPreferenceData(from: preferenceResponse, for: product, in: ctx)
                    
                    try save()
                }
            }
            
            try await canWeContinue(needsToBeLoggedIn: true)
            
            return product_id
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    
    /// Edit an existing ``Tag``.
    /// - Parameters:
    ///   - tag_id: id of the ``Tag`` that needs to be edited.
    ///   - year: year of the ``Variant``. Can use ``Variant/CURRENT_VARIANT_YEAR`` if you want the latest variant, or ``Variant/NON_VARIANT`` if the product is not vintaged.
    ///   - rating: pass one of ``RatingLevel/LOVE``, ``RatingLevel/LIKE``, ``RatingLevel/SOSO``, ``RatingLevel/DISLIKE``. Pass ``RatingLevel/NONE`` is not a rating. Defaults to ``RatingLevel/NONE``.
    ///   - location: location of the tag. Defaults to *nil*.
    ///   - notes: any notes to go along with the tag. Defaults to *nil*.
    ///   - price: price of the product tagged. Defaults to *nil*.
    ///   - quantity: quantity purchased of the product tagged. Defaults to *nil*.
    ///   - format_ml: size of the product tagged in milliliters. Defaults to *nil*.
    public func editTag(
        tag_id : Int,
        year : Int,
        rating : RatingLevel? = nil,
        occasion : String? = nil,
        location : String? = nil,
        notes : String? = nil,
        price : Decimal? = nil,
        quantity : Int? = nil,
        format_ml : Int? = nil,
    ) async throws {
        let (product_id, collection_id, tag_type, value): (Int, Int, TagType?, String?) =
        try Storage.withContext { ctx, save in
            guard let tag = try Storage.fetchById(Tag.self, id: tag_id, in: ctx) else {
                throw PreferabliException.init(type: .BadSwiftData, message: "Tag not found.", code: 404)
            }
            return (tag.product_id, tag.collection_id, tag.tag_type, tag.value)
        }
        
        try await createOrEditTagActual(tag_id: tag_id, product_id: product_id, year: year, collection_id: collection_id, value: value, tag_type: tag_type, location: location, notes: notes, price: price, quantity: quantity, format_ml: format_ml)
    }
    
    @discardableResult
    public func ensureJumpstartCollection(force_refresh: Bool = false) async throws -> Int {
        try await canWeContinue(needsToBeLoggedIn: false)
        
        let ks  = Storage.getKeyStore()
        let key = BuiltInCollection.jumpstart.idKey
        
        var collectionID = ks.integer(forKey: key)
        var needsFetch   = force_refresh || collectionID <= 0
        
        // If we have an id, make sure the Collection row actually exists.
        if !needsFetch {
            let exists = try Storage.withContext { ctx, save in
                try Storage.fetchById(Collection.self, id: collectionID, in: ctx) != nil
            }
            if !exists {
                needsFetch = true
            }
        }
        
        guard needsFetch else {
            return collectionID
        }
        
        Analytics.track(["event": "jumpstart_bootstrap"])
        
        // 1) Fetch Jumpstart collection from API
        let dto: CollectionDTO = try await api
            .getAlamo()
            .get(APIEndpoints.jumpstartCollection)
        
        // 2) Upsert into SwiftData and grab the id
        collectionID = try Storage.withContext { ctx, save in
            let collection = try Storage.upsertCollection(from: dto, in: ctx)
            try save()
            return collection.id
        }
        
        // 3) Persist id for future use
        ks.set(collectionID, forKey: key)
        
        // If you still have an explicit ETag helper, wire it here:
        // PreferabliTools.saveCollectionEtag(from: dto, collectionId: collectionID)
        
        return collectionID
    }
}

extension Preferabli {

    @MainActor
    private static var forcedLogoutHandler: (@Sendable () async -> Void)?

    @MainActor
    internal static var isRunningForcedLogoutHandler = false

    @MainActor
    public static func setForcedLogoutHandler(
        _ handler: (@Sendable () async -> Void)?
    ) {
        forcedLogoutHandler = handler
    }

    /// User-initiated logout API.
    /// Still serialized through PreferabliTools.withLogout.
    public func logout() async throws {
        try await PreferabliTools.withLogout {
            await self.performLogoutCleanupLocked()
        }
    }

    /// User-initiated logout with coordinated app UI teardown.
    ///
    /// Storage admission is closed and existing storage operations are drained before
    /// `teardownUI` runs. This prevents SwiftData saves from racing SwiftUI's removal
    /// of the old model-container tree.
    public func logout(
        tearingDownUI teardownUI: @escaping @MainActor @Sendable () async -> Void
    ) async throws {
        try await PreferabliTools.withLogout {
            await self.performLogoutCleanupLocked(tearingDownUI: teardownUI)
        }
    }

    /// Called by networking when refresh fails.
    /// The app handler should use coordinated logout so storage drains before UI teardown.
    internal func handleRefreshFailureLogout() async {
        let handler = await MainActor.run { Preferabli.forcedLogoutHandler }
        if let handler {
            let shouldRun = await MainActor.run { () -> Bool in
                if Preferabli.isRunningForcedLogoutHandler { return false }
                Preferabli.isRunningForcedLogoutHandler = true
                return true
            }

            guard shouldRun else { return }

            defer {
                Task { @MainActor in
                    Preferabli.isRunningForcedLogoutHandler = false
                }
            }

            await handler()
            return
        }

        // Fallback only if app forgot to register a handler.
        // This is less ideal because UI teardown may not have happened.
        try? await logout()
    }

    /// Legacy logout entry point for clients that do not install SwiftData into SwiftUI.
    @available(*, deprecated, message: "Use logout(tearingDownUI:) when replacing a SwiftUI model container.")
    public func logoutAfterUITeardown() async throws {
        try await PreferabliTools.withLogout {
            await self.performLogoutCleanupLocked()
        }
    }

    /// Actual shared cleanup implementation.
    /// Assumes caller has already entered the logout gate.
    private func performLogoutCleanupLocked(
        tearingDownUI teardownUI: (@MainActor @Sendable () async -> Void)? = nil
    ) async {
        await Storage.beginLogoutCancellation()

        await PreferabliTools.cancelAllInflight()

        // The old SwiftUI model-container tree must remain installed until all
        // registered storage work above has stopped. The app can tear it down now.
        if let teardownUI {
            await teardownUI()
        }

        do {
            try await clearAllData()
        } catch {
            print("performLogoutCleanupLocked clearAllData error: \(error)")
        }

        await sessionBootstrapper.reset(preferabli: self)
        await Storage.endLogoutCancellation()
    }
}

// Gen AI Calls
extension Preferabli {

    @discardableResult
    public func startGenAIConversation() async throws -> String {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            let auth = try await genAIAuthContext()
            
            Analytics.track(["event": "gen_ai_start_conversation"])

            let params: SParams = [
                "source": GenAIMessage.Source.client,
                "user_id": PreferabliTools.getPreferabliUserId(),
                "use_wine_utterance_objects": false,
                "origin_id": auth.originId,
                "product_category_context": "wine",
                "integration_id": 13242
            ]

            let body: GenAIStartConversationDTO = try await api
                .getAlamo()
                .post(APIEndpoints.genAIStart, sjson: params, headers: auth.headers)

            return body.sessionId
        } catch {
            handleError(error: error)
            throw error
        }
    }

    public func getGenAIThinkingTexts() async throws -> [Int: [String]] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
                        
            Analytics.track(["event": "gen_ai_thinking_texts"])

            let auth = try await genAIAuthContext()

            let body: [GenAIThinkingDTO] = try await api
                .getAlamo()
                .get(
                    APIEndpoints.genAIThinking,
                    sparams: ["origin_id": auth.originId],
                    headers: auth.headers
                )

            var result: [Int: [String]] = [:]
            for item in body {
                guard let threshold = item.thresholdInSeconds,
                      let text = item.displayText,
                      !text.isEmptyOrWhitespace()
                else { continue }

                result[threshold, default: []].append(text)
            }

            return result.isEmpty ? [0: ["Thinking…"]] : result
        } catch {
            handleError(error: error)
            throw error
        }
    }

    public func getGenAIConversationHistory(sessionId: String) async throws -> [GenAIMessage] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "gen_ai_conversation_history"])
            
            let auth = try await genAIAuthContext()

            let body: [GenAIMessageDTO] = try await api
                .getAlamo()
                .get(
                    APIEndpoints.genAIConversationHistory(sessionId: sessionId),
                    sparams: ["origin_id": auth.originId],
                    headers: auth.headers
                )

            var messages: [GenAIMessage] = []
            for dto in body {
                let message = try await upsertAndHydrateGenAIMessage(dto)
                messages.append(message)
            }

            return messages.sorted { $0.turn < $1.turn }
        } catch {
            handleError(error: error)
            throw error
        }
    }

    public func getGenAIHistory() async throws -> [GenAIHistoryConversationSummary] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "gen_ai_history_viewed"])

            let auth = try await genAIAuthContext()

            let body: GenAIHistoryResponseDTO = try await api
                .getAlamo()
                .get(
                    APIEndpoints.genAIHistory,
                    sparams: [
                        "user_id": PreferabliTools.getPreferabliUserId(),
                        "origin_id": auth.originId
                    ],
                    headers: auth.headers
                )

            var summaries: [GenAIHistoryConversationSummary] = []

            for sessionId in body.keys.sorted() {
                let maybeDTO = body[sessionId] ?? nil

                if let dto = maybeDTO {
                    let message = try await upsertAndHydrateGenAIMessage(
                        dto,
                        fallbackSessionId: sessionId,
                        fallbackTurn: dto.turn
                    )

                    summaries.append(
                        makeGenAIHistorySummary(
                            sessionId: sessionId,
                            messageId: message.id,
                            turn: message.turn,
                            previewText: dto.historyPreviewText,
                            fallbackPreviewText: message.messageText,
                            createdAt: message.created_at
                        )
                    )
                } else if let localMessage = try fetchRepresentativeGenAIHistoryMessage(sessionId: sessionId) {
                    summaries.append(
                        makeGenAIHistorySummary(
                            sessionId: sessionId,
                            messageId: localMessage.id,
                            turn: localMessage.turn,
                            previewText: localMessage.messageText,
                            fallbackPreviewText: localMessage.utterance,
                            createdAt: localMessage.created_at
                        )
                    )
                }
            }

            return summaries.sorted { lhs, rhs in
                switch (lhs.createdAt, rhs.createdAt) {
                case let (left?, right?):
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.sessionId < rhs.sessionId
                }
            }
        } catch {
            handleError(error: error)
            throw error
        }
    }

    @discardableResult
    public func sendGenAIMessage(
        utterance: String,
        sessionId: String,
        turn: Int,
        source: String = GenAIMessage.Source.client,
        dialogOverride: Bool = false
    ) async throws -> GenAIMessage {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "gen_ai_send_message"])
            
            let auth = try await genAIAuthContext()

            var params: SParams = [
                "utterance": utterance,
                "session_id": sessionId,
                "turn": turn,
                "source": source,
                "origin_id": auth.originId
            ]

            if dialogOverride {
                params["dialog_override"] = true
            }

            let dto: GenAIMessageDTO = try await api
                .getAlamo()
                .post(APIEndpoints.genAI, sjson: params, headers: auth.headers)

            return try await upsertAndHydrateGenAIMessage(
                dto,
                fallbackSessionId: sessionId,
                fallbackTurn: turn
            )
        } catch {
            handleError(error: error)
            throw error
        }
    }

    public func postGenAIDialogOverrideMessage(
        utterance: String,
        sessionId: String,
        turn: Int,
        source: String
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "gen_ai_dialog_override"])
            
            let auth = try await genAIAuthContext()

            let params: SParams = [
                "utterance": utterance,
                "session_id": sessionId,
                "turn": turn,
                "dialog_override": true,
                "source": source,
                "origin_id": auth.originId
            ]

            try await api
                .getAlamo()
                .post(APIEndpoints.genAI, sjson: params, headers: auth.headers)
        } catch {
            handleError(error: error)
            throw error
        }
    }

    public func updateGenAIConversationCategory(
        category: String,
        sessionId: String
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "gen_ai_category_selected", "category": category])
            
            let auth = try await genAIAuthContext()

            let params: SParams = [
                "product_category_context": category,
                "origin_id": auth.originId
            ]
            
            try await api
                .getAlamo()
                .put(APIEndpoints.genAIConversation(sessionId: sessionId), sjson: params, headers: auth.headers)
            
        } catch {
            handleError(error: error)
            throw error
        }
    }

    @discardableResult
    public func selectGenAIItem(
        sessionId: String,
        turn: Int,
        productId: Int?,
        productName: String?,
        foodId: Int?,
        foodName: String?,
        entityProbability: Double?,
        recognitionType: String?,
        isFood: Bool
    ) async throws -> GenAIMessage {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "gen_ai_item_selected", "food": isFood])
            
            let auth = try await genAIAuthContext()

            var params: SParams = [
                "session_id": sessionId,
                "turn": turn,
                "origin_id": auth.originId
            ]

            if let productId {
                var selection: SParams = [
                    "entity_id": productId,
                    "entity_type": "product_name"
                ]
                if let productName { selection["entity_name"] = productName }
                if let entityProbability { selection["entity_prob"] = entityProbability }

                params["user_action"] = "btn_wine_entity_confirm"
                params["user_selection"] = selection
            } else if let foodId {
                var selection: SParams = [
                    "entity_id": foodId,
                    "entity_type": "food_name"
                ]
                if let foodName { selection["food_entity"] = foodName }
                if let entityProbability { selection["score"] = entityProbability }
                if let recognitionType { selection["recog_type"] = recognitionType }

                params["user_action"] = "btn_food_entity_confirm"
                params["user_selection"] = selection
            } else if isFood {
                params["user_action"] = "btn_food_entity_reject"
            } else {
                params["user_action"] = "btn_wine_entity_reject"
            }

            let dto: GenAIMessageDTO = try await api
                .getAlamo()
                .post(APIEndpoints.genAI, sjson: params, headers: auth.headers)

            return try await upsertAndHydrateGenAIMessage(
                dto,
                fallbackSessionId: sessionId,
                fallbackTurn: turn
            )
        } catch {
            handleError(error: error)
            throw error
        }
    }

    @discardableResult
    public func upsertGenAIFeedback(
        sessionId: String,
        transactionId: String,
        feedbackId: Int?,
        positiveReaction: Bool,
        reportedIssue: String?
    ) async throws -> Int? {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track([
                "event": "gen_ai_feedback",
                "positive_reaction": positiveReaction
            ])
            
            let auth = try await genAIAuthContext()

            var params: SParams = [
                "session_id": sessionId,
                "transaction_id": transactionId,
                "positive_reaction": positiveReaction,
                "origin_id": auth.originId
            ]

            if let reportedIssue, !reportedIssue.isEmptyOrWhitespace() {
                params["reported_issue"] = reportedIssue
            }

            let dto: GenAIFeedbackDTO
            if let feedbackId, feedbackId > 0 {
                dto = try await api
                    .getAlamo()
                    .put(APIEndpoints.genAIFeedback(id: feedbackId), sjson: params, headers: auth.headers)
            } else {
                dto = try await api
                    .getAlamo()
                    .post(APIEndpoints.genAIFeedback, sjson: params, headers: auth.headers)
            }

            return dto.id
        } catch {
            handleError(error: error)
            throw error
        }
    }

    public func deleteGenAIConversation(sessionId: String) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "gen_ai_delete_conversation"])
            
            let auth = try await genAIAuthContext()

            let url = APIEndpoints.genAIConversation(sessionId: sessionId) + "?origin_id=\(auth.originId)"

            try await api
                .getAlamo()
                .delete(url, headers: auth.headers)
            
        } catch {
            handleError(error: error)
            throw error
        }
    }

    public func getGenAIVoices() async throws -> [GenAIVoiceOptionDTO] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "gen_ai_voices"])
            
            let auth = try await genAIAuthContext()

            return try await api
                .getAlamo()
                .get(
                    APIEndpoints.genAIVoices,
                    sparams: ["origin_id": auth.originId],
                    headers: auth.headers
                )
            
        } catch {
            handleError(error: error)
            throw error
        }
    }

    public func updateGenAIVoice(
        voiceId: Int,
        sessionId: String
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "gen_ai_voice_selected", "voice_option_id": voiceId])
            
            let auth = try await genAIAuthContext()

            let params: SParams = [
                "voice_option_id": voiceId,
                "session_id": sessionId,
                "origin_id": auth.originId
            ]

            try await api
                .getAlamo()
                .post(APIEndpoints.updateGenAIVoices, sjson: params, headers: auth.headers)
            
        } catch {
            handleError(error: error)
            throw error
        }
    }

    private func makeGenAIHistorySummary(
        sessionId: String,
        messageId: Int?,
        turn: Int?,
        previewText: String?,
        fallbackPreviewText: String?,
        createdAt: Date?
    ) -> GenAIHistoryConversationSummary {
        let normalizedPreview = previewText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFallback = fallbackPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedPreview = normalizedPreview?.isEmpty == false ? normalizedPreview : nil

        return GenAIHistoryConversationSummary(
            sessionId: sessionId,
            messageId: messageId,
            turn: turn,
            previewText: resolvedPreview ?? normalizedFallback ?? "",
            createdAt: createdAt
        )
    }

    private func fetchRepresentativeGenAIHistoryMessage(sessionId: String) throws -> GenAIMessage? {
        try Storage.withContext { ctx, save in
            var descriptor = FetchDescriptor<GenAIMessage>(
                predicate: #Predicate { message in
                    message.sessionId == sessionId && message.isTombstoned == false
                },
                sortBy: [
                    SortDescriptor(\.created_at, order: .reverse),
                    SortDescriptor(\.turn, order: .forward)
                ]
            )
            descriptor.fetchLimit = 1
            return try ctx.fetch(descriptor).first
        }
    }

    private func upsertAndHydrateGenAIMessage(
        _ dto: GenAIMessageDTO,
        fallbackSessionId: String? = nil,
        fallbackTurn: Int? = nil
    ) async throws -> GenAIMessage {
        let messageId = try Storage.withContext { ctx, save in
            let message = try Storage.upsertGenAIMessage(
                from: dto,
                fallbackSessionId: fallbackSessionId,
                fallbackTurn: fallbackTurn,
                in: ctx
            )
            try save()
            return message.id
        }

        try await hydrateGenAIProducts(for: dto, messageId: messageId)
        try await hydrateGenAIFoodsIfNeeded(foodIds: dto.foodIds)

        return try Storage.withContext { ctx, save in
            guard let message = try Storage.fetchGenAIMessage(id: messageId, in: ctx) else {
                throw PreferabliException(type: .DatabaseError)
            }
            return message
        }
    }

    private func hydrateGenAIProducts(
        for dto: GenAIMessageDTO,
        messageId: Int
    ) async throws {
        let directProductIds = dto.productEntityIds.uniqued()
        let variantIds = dto.variantIds.uniqued()

        guard !directProductIds.isEmpty || !variantIds.isEmpty else { return }

        var productIdsForMessage = directProductIds
        var productDTOs: [ProductDTO] = []

        if !directProductIds.isEmpty {
            let directDTOs: [ProductDTO] = try await api
                .getAlamo()
                .get(APIEndpoints.products, sparams: ["product_ids": directProductIds])
            productDTOs.append(contentsOf: directDTOs)
        }

        if !variantIds.isEmpty {
            let variantDTOs: [ProductDTO] = try await api
                .getAlamo()
                .get(APIEndpoints.products, sparams: ["variant_ids": variantIds])
            productDTOs.append(contentsOf: variantDTOs)

            var productIdByVariantId: [Int: Int] = [:]
            for productDTO in variantDTOs {
                for variantDTO in productDTO.variants ?? [] {
                    productIdByVariantId[variantDTO.id] = productDTO.id
                }
            }

            productIdsForMessage.append(contentsOf: variantIds.compactMap { productIdByVariantId[$0] })
        }

        productIdsForMessage = productIdsForMessage.uniqued()

        try Storage.withContext { ctx, save in
            for productDTO in productDTOs {
                _ = try Storage.upsertProduct(from: productDTO, in: ctx)
            }
            try Storage.updateGenAIMessageProductIds(
                messageId: messageId,
                productIds: productIdsForMessage,
                in: ctx
            )
            try save()
        }
    }

    private func hydrateGenAIFoodsIfNeeded(foodIds: [Int]) async throws {
        let foodIds = foodIds.uniqued()
        guard !foodIds.isEmpty else { return }

        let missingFoodIds: [Int] = try Storage.withContext { ctx, save in
            var missing: [Int] = []
            for foodId in foodIds {
                if try Storage.fetchById(Food.self, id: foodId, in: ctx) == nil {
                    missing.append(foodId)
                }
            }
            return missing
        }

        guard !missingFoodIds.isEmpty else { return }

        let foodDTOs: [FoodDTO] = try await api
            .getAlamo()
            .get(APIEndpoints.foods)

        try Storage.withContext { ctx, save in
            for foodDTO in foodDTOs {
                _ = try Storage.upsertFood(from: foodDTO, in: ctx)
            }
            try save()
        }
    }
    
    public func getGenAILambda(
        originId: String,
        headers: HTTPHeaders? = nil
    ) async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "gen_ai_lambda"])

            let defaults = Storage.getKeyStore()

            let lambdas: [GenAILambdaDTO] = try await api.getAlamo().get(
                APIEndpoints.genAILambda(lastPiece: "current"),
                sparams: ["origin_id": originId],
                headers: headers
            )

            if let lambda = lambdas.first(where: { $0.isCurrent }) {
                defaults.set(lambda.url, forKey: "genAILambda")
            } else if let lambda = lambdas.first(where: { $0.isStaging }) {
                defaults.set(lambda.url, forKey: "genAILambda")
            } else if let lambda = lambdas.first(where: { $0.isDev }) {
                defaults.set(lambda.url, forKey: "genAILambda")
            } else {
                defaults.set(APIEndpoints.genAISeedLambda, forKey: "genAILambda")
            }
        } catch {
            Storage.getKeyStore().set(APIEndpoints.genAISeedLambda, forKey: "genAILambda")
            handleError(error: error)
            throw error
        }
    }
    
    private func genAIAuthContext() async throws -> (originId: String, headers: HTTPHeaders) {
        let originId = try await api.genAIOriginId()
        let headers = try await api.genAIHeaders()

        try await getGenAILambda(originId: originId, headers: headers)

        return (originId, headers)
    }
    
    public func getGenAIProductDescription(id: Int) async throws -> GenAIProductDescriptionDTO {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)

            Analytics.track([
                "event": "gen_ai_product_description",
                "product_id": id
            ])

            let auth = try await genAIAuthContext()

            return try await api
                .getAlamo()
                .get(
                    APIEndpoints.genAIProductDescription(id: id),
                    sparams: ["origin_id": auth.originId],
                    headers: auth.headers
                )
        } catch {
            handleError(error: error)
            throw error
        }
    }
}

extension Preferabli {

    /// Fetches and stores a Content record, including children and associations present in the payload.
    /// - Returns: the content id for use with SwiftData queries.
    public func getContent(force_refresh: Bool = false, content_id: Int) async throws -> Int {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "content_refresh"])

            var needsRefresh = true

            if !force_refresh {
                try Storage.withContext { ctx, save in
                    if try Storage.fetchById(ContentItem.self, id: content_id, in: ctx) != nil {
                        needsRefresh = PreferabliTools.hasMinutesPassed(
                            minutes: 60,
                            startDate: Storage.getKeyStore().object(forKey: "lastCalledContent\(content_id)") as? Date
                        )
                    }
                }
            }

            if needsRefresh {
                let body: ContentDTO = try await api.getAlamo().get(APIEndpoints.content(id: content_id))

                try await Storage.withBackgroundContext { ctx, save in
                    _ = try Storage.upsertContent(from: body, in: ctx)
                    try save()

                    Storage.getKeyStore().set(Date(), forKey: "lastCalledContent\(content_id)")
                }
            }

            return content_id

        } catch {
            handleError(error: error)
            throw error
        }
    }

    /// Fetches and stores one paginated page of children for a Content record.
    ///
    /// The children endpoint returns a flat array of ContentDTOs. The parent/child relationship
    /// is created locally using the `content_id` passed into this method.
    ///
    /// - Returns: the child ids returned by this page. If the count is less than `limit`, callers
    ///   can treat that as the end of pagination.
    @discardableResult
    public func getContentChildren(
        force_refresh: Bool = false,
        content_id: Int,
        limit: Int = 25,
        offset: Int = 0
    ) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track([
                "event": "content_children_refresh",
                "content_id": content_id,
                "limit": limit,
                "offset": offset
            ])

            let params: SParams = [
                "limit": limit,
                "offset": offset
            ]

            let body: [ContentDTO] = try await api
                .getAlamo()
                .get(APIEndpoints.contentChildren(id: content_id), sparams: params)

            try await Storage.withBackgroundContext { ctx, save in
                _ = try Storage.upsertContentChildren(
                    parentID: content_id,
                    from: body,
                    replaceExisting: offset == 0 || force_refresh,
                    in: ctx
                )
                try save()
            }

            return body.map(\.id)

        } catch {
            handleError(error: error)
            throw error
        }
    }

    /// Fetches and stores a Personality record.
    /// - Returns: the personality id for use with SwiftData queries.
    public func getPersonality(force_refresh: Bool = false, personality_id: Int) async throws -> Int {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track(["event": "personality_refresh"])

            var needsRefresh = true

            if !force_refresh {
                try Storage.withContext { ctx, save in
                    if try Storage.fetchById(Personality.self, id: personality_id, in: ctx) != nil {
                        needsRefresh = PreferabliTools.hasMinutesPassed(
                            minutes: 60,
                            startDate: Storage.getKeyStore().object(forKey: "lastCalledPersonality\(personality_id)") as? Date
                        )
                    }
                }
            }

            if needsRefresh {
                let body: PersonalityDTO = try await api.getAlamo().get(APIEndpoints.personality(id: personality_id))

                try await Storage.withBackgroundContext { ctx, save in
                    _ = try Storage.upsertPersonality(from: body, in: ctx)
                    try save()

                    Storage.getKeyStore().set(Date(), forKey: "lastCalledPersonality\(personality_id)")
                }
            }

            return personality_id

        } catch {
            handleError(error: error)
            throw error
        }
    }


    /// Fetches and stores one paginated page of content associations for a Personality record.
    ///
    /// The personality endpoint no longer embeds content associations directly. This endpoint
    /// returns a flat array of ContentPersonalityAssociationDTOs, each with its associated content.
    ///
    /// - Returns: the association ids returned by this page. If the count is less than `limit`,
    ///   callers can treat that as the end of pagination.
    @discardableResult
    public func getPersonalityContentAssociations(
        force_refresh: Bool = false,
        personality_id: Int,
        limit: Int = 25,
        offset: Int = 0
    ) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track([
                "event": "personality_content_associations_refresh",
                "personality_id": personality_id,
                "limit": limit,
                "offset": offset
            ])

            let params: SParams = [
                "limit": limit,
                "offset": offset
            ]

            let body: [ContentPersonalityAssociationDTO] = try await api
                .getAlamo()
                .get(APIEndpoints.personalityContentAssociations(id: personality_id), sparams: params)

            try await Storage.withBackgroundContext { ctx, save in
                _ = try Storage.upsertPersonalityContentAssociations(
                    personalityID: personality_id,
                    from: body,
                    replaceExisting: offset == 0 || force_refresh,
                    in: ctx
                )
                try save()
            }

            return body.map(\.id)

        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    @discardableResult
    public func getPersonalityItineraries(
        force_refresh: Bool = false,
        personality_id: Int,
        limit: Int = 25,
        offset: Int = 0
    ) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            Analytics.track([
                "event": "personality_itineraries_refresh",
                "personality_id": personality_id,
                "limit": limit,
                "offset": offset
            ])

            let params: SParams = [
                "limit": limit,
                "offset": offset
            ]

            let body: [ItineraryDTO] = try await api
                .getAlamo()
                .get(APIEndpoints.personalityItineraries(id: personality_id), sparams: params)

            try await Storage.withBackgroundContext { ctx, save in
                for itineraryDTO in body {
                    let market = try Storage.fetchById(
                        Market.self,
                        id: itineraryDTO.market_id,
                        in: ctx
                    )

                    _ = try Storage.upsertItinerary(
                        from: itineraryDTO,
                        market: market,
                        in: ctx
                    )
                }

                try save()
            }

            return body.map(\.id)

        } catch {
            handleError(error: error)
            throw error
        }
    }
}

extension Preferabli {

    /// Fetches the complete itinerary list for a market and stores it in SwiftData.
    ///
    /// The server does not return the Market relationship, so `market_id` is resolved
    /// locally and supplied to every itinerary upsert.
    ///
    /// - Returns: itinerary ids in the same order as the API response.
    @discardableResult
    public func getItineraries(market_id: Int) async throws -> [Int] {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)

            Analytics.track([
                "event": "get_itineraries",
                "market_id": market_id
            ])

            let body: [ItineraryDTO] = try await api
                .getAlamo()
                .get(APIEndpoints.itinerariesForMarket(id: market_id))

            let itineraryIDs = try await Storage.withBackgroundContext { ctx, save in
                guard let market = try Storage.fetchById(
                    Market.self,
                    id: market_id,
                    in: ctx
                ) else {
                    throw PreferabliException(
                        type: .BadSwiftData,
                        message: "Could not get itineraries because Market \(market_id) is not stored locally. Fetch markets before itineraries.",
                        code: 660
                    )
                }

                let itineraries = try Storage.upsertItineraries(
                    from: body,
                    market: market,
                    replaceExisting: true,
                    in: ctx
                )

                try save()
                return itineraries.map(\.id)
            }

            return itineraryIDs
        } catch {
            handleError(error: error)
            throw error
        }
    }

    /// Fetches one itinerary by id and stores it in SwiftData.
    ///
    /// If the response references a locally stored market, its SwiftData relationship
    /// is populated. Marketless itineraries and references to markets not stored locally
    /// are still persisted.
    ///
    /// - Returns: the itinerary id for use with SwiftData queries.
    public func getItinerary(
        force_refresh: Bool = false,
        itinerary_id: Int
    ) async throws -> Int {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)

            Analytics.track([
                "event": "itinerary_refresh",
                "itinerary_id": itinerary_id
            ])

            var needsRefresh = true

            if !force_refresh {
                try Storage.withContext { ctx, _ in
                    if let itinerary = try Storage.fetchById(
                        Itinerary.self,
                        id: itinerary_id,
                        in: ctx
                    ) {
                        needsRefresh = PreferabliTools.hasMinutesPassed(
                            minutes: 60,
                            startDate: Storage.getKeyStore().object(
                                forKey: "lastCalledItinerary\(itinerary_id)"
                            ) as? Date
                        )
                    }
                }
            }

            if needsRefresh {
                let body: ItineraryDTO = try await api
                    .getAlamo()
                    .get(APIEndpoints.itinerary(id: itinerary_id))

                try await Storage.withBackgroundContext { ctx, save in
                    let market = try Storage.fetchById(
                        Market.self,
                        id: body.market_id,
                        in: ctx
                    )

                    _ = try Storage.upsertItinerary(
                        from: body,
                        market: market,
                        in: ctx
                    )

                    try save()
                    Storage.getKeyStore().set(
                        Date(),
                        forKey: "lastCalledItinerary\(itinerary_id)"
                    )
                }
            }

            return itinerary_id
        } catch {
            handleError(error: error)
            throw error
        }
    }
}
