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
    
    internal static let versionCode = 12
    
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
        Mixpanel.mainInstance().registerSuperProperties([
            "CLIENT_INTERFACE": client_interface,
            "INTEGRATION_ID": integration_id
        ])
        
        PreferabliTools.addSDKProperties()
        
        // Small helper so we don’t repeat the logging gate everywhere.
        let log: @Sendable (String) -> Void = { msg in
            if logging_enabled { print(msg) }
        }
        
        // 1) Do upgrade/startup first (highest value work).
        // Use Task { } so we keep actor inheritance and don’t “fully detach” unless needed.
        Task(priority: .high) {
            do {
                try await main.handleUpgrade()
                try await main.handleStartupActions()
            } catch {
                await main.handleError(error: error)
            }
            
            // 2) Only after startup work completes, do maintenance (background).
            // Serialize prune -> reindex to avoid concurrent graph churn.
            //            Task.detached(priority: .background) {
            //                await Storage.pruneTombstones(batchSize: 150, log: log)
            //
            //                // Gate expensive reindex so it only runs when needed.
            //                // Tie it to versionCode (or schema hash) so upgrades trigger it.
            //                let ks = Storage.getKeyStore()
            //                let reindexKey = "didReindexSearchableContent_v\(await Preferabli.versionCode)"
            //
            //                if !ks.bool(forKey: reindexKey) {
            //                    await Storage.reindexSearchableContent(batchSize: 250, log: log)
            //                    ks.set(true, forKey: reindexKey)
            //                } else {
            //                    log("Skipping reindex (already completed for \(reindexKey))")
            //                }
            //            }
        }
    }
    
    private func isInternal() -> Bool {
        return Preferabli.INTEGRATION_ID == -1
    }
    
    private func handleUpgrade() async throws {
        let versionCode = Preferabli.versionCode
        let savedVersionCode = Storage.getKeyStore().integer(forKey: "versionCode")
        
        if (savedVersionCode != versionCode) {
            if (savedVersionCode == 0) {
                // new user do nothing for now
            } else {
                // user has upgraded the app always pull new data
                try await Storage.databaseUpgraded()
            }
            // we handled either possible situation so update the version code to current version
            Storage.getKeyStore().set(versionCode, forKey: "versionCode")
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
        do {
            // delete all from core data
            try await Storage.reset()
            
            // clear HTTP cache
            await api.clearUrlCache()
            await api.refreshDefaults()
            
            let keyStore = Storage.getKeyStore()
            let integration_id = keyStore.integer(forKey: "INTEGRATION_ID")
            let client_interface = keyStore.string(forKey: "CLIENT_INTERFACE")
            let storeFile = keyStore.string(forKey: "swiftdata_store_filename")
            
            keyStore.removePersistentDomain(forName: "Preferabli")
            
            keyStore.set(integration_id, forKey: "INTEGRATION_ID")
            keyStore.set(client_interface, forKey: "CLIENT_INTERFACE")
            keyStore.set(storeFile, forKey: "swiftdata_store_filename")
        } catch {
            print(error)
        }
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
            
            try await userUpdated(dto: user)
        }
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
    
    public func logout() async throws {
        try await canWeContinue(needsToBeLoggedIn: true)
        
        try await PreferabliTools.withLogout {
            // ✅ first thing
            await Storage.beginLogoutCancellation()
            defer { Task { await Storage.endLogoutCancellation() } }
            
            // then cancel other inflight
            await PreferabliTools.cancelAllInflight()
            
            // then wipe
            try await clearAllData()
            await sessionBootstrapper.reset(preferabli: self)
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
    
    internal func userUpdated(dto : PreferabliUserDTO) throws {
        try Storage.withContext { ctx in
            let user = try Storage.upsertPreferabliUser(from: dto, in: ctx)
            try ctx.save()
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
            let productIds = try Storage.withContext { ctx in
                var productsToReturn = [Int]()
                
                // Upsert in sorted order to maintain relevance
                for imageRec in sortedResults {
                    let p = try Storage.upsertProduct(from: imageRec.product, in: ctx)
                    productsToReturn.append(p.id)
                }
                try ctx.save()
                return productsToReturn
            }
            
            // 5. Return both the list and the optional winner
            return (ids: productIds, bestMatchID: bestMatchID)
            
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
            
            var searchResponse : SearchResponseDTO = try await api.getAlamo().get(APIEndpoints.search, sparams: dictionary)
            
            // Upsert Products
            let productIds = try Storage.withContext { ctx in
                var productsToReturn = [Int]()
                
                for pd in searchResponse.products {
                    let p = try Storage.upsertProduct(from: pd, in: ctx)
                    productsToReturn.append(p.id)
                }
                try ctx.save()
                return productsToReturn
            }
            
            return productIds
            
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
            try Storage.withContext { ctx in
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
                
                try ctx.save()
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
            let missingVariantIds: [Int] = try Storage.withContext { ctx in
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
            let productIds: [Int] = try Storage.withContext { ctx in
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
                
                try ctx.save()
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
                "platform": "ios_tastefuli_app",
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
            
            let foodIds = try Storage.withContext { ctx in
                
                var foodIds: [Int] = []
                
                for food in body {
                    let food = try Storage.upsertFoodCategory(from: food, in: ctx)
                    foodIds.append(food.id)
                }
                
                try ctx.save()
                
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
                let localIds: [Int] = try await Storage.withBackgroundContext { ctx in
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
            
            let ids: [Int] = try await Storage.withBackgroundContext { ctx in
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
                
                try ctx.save()
                return out
            }
            
            ks.set(Date(), forKey: "lastCalledUserCollections")
            ks.set(true, forKey: "hasLoadedUserCollections")
            
            let cellarIDs: [Int] = body
                .filter { ($0.relationship_type ?? "") == "mycellar" }
                .compactMap { $0.collection_id }
            
            Storage.saveCellarCollectionIDs(cellarIDs)
            
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
            
            let mediaIds = try Storage.withContext { ctx in
                
                var mediaIds: [Int] = []
                
                for media in body {
                    let media = try Storage.upsertMedia(from: media, in: ctx)
                    mediaIds.append(media.id)
                }
                
                try ctx.save()
                
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
            
            let styleIds = try Storage.withContext { ctx in
                var styleIds = [Int]()
                for styleDTO in body {
                    let style = try Storage.upsertStyle(from: styleDTO, in: ctx)
                    styleIds.append(style.id)
                }
                try ctx.save()
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
            
            let productIDs = try Storage.withContext { ctx in
                var productIDs = [Int]()
                
                if let first = body.first {
                    for item in body.first!.products {
                        let product = try Storage.upsertProduct(from: item, in: ctx)
                        productIDs.append(product.id)
                    }
                    
                    try ctx.save()
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
            
            let productIDs = try Storage.withContext { ctx in
                var productIDs = [Int]()
                
                if let first = body.first {
                    for item in body.first!.products {
                        let product = try Storage.upsertProduct(from: item, in: ctx)
                        productIDs.append(product.id)
                    }
                    
                    try ctx.save()
                }
                
                try ctx.save()
                
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
            
            let productIDs = try Storage.withContext { ctx in
                var productIDs = [Int]()
                
                for item in body.results {
                    let product = try Storage.upsertProduct(from: item.product, in: ctx)
                    
                    if let rating = item.formatted_predict_rating {
                        let preferenceDataDTO = PreferenceDataDTO(formatted_predict_rating: rating)
                        try Storage.upsertPreferenceData(from: preferenceDataDTO, for: product, in: ctx)
                    }
                    
                    productIDs.append(product.id)
                }
                
                try ctx.save()
                
                return productIDs
            }
            
            return productIDs
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func productsForFood(recipeId : Int) async throws -> [Int]
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "flttt"])
            
            var params: SParams = [
                "recipe_id": recipeId,
                "collection_id": Preferabli.PRIMARY_INVENTORY_ID
            ]
            
            if Preferabli.isPreferabliUserLoggedIn() {
                params["user_id"] = PreferabliTools.getPreferabliUserId()
            } else if Preferabli.isCustomerLoggedIn() {
                params["channel_customer_id"] = PreferabliTools.getCustomerId()
            }
            
            let body: FLTTTResponseDTO = try await api.getAlamo().get(APIEndpoints.flttt, sparams: params)
            
            let productIDs = try Storage.withContext { ctx in
                var productIDs = [Int]()
                
                for item in body.products {
                    let product = try Storage.upsertProduct(from: item, in: ctx)
                    productIDs.append(product.id)
                }
                
                try ctx.save()
                
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
            
            let recipeIdsFirst = try await Storage.withContext { ctx in
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
            
            let recipeIds = try await Storage.withContext { ctx in
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
                
                try ctx.save()
                
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
            try Storage.withContext { ctx in
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
                try Storage.withContext { ctx in
                    guard let product = try Storage.fetchById(Product.self, id: product_id, in: ctx) else {
                        throw PreferabliException.init(type: .BadSwiftData, message: "Product not found.", code: 404)
                    }
                    
                    // Now we call upsert with a guaranteed-valid product and context
                    let profile = try Storage.upsertProductProfile(from: body, for: product, in: ctx)
                    
                    // Save the write context
                    try ctx.save()
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
            
            try await Storage.withBackgroundContext { ctx in
                guard let user = try Storage.fetchById(PreferabliUser.self, id: PreferabliTools.getPreferabliUserId(), in: ctx) else {
                    return
                }
                
                var favorites = user.favorite_venue_ids ?? []
                favorites.append(venueId)
                user.favorite_venue_ids = favorites
                
                try ctx.save()
            }
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func unfavoriteVenue(venueId : Int) async throws
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            
            Analytics.track(["event": "unfavorite_venue"])
            
            _ = try await api.getAlamo().delete(APIEndpoints.favoriteVenue(id: PreferabliTools.getPreferabliUserId(), venueId: venueId))
            
            try await Storage.withBackgroundContext { ctx in
                guard let user = try Storage.fetchById(PreferabliUser.self, id: PreferabliTools.getPreferabliUserId(), in: ctx) else {
                    return
                }
                
                var favorites = user.favorite_venue_ids ?? []
                favorites.removeAll { $0 == venueId }
                user.favorite_venue_ids = favorites
                
                try ctx.save()
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
            let channelIds = try await Storage.withBackgroundContext { ctx in
                var channelIds = [Int]()
                for channelDTO in body {
                    let channel = try Storage.upsertChannel(from: channelDTO, in: ctx)
                    channelIds.append(channel.id)
                }
                // Save the write context
                try ctx.save()
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
            
            let params: SParams = ["limit": 10000, "offset": 0]
            let body: [VenueDTO] = try await api.getAlamo().get(APIEndpoints.venues(id: market_id), sparams: params)
            
            let venueIds: [Int] = try await Storage.withBackgroundContext { ctx in
                var venueIds: [Int] = []
                venueIds.reserveCapacity(body.count)
                
                guard let market = try Storage.fetchById(Market.self, id: market_id, in: ctx) else {
                    return []
                }
                
                // 1) Keep set from API
                let keepIDs = Set(body.map(\.id))
                
                // 2) Upsert returned venues + ensure they're linked to this market
                for venueDTO in body {
                    if let venue = try Storage.upsertVenue(from: venueDTO, market: market, in: ctx) {
                        venueIds.append(venue.id)
                    }
                }
                
                // 3) Source-of-truth for Market<->Venue: remove market from venues not in response
                try Storage.disassociateVenuesNotInSet(keepVenueIDs: keepIDs, from: market, in: ctx)
                
                try ctx.save()
                return venueIds
            }
            
            return venueIds
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getCTABuckets(
        force_refresh: Bool = false,
        market_id: Int? = nil,
        section: String? = nil
    ) async throws -> [Int] {
        let api = self.api
        let loggingEnabled = self.loggingEnabled // (unused for now, but left intact)
        
        return try await BucketsLoader.shared.run { [weak self] in
            guard let self else { return [] }
            
            do {
                try await self.canWeContinue(needsToBeLoggedIn: false)
                Analytics.track(["event": "get_cta_buckets"])
                
                let isGeneralCall = (market_id == nil && section == nil)
                
                // Only short-circuit for the *general* (unscoped) load
                if isGeneralCall,
                   !force_refresh,
                   Storage.getKeyStore().bool(forKey: "hasLoadedBuckets") {
                    
                    let localIds: [Int] = try await Storage.withBackgroundContext { ctx in
                        let buckets = try ctx.fetch(FetchDescriptor<CTABucket>())
                        return buckets.map { $0.id }
                    }
                    
                    if !localIds.isEmpty { return localIds }
                }
                
                var params: SParams = ["domain": "tastefuli-v3"]
                
                if let market_id {
                    params["market_ids[]"] = market_id
                }
                
                if let section {
                    params["section"] = section
                }
                
                let body: [CTABucketResponseDTO] = try await api
                    .getAlamo()
                    .get(APIEndpoints.ctaBuckets, sparams: params)
                
                let dtoIds: [Int] = try await Storage.withBackgroundContext { ctx in
                    let ids = try Storage.upsertCTABucketsSourceOfTruth(
                        from: body,
                        scopeMarketId: market_id,
                        scopeSection: section,
                        in: ctx
                    )
                    try ctx.save()
                    return ids
                }
                
                if isGeneralCall {
                    Storage.getKeyStore().set(true, forKey: "hasLoadedBuckets")
                }
                
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
                    let localIds: [Int] = try await Storage.withBackgroundContext { ctx in
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
                
                try await Storage.withBackgroundContext { ctx in
                    _ = try Storage.upsertMarketsSourceOfTruth(from: body, in: ctx)
                    try ctx.save()
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
                let localIds: [Int] = try await Storage.withBackgroundContext { ctx in
                    let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
                    return recipes.map { $0.id }
                }
                if !localIds.isEmpty { return localIds }
            }
            
            let body: [RecipeDTO] = try await api.getAlamo().get(APIEndpoints.recipes)
            
            let recipeIds : [Int] = try await Storage.withBackgroundContext { ctx in
                var recipeIds : [Int] = []
                for recipe in body {
                    let recipeActual = try Storage.upsertRecipe(from: recipe, in: ctx)
                    recipeIds.append(recipeActual.id)
                }
                try ctx.save()
                
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
                let localIds: [Int] = try await Storage.withBackgroundContext { ctx in
                    let recipes = try ctx.fetch(FetchDescriptor<Recipe>())
                    return recipes.map { $0.id }
                }
                if !localIds.isEmpty { return localIds }
            }
            
            let body: [RecipeGroupDTO] = try await api.getAlamo().get(APIEndpoints.recipeGroups)
            
            let recipeGroupIds : [Int] = try await Storage.withBackgroundContext { ctx in
                var recipeGroupIds : [Int] = []
                for recipeGroup in body {
                    let recipeActual = try Storage.upsertRecipeGroup(from: recipeGroup, in: ctx)
                    recipeGroupIds.append(recipeActual.id)
                }
                try ctx.save()
                
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
                try Storage.withContext { ctx in
                    if let product = try Storage.fetchById(Product.self, id: product_id, in: ctx) {
                        
                        needsRefresh = PreferabliTools.hasMinutesPassed(minutes: 60, startDate: Storage.getKeyStore().object(forKey: "lastCalledProduct\(product_id)") as? Date)
                    }
                }
            }
            
            if needsRefresh {
                let body: ProductDTO = try await api.getAlamo().get(APIEndpoints.product(id: product_id))
                
                try Storage.withContext { ctx in
                    try Storage.upsertProduct(from: body, in: ctx)
                    
                    try ctx.save()
                }
            }
            
            return product_id
            
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
                try Storage.withContext { ctx in
                    if let venue = try Storage.fetchById(Venue.self, id: venue_id, in: ctx) {
                        needsRefresh = PreferabliTools.hasMinutesPassed(minutes: 60, startDate: Storage.getKeyStore().object(forKey: "lastCalledVenue\(venue_id)") as? Date)
                    }
                }
            }
            
            if needsRefresh {
                let body: VenueDTO = try await api.getAlamo().get(APIEndpoints.venue(id: venue_id))
                
                try Storage.withContext { ctx in
                    try Storage.upsertVenue(from: body, in: ctx)
                    
                    try ctx.save()
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
            
            
            let body: [ReservationDTO]
            
#if DEBUG
            body = try Self.decodeStubReservationsJSON()
#else
            body = try await api.getAlamo().get(APIEndpoints.reservations(id: PreferabliTools.getPreferabliUserId()))
#endif
            
            let reservationIds = try Storage.withContext { ctx in
                var ids = [Int]()
                for dto in body {
                    let reservation = try Storage.upsertReservation(from: dto, in: ctx)
                    ids.append(reservation.id)
                }
                
                try ctx.save()
                
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
                try Storage.withContext { ctx in
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
                let body: [ExperienceDTO]
                
#if DEBUG
                body = try Self.decodeStubExperiencesJSON()
#else
                body = try await api.getAlamo().get(APIEndpoints.experiences(id: venue_id))
#endif
                
                experienceIds = try Storage.withContext { ctx in
                    var ids = [Int]()
                    if let venue = try Storage.fetchById(Venue.self, id: venue_id, in: ctx) {
                        for dto in body {
                            try Storage.upsertExperience(from: dto, venue: venue, in: ctx)
                        }
                        
                        Storage.getKeyStore().set(Date(), forKey: "lastCalledVenueExperiences\(venue_id)")
                        try ctx.save()
                    }
                    
                    return ids
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
            
            if (booking_code != "E4TDERV9") {
                throw PreferabliException.init(error: .init(code: 12378, message: "Temp fail!! Only one code works."))
            }

#if DEBUG
            let body: BalloonResponseDTO = try Self.decodeStubBallooonJSON()
#else
            let body = try await api.getAlamo().get(APIEndpoints.experiences(id: venue_id))
#endif
            
            let reservationId = try Storage.withContext { ctx in
                let reservation = try Storage.upsertBalloonReservation(from: body.data.booking, in: ctx)
                try ctx.save()
                return reservation.id
            }
            
            return reservationId
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    public func getExperience(force_refresh : Bool = false, experience_id : Int) async throws -> Int
    {
        do {
            try await canWeContinue(needsToBeLoggedIn: false)
            
            Analytics.track(["event": "experience_refresh"])
            //
            //            var needsRefresh = true
            //
            //            if (!force_refresh) {
            //                try Storage.withContext { ctx in
            //                    if let venue = try Storage.fetchById(Venue.self, id: venue_id, in: ctx) {
            //                        needsRefresh = PreferabliTools.hasMinutesPassed(minutes: 60, startDate: Storage.getKeyStore().object(forKey: "lastCalledVenue\(venue_id)") as? Date)
            //                    }
            //                }
            //            }
            //
            //            if needsRefresh {
            //                let body: VenueDTO = try await api.getAlamo().get(APIEndpoints.product(id: venue_id))
            //
            //                try Storage.withContext { ctx in
            //                    try Storage.upsertVenue(from: body, in: ctx)
            //
            //                    try ctx.save()
            //                }
            //            }
            //
            return experience_id
            
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
            try Storage.withContext { ctx in
                _ = try Storage.upsertCollection(from: collectionDTO, in: ctx)
                _ = try Storage.upsertUserCollection(from: userCollectionDTO, in: ctx)
                try ctx.save()
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
            
            try Storage.withContext { ctx in
                _ = try Storage.upsertCollection(from: collectionDTO, in: ctx)
                try ctx.save()
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
            
            try Storage.withContext { ctx in
                guard let userCollection = try Storage.fetchById(UserCollection.self, id: userCollectionId, in: ctx) else {
                    return
                }
                
                ctx.delete(userCollection)
                
                try ctx.save()
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
            
            try Storage.withContext { ctx in
                guard let ordering = try Storage.fetchById(CollectionOrder.self, id: orderingId, in: ctx) else {
                    return
                }
                ctx.delete(ordering)
                
                if let collection = try Storage.fetchById(Collection.self, id: collectionId, in: ctx) {
                    collection.product_count = max(0, (collection.product_count ?? 0) - 1)
                    collection.updated_at = Date()
                }
                
                try ctx.save()
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
            let missingVariantIds: [Int] = try await Storage.withBackgroundContext { ctx in
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
            let productIds: [Int] = try await Storage.withBackgroundContext { ctx in
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
                
                try ctx.save()
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
                if let local = try Storage.withContext({ ctx -> (Int, Int)? in
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
                _ = try Storage.withContext { ctx in
                    _ = try Storage.upsertCollection(from: dto, in: ctx)
                    try ctx.save()
                }
                
                guard let after = try Storage.withContext({ ctx -> (Int, Int)? in
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
            try Storage.withContext { ctx in
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
                
                try ctx.save()
            }
            
            try await canWeContinue(needsToBeLoggedIn: true)
            
        } catch {
            handleError(error: error)
            throw error
        }
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
    public func rateProduct(product_id : Int, year : Int, rating : RatingLevel, location : String? = nil, notes : String? = nil, price : Decimal? = nil, format_ml : Int? = nil) async throws {
        Analytics.track( ["event" : "rate_product"])
        try await createOrEditTagActual(product_id: product_id, year: year, collection_id: Storage.getKeyStore().integer(forKey: "ratings_id"), value: rating.getValue(), tag_type: .RATING, location: location, notes: notes, price: price, quantity: nil, format_ml: format_ml)
    }
    
    /// Toggles the wishlist status of a ``Product``. Creates a ``Tag`` of type ``TagType/WISHLIST`` if none already exists. Deletes the wishlist tag if it already does. User must be logged in to run this call.
    /// - Parameters:
    ///   - product_id: id of the starting ``Product``.  Only pass a Preferabli product id. If necessary, call ``Preferabli/getPreferabliProductId(merchant_product_id:merchant_variant_id:onCompletion:onFailure:)`` to convert your product id into a Preferabli product id.
    public func toggleProductOnWishlist(product_id : Int) async throws {
        Analytics.track( ["event" : "wishlist_product"])
        
        var existingTagId : Int?
        try Storage.withContext { ctx in
            let product = try Storage.fetchById(Product.self, id: product_id, in: ctx)
            existingTagId = product?.cachedWishlist?.id
            product?.cachedWishlist?.isTombstoned = true
            product?.cachedWishlist = nil
            try ctx.save()
        }
        
        if let existingTagId = existingTagId {
            try await deleteTag(tag_id: existingTagId)
        } else {
            try await createOrEditTagActual(product_id: product_id, year: Variant.CURRENT_VARIANT_YEAR, collection_id: Storage.getKeyStore().integer(forKey: "wishlist_id"), value: nil, tag_type: .WISHLIST, location: nil, notes: nil, price: nil, quantity: nil, format_ml: nil)
        }
    }
    
    public func submitProduct(
        name : String? = nil,
        image : Data? = nil,
        category : ProductCategory,
        subcategory : ProductSubcategory? = nil,
        type : ProductType? = nil,
        onTempProductSaved: ((Int) -> Void)? = nil
    ) async throws {
        
        Analytics.track( ["event" : "submit_product"])
        
        try await canWeContinue(needsToBeLoggedIn: false)
        
        let tempProductId = Storage.generateRandomLongId()
        let tempVariantId = Storage.generateRandomLongId()
        
        try Storage.withContext { ctx in
            let productDTO = ProductDTO(id: tempProductId, name: name, category: category.getCategoryName(), subcategory: subcategory?.getSubcategoryName(), type: type?.getTypeName())
            let product = try Storage.upsertProduct(from: productDTO, in: ctx)
            product.temporaryImage = image
            product.temporaryName = name
            
            let variantDTO = VariantDTO.init(id: tempVariantId, created_at: Date.init(), updated_at: Date.init(), num_dollar_signs: nil, price: nil, recommendable: false, year: Variant.CURRENT_VARIANT_YEAR, primary_image: nil, product_id: tempProductId)
            let variant = try Storage.upsertVariant(from: variantDTO, product: product, in: ctx)
            
            try ctx.save()
        }
        
        if let onTempProductSaved {
            await MainActor.run {
                onTempProductSaved(tempProductId)
            }
        }
        
        let payload: SParams = [
            "name"         : name,
            "category"     : category.getCategoryName(),
            "subcategory"  : subcategory?.getSubcategoryName(),
            "type"         : type?.getTypeName()
        ]
        
        var variantPayload: SParams = [
            "year"         : Variant.CURRENT_VARIANT_YEAR,
        ]
        
        if let image = image {
            var mediaResponse : MediaDTO = try await api.getAlamo().upload(APIEndpoints.postMedia, data: image)
            variantPayload["image_ids"] = [mediaResponse.id]
            variantPayload["primary_image_id"] = mediaResponse.id
        }
        
        let productDTO : ProductDTO = try await api.getAlamo().post(APIEndpoints.products, sjson: payload)
        let variantDTO : VariantDTO = try await api.getAlamo().post(APIEndpoints.variants(product_id: productDTO.id), sjson: variantPayload)
        
        try Storage.withContext { ctx in
            let product = try Storage.upsertProduct(from: productDTO, tempProductId: tempProductId, in: ctx)
            let varaint = try Storage.upsertVariant(from: variantDTO, product: product, in: ctx)
            try ctx.save()
        }
    }
    
    private func createOrEditTagActual(
        tag_id: Int? = nil,
        product_id: Int,
        year: Int,
        collection_id: Int,
        value: String? = nil,
        tag_type: TagType?,
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
            
            try Storage.withContext { ctx in
                let product = try Storage.fetchById(Product.self, id: product_id, in: ctx)
                guard let product = product else {
                    needsRefresh = true
                    return
                }
                
                let variant : Variant
                if let v = product.getVariantWithYear(year: year) {
                    variant = v
                } else {
                    // let's create a temp variant with the correct year. update it later.
                    let variantDTO = VariantDTO.init(id: tempVariantId, created_at: Date.init(), updated_at: Date.init(), num_dollar_signs: nil, price: nil, recommendable: false, year: year, primary_image: nil, product_id: product_id)
                    variant = try Storage.upsertVariant(from: variantDTO, product: product, in: ctx)
                    needsRefresh = true
                }
                
                let tagDTO : TagDTO = TagDTO.init(id: tempTagId, collection_id: collection_id, comment: notes, created_at: Date.init(), location: location, badge: nil, tagged_in_collection_id: tagged_in_collection_id, tagged_in_channel_id: nil, tagged_in_channel_name: nil, type: tag_type?.getDatabaseName(), updated_at: Date.init(), user_id: PreferabliTools.getPreferabliUserId(), value: value, bin: bin, variant_id: variant.id, quantity: quantity, format_ml: format_ml, price: price, customer_id: PreferabliTools.getCustomerId())
                let tag = try Storage.upsertTag(from: tagDTO, variant: variant, in: ctx)
                product.updateCachedRelationships()
                try ctx.save()
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
            let tag_id: Int = try Storage.withContext { ctx in
                
                let product : Product?
                if let productDTO = productDTO {
                    product = try Storage.upsertProduct(from: productDTO, in: ctx)
                } else {
                    product = try Storage.fetchById(Product.self, id: product_id, in: ctx)
                }
                
                guard let product = product else {
                    throw PreferabliException.init(type: .BadSwiftData, message: "Could not add new tag due to database error involving Product. This should never happen.", code: 600)
                }
                
                guard let variant = product.getVariantWithYear(year: year), variant.hasValidID else {
                    throw PreferabliException.init(type: .BadSwiftData, message: "Could not add new tag due to database error involving Variant. This should never happen.", code: 600)
                }
                
                let tag = try Storage.upsertTag(from: tagDTO, variant: variant, tempTagId: tempTagId, in: ctx)
                
                try ctx.save()
                
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
            
            try Storage.withContext { ctx in
                let tag = try Storage.fetchById(Tag.self, id: tag_id, in: ctx)
                tag?.isTombstoned = true
                tag?.variant.product.updateCachedRelationships()
                try ctx.save()
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
                try await Storage.withContext { ctx in
                    guard let tag = try Storage.fetchById(Tag.self, id: tag_id, in: ctx), tag.product_id != nil else {
                        throw PreferabliException(type: .DatabaseError)
                    }
                    tag.isTombstoned = false
                    tag.variant.product.updateCachedRelationships()
                    try ctx.save()
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
            
            let needsRefresh = try await Storage.withContext { ctx in
                var needsRefresh = false
                guard let product = try Storage.fetchById(Product.self, id: product_id, in: ctx) else {
                    throw PreferabliException.init(type: .BadSwiftData, message: "Product not found.", code: 404)
                }
                
                if (!(product.recommendable ?? false)) {
                    let dto = PreferenceDataDTO.init(title: "maybe")
                    try Storage.upsertPreferenceData(from: dto, for: product, in: ctx)
                    try ctx.save()
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
                
                try await Storage.withContext { ctx in
                    guard let product = try Storage.fetchById(Product.self, id: product_id, in: ctx) else {
                        throw PreferabliException.init(type: .BadSwiftData, message: "Product not found.", code: 404)
                    }
                    
                    try Storage.upsertPreferenceData(from: preferenceResponse, for: product, in: ctx)
                    
                    try ctx.save()
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
        location : String? = nil,
        notes : String? = nil,
        price : Decimal? = nil,
        quantity : Int? = nil,
        format_ml : Int? = nil,
    ) async throws {
        let (product_id, collection_id, tag_type, value): (Int, Int, TagType?, String?) =
        try Storage.withContext { ctx in
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
            let exists = try Storage.withContext { ctx in
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
        collectionID = try Storage.withContext { ctx in
            let collection = try Storage.upsertCollection(from: dto, in: ctx)
            try ctx.save()
            return collection.id
        }
        
        // 3) Persist id for future use
        ks.set(collectionID, forKey: key)
        
        // If you still have an explicit ETag helper, wire it here:
        // PreferabliTools.saveCollectionEtag(from: dto, collectionId: collectionID)
        
        return collectionID
    }
}


private extension Preferabli {
    static func decodeStubExperiencesJSON() throws -> [ExperienceDTO] {
        let json = """
        [
          {
            "Affiliates": [],
            "ExperienceBenefits": [
              {
                "description": "What’s Included:\\n• 5 wine flight\\n• 5 Kollar chocolates\\n• 90-minute experience\\n• Accommodates 1-8 guests\\n\\nReservation no-shows and late cancellations will be charged the total retail value of the tasting.\\n",
                "experience_benefits_id": 374,
                "experience_id": 376,
                "image_url": "https://assets.cuveecollective.com/brands/undefined/experience/experience_benefits/0088d200fe869ebc12a01910c.jpg",
                "subtitle": "In Person Tasting",
                "title": "Reservations MUST Be Made In Advance"
              }
            ],
            "ExperienceOperationHoursNormals": [],
            "ExperiencePrices": [
              {
                "active": true,
                "age_range": "21+",
                "experience_economics": null,
                "experience_id": 376,
                "experience_price_id": 363,
                "experience_tier": null,
                "guest_increment": 1,
                "incentive_type_id": null,
                "list_price": 0,
                "max_count": 8,
                "min_count": 1,
                "partner_ref": 30,
                "price": 75,
                "price_type": "adult",
                "stripe_product_price_id": "price_1PhlLqI3TXWMhy8uUUYKuedO"
              }
            ],
            "Experience_types": [],
            "FavoritesExperiences": [],
            "booking_link": "https://www.exploretock.com/maxvillewinery/experience/442453/maxville-kollar-chocolate-wine-pairing",
            "booking_terms": "\\"<ul><li>Cancellations must be made at least 48 hours in advance.</li><li><strong>No-shows:</strong> No-shows or cancellations made within 48 hours of the reservation may be charged the full retail price of the tasting. This includes promotional offers and free tastings.</li><li>This property does not allow shared tastings.</li><li>This property does not allow or any persons under the age of 21 on-site.</li></ul>\\"",
            "brand_id": 135,
            "cuvee_experience": false,
            "description": "\\"<p>Description</p>\\"",
            "discount_code": null,
            "duration": null,
            "experience_type": "in_person",
            "header_image_url": "https://assets.cuveecollective.com/brands/maxville-winery/experience/597bb24fb4a0872b93bb2e937.jpg",
            "id": 376,
            "min_availability_notice_days": 0,
            "name": "Chocolate & Wine Pairing",
            "number_of_wines_poured": null,
            "order": 0,
            "prepayment_required": true,
            "price": null,
            "qualifier": false,
            "qualifier_text": "",
            "qualifier_title": "",
            "reservation_api": "cuvee_reservation_request",
            "reservation_notice": "",
            "reservation_options": null,
            "reservation_type": "Cuvee Web Request",
            "show_upgrade": false,
            "stripe_product_id": "prod_QYt6WU4syXFTZy",
            "terms_and_conditions": "\\"<ul><li>Reservations must be made via the Tastefuli app or Tastefuli Concierge.<li>Winery and Tastefuli reserve the right to refuse or cancel any reservation or service before or upon arrival. In any dispute, Winery and Tastefuli's decision is final.<li>Winery or Tastefuli may contact the guest who has booked the reservation. Please ensure your email and phone number are updated in your Tastefuli profile settings.</ul>\\"",
            "unit_label": null,
            "upgrade_experience_id": null,
            "visible": true,
            "wt_nft_id": 0
          },
          {
            "Affiliates": [],
            "ExperienceBenefits": [
              {
                "description": "What's included:\\n• 5 wine flight\\n• House-made charcuterie and artisan cheeses \\n• 90-minute experience\\n• Accommodates 2-8 guests\\n\\nReservation no-shows and late cancellations will be charged the total retail value of the tasting.\\n",
                "experience_benefits_id": 372,
                "experience_id": 374,
                "image_url": "https://assets.cuveecollective.com/brands/undefined/experience/experience_benefits/0088d200fe869ebc12a01910e.jpg",
                "subtitle": "In Person Tasting",
                "title": "Reservations MUST Be Made In Advance"
              }
            ],
            "ExperienceOperationHoursNormals": [
              {
                "day_of_week": 3,
                "end_times": ["15:00:00"],
                "experience_id": 374,
                "id": 2107,
                "increment": 60,
                "start_times": ["10:00:00"]
              },
              {
                "day_of_week": 4,
                "end_times": ["15:00:00"],
                "experience_id": 374,
                "id": 2108,
                "increment": 60,
                "start_times": ["10:00:00"]
              },
              {
                "day_of_week": 5,
                "end_times": ["15:00:00"],
                "experience_id": 374,
                "id": 2109,
                "increment": 60,
                "start_times": ["10:00:00"]
              },
              {
                "day_of_week": 6,
                "end_times": ["15:00:00"],
                "experience_id": 374,
                "id": 2110,
                "increment": 60,
                "start_times": ["10:00:00"]
              },
              {
                "day_of_week": 7,
                "end_times": ["15:00:00"],
                "experience_id": 374,
                "id": 2111,
                "increment": 60,
                "start_times": ["10:00:00"]
              }
            ],
            "ExperiencePrices": [
              {
                "active": true,
                "age_range": "21+",
                "experience_economics": "incentivized",
                "experience_id": 374,
                "experience_price_id": 590,
                "experience_tier": "tier_1",
                "guest_increment": 1,
                "incentive_type_id": null,
                "list_price": 0,
                "max_count": 8,
                "min_count": 2,
                "partner_ref": 15,
                "price": 38,
                "price_type": "adult",
                "stripe_product_price_id": "price_1SAG3kI3TXWMhy8uKYs1soHs"
              }
            ],
            "Experience_types": [
              {
                "filter_order": null,
                "filter_visible": true,
                "highlight": true,
                "home_order": 2,
                "home_visible": true,
                "icon_url": null,
                "id": 20,
                "image_url": "app/experience_types/thumb/visit_exclusive_to_tastefuli_3.jpg",
                "market_id": 1,
                "name": "Featured Tastings"
              },
              {
                "filter_order": 1,
                "filter_visible": true,
                "highlight": false,
                "home_order": 3,
                "home_visible": true,
                "icon_url": null,
                "id": 1,
                "image_url": "app/experience_types/thumb/top_rated_1_thumb.jpg",
                "market_id": 1,
                "name": "Top Rated Tastings"
              }
            ],
            "FavoritesExperiences": [],
            "booking_link": "https://www.exploretock.com/maxvillewinery/experience/private/02a8d419-802e-441d-8c57-d7a809125157",
            "booking_terms": "\\"<ul><li>Cancellations must be made at least 48 hours in advance.</li><li><strong>No-shows:</strong> No-shows or cancellations made within 48 hours of the reservation may be charged the full retail price of the tasting. This includes promotional offers and free tastings.</li><li>This property does not allow shared tastings.</li><li>This property does not allow or any persons under the age of 21 on-site.</li></ul>\\"",
            "brand_id": 135,
            "cuvee_experience": true,
            "description": "\\"<p>Description</p>\\"",
            "discount_code": "",
            "duration": null,
            "experience_type": "in_person",
            "header_image_url": "https://assets.cuveecollective.com/brands/maxville-winery/experience/Maxville2for1.jpg",
            "id": 374,
            "min_availability_notice_days": 0,
            "name": "Estate Tasting",
            "number_of_wines_poured": null,
            "order": 1,
            "prepayment_required": true,
            "price": null,
            "qualifier": false,
            "qualifier_text": "",
            "qualifier_title": "",
            "reservation_api": "cuvee_reservation_request",
            "reservation_notice": "",
            "reservation_options": null,
            "reservation_type": "Cuvee Web Request",
            "show_upgrade": false,
            "stripe_product_id": "prod_QYt1lacBmr5aTg",
            "terms_and_conditions": "\\"<ul><li>Reservations must be made via the Tastefuli app or Tastefuli Concierge.<li>Winery and Tastefuli reserve the right to refuse or cancel any reservation or service before or upon arrival. In any dispute, Winery and Tastefuli's decision is final.<li>Winery or Tastefuli may contact the guest who has booked the reservation. Please ensure your email and phone number are updated in your Tastefuli profile settings.</ul>\\"",
            "unit_label": null,
            "upgrade_experience_id": null,
            "visible": true,
            "wt_nft_id": 0
          },
          {
            "Affiliates": [],
            "ExperienceBenefits": [
              {
                "description": "What’s Included:\\n• Five wine flight\\n• 90-minute experience\\n• Accommodates 1-8 guests\\n\\nReservation no-shows and late cancellations will be charged the total retail value of the tasting.",
                "experience_benefits_id": 373,
                "experience_id": 375,
                "image_url": "https://assets.cuveecollective.com/brands/undefined/experience/experience_benefits/75233a75354f1f2010776ad4a.jpg",
                "subtitle": "In Person Tasting",
                "title": "Reservations MUST Be Made In Advance"
              }
            ],
            "ExperienceOperationHoursNormals": [
              {
                "day_of_week": 3,
                "end_times": ["15:00:00"],
                "experience_id": 375,
                "id": 2244,
                "increment": 60,
                "start_times": ["10:00:00"]
              },
              {
                "day_of_week": 4,
                "end_times": ["15:00:00"],
                "experience_id": 375,
                "id": 2245,
                "increment": 60,
                "start_times": ["10:00:00"]
              },
              {
                "day_of_week": 5,
                "end_times": ["15:00:00"],
                "experience_id": 375,
                "id": 2246,
                "increment": 60,
                "start_times": ["10:00:00"]
              },
              {
                "day_of_week": 6,
                "end_times": ["15:00:00"],
                "experience_id": 375,
                "id": 2247,
                "increment": 60,
                "start_times": ["10:00:00"]
              },
              {
                "day_of_week": 7,
                "end_times": ["15:00:00"],
                "experience_id": 375,
                "id": 2248,
                "increment": 60,
                "start_times": ["10:00:00"]
              }
            ],
            "ExperiencePrices": [
              {
                "active": true,
                "age_range": "21+",
                "experience_economics": null,
                "experience_id": 375,
                "experience_price_id": 525,
                "experience_tier": null,
                "guest_increment": 1,
                "incentive_type_id": null,
                "list_price": 0,
                "max_count": 6,
                "min_count": 1,
                "partner_ref": 30,
                "price": 110,
                "price_type": "adult",
                "stripe_product_price_id": "price_1RZF68I3TXWMhy8uJqgnV4np"
              }
            ],
            "Experience_types": [
              {
                "filter_order": 12,
                "filter_visible": true,
                "highlight": false,
                "home_order": 7,
                "home_visible": true,
                "icon_url": null,
                "id": 12,
                "image_url": "app/experience_types/thumb/scenic_views_1_thumb.jpg",
                "market_id": 1,
                "name": "Scenic Views"
              },
              {
                "filter_order": 2,
                "filter_visible": true,
                "highlight": false,
                "home_order": 6,
                "home_visible": true,
                "icon_url": null,
                "id": 2,
                "image_url": "app/experience_types/thumb/food_and_wine_pairings_1_thumb.jpg",
                "market_id": 1,
                "name": "Food + Wine Pairings"
              }
            ],
            "FavoritesExperiences": [],
            "booking_link": "https://www.exploretock.com/maxvillewinery/experience/372772/grand-reserve-tasting",
            "booking_terms": "\\"<ul><li>Cancellations must be made at least 48 hours in advance.</li><li><strong>No-shows:</strong> No-shows or cancellations made within 48 hours of the reservation may be charged the full retail price of the tasting. This includes promotional offers and free tastings.</li><li>This property does not allow shared tastings.</li><li>This property does not allow or any persons under the age of 21 on-site.</li></ul>\\"",
            "brand_id": 135,
            "cuvee_experience": false,
            "description": "\\"<p>Description</p>\\"",
            "discount_code": null,
            "duration": null,
            "experience_type": "in_person",
            "header_image_url": "https://assets.cuveecollective.com/brands/maxville-winery/experience/Maxville.jpg",
            "id": 375,
            "min_availability_notice_days": 1,
            "name": "Grand Reserve Tasting",
            "cancellation_fee": "$50",
            "reservations_provider": "tock",
            "primary_inventory_id": 737056,
            "number_of_wines_poured": null,
            "order": 3,
            "prepayment_required": true,
            "price": null,
            "qualifier": false,
            "qualifier_text": "",
            "qualifier_title": "",
            "reservation_api": "cuvee_reservation_request",
            "reservation_notice": "",
            "reservation_options": null,
            "reservation_type": "Cuvee Web Request",
            "show_upgrade": false,
            "stripe_product_id": "prod_QYt4yzMJpmuhJu",
            "terms_and_conditions": "\\"<ul><li>Reservations must be made via the Tastefuli app or Tastefuli Concierge.<li>Winery and Tastefuli reserve the right to refuse or cancel any reservation or service before or upon arrival. In any dispute, Winery and Tastefuli's decision is final.<li>Winery or Tastefuli may contact the guest who has booked the reservation. Please ensure your email and phone number are updated in your Tastefuli profile settings.</ul>\\"",
            "unit_label": null,
            "upgrade_experience_id": null,
            "visible": true,
            "wt_nft_id": 0
          }
        ]
        """
        
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode([ExperienceDTO].self, from: data)
    }
    
    static func decodeStubReservationsJSON() throws -> [ReservationDTO] {
        let json = #"""
        [
          {
            "id": 4848,
            "date": "2025-04-03",
            "requested_times": [
              "14:00"
            ],
            "status": "availability_requested",
            "customer_slug": "629bc72b-4647-4188-a198-37ae9a3c80cc",
            "brand": {
              "id": 47,
              "name": "Reynolds Family Winery",
              "logo_image_url": "https://assets.cuveecollective.com/brands/Reynolds-Family-Winery/960f2a26505a73251ee6d8e04.jpg"
            },
            "experience": {
              "id": 428,
              "name": "DON'T USE",
              "header_image_url": "https://assets.cuveecollective.com/brands/Reynolds-Family-Winery/experience/Reynolds2for1.jpg"
            },
            "ConciergeReservationRequestGuests": [
              {
                "concierge_reservation_request": 4848,
                "experience_price_id": 461,
                "quantity": 1,
                "ExperiencePrice": {
                  "experience_pr": 461,
                  "experience_id": 428,
                  "price_type": "adult",
                  "price": 0,
                  "min_count": 1,
                  "max_count": 4,
                  "guest_increme": 1,
                  "partner_ref": 18,
                  "age_range": "21+",
                  "stripe_produc": "price_1R04MMI3TXWMhy8uO4ijd8WV",
                  "active": false,
                  "experience_ec": null,
                  "experience_ti": null,
                  "list_price": 0,
                  "incentive_typ": null
                }
              }
            ],
            "ConciergeReservationBooking": null
          },
          {
            "id": 7206,
            "date": "2025-08-28",
            "requested_times": [
              "10:00"
            ],
            "status": "booking_confirmed",
            "customer_slug": "58133c47-c2d2-49ea-9af3-a8736bbedb31",
            "brand": {
              "id": 125,
              "name": "Cuvee Collective Test Update",
              "logo_image_url": "https://assets.cuveecollective.com/brands/cuvee-collective-test-two/dc100f74e3f4d0ccb272cea34.jpg"
            },
            "experience": {
              "id": 381,
              "name": "TEST_EXPERIENCE_2",
              "header_image_url": "https://assets.cuveecollective.com/brands/cuvee-collective-test-two/experience/84ae2a9609b645f6451ecf938.jpg"
            },
            "ConciergeReservationRequestGuests": [
              {
                "concierge_reservation_request": 7206,
                "experience_price_id": 372,
                "quantity": 2,
                "ExperiencePrice": {
                  "experience_pr": 372,
                  "experience_id": 381,
                  "price_type": "adult",
                  "price": 78,
                  "min_count": 1,
                  "max_count": 2,
                  "guest_increme": 1,
                  "partner_ref": 0,
                  "age_range": "21+",
                  "stripe_produc": "price_1PkvtVI3TXWMhy8ulP3orjzs",
                  "active": true,
                  "experience_ec": null,
                  "experience_ti": null,
                  "list_price": 0,
                  "incentive_typ": null
                }
              }
            ],
            "ConciergeReservationBooking": {
              "id": 3388,
              "experience_id": 381,
              "brand_id": 125,
              "request_id": 7206,
              "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
              "date": "2025-08-28",
              "confirmed_time": "10:00:00",
              "specific_requests": null,
              "payment_method_id": "EXTERNAL",
              "status": "booking_confirmed",
              "booking_type": null,
              "created_on": "2025-06-30T14:16:50.803Z",
              "updated_on": "2025-06-30T14:16:50.840Z",
              "customer_slug": "771ac6cc-7550-4a4e-ac13-b279727d517a",
              "modification_link": "https://www.exploretock.com/tankgaragewinery/receipt?purchaseId=324836161&source=checkout",
              "booking_confirmation_ref": "TOCK-R-3V3C4SCO",
              "experience": {
                "id": 381,
                "name": "TEST_EXPERIENCE_2",
                "header_image_url": "brands/cuvee-collective-test-two/experience/84ae2a9609b645f6451ecf938.jpg"
              },
              "ConciergeReservationBookingGuests": [
                {}
              ]
            }
          },
          {
            "id": 7208,
            "date": "2025-06-30",
            "requested_times": [
              "10:00:00"
            ],
            "status": "booking_confirmed",
            "customer_slug": "f0a67df6-94c6-49b6-9d94-2ce1db3008d2",
            "brand": {
              "id": 125,
              "name": "Cuvee Collective Test Update",
              "logo_image_url": "https://assets.cuveecollective.com/brands/cuvee-collective-test-two/dc100f74e3f4d0ccb272cea34.jpg"
            },
            "experience": {
              "id": 381,
              "name": "TEST_EXPERIENCE_2",
              "header_image_url": "https://assets.cuveecollective.com/brands/cuvee-collective-test-two/experience/84ae2a9609b645f6451ecf938.jpg"
            },
            "ConciergeReservationRequestGuests": [
              {
                "concierge_reservation_request": 7208,
                "experience_price_id": 372,
                "quantity": 2,
                "ExperiencePrice": {
                  "experience_pr": 372,
                  "experience_id": 381,
                  "price_type": "adult",
                  "price": 78,
                  "min_count": 1,
                  "max_count": 2,
                  "guest_increme": 1,
                  "partner_ref": 0,
                  "age_range": "21+",
                  "stripe_produc": "price_1PkvtVI3TXWMhy8ulP3orjzs",
                  "active": true,
                  "experience_ec": null,
                  "experience_ti": null,
                  "list_price": 0,
                  "incentive_typ": null
                }
              }
            ],
            "ConciergeReservationBooking": {
              "id": 3389,
              "experience_id": 381,
              "brand_id": 125,
              "request_id": 7208,
              "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
              "date": "2025-08-07",
              "confirmed_time": "10:00:00",
              "specific_requests": "[\n  {\n    \"answer\" : \"Nothing now\",\n    \"question\" : \"Is there anything you'd like us to know before your visit?\"\n  }\n]",
              "payment_method_id": "EXTERNAL",
              "status": "booking_cancelled",
              "booking_type": null,
              "created_on": "2025-06-30T15:13:39.635Z",
              "updated_on": "2025-06-30T15:54:58.650Z",
              "customer_slug": "18ad8d13-320b-4b61-a9d3-f0105a9ce264",
              "modification_link": "https://www.exploretock.com/tankgaragewinery/receipt?purchaseId=324840772&source=checkout",
              "booking_confirmation_ref": "TOCK-R-7FGL2WMX",
              "experience": {
                "id": 381,
                "name": "TEST_EXPERIENCE_2",
                "header_image_url": "brands/cuvee-collective-test-two/experience/84ae2a9609b645f6451ecf938.jpg"
              },
              "ConciergeReservationBookingGuests": [
                {}
              ]
            }
          },
          {
            "id": 7210,
            "date": "2025-09-03",
            "requested_times": [
              "10:00:00"
            ],
            "status": "booking_confirmed",
            "customer_slug": "cc148b66-6a03-465a-8d22-16605528d642",
            "brand": {
              "id": 125,
              "name": "Cuvee Collective Test Update",
              "logo_image_url": "https://assets.cuveecollective.com/brands/cuvee-collective-test-two/dc100f74e3f4d0ccb272cea34.jpg"
            },
            "experience": {
              "id": 381,
              "name": "TEST_EXPERIENCE_2",
              "header_image_url": "https://assets.cuveecollective.com/brands/cuvee-collective-test-two/experience/84ae2a9609b645f6451ecf938.jpg"
            },
            "ConciergeReservationRequestGuests": [
              {
                "concierge_reservation_request": 7210,
                "experience_price_id": 372,
                "quantity": 2,
                "ExperiencePrice": {
                  "experience_pr": 372,
                  "experience_id": 381,
                  "price_type": "adult",
                  "price": 78,
                  "min_count": 1,
                  "max_count": 2,
                  "guest_increme": 1,
                  "partner_ref": 0,
                  "age_range": "21+",
                  "stripe_produc": "price_1PkvtVI3TXWMhy8ulP3orjzs",
                  "active": true,
                  "experience_ec": null,
                  "experience_ti": null,
                  "list_price": 0,
                  "incentive_typ": null
                }
              }
            ],
            "ConciergeReservationBooking": {
              "id": 3391,
              "experience_id": 381,
              "brand_id": 125,
              "request_id": 7210,
              "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
              "date": "2025-09-03",
              "confirmed_time": "10:00:00",
              "specific_requests": "[\n  {\n    \"question\" : \"Is there anything you'd like us to know before your visit?\",\n    \"answer\" : \"Nothing here\"\n  }\n]",
              "payment_method_id": "EXTERNAL",
              "status": "booking_cancelled",
              "booking_type": null,
              "created_on": "2025-06-30T17:06:20.506Z",
              "updated_on": "2025-06-30T17:07:22.435Z",
              "customer_slug": "ec2f9ed0-02c2-4a16-b263-cd443550e292",
              "modification_link": "https://www.exploretock.com/tankgaragewinery/receipt?purchaseId=325045447&source=checkout",
              "booking_confirmation_ref": "TOCK-R-UDG7ODRK",
              "experience": {
                "id": 381,
                "name": "TEST_EXPERIENCE_2",
                "header_image_url": "brands/cuvee-collective-test-two/experience/84ae2a9609b645f6451ecf938.jpg"
              },
              "ConciergeReservationBookingGuests": [
                {}
              ]
            }
          },
          {
            "id": 7228,
            "date": "2025-07-25",
            "requested_times": [
              "17:00"
            ],
            "status": "booking_confirmed",
            "customer_slug": "94d176f9-19fd-4340-ac36-40757f6e258e",
            "brand": {
              "id": 125,
              "name": "Cuvee Collective Test Update",
              "logo_image_url": "https://assets.cuveecollective.com/brands/cuvee-collective-test-two/dc100f74e3f4d0ccb272cea34.jpg"
            },
            "experience": {
              "id": 381,
              "name": "TEST_EXPERIENCE_2",
              "header_image_url": "https://assets.cuveecollective.com/brands/cuvee-collective-test-two/experience/84ae2a9609b645f6451ecf938.jpg"
            },
            "ConciergeReservationRequestGuests": [
              {
                "concierge_reservation_request": 7228,
                "experience_price_id": 372,
                "quantity": 1,
                "ExperiencePrice": {
                  "experience_pr": 372,
                  "experience_id": 381,
                  "price_type": "adult",
                  "price": 78,
                  "min_count": 1,
                  "max_count": 2,
                  "guest_increme": 1,
                  "partner_ref": 0,
                  "age_range": "21+",
                  "stripe_produc": "price_1PkvtVI3TXWMhy8ulP3orjzs",
                  "active": true,
                  "experience_ec": null,
                  "experience_ti": null,
                  "list_price": 0,
                  "incentive_typ": null
                }
              }
            ],
            "ConciergeReservationBooking": {
              "id": 3398,
              "experience_id": 381,
              "brand_id": 125,
              "request_id": 7228,
              "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
              "date": "2025-07-25",
              "confirmed_time": "17:00:00",
              "specific_requests": "[\n  {\n    \"question\" : \"Is there anything you'd like us to know before you visit?\",\n    \"answer\" : \"Test this\"\n  }\n]",
              "payment_method_id": "EXTERNAL",
              "status": "booking_cancelled",
              "booking_type": null,
              "created_on": "2025-07-02T12:09:16.621Z",
              "updated_on": "2025-07-02T12:11:46.124Z",
              "customer_slug": "f60c7baf-ec78-4bee-8690-e5bead9bc938",
              "modification_link": "https://www.exploretock.com/cornerstone/receipt?token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJwdXJjaGFzZUlkIjoiMzI1MzA3NjcxIiwiZXhwIjoxNzU0MDkyODAwLCJ0eXBlIjoicHVyY2hhc2UiLCJpYXQiOjE3NTE0NTgxMTh9.0HHiJzkFC8RRJoohHxoluFSbPRh4gGrlaCXiO2dtXxM",
              "booking_confirmation_ref": "TOCK-R-JB0I701C",
              "experience": {
                "id": 381,
                "name": "TEST_EXPERIENCE_2",
                "header_image_url": "brands/cuvee-collective-test-two/experience/84ae2a9609b645f6451ecf938.jpg"
              },
              "ConciergeReservationBookingGuests": [
                {}
              ]
            }
          },
          {
            "id": 9494,
            "date": "2026-01-31",
            "requested_times": [
              "17:00"
            ],
            "status": "booking_confirmed",
            "customer_slug": "5b523d64-2998-4ec2-b4e3-c843cd6244e2",
            "brand": {
              "id": 113,
              "name": "Cornerstone Cellars",
              "logo_image_url": "https://assets.cuveecollective.com/brands/cornerstone-cellars/61b0fdcef76180ad43d679612.jpg"
            },
            "experience": {
              "id": 295,
              "name": "Taste of Cornerstone Flight",
              "header_image_url": "https://assets.cuveecollective.com/brands/cornerstone-cellars/experience/complimentary%20tasting%20cover%20photo%201.jpg"
            },
            "ConciergeReservationRequestGuests": [
              {
                "concierge_reservation_request": 9494,
                "experience_price_id": 506,
                "quantity": 2,
                "ExperiencePrice": {
                  "experience_pr": 506,
                  "experience_id": 295,
                  "price_type": "adult",
                  "price": 0,
                  "min_count": 1,
                  "max_count": 2,
                  "guest_increme": 1,
                  "partner_ref": 0,
                  "age_range": "21+",
                  "stripe_produc": "price_1RGnd6I3TXWMhy8uYnlkW4pt",
                  "active": true,
                  "experience_ec": null,
                  "experience_ti": null,
                  "list_price": 0,
                  "incentive_typ": null
                }
              }
            ],
            "ConciergeReservationBooking": {
              "id": 4763,
              "experience_id": 295,
              "brand_id": 113,
              "request_id": 9494,
              "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
              "date": "2026-01-31",
              "confirmed_time": "17:00:00",
              "specific_requests": null,
              "payment_method_id": "EXTERNAL",
              "status": "booking_cancelled",
              "booking_type": null,
              "created_on": "2026-01-20T20:04:16.033Z",
              "updated_on": "2026-01-20T20:04:43.623Z",
              "customer_slug": "36b19dd4-1e50-4a23-9608-3016cefa7ab2",
              "modification_link": "https://www.exploretock.com/cornerstone/receipt?purchaseId=349804360",
              "booking_confirmation_ref": "TOCK-R-EHO2MI82",
              "experience": {
                "id": 295,
                "name": "Taste of Cornerstone Flight",
                "header_image_url": "brands/cornerstone-cellars/experience/complimentary%20tasting%20cover%20photo%201.jpg"
              },
              "ConciergeReservationBookingGuests": [
                {}
              ]
            }
          },
          {
            "id": 9884,
            "date": "2026-05-22",
            "requested_times": [
              "12:00"
            ],
            "status": "booking_confirmed",
            "customer_slug": "ea976900-c6ed-4451-8f08-907c84e55e8c",
            "brand": {
              "id": 484,
              "name": "No Love Lost Wine Co.",
              "logo_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/b8f88933641ea8919ced4ec03.jpg"
            },
            "experience": {
              "id": 643,
              "name": "2 for 1 Tasting",
              "header_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg"
            },
            "ConciergeReservationRequestGuests": [
              {
                "concierge_reservation_request": 9884,
                "experience_price_id": 683,
                "quantity": 2,
                "ExperiencePrice": {
                  "experience_pr": 683,
                  "experience_id": 643,
                  "price_type": "adult",
                  "price": 18,
                  "min_count": 1,
                  "max_count": 6,
                  "guest_increme": 1,
                  "partner_ref": 5,
                  "age_range": "21+",
                  "stripe_produc": "price_1SNdsQI3TXWMhy8uEhcvxw8L",
                  "active": true,
                  "experience_ec": "incentivized",
                  "experience_ti": "tier_1",
                  "list_price": 0,
                  "incentive_typ": null
                }
              }
            ],
            "ConciergeReservationBooking": {
              "id": 5072,
              "experience_id": 643,
              "brand_id": 484,
              "request_id": 9884,
              "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
              "date": "2026-05-22",
              "confirmed_time": "12:00:00",
              "specific_requests": null,
              "payment_method_id": "EXTERNAL",
              "status": "booking_confirmed",
              "booking_type": null,
              "created_on": "2026-04-02T15:23:05.035Z",
              "updated_on": "2026-04-02T15:23:05.067Z",
              "customer_slug": "fcfbbb54-7a04-43c9-9056-e5b864a20438",
              "modification_link": "https://www.exploretock.com/nolovelost/receipt?token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3ODAwODEyMDAsImlhdCI6MTc3NTE0MzM4MiwicHVyY2hhc2VJZCI6IjM1ODIzNDcwMyIsInR5cGUiOiJwdXJjaGFzZSJ9.5FMMcxb2XNvHDduKIQEHdu_FYviCcAqIs10_bngV9Kk",
              "booking_confirmation_ref": "TOCK-R-182VYW2N",
              "experience": {
                "id": 643,
                "name": "2 for 1 Tasting",
                "header_image_url": "brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg"
              },
              "ConciergeReservationBookingGuests": [
                {}
              ]
            }
          },
          {
            "id": 9886,
            "date": "2026-05-30",
            "requested_times": [
              "12:00"
            ],
            "status": "booking_confirmed",
            "customer_slug": "14da6036-f7a9-4b05-846b-75b70b51fd3e",
            "brand": {
              "id": 484,
              "name": "No Love Lost Wine Co.",
              "logo_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/b8f88933641ea8919ced4ec03.jpg"
            },
            "experience": {
              "id": 643,
              "name": "2 for 1 Tasting",
              "header_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg"
            },
            "ConciergeReservationRequestGuests": [
              {
                "concierge_reservation_request": 9886,
                "experience_price_id": 683,
                "quantity": 2,
                "ExperiencePrice": {
                  "experience_pr": 683,
                  "experience_id": 643,
                  "price_type": "adult",
                  "price": 18,
                  "min_count": 1,
                  "max_count": 6,
                  "guest_increme": 1,
                  "partner_ref": 5,
                  "age_range": "21+",
                  "stripe_produc": "price_1SNdsQI3TXWMhy8uEhcvxw8L",
                  "active": true,
                  "experience_ec": "incentivized",
                  "experience_ti": "tier_1",
                  "list_price": 0,
                  "incentive_typ": null
                }
              }
            ],
            "ConciergeReservationBooking": {
              "id": 5074,
              "experience_id": 643,
              "brand_id": 484,
              "request_id": 9886,
              "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
              "date": "2026-05-30",
              "confirmed_time": "12:00:00",
              "specific_requests": null,
              "payment_method_id": "EXTERNAL",
              "status": "booking_confirmed",
              "booking_type": null,
              "created_on": "2026-04-02T15:36:33.545Z",
              "updated_on": "2026-04-02T15:36:33.578Z",
              "customer_slug": "0c6c3865-4443-4911-aad3-60b67820b7a7",
              "modification_link": "https://www.exploretock.com/nolovelost/receipt?token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3ODA3NzI0MDAsImlhdCI6MTc3NTE0NDE5MCwidHlwZSI6InB1cmNoYXNlIiwicHVyY2hhc2VJZCI6IjM1ODIzNjIxMSJ9.Z2Q7jPBTF37DGZgqPhMYBkNxgXFgrp-jsZRdIxrv7Qk",
              "booking_confirmation_ref": "TOCK-R-8V1Z6BEL",
              "experience": {
                "id": 643,
                "name": "2 for 1 Tasting",
                "header_image_url": "brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg"
              },
              "ConciergeReservationBookingGuests": [
                {}
              ]
            }
          },
          {
            "id": 9885,
            "date": "2026-05-15",
            "requested_times": [
              "12:30"
            ],
            "status": "booking_confirmed",
            "customer_slug": "be7989b5-f671-43d7-b89b-5290a4eb39da",
            "brand": {
              "id": 484,
              "name": "No Love Lost Wine Co.",
              "logo_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/b8f88933641ea8919ced4ec03.jpg"
            },
            "experience": {
              "id": 643,
              "name": "2 for 1 Tasting",
              "header_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg"
            },
            "ConciergeReservationRequestGuests": [
              {
                "concierge_reservation_request": 9885,
                "experience_price_id": 683,
                "quantity": 2,
                "ExperiencePrice": {
                  "experience_pr": 683,
                  "experience_id": 643,
                  "price_type": "adult",
                  "price": 18,
                  "min_count": 1,
                  "max_count": 6,
                  "guest_increme": 1,
                  "partner_ref": 5,
                  "age_range": "21+",
                  "stripe_produc": "price_1SNdsQI3TXWMhy8uEhcvxw8L",
                  "active": true,
                  "experience_ec": "incentivized",
                  "experience_ti": "tier_1",
                  "list_price": 0,
                  "incentive_typ": null
                }
              }
            ],
            "ConciergeReservationBooking": {
              "id": 5073,
              "experience_id": 643,
              "brand_id": 484,
              "request_id": 9885,
              "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
              "date": "2026-05-15",
              "confirmed_time": "12:30:00",
              "specific_requests": null,
              "payment_method_id": "EXTERNAL",
              "status": "booking_cancelled",
              "booking_type": null,
              "created_on": "2026-04-02T15:30:19.590Z",
              "updated_on": "2026-04-02T16:00:04.700Z",
              "customer_slug": "bf26aeef-1ade-47e5-b287-17dc07dcacaa",
              "modification_link": "https://www.exploretock.com/nolovelost/receipt?token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3Nzk0NzY0MDAsImlhdCI6MTc3NTE0Mzc0MCwicHVyY2hhc2VJZCI6IjM1ODIzNTM4OCIsInR5cGUiOiJwdXJjaGFzZSJ9.LuPkMO5N6UtBzWR2oRxLP45u_VUVw2QHXxiVohccXeo",
              "booking_confirmation_ref": "TOCK-R-ZIWMQ0IC",
              "experience": {
                "id": 643,
                "name": "2 for 1 Tasting",
                "header_image_url": "brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg"
              },
              "ConciergeReservationBookingGuests": [
                {}
              ]
            }
          },
          {
            "id": 9936,
            "date": "2026-06-12",
            "requested_times": [
              "13:15"
            ],
            "status": "booking_confirmed",
            "customer_slug": "5ddcd502-a4c2-47e0-af65-f5cf027e56c6",
            "brand": {
              "id": 484,
              "name": "No Love Lost Wine Co.",
              "logo_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/b8f88933641ea8919ced4ec03.jpg"
            },
            "experience": {
              "id": 643,
              "name": "2 for 1 Tasting",
              "header_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg"
            },
            "ConciergeReservationRequestGuests": [
              {
                "concierge_reservation_request": 9936,
                "experience_price_id": 683,
                "quantity": 2,
                "ExperiencePrice": {
                  "experience_pr": 683,
                  "experience_id": 643,
                  "price_type": "adult",
                  "price": 18,
                  "min_count": 1,
                  "max_count": 6,
                  "guest_increme": 1,
                  "partner_ref": 5,
                  "age_range": "21+",
                  "stripe_produc": "price_1SNdsQI3TXWMhy8uEhcvxw8L",
                  "active": true,
                  "experience_ec": "incentivized",
                  "experience_ti": "tier_1",
                  "list_price": 0,
                  "incentive_typ": null
                }
              }
            ],
            "ConciergeReservationBooking": {
              "id": 5115,
              "experience_id": 643,
              "brand_id": 484,
              "request_id": 9936,
              "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
              "date": "2026-06-12",
              "confirmed_time": "13:15:00",
              "specific_requests": null,
              "payment_method_id": "EXTERNAL",
              "status": "booking_confirmed",
              "booking_type": null,
              "created_on": "2026-04-08T19:56:17.851Z",
              "updated_on": "2026-04-08T19:56:17.891Z",
              "customer_slug": "72b65338-75dd-4076-aed6-afcfed65c939",
              "modification_link": "https://www.exploretock.com/nolovelost/receipt?token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3ODE5MDAxMDAsImlhdCI6MTc3NTY3ODE3NSwidHlwZSI6InB1cmNoYXNlIiwicHVyY2hhc2VJZCI6IjM1ODkxMDM0OSJ9.jeGMuD9uNWulP66brW2qcZabLaH6CszVa17A_ruKybQ",
              "booking_confirmation_ref": "TOCK-R-22O2YCNH",
              "experience": {
                "id": 643,
                "name": "2 for 1 Tasting",
                "header_image_url": "brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg"
              },
              "ConciergeReservationBookingGuests": [
                {}
              ]
            }
          },
        {
          "ConciergeReservationBooking": {
            "ConciergeReservationBookingGuests": [
              {}
            ],
            "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
            "booking_confirmation_ref": "TOCK-R-1FJLKRTG",
            "booking_type": null,
            "brand_id": 484,
            "confirmed_time": "12:00:00",
            "created_on": "2026-04-09T00:45:37.522Z",
            "customer_slug": "b4dc80c8-aaab-4934-b1ae-da23770dfeb6",
            "date": "2026-05-26",
            "experience": {
              "header_image_url": "brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg",
              "id": 643,
              "name": "2 for 1 Tasting"
            },
            "experience_id": 643,
            "id": 5116,
            "modification_link": "https://www.exploretock.com/nolovelost/receipt?token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3ODA0MjY4MDAsImlhdCI6MTc3NTY5NTUzNCwidHlwZSI6InB1cmNoYXNlIiwicHVyY2hhc2VJZCI6IjM1ODk1MTU4MiJ9.6By0ZPTlqv3OyiIgDFAL1IJ6ajosvhkXz7GTbXWY5OM",
            "payment_method_id": "EXTERNAL",
            "request_id": 9938,
            "specific_requests": null,
            "status": "booking_confirmed",
            "updated_on": "2026-04-09T00:45:37.554Z"
          },
          "ConciergeReservationRequestGuests": [
            {
              "ExperiencePrice": {
                "active": true,
                "age_range": "21+",
                "experience_ec": "incentivized",
                "experience_id": 643,
                "experience_pr": 683,
                "experience_ti": "tier_1",
                "guest_increme": 1,
                "incentive_typ": null,
                "list_price": 0,
                "max_count": 6,
                "min_count": 1,
                "partner_ref": 5,
                "price": 18,
                "price_type": "adult",
                "stripe_produc": "price_1SNdsQI3TXWMhy8uEhcvxw8L"
              },
              "concierge_reservation_request": 9938,
              "experience_price_id": 683,
              "quantity": 2
            }
          ],
          "brand": {
            "id": 484,
            "logo_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/b8f88933641ea8919ced4ec03.jpg",
            "name": "No Love Lost Wine Co."
          },
          "customer_slug": "c699d9f9-6a99-4aa8-b3a5-dbe462ba52e7",
          "date": "2026-05-26",
          "experience": {
            "header_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg",
            "id": 643,
            "name": "2 for 1 Tasting"
          },
          "id": 9938,
          "requested_times": [
            "12:00"
          ],
          "status": "booking_confirmed"
        },
        {
          "ConciergeReservationBooking": {
            "ConciergeReservationBookingGuests": [
              {}
            ],
            "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
            "booking_confirmation_ref": "TOCK-R-GURDYSVW",
            "booking_type": null,
            "brand_id": 484,
            "confirmed_time": "12:15:00",
            "created_on": "2026-04-09T01:28:27.355Z",
            "customer_slug": "301aa4e3-0a0d-41b6-aca2-88bdafc2a7c9",
            "date": "2026-07-09",
            "experience": {
              "header_image_url": "brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg",
              "id": 643,
              "name": "2 for 1 Tasting"
            },
            "experience_id": 643,
            "id": 5117,
            "modification_link": "https://www.exploretock.com/nolovelost/receipt?token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3ODQyMjkzMDAsImlhdCI6MTc3NTY5ODEwNCwicHVyY2hhc2VJZCI6IjM1ODk1NjIyOCIsInR5cGUiOiJwdXJjaGFzZSJ9.0W2k2v03Av68lOW1VxgFGtIRK0IMMZlWJNZEevlJ5Rk",
            "payment_method_id": "EXTERNAL",
            "request_id": 9939,
            "specific_requests": null,
            "status": "booking_confirmed",
            "updated_on": "2026-04-09T01:28:27.389Z"
          },
          "ConciergeReservationRequestGuests": [
            {
              "ExperiencePrice": {
                "active": true,
                "age_range": "21+",
                "experience_ec": "incentivized",
                "experience_id": 643,
                "experience_pr": 683,
                "experience_ti": "tier_1",
                "guest_increme": 1,
                "incentive_typ": null,
                "list_price": 0,
                "max_count": 6,
                "min_count": 1,
                "partner_ref": 5,
                "price": 18,
                "price_type": "adult",
                "stripe_produc": "price_1SNdsQI3TXWMhy8uEhcvxw8L"
              },
              "concierge_reservation_request": 9939,
              "experience_price_id": 683,
              "quantity": 2
            }
          ],
          "brand": {
            "id": 484,
            "logo_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/b8f88933641ea8919ced4ec03.jpg",
            "name": "No Love Lost Wine Co."
          },
          "customer_slug": "b8e014f2-d828-4c10-988b-20e8ec169c64",
          "date": "2026-07-09",
          "experience": {
            "header_image_url": "https://assets.cuveecollective.com/brands/no-love-lost-wine-co/experience/NoLoveLostEx.jpg",
            "id": 643,
            "name": "2 for 1 Tasting"
          },
          "id": 9939,
          "requested_times": [
            "12:15"
          ],
          "status": "booking_confirmed"
        },
        {
          "ConciergeReservationBooking": {
            "ConciergeReservationBookingGuests": [
              {}
            ],
            "account_id": "996150a9-135e-41b7-a33a-8cef56e2e09b",
            "booking_confirmation_ref": "VVNACFHP",
            "booking_type": null,
            "brand_id": 591,
            "confirmed_time": "14:00:00",
            "created_on": "2026-04-09T12:36:39.823Z",
            "customer_slug": "04b15a72-6a86-4819-a6d3-f4e85f10a6b5",
            "date": "2026-05-16",
            "experience": {
              "header_image_url": "brands/duttonestatewinery/experience/Dutton%20Estate%202%20for%201.jpg",
              "id": 893,
              "name": "2 for 1 Vineyard Garden Wine Tasting"
            },
            "experience_id": 893,
            "id": 5118,
            "modification_link": "https://www.cellarpass.com/rsvp-confirmation/5b4a807c-6e45-4989-9a70-7a9bb6fe6acb?mid=7017&sh=true&isguest=1&access=tasteful1c0d3",
            "payment_method_id": "EXTERNAL",
            "request_id": 9941,
            "specific_requests": null,
            "status": "booking_confirmed",
            "updated_on": "2026-04-09T12:36:39.861Z"
          },
          "ConciergeReservationRequestGuests": [
            {
              "ExperiencePrice": {
                "active": true,
                "age_range": "21+",
                "experience_ec": "incentivized",
                "experience_id": 893,
                "experience_pr": 1049,
                "experience_ti": "tier_1",
                "guest_increme": 1,
                "incentive_typ": 2,
                "list_price": 40,
                "max_count": 10,
                "min_count": 1,
                "partner_ref": 6,
                "price": 20,
                "price_type": "adult",
                "stripe_produc": "price_1T6yXaI3TXWMhy8us06x5npA"
              },
              "concierge_reservation_request": 9941,
              "experience_price_id": 1049,
              "quantity": 1
            }
          ],
          "brand": {
            "id": 591,
            "logo_image_url": "https://assets.cuveecollective.com/brands/duttonestatewinery/b99d42f5f4dbaceef9e33c541.jpg",
            "name": "Dutton Estate Winery"
          },
          "customer_slug": "9899a2b7-b781-4473-96ae-a215cd014ca4",
          "date": "2026-05-16",
          "experience": {
            "header_image_url": "https://assets.cuveecollective.com/brands/duttonestatewinery/experience/Dutton%20Estate%202%20for%201.jpg",
            "id": 893,
            "name": "2 for 1 Vineyard Garden Wine Tasting"
          },
          "id": 9941,
          "requested_times": [
            "14:00"
          ],
          "status": "booking_confirmed"
        },
        {
          "ConciergeReservationBooking": null,
          "ConciergeReservationRequestGuests": [
            {
              "ExperiencePrice": {
                "active": true,
                "age_range": "21+",
                "experience_ec": "complimentary",
                "experience_id": 293,
                "experience_pr": 672,
                "experience_ti": "tier_1",
                "guest_increme": 1,
                "incentive_typ": null,
                "list_price": 0,
                "max_count": 4,
                "min_count": 1,
                "partner_ref": 20,
                "price": 0,
                "price_type": "adult",
                "stripe_produc": "price_1SGkoRI3TXWMhy8ud8KrkJTK"
              },
              "concierge_reservation_request": 9942,
              "experience_price_id": 672,
              "quantity": 1
            }
          ],
          "brand": {
            "id": 6,
            "logo_image_url": "https://assets.cuveecollective.com/brands/robert-craig-winery/ee200b5191780f283fe5da534.jpg",
            "name": "Robert Craig Tasting Salon"
          },
          "customer_slug": "d3fe22cb-b7f9-462c-926b-ebdff86e9f75",
          "date": "2026-05-21",
          "experience": {
            "header_image_url": "https://assets.cuveecollective.com/brands/robert-craig-winery/experience/complimentary%20tasting%20image%20with%20banner.jpg",
            "id": 293,
            "name": "Salon Select Experience"
          },
          "id": 9942,
          "requested_times": [
            "14:00"
          ],
          "times_available": [
            "14:00", "16:00", "18:00"
          ],
          "status": "availability_provided"
        }
        ]
        """#
        
        let data = Data(json.utf8)
        
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            
            let decoder = JSONDecoder()
            return try decoder.decode([ReservationDTO].self, from: data)
        } catch let error as DecodingError {
            print("Reservation decode failed: \(error)")
            throw error
        } catch {
            print("Reservation JSON parse failed: \(error)")
            throw error
        }
    }
    
    static func decodeStubBallooonJSON() throws -> BalloonResponseDTO {
        let json = #"""
        {
          "data": {
            "balloon_brand": {
              "logo_image_url": "/app/partners/blank.png",
              "meet_location_landmark_address": "6525 Washington St\nYountville, CA 94599",
              "meet_location_landmark_coordinates": "38.3944, -122.3543",
              "meet_location_landmark_name": ""
            },
            "booking": {
              "customer_email": "oliviagbeeson@gmail.com",
              "customer_name": "Olivia Beeson",
              "customer_phone": "+16144041996",
              "id": "E4TDERV9",
              "items": [
                {
                  "meeting_point": "6525 Washington St\nYountville, CA 94599",
                  "meeting_point_coordinates": "38.3944, -122.3543",
                  "qty": 4,
                  "sku": "32d9889f-369e-452a-bde8-f3a19b9f2172",
                  "start_date": 1775135700
                }
              ]
            }
          },
          "message": "Successfully.",
          "status": 1,
          "statusCode": 200
        }
        """#
        
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(BalloonResponseDTO.self, from: data)
    }
}
