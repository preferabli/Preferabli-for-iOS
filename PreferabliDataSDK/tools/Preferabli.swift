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
            Task.detached(priority: .background) {
                await Storage.pruneTombstones(batchSize: 500, log: log)

                // Gate expensive reindex so it only runs when needed.
                // Tie it to versionCode (or schema hash) so upgrades trigger it.
                let ks = Storage.getKeyStore()
                let reindexKey = "didReindexSearchableContent_v\(await Preferabli.versionCode)"

                if !ks.bool(forKey: reindexKey) {
                    await Storage.reindexSearchableContent(batchSize: 250, log: log)
                    ks.set(true, forKey: reindexKey)
                } else {
                    log("Skipping reindex (already completed for \(reindexKey))")
                }
            }
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
        // delete all from core data
        await MainActor.run {
            Storage.wipePersistentStoreFilesAndRebuild()
        }
        
        // clear HTTP cache
        await api.clearUrlCache()
        await api.refreshDefaults()
        
        let keyStore = Storage.getKeyStore()
        let integration_id = keyStore.integer(forKey: "INTEGRATION_ID")
        let client_interface = keyStore.string(forKey: "CLIENT_INTERFACE")

        keyStore.removePersistentDomain(forName: "Preferabli")
        keyStore.set(integration_id, forKey: "INTEGRATION_ID")
        keyStore.set(client_interface, forKey: "CLIENT_INTERFACE")
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
            
            try userUpdated(dto: user)
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
        let isLoggingOut = await PreferabliTools.isLoggedOutOrLoggingOut()
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
            
            try userUpdated(dto: dto)

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
                
                try userUpdated(dto: dto)

                loadUserData()
            }
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    /// Logout a customer or a user.
    public func logout() async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            
            Analytics.track( ["event" : "logout"])
            
            try await PreferabliTools.logout()
            
            try await clearAllData()
            
            sessionBootstrapper.reset(preferabli: self)
            
            try await createAnonymousSession(create_anonymous_user: isInternal())
            
        } catch {
            handleError(error: error)
            throw error
        }
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

            let finalAvatarId: Int
            if let avatarId {
                // ✅ Selecting an existing media avatar (no upload)
                finalAvatarId = avatarId
            } else if let image {
                // ✅ Upload local/cropped image, then set avatar_id to uploaded media id
                let mediaResponse: MediaDTO = try await api.getAlamo().upload(APIEndpoints.postMedia, data: image)
                finalAvatarId = mediaResponse.id
            } else {
                // ✅ Initials avatar
                finalAvatarId = -1
            }

            var params: SParams = [
                "avatar_id": finalAvatarId
            ]

            // ✅ Optional initials styling (you said you'll handle details server-side)
            if let initialsBackgroundHex {
                params["initials_bg"] = initialsBackgroundHex   // TODO: confirm param name
            }
            if let initialsTextHex {
                params["initials_text"] = initialsTextHex       // TODO: confirm param name
            }

            let user : PreferabliUserDTO = try await api
                .getAlamo()
                .put(APIEndpoints.user(id: PreferabliTools.getPreferabliUserId()), sjson: params)
            
            try userUpdated(dto: user)

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
                "category": category.getCategoryName(),
                "limit": 10,
            ]
            
            if let type {
                params["type"] = type.getTypeName()
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
                "category": category.getCategoryName(),
            ]
            
            if let type {
                params["type"] = type.getTypeName()
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
                "type": product_type?.getTypeName()
            ]
            
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
    
    public func getProductShareQRCode(shareLink : String, width : Int, tint : Color, background : Color = .white) async throws -> Data
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
    
    //    /// Get help finding out where a ``Product`` is in stock.
    //    /// - Parameters:
    //    ///   - product_id: id of the starting ``Product``.  Only pass a Preferabli product id. If necessary, call ``Preferabli/getPreferabliProductId(merchant_product_id:merchant_variant_id:onCompletion:onFailure:)`` to convert your product id into a Preferabli product id.
    //    ///   - fulfill_sort: pass ``FulfillSort`` for sorting & filtering options. If sorting by distance, ``Location`` MUST be present!
    //    ///   - append_nonconforming_results: pass true if you want results that *DO NOT* conform to all filtering & sorting parameters to be returned. Useful so that something is returned even if the user's filter parameters are too narrow. All results that do not conform contain nonconforming_result = true within. Defaults to *true*.
    //    ///   - lock_to_integration: pass true if you only want to draw results from your integration. Defaults to *true*.
    //    ///   - onCompletion: returns ``WhereToBuy`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func whereToBuy(product_id : Int, fulfill_sort : FulfillSort = FulfillSort.init(), append_nonconforming_results : Bool = true, lock_to_integration : Bool = true, onCompletion: @escaping (WhereToBuy) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh, {
    //            await self.whereToBuyActual(product_id: product_id, fulfill_sort: fulfill_sort, append_nonconforming_results: append_nonconforming_results, lock_to_integration: lock_to_integration, onCompletion: onCompletion, onFailure: onFailure)
    //        })
    //    }
    //
    //    private func whereToBuyActual(product_id : Int, fulfill_sort : FulfillSort, append_nonconforming_results : Bool, lock_to_integration : Bool, onCompletion: @escaping (WhereToBuy) -> (), onFailure: @escaping (PreferabliException) -> ()) async {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: false)
    //
    //            Analytics.track( ["event" : "where_to_buy"])
    //
    //            var sort_by = "nearest_first"
    //            if (fulfill_sort.type == .DISTANCE && fulfill_sort.ascending) {
    //                sort_by = "nearest_first"
    //            } else if (fulfill_sort.type == .DISTANCE) {
    //                sort_by = "furthest_first"
    //            } else if (fulfill_sort.ascending){
    //                sort_by = "price_asc"
    //            } else {
    //                sort_by = "price_desc"
    //            }
    //
    //            var params = ["product_id" : product_id, "sort_by" : sort_by, "merge_products" : true, "pickup" : fulfill_sort.include_pickup, "local_delivery" : fulfill_sort.include_delivery, "standard_shipping" : fulfill_sort.include_shipping, "append_nonconforming_results" : append_nonconforming_results, "limit" : 1000, "offset" : 0, "distance_miles" : fulfill_sort.distance_miles] as [String : Any]
    //
    //            if (fulfill_sort.type == .DISTANCE && fulfill_sort.location == nil) {
    //                throw PreferabliException.init(type: .OtherError, message: "Sort by distance requires a location.")
    //            } else if (fulfill_sort.location != nil) {
    //                if (PreferabliTools.isNullOrWhitespace(string: fulfill_sort.location!.zip_code)) {
    //                    params["lat"] = fulfill_sort.location!.latitude
    //                    params["long"] = fulfill_sort.location!.longitude
    //                } else {
    //                    params["zip_code"] = fulfill_sort.location!.zip_code
    //                }
    //            } else {
    //                params["in_stock_anywhere"] = true
    //            }
    //
    //            if (lock_to_integration) {
    //                var channelIds = Array<Int>()
    //                channelIds.append(Preferabli.CHANNEL_ID)
    //                params["channel_ids"] = channelIds
    //            }
    //
    //            if (fulfill_sort.variant_year != Variant.NON_VARIANT) {
    //                var years = Array<Int>()
    //                years.append(fulfill_sort.variant_year)
    //                params["years"] = years
    //            }
    //
    //            var marketplaceResponse = try Preferabli.api.getAlamo().get(APIEndpoints.wheretobuy, params: params)
    //            marketplaceResponse = try await APIService.continueOrThrowPreferabliException(response: marketplaceResponse)
    //            let dictionary = try APIService.continueOrThrowJSONException(data: marketplaceResponse.data!) as! NSArray
    //
    //            let firstElement = dictionary.firstObject as? [String : Any]
    //            let venueResults = firstElement?["venue_results"] as? Array<[String : Any]>
    //            let lookupResults = firstElement?["lookup_results"] as? Array<[String : Any]>
    //
    //            try await Storage.withContext { ctx in
    //                var venues = Array<Venue>()
    //                if (venueResults != nil) {
    //                    for venueObject in venueResults! {
    //                        let venue = try Storage.upsertVenue(from: venueObject, in: ctx)
    //                        venues.append(venue)
    //                    }
    //                }
    //
    //            var lookups = Array<MerchantProductLink>()
    //            if (lookupResults != nil) {
    //                for lookupObject in lookupResults! {
    //                    let lookup = MerchantProductLink.init(map: lookupObject)
    //                    if (lookupObject["venues"] != nil) {
    //                        var venues = Array<Venue>()
    //                        for venue in lookupObject["venues"] as! Array<[String : Any]> {
    //                            let venue = try Storage.upsertVenue(from: venue, in: ctx)
    //                            venues.append(venue)
    //                        }
    //                        lookup.venues = venues
    //                    }
    //                    lookups.append(lookup)
    //                }
    //            }
    //            try ctx.save()
    //        }
    //
    ////            let WTB = WhereToBuy(links: lookups, venues: venues)
    ////
    ////            DispatchQueue.main.async {
    ////                onCompletion(WTB)
    ////            }
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    
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
        
        let tempProductId = PreferabliTools.generateRandomLongId()
        let tempVariantId = PreferabliTools.generateRandomLongId()
        
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
            
            let tempTagId = tag_id ?? PreferabliTools.generateRandomLongId()
            let tempVariantId = PreferabliTools.generateRandomLongId()
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

                Task.detached(priority: .background) { [weak self] in
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
            
            var needsRefresh = false
            
            try Storage.withContext { ctx in
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
                
                try Storage.withContext { ctx in
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
