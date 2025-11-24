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
    
    private static var _main: Preferabli?
    
    /// Use this instance to make Preferabli API calls.
    public static var main: Preferabli {
        guard let s = _main else { fatalError("Call Preferabli.initialize(_) first.") }
        return s
    }
    
    public static var storage: StorageFacade { StorageFacade() }
    
    internal static let versionCode = 12
    
    public let loggingEnabled : Bool
    internal let api : APIService
    internal let hasBeenInitialized : Bool
    
    internal var startupThreadRunning = false
    
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
    
    private var profileFetches = [Int: Task<Int, Error>]()
    
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
    static public func initialize(client_interface: String, integration_id : Int, logging_enabled : Bool = false) {
        Storage.getKeyStore().set(integration_id, forKey: "INTEGRATION_ID")
        Storage.getKeyStore().set(client_interface, forKey: "CLIENT_INTERFACE")
        Storage.getKeyStore().set(UIScreen.main.scale, forKey: "mainScale")
        
        guard _main == nil else { return }
        _main = Preferabli(logging_enabled: logging_enabled)
        
        Mixpanel.initialize(token: SDKConfig.mixpanelKey, trackAutomaticEvents: false, instanceName: "PreferabliDataSDK")
        Mixpanel.mainInstance().registerSuperProperties(["CLIENT_INTERFACE" : client_interface, "INTEGRATION_ID" : integration_id])
        
        PreferabliTools.addSDKProperties()
        
        Task.detached(priority: .high) {
            do {
                try await main.handleUpgrade()
                try await main.handleStartupActions()
            } catch {
                await main.handleError(error: error)
            }
        }
        
        Storage.pruneTombstones { message in
            if (logging_enabled) {
                print(message)
            }
        }
        
        Storage.reindexSearchableContent { message in
            if (logging_enabled) {
                print(message)
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
        try await Storage.reset()
        
        // clear HTTP cache
        await api.clearUrlCache()
        await api.refreshDefaults()
        
        let integration_id = Storage.getKeyStore().integer(forKey: "INTEGRATION_ID")
        let client_interface = Storage.getKeyStore().string(forKey: "CLIENT_INTERFACE")
        
        UserDefaults.standard.removePersistentDomain(forName: "Preferabli")
        
        Storage.getKeyStore().set(integration_id, forKey: "INTEGRATION_ID")
        Storage.getKeyStore().set(client_interface, forKey: "CLIENT_INTERFACE")
    }
    
    private func loadUserData() {
        if (Preferabli.isPreferabliUserLoggedIn() || Preferabli.isCustomerLoggedIn()) {
            Task.detached(priority: .background) {
                await CollectionLoader.shared.ensureWarm(BuiltInCollection.ratings)
                await CollectionLoader.shared.ensureWarm(BuiltInCollection.wishlist)
            }
        }
    }
    
    private func createAnonymousSession(create_anonymous_user: Bool) async throws {
        // already have a token? nothing to do
        if !Storage.getKeyStore().string(forKey: "access_token").isEmptyOrWhitespace { return }
        
        // 1) Create anonymous session (no token required)
        let params: SParams = ["login_as_anonymous": true]
        
        let sessionDTO: SessionDTO = try await api.getAlamo(requiresAccessToken: false).post(APIEndpoints.postSession, sjson: params)
        await sessionDTO.saveSession()
        
        // 2) Optionally create an anonymous user (typed POST + DTO upsert)
        if create_anonymous_user {
            let createParams: SParams = ["anonymous": true]
            
            let dto: PreferabliUserDTO = try await api.getAlamo().post(APIEndpoints.users, sjson: createParams)
            
            try Storage.withContext { ctx in
                let user = try Storage.upsertPreferabliUser(from: dto, in: ctx)
                try ctx.save()
                PreferabliTools.setUserProperties(user: user)
            }
            PreferabliTools.addSDKProperties()
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
    
    //
    //    /// Link an existing customer or create a new one if they are not in our system.
    //    /// - Parameters:
    //    ///   - merchant_customer_identification: unique identifier for your customer. Usually an email address or a phone number.
    //    ///   - merchant_customer_verification: authentication key given to you by your API.
    //    ///   - onCompletion: returns ``Customer`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func loginCustomer(merchant_customer_identification : String, merchant_customer_verification : String, onCompletion: @escaping (Int) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh, {
    //            await self.loginCustomerActual(merchant_customer_identification: merchant_customer_identification, merchant_customer_verification: merchant_customer_verification, onCompletion: onCompletion, onFailure: onFailure)
    //        })
    //    }
    //
    //    private func loginCustomerActual(
    //        merchant_customer_identification : String,
    //        merchant_customer_verification : String,
    //        onCompletion: @escaping (Int) -> (),
    //        onFailure: @escaping (PreferabliException) -> ()
    //    ) async {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: false)
    //            Analytics.track( ["event" : "login_customer"])
    //
    //            let parameters: [String: Any] = [
    //                "merchant_customer_identification": merchant_customer_identification,
    //                "merchant_customer_verification" : merchant_customer_verification,
    //                "merchant_channel_id"            : Preferabli.CHANNEL_ID
    //            ]
    //
    //            var sessionResponse = try Preferabli.api.getAlamo(requiresAccessToken: false)
    //                .post(APIEndpoints.postSession, json: parameters)
    //            sessionResponse = try await APIService.continueOrThrowPreferabliException(response: sessionResponse)
    //            let session = SessionData(map: try APIService.continueOrThrowJSONException(data: sessionResponse.data!) as! [String : Any])
    //
    //            var customerResponse = try Preferabli.api.getAlamo()
    //                .get(APIEndpoints.customer(id: Preferabli.CHANNEL_ID, customerId: session.customer_id!))
    //            customerResponse = try await APIService.continueOrThrowPreferabliException(response: customerResponse)
    //            let customerDictionary = try APIService.continueOrThrowJSONException(data: customerResponse.data!) as! [String : Any]
    //
    //            var customerId : Int? = nil
    //            try await Storage.withContext { ctx in
    //                let customer = try Storage.upsertCustomer(from: customerDictionary, in: ctx)
    //                customerId = customer.id
    //                try ctx.save()
    //            }
    //
    //            guard let idCopy = customerId else {
    //                throw PreferabliException(type: .DatabaseError)
    //            }
    //
    //            await MainActor.run {
    //                onCompletion(idCopy)
    //            }
    //
    //            loadUserData()
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    
    
    //    /// Get the current logged in ``Customer``.
    //    /// - Parameters:
    //    ///   - force_refresh: pass true if you want to force a refresh from the API and wait for the results to return. Otherwise, the call will load locally if available and run a background refresh only if one has not been initiated in the past 5 minutes. Defaults to *false*.
    //    ///   - onCompletion: returns ``Customer`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func getCustomer(
    //        force_refresh : Bool = false,
    //        onCompletion: @escaping (Customer) -> () = {_ in },
    //        onFailure: @escaping (PreferabliException) -> () = {_ in }
    //    ) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh) {
    //            await self.getCustomerActual(force_refresh: force_refresh, onCompletion: onCompletion, onFailure: onFailure)
    //        }
    //    }
    //
    //    private func getCustomerActual(
    //        force_refresh : Bool,
    //        onCompletion: @escaping (Customer) -> (),
    //        onFailure: @escaping (PreferabliException) -> ()
    //    ) async {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: true)
    //            guard Preferabli.isCustomerLoggedIn() else {
    //                throw PreferabliException(type: .OtherError, message: "No customer found. Are you sure there is a customer logged in?")
    //            }
    //
    //            Analytics.track( ["event" : "get_customer"])
    //
    //            // Force refresh fetches from API and upserts
    //            if force_refresh || PreferabliTools.hasMinutesPassed(minutes: 5, startDate: Storage.getKeyStore().object(forKey: "lastCalledCustomer") as? Date) {
    //                var customerResponse = try Preferabli.api.getAlamo()
    //                    .get(APIEndpoints.customer(id: Preferabli.CHANNEL_ID, customerId: PreferabliTools.getCustomerId()))
    //                customerResponse = try await APIService.continueOrThrowPreferabliException(response: customerResponse)
    //                let customerDictionary = try APIService.continueOrThrowJSONException(data: customerResponse.data!) as! [String : Any]
    //                try await Storage.withContext { ctx in
    //                    let _ = try Storage.upsertCustomer(from: customerDictionary, in: ctx)
    //                    try ctx.save()
    //                }
    //                Storage.getKeyStore().set(Date(), forKey: "lastCalledCustomer")
    //            }
    //
    //            // Local read
    //            let id = PreferabliTools.getCustomerId()
    //            try await Storage.withContext { ctx in
    //                guard let customer = try Storage.fetchById(Customer.self, id: id, in: ctx) else {
    //                    throw PreferabliException(type: .MappingNotFound)
    //                }
    //            }
    //
    //            DispatchQueue.main.async { onCompletion(customer) }
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    //
    
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
            
            var sessionDTO: SessionDTO = try await api.getAlamo(requiresAccessToken: false).post(APIEndpoints.postSession, sjson: params)
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
            
            try Storage.withContext { ctx in
                let user = try Storage.upsertPreferabliUser(from: dto, in: ctx)
                try ctx.save()
                PreferabliTools.setUserProperties(user: user)
            }
            
            PreferabliTools.addSDKProperties()
            loadUserData()
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    
    
    //    /// Signup a new Preferabli user. Most SDK installations will never use this.
    //    /// - Parameters:
    //    ///   - email: user's email address.
    //    ///   - password: user's password.
    //    ///   - user_claim_code: use if the user has previous ratings tied to a claim code. Defaults to *nil*.
    //    ///   - cellar_name: changes the name of the user's default first cellar. Defaults to *nil*.
    //    ///   - onCompletion: returns ``PreferabliUser`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func signupPreferabliUser(email : String, password : String, user_claim_code : String? = nil, cellar_name : String? = nil, onCompletion: @escaping (PreferabliUser) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh, {
    //            self.signupPreferabliUserActual(email: email, password: password, user_claim_code: user_claim_code,  cellar_name: cellar_name, onCompletion: onCompletion, onFailure: onFailure)
    //        })
    //    }
    //
    //    private func signupPreferabliUserActual(
    //        email: String,
    //        password: String,
    //        user_claim_code: String?,
    //        cellar_name: String?,
    //        onCompletion: @escaping (PreferabliUser) -> (),
    //        onFailure: @escaping (PreferabliException) -> ()
    //    ) async {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: false)
    //
    //            Analytics.track( ["event" : "signup_user"])
    //
    //            // Build payload
    //            var parameters: [String: Any] = ["email": email, "password": password, "subscribed": 1]
    //            if !PreferabliTools.isNullOrWhitespace(string: user_claim_code) {
    //                parameters["use_user_claim_code"] = user_claim_code
    //            }
    //            if !PreferabliTools.isNullOrWhitespace(string: cellar_name) {
    //                parameters["cellar_name"] = cellar_name
    //            }
    //
    //            // Create account (no token required)
    //            var userResponse = try Preferabli.api
    //                .getAlamo(requiresAccessToken: false)
    //                .post(APIEndpoints.users, json: parameters)
    //            userResponse = try await APIService.continueOrThrowPreferabliException(response: userResponse)
    //            let userDictionary = try APIService.continueOrThrowJSONException(data: userResponse.data!) as! [String: Any]
    //
    //            // Persist & return SwiftData user
    //            let ctx = await Preferabli.storage.newContext()
    //            let user = try Storage.upsertPreferabliUser(from: userDictionary, in: ctx)
    //            try ctx.save()
    //
    //            DispatchQueue.main.async { onCompletion(user) }
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    //
    /// Logout a customer or a user.
    public func logout() async throws {
        do {
            try await canWeContinue(needsToBeLoggedIn: true)
            
            Analytics.track( ["event" : "logout"])
            
            try await PreferabliTools.logout()
            
            try await clearAllData()
            
            try await createAnonymousSession(create_anonymous_user: isInternal())
            
        } catch {
            handleError(error: error)
            throw error
        }
    }
    //
    //    /// Resets the password of an existing Preferabli user. Most SDK installations will never use this.
    //    /// - Parameters:
    //    ///   - email: user's email address.
    //    ///   - onCompletion: returns if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func forgotPassword(email : String, onCompletion: @escaping () -> () = { }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh, {
    //            self.forgotPasswordActual(email: email, onCompletion: onCompletion, onFailure: onFailure)
    //        })
    //    }
    //
    //    private func forgotPasswordActual(email : String, onCompletion: @escaping () -> (), onFailure: @escaping (PreferabliException) -> ()) {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: false)
    //
    //            Analytics.track( ["event" : "forgot_password"])
    //
    //            let parameters = ["email": email]
    //
    //            var forgotResponse = try Preferabli.api.getAlamo(requiresAccessToken: false).get(APIEndpoints.resetPassword, params: parameters)
    //            forgotResponse = try await APIService.continueOrThrowPreferabliException(response: forgotResponse)
    //
    //            DispatchQueue.main.async {
    //                onCompletion()
    //            }
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    //
    //    /// Performs label recognition on a supplied image. Returns any ``Product`` matches.
    //    /// - Parameters:
    //    ///   - image: label image you want to search for.
    //    ///   - include_merchant_links: pass true if you want the results to include an array of ``MerchantProductLink`` embedded in ``Variant``. These connect Preferabli products to your own. Passing true requires additional resources and therefore will take longer. Defaults to *true*.
    //    ///   - onCompletion: returns ``Media``, \[``LabelRecResult``\] if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func labelRecognition(image : UIImage, include_merchant_links: Bool = true, onCompletion: @escaping (Media, [LabelRecResult]) -> () = {_,_  in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh, {
    //            self.labelRecognitionActual(image: image, include_merchant_links: include_merchant_links, onCompletion: onCompletion, onFailure: onFailure)
    //        })
    //    }
    //
    //    private func labelRecognitionActual(
    //        image : UIImage,
    //        include_merchant_links: Bool,
    //        onCompletion: @escaping (Media, [LabelRecResult]) -> (),
    //        onFailure: @escaping (PreferabliException) -> ()
    //    ) async {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: false)
    //            Analytics.track( ["event" : "label_rec"])
    //
    //            let resizedImage = PreferabliTools.resizeImage(image: image, newDimension: 1000)!
    //            let imageData = resizedImage.jpegData(compressionQuality: 0.60)!
    //
    //            var mediaResponse = try Preferabli.api.getAlamo().syncUpload(url: APIEndpoints.postMedia, data: imageData)
    //            mediaResponse = try await APIService.continueOrThrowPreferabliException(response: mediaResponse)
    //            let imageDictionary = try APIService.continueOrThrowJSONException(data: mediaResponse.data!)
    //
    //            let ctx = await Preferabli.storage.newContext()
    //            let media = try Storage.upsertMedia(from: imageDictionary, in: ctx)
    //
    //            var imageRecResponse = try Preferabli.api.getAlamo().get(APIEndpoints.imageRec, params: ["media_id" : media.id])
    //            imageRecResponse = try await APIService.continueOrThrowPreferabliException(response: imageRecResponse)
    //            let imageRecDictionaries = try APIService.continueOrThrowJSONException(data: imageRecResponse.data!) as! [[String : Any]]
    //
    //            var results = [LabelRecResult]()
    //            var products = [Product]()
    //            for rec in imageRecDictionaries {
    //                let p = try Storage.upsertProduct(from: rec["product"] as! [String : Any], in: ctx)
    //                products.append(p)
    //                results.append(LabelRecResult(score: rec["score"] as! NSNumber, product: p))
    //            }
    //            try ctx.save()
    //
    //            if include_merchant_links {
    //                try await addMerchantDataToProducts(products: products)
    //            }
    //
    //            DispatchQueue.main.async { onCompletion(media, results) }
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    //

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
    
    
    
    //    /// Get rated products. Customer must be logged in to run this call.
    //    /// - Parameters:
    //    ///   - force_refresh: pass true if you want to force a refresh from the API and wait for the results to return. Otherwise, the call will load locally if available and run a background refresh only if one has not been initiated in the past 5 minutes. Defaults to *false*.
    //    ///   - include_merchant_links: pass true if you want the results to include an array of ``MerchantProductLink`` embedded in ``Variant``. These connect Preferabli products to your own. Passing true requires additional resources and therefore will take longer. Defaults to *true*.
    //    ///   - onCompletion: returns an array of ``Product`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func getRatedProducts(force_refresh : Bool = false, include_merchant_links: Bool = true, onCompletion: @escaping ([Product]) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        getRatedProducts(force_refresh: force_refresh, include_merchant_links: include_merchant_links, priority: .veryHigh, onCompletion: onCompletion, onFailure: onFailure)
    //    }
    //
    //    internal func getRatedProducts(force_refresh : Bool = false, include_merchant_links: Bool = true, priority : Operation.QueuePriority = .veryHigh, onCompletion: @escaping ([Product]) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: priority, {
    //
    //            do {
    //                try await canWeContinue(needsToBeLoggedIn: true)
    //                Analytics.track( ["event" : "get_rated_products"])
    //
    //                let products : Array<Product>
    //                if (Preferabli.isPreferabliUserLoggedIn()) {
    //                    products = try self.getProductsInCollection(priority: priority, force_refresh: force_refresh, collection_id:  Storage.getKeyStore().integer(forKey: "ratings_id"))
    //                } else {
    //                    products = try self.getCustomerTagProducts(force_refresh: force_refresh, tag_type: "rating")
    //                }
    //
    //                if (include_merchant_links) {
    //                    try self.addMerchantDataToProducts(products: products)
    //                }
    //
    //                DispatchQueue.main.async {
    //                    onCompletion(products)
    //                }
    //
    //            } catch {
    //                self.handleError(error: error, onFailure: onFailure)
    //            }
    //        })
    //    }
    //
    //    /// Get wishlisted products. Customer must be logged in to run this call.
    //    /// - Parameters:
    //    ///   - force_refresh: pass true if you want to force a refresh from the API and wait for the results to return. Otherwise, the call will load locally if available and run a background refresh only if one has not been initiated in the past 5 minutes. Defaults to *false*.
    //    ///   - include_merchant_links: pass true if you want the results to include an array of ``MerchantProductLink`` embedded in ``Variant``. These connect Preferabli products to your own. Passing true requires additional resources and therefore will take longer. Defaults to *true*.
    //    ///   - onCompletion: returns an array of ``Product`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func getWishlistedProducts(force_refresh : Bool = false, include_merchant_links: Bool = true, onCompletion: @escaping ([Product]) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        getWishlistedProducts(force_refresh: force_refresh, include_merchant_links: include_merchant_links, priority: .veryHigh, onCompletion: onCompletion, onFailure: onFailure)
    //    }
    //
    //    internal func getWishlistedProducts(force_refresh : Bool = false, include_merchant_links: Bool = true, priority : Operation.QueuePriority = .veryHigh, onCompletion: @escaping ([Product]) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: priority, {
    //            do {
    //                try await canWeContinue(needsToBeLoggedIn: true)
    //                Analytics.track( ["event" : "get_wishlist_products"])
    //
    //                let products : Array<Product>
    //                if (Preferabli.isPreferabliUserLoggedIn()) {
    //                    products = try self.getProductsInCollection(priority: priority, force_refresh: force_refresh, collection_id: Storage.getKeyStore().integer(forKey: "wishlist_id"))
    //                } else {
    //                    products = try self.getCustomerTagProducts(force_refresh: force_refresh, tag_type: "wishlist")
    //                }
    //
    //                if (include_merchant_links) {
    //                    try self.addMerchantDataToProducts(products: products)
    //                }
    //
    //                DispatchQueue.main.async {
    //                    onCompletion(products)
    //                }
    //
    //            } catch {
    //                self.handleError(error: error, onFailure: onFailure)
    //            }
    //        })
    //    }
    //
    //    /// Get purchased products. Customer must be logged in to run this call.
    //    /// - Parameters:
    //    ///   - force_refresh: pass true if you want to force a refresh from the API and wait for the results to return. Otherwise, the call will load locally if available and run a background refresh only if one has not been initiated in the past 5 minutes. Defaults to *false*.
    //    ///   - lock_to_integration: pass true if you only want to draw results from your integration. Defaults to *true*.
    //    ///   - include_merchant_links: pass true if you want the results to include an array of ``MerchantProductLink`` embedded in ``Variant``. These connect Preferabli products to your own. Passing true requires additional resources and therefore will take longer. Defaults to *true*.
    //    ///   - onCompletion: returns an array of ``Product`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func getPurchasedProducts(force_refresh : Bool = false, lock_to_integration : Bool = true, include_merchant_links: Bool = true, onCompletion: @escaping ([Product]) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        getPurchasedProducts(force_refresh: force_refresh, lock_to_integration: lock_to_integration, include_merchant_links: include_merchant_links, priority: .veryHigh, onCompletion: onCompletion, onFailure: onFailure)
    //    }
    //
    //    internal func getPurchasedProducts(force_refresh : Bool = false, lock_to_integration : Bool = true, include_merchant_links: Bool = true, priority : Operation.QueuePriority = .veryHigh, onCompletion: @escaping ([Product]) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: priority, {
    //            do {
    //                try await canWeContinue(needsToBeLoggedIn: true)
    //                Analytics.track( ["event" : "get_purchase_history"])
    //
    //                let products : Array<Product>
    //                if (Preferabli.isPreferabliUserLoggedIn()) {
    //                    products = try PreferabliUserTools.sharedInstance.getPurchaseHistory(priority: priority, forceRefresh: force_refresh, lock_to_integration: lock_to_integration)
    //                } else {
    //                    products = try self.getCustomerTagProducts(force_refresh: force_refresh, tag_type: "purchase")
    //                }
    //
    //                if (include_merchant_links) {
    //                    try self.addMerchantDataToProducts(products: products)
    //                }
    //
    //                onCompletion(products)
    //
    //            } catch {
    //                self.handleError(error: error, onFailure: onFailure)
    //            }
    //        })
    //    }
    //
    //    private func getProductsInCollection(
    //        priority : Operation.QueuePriority,
    //        force_refresh : Bool,
    //        collection_id : Int
    //    ) async throws -> [Product] {
    //        try await canWeContinue(needsToBeLoggedIn: true)
    //
    //        if force_refresh || !Storage.getKeyStore().bool(forKey: "hasLoaded\(collection_id)") {
    //            try LoadCollectionTools.sharedInstance.loadCollectionViaTags(
    //                priority: priority, force_refresh: force_refresh, collection_id: collection_id
    //            )
    //        } else if PreferabliTools.hasMinutesPassed(minutes: 5, startDate: Storage.getKeyStore().object(forKey: "lastCalled\(collection_id)") as? Date) {
    //            PreferabliTools.startNewAsyncWorkThread(priority: .low) {
    //                try? LoadCollectionTools.sharedInstance.loadCollectionViaTags(
    //                    priority: .low, force_refresh: false, collection_id: collection_id
    //                )
    //            }
    //        }
    //
    //        let ctx = await Preferabli.storage.newContext()
    //        let pred = #Predicate<Product> { p in
    //            p.variants.contains { v in
    //                v.tags.contains { t in t.collection_id == collection_id }
    //            }
    //        }
    //        return try ctx.fetch(FetchDescriptor<Product>(predicate: pred))
    //    }
    //
    //    private func getCustomerTagProducts(force_refresh : Bool, tag_type : String?) async throws -> [Product]  {
    //        try await canWeContinue(needsToBeLoggedIn: true)
    //
    //        if (force_refresh || !Storage.getKeyStore().bool(forKey: "hasLoaded" + (tag_type ?? "AllCustomerTags"))) {
    //            try self.getCustomerTagProductsActual(tag_type: tag_type)
    //        } else if PreferabliTools.hasMinutesPassed(minutes: 5, startDate: Storage.getKeyStore().object(forKey: "lastCalled" + (tag_type ?? "AllCustomerTags")) as? Date) {
    //            PreferabliTools.startNewAsyncWorkThread(priority: .low) {
    //                try? self.getCustomerTagProductsActual(tag_type: tag_type)
    //            }
    //        }
    //
    //        let ctx = await Preferabli.storage.newContext()
    //        let customerId = PreferabliTools.getCustomerId()
    //
    //        let pred: Predicate<Product>
    //        if let tag_type {
    //            pred = #Predicate<Product> { p in
    //                p.variants.contains { v in
    //                    v.tags.contains { t in (t.customer_id == customerId) && (t.type == tag_type) }
    //                }
    //            }
    //        } else {
    //            pred = #Predicate<Product> { p in
    //                p.variants.contains { v in
    //                    v.tags.contains { t in t.customer_id == customerId }
    //                }
    //            }
    //        }
    //        return try ctx.fetch(FetchDescriptor<Product>(predicate: pred))
    //    }
    //
    //    private func getCustomerTagProductsActual(tag_type : String?) async throws {
    //        var params: [String: Any] = ["offset": 0, "limit": 9999]
    //        if let tag_type { params["tag_type"] = tag_type }
    //
    //        var getTagsResponse = try Preferabli.api.getAlamo()
    //            .get(APIEndpoints.customerTags(id: Preferabli.CHANNEL_ID, and: PreferabliTools.getCustomerId()), params: params)
    //        getTagsResponse = try await APIService.continueOrThrowPreferabliException(response: getTagsResponse)
    //
    //        let tagDictionaries = try APIService.continueOrThrowJSONException(data: getTagsResponse.data!) as! [[String: Any]]
    //        let ctx = await Preferabli.storage.newContext()
    //
    //        // Group tags by variant id
    //        var tagMap = [Int: [Tag]]()
    //        for td in tagDictionaries {
    //            let vid = (td["variant_id"] as! NSNumber).intValue
    //            // Create SwiftData Tag minimally; your upsertTag helper can replace this if you have one
    //            let tag = try Storage.upsertTag(from: td, in: ctx)
    //            ctx.insert(tag)
    //            tagMap[vid, default: []].append(tag)
    //        }
    //
    //        // Pull products for these variant ids
    //        let variantIds = Array(tagMap.keys)
    //        var getProductsResponse = try Preferabli.api.getAlamo()
    //            .get(APIEndpoints.products, params: ["variant_ids" : variantIds])
    //        getProductsResponse = try await APIService.continueOrThrowPreferabliException(response: getProductsResponse)
    //        let productDictionaries = try APIService.continueOrThrowJSONException(data: getProductsResponse.data!) as! [[String : Any]]
    //
    //        for pd in productDictionaries {
    //            let p = try Storage.upsertProduct(from: pd, in: ctx)
    //            // attach tags to matching variants if you keep Tag as a relationship on Variant
    //            for v in p.variants {
    //                if let tags = tagMap[v.id] {
    //                    v.tags = tags
    //                }
    //            }
    //        }
    //
    //        try ctx.save()
    //        Storage.getKeyStore().set(Date(), forKey: "lastCalled" + (tag_type ?? "AllCustomerTags"))
    //        Storage.getKeyStore().set(true,   forKey: "hasLoaded" + (tag_type ?? "AllCustomerTags"))
    //    }
    //
    //    /// Get all the questions and choices needed to run a Guided Rec. Present the questions to the user, then pass the answers to ``Preferabli/getGuidedRecResults(guided_rec_id:selected_choice_ids:price_min:price_max:collection_id:include_merchant_links:onCompletion:onFailure:)`` to get results.
    //    /// - Parameters:
    //    ///   - guided_rec_id: id of the Guided Rec you wish to run. See ``GuidedRec`` for all the default Guided Rec options. Defaults to ``GuidedRec/WINE_DEFAULT``.
    //    ///   - onCompletion: returns ``GuidedRec`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func getGuidedRec(guided_rec_id: Int = GuidedRec.WINE_DEFAULT, onCompletion: @escaping (GuidedRec) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh, {
    //            self.getGuidedRecActual(guided_rec_id: guided_rec_id, onCompletion: onCompletion, onFailure: onFailure)
    //        })
    //    }
    //
    //    private func getGuidedRecActual(guided_rec_id: Int, onCompletion: @escaping (GuidedRec) -> (), onFailure: @escaping (PreferabliException) -> ()) async {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: false)
    //
    //            Analytics.track( ["event" : "get_guided_rec"])
    //
    //            var instantRecResponse = try Preferabli.api.getAlamo().get(APIEndpoints.guidedRec(id: guided_rec_id))
    //            instantRecResponse = try await APIService.continueOrThrowPreferabliException(response: instantRecResponse)
    //            let dictionary = try APIService.continueOrThrowJSONException(data: instantRecResponse.data!) as! [String : Any]
    //            let quiz = GuidedRec(map: dictionary)
    //
    //            DispatchQueue.main.async {
    //                onCompletion(quiz)
    //            }
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    //
    //    /// Get Guided Rec results based on the selected ``GuidedRecChoice``.
    //    /// - Parameters:
    //    ///   - guided_rec_id: id of the Guided Rec you wish to run.
    //    ///   - selected_choice_ids: an array of selected ``GuidedRecChoice`` ids.
    //    ///   - price_min: pass if you want to lock results to a minimum price. Defaults to *nil*.
    //    ///   - price_max: pass if you want to lock results to a maximum price. Defaults to *nil*.
    //    ///   - collection_id: the id of a specific ``Collection`` that you want to draw results from. Defaults to ``PRIMARY_INVENTORY_ID``. Pass *nil* for results from anywhere.
    //    ///   - include_merchant_links: pass true if you want the results to include an array of ``MerchantProductLink`` embedded in ``Variant``. These connect Preferabli products to your own. Passing true requires additional resources and therefore will take longer. Defaults to *true*.
    //    ///   - onCompletion: returns an array of ``Product`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func getGuidedRecResults(guided_rec_id: Int, selected_choice_ids : Array<Int>, price_min : Int? = nil, price_max : Int? = nil, collection_id : Int? = Preferabli.PRIMARY_INVENTORY_ID, include_merchant_links: Bool = true, onCompletion: @escaping ([Int]) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh, {
    //            await self.getGuidedRecResultsActual(guided_rec_id: guided_rec_id, selected_choice_ids: selected_choice_ids, price_min: price_min, price_max: price_max, collection_id: collection_id, include_merchant_links: include_merchant_links, onCompletion: onCompletion, onFailure: onFailure)
    //        })
    //    }
    //
    //    private func getGuidedRecResultsActual(
    //        guided_rec_id: Int,
    //        selected_choice_ids : Array<Int>,
    //        price_min : Int?,
    //        price_max : Int?,
    //        collection_id : Int?,
    //        include_merchant_links: Bool,
    //        onCompletion: @escaping ([Int]) -> (),
    //        onFailure: @escaping (PreferabliException) -> ()
    //    ) async {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: false)
    //            Analytics.track( ["event" : "get_guided_rec_results"])
    //
    //            var payload: [String : Any] = [
    //                "limit": 8,
    //                "sort_by": "preference",
    //                "questionnaire_id": guided_rec_id,
    //                "offset": 0,
    //                "questionnaire_choice_ids": selected_choice_ids
    //            ]
    //            var filters = [[String: Any]]()
    //            if let price_min { filters.append(["key":"price_min","value":price_min]) }
    //            if let price_max { filters.append(["key":"price_max","value":price_max]) }
    //            payload["filters"] = filters
    //
    //            var recResponse = try Preferabli.api.getAlamo().post(
    //                collection_id == nil ? APIEndpoints.guidedRecResults() : APIEndpoints.guidedRecResults(id: collection_id!),
    //                json: payload
    //            )
    //            recResponse = try await APIService.continueOrThrowPreferabliException(response: recResponse)
    //            let recDictionary = try APIService.continueOrThrowJSONException(data: recResponse.data!) as! [String : Any]
    //
    //            // Gather variant_ids and prediction map
    //            var variantIds = [Int]()
    //            var predictedByVariant = [Int: Int]() // variant_id -> formatted_predict_rating
    //            if let types = recDictionary["types"] as? [[String: Any]] {
    //                for type in types {
    //                    if let results = type["results"] as? [[String: Any]] {
    //                        for r in results {
    //                            if let vid = (r["variant_id"] as? NSNumber)?.intValue {
    //                                variantIds.append(vid)
    //                                if let wili = r["formatted_predict_rating"] as? Int {
    //                                    predictedByVariant[vid] = wili
    //                                }
    //                            }
    //                        }
    //                    }
    //                }
    //            }
    //
    //            // Pull products for these variants, then upsert to SwiftData
    //            var getProductsResponse = try Preferabli.api.getAlamo().get(APIEndpoints.products, params: ["variant_ids" : variantIds])
    //            getProductsResponse = try await APIService.continueOrThrowPreferabliException(response: getProductsResponse)
    //            let productDictionaries = try APIService.continueOrThrowJSONException(data: getProductsResponse.data!) as! [[String : Any]]
    //
    //            var productsToReturn = [Product]()
    //            var productIds = [Int]()
    //
    //            try await Storage.withContext { ctx in
    //                for pd in productDictionaries {
    //                    let p = try Storage.upsertProduct(from: pd, in: ctx)
    //
    //                    // Attach prediction per matching variant
    //                    for v in p.variants {
    //                        if let pr = predictedByVariant[v.id] {
    //                            v.preference_data = PreferenceData(
    //                                title: nil, details: nil, confidence_code: nil, formatted_predict_rating: pr
    //                            )
    //                        }
    //                    }
    //                    productsToReturn.append(p)
    //                }
    //
    //                try ctx.save()
    //            }
    //
    ////            if include_merchant_links {
    ////                try await addMerchantDataToProducts(products: productsToReturn)
    ////            }
    //
    //            await MainActor.run { onCompletion(productIds) }
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    
    //            // --- 3) Merchant links (network OFF-main, apply ON-main) ---
    //            if include_merchant_links, !variantIDs.isEmpty {
    //                let linksByVariant = try await fetchMerchantLinks(for: Array(variantIDs))
    //
    //                try await Storage.withContext { ctx in
    //                    // Fetch the variants we need by id and apply links
    //                    let ids = Array(variantIDs)
    //                    var fd = FetchDescriptor<Variant>(
    //                        predicate: #Predicate<Variant> { ids.contains($0.id) }
    //                    )
    //                    let variants = try ctx.fetch(fd)
    //                    for v in variants {
    //                        if let links = linksByVariant[v.id] {
    //                            v.merchant_links = links
    //                        }
    //                    }
    //                    try ctx.save()
    //                }
    //            }
    
    
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
            
            var productIDs: [Int] = []
            var variantIDs = Set<Int>()
            
            try Storage.withContext { ctx in
                productIDs.reserveCapacity(body.results.count)
                
                for item in body.results {
                    let product = try Storage.upsertProduct(from: item.product, in: ctx)
                    let preference_data = PreferenceData(product: product)
                    
                    if let rating = item.formatted_predict_rating {
                        let preferenceDataDTO = PreferenceDataDTO(formatted_predict_rating: rating)
                        try Storage.upsertPreferenceData(from: preferenceDataDTO, for: product, in: ctx)
                    }
                    
                    for v in product.variants { variantIDs.insert(v.id) }
                    productIDs.append(product.id)
                }
                
                try ctx.save()
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
    
    
    //    /// Fetch merchant links for a set of variant IDs (NETWORK ONLY).
    //    private func fetchMerchantLinks(for variantIDs: [Int]) async throws -> [Int: [MerchantProductLink]] {
    //        if variantIDs.isEmpty { return [:] }
    //
    //        // Build the request payload (one entry per variant id, matching your existing API)
    //        var payload: [[String: Any]] = []
    //        payload.reserveCapacity(variantIDs.count)
    //        for vid in variantIDs {
    //            payload.append([
    //                "number": vid,
    //                "variant_ids": [vid]
    //            ])
    //        }
    //
    //        var response = try Preferabli.api.getAlamo()
    //            .post(APIEndpoints.lookupConversion(id: Preferabli.INTEGRATION_ID), jsonObject: payload)
    //        response = try await APIService.continueOrThrowPreferabliException(response: response)
    //
    //        let arr = try APIService.continueOrThrowJSONException(data: response.data!) as! [[String: Any]]
    //
    //        // Build a Sendable dictionary: variantID -> [MerchantProductLink]
    //        var result: [Int: [MerchantProductLink]] = [:]
    //        result.reserveCapacity(arr.count)
    //
    //        for item in arr {
    //            guard
    //                let variantID = item["number"] as? Int,
    //                let lookups = item["lookups"] as? [[String: Any]]
    //            else { continue }
    //
    //            var links: [MerchantProductLink] = []
    //            links.reserveCapacity(lookups.count)
    //            for lk in lookups {
    //                links.append(MerchantProductLink(map: lk))
    //            }
    //            result[variantID] = links
    //        }
    //
    //        return result
    //    }
    
    //
    //
    //    /// Call this to convert your merchant product / variant id to the Preferabli product id for use with our functions.
    //    /// - Parameters:
    //    ///   - merchant_product_id: the id of your product (as it appears in your system). *Either this or merchant_variant_id is required.*
    //    ///   - merchant_variant_id: the id of your product variant (as it appears in your system). *Used only if you have a hierarchical database format for your products.*
    //    ///   - onCompletion: returns product id if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func getPreferabliProductId(merchant_product_id : String? = nil, merchant_variant_id : String? = nil, onCompletion: @escaping (Int) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh, {
    //            await self.getPreferabliProductIdActual(merchant_product_id: merchant_product_id, merchant_variant_id: merchant_variant_id, onCompletion: onCompletion, onFailure: onFailure)
    //        })
    //    }
    //
    //    private func getPreferabliProductIdActual(merchant_product_id : String?, merchant_variant_id : String?, onCompletion: @escaping (Int) -> (), onFailure: @escaping (PreferabliException) -> ()) async {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: false)
    //
    //            if (merchant_product_id == nil && merchant_variant_id == nil) {
    //                throw PreferabliException.init(type: .MappingNotFound)
    //            }
    //
    //            Analytics.track( ["event" : "get_preferabli_id"])
    //
    //            var dictionaries = Array<[String : Any]>()
    //
    //            var dictionary = [String : Any]()
    //            dictionary["number"] = 1
    //            if (merchant_product_id != nil) {
    //                dictionary["merchant_product_ids"] = [merchant_product_id!]
    //            }
    //            if (merchant_variant_id != nil) {
    //                dictionary["merchant_variant_ids"] = [merchant_variant_id!]
    //            }
    //            dictionaries.append(dictionary)
    //
    //            var conversionResponse = try Preferabli.api.getAlamo().post(APIEndpoints.lookupConversion(id: Preferabli.INTEGRATION_ID), jsonObject: dictionaries)
    //            conversionResponse = try await APIService.continueOrThrowPreferabliException(response: conversionResponse)
    //            let conversionDictionaries = try APIService.continueOrThrowJSONException(data: conversionResponse.data!) as! Array<[String : Any]>
    //            for dictionary in conversionDictionaries {
    //                let lookups = dictionary["lookups"] as! Array<[String : Any]>
    //                if (lookups.count > 0) {
    //                    let lookup = lookups[0]
    //                    DispatchQueue.main.async {
    //                        onCompletion((lookup["product_id"] as! Int))
    //                    }
    //                    return
    //                }
    //            }
    //
    //            throw PreferabliException.init(type: .MappingNotFound)
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    //
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
    //
    //    /// Get the Preference Profile of the customer. Customer must be logged in to run this call.
    //    /// - Parameters:
    //    ///   - force_refresh: pass true if you want to force a refresh from the API and wait for the results to return. Otherwise, the call will load locally if available and run a background refresh only if one has not been initiated in the past 5 minutes. Defaults to *false*.
    //    ///   - onCompletion: returns ``Profile`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func getProfile(force_refresh : Bool = false, onCompletion: @escaping (Int) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh, {
    //            await self.getProfileActual(force_refresh: force_refresh, onCompletion: onCompletion, onFailure: onFailure)
    //        })
    //    }
    //
    //    private func getProfileActual(
    //        force_refresh: Bool = false,
    //        onCompletion: @escaping (Int) -> () = { _ in },
    //        onFailure: @escaping (PreferabliException) -> ()  = { _ in }
    //    ) async {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: true)
    //            Analytics.track( ["event" : "get_profile"])
    //
    //            // Refresh now if needed
    //            let ks = Storage.getKeyStore()
    //            let hasLoaded = ks.bool(forKey: "hasLoadedProfile")
    //            if force_refresh || !hasLoaded {
    //                try await getProfileActual(force_refresh: force_refresh)
    //            } else if PreferabliTools.hasMinutesPassed(minutes: 5, startDate: ks.object(forKey: "lastCalledProfile") as? Date) {
    //                PreferabliTools.startNewAsyncWorkThread(priority: .low) {
    //                    do {
    //                        try await self.getProfileActual(force_refresh: false)
    //                    } catch {
    //                        if Preferabli.loggingEnabled { print(error) }
    //                    }
    //                }
    //            }
    //
    //            var profileId : Int? = nil
    //            try await Storage.withContext { ctx in
    //                let lookingForCustomer = Preferabli.isCustomerLoggedIn()
    //                let targetId = lookingForCustomer ? PreferabliTools.getCustomerId() : PreferabliTools.getPreferabliUserId()
    //
    //                let profile: Profile? = {
    //                    if lookingForCustomer {
    //                        var fd = FetchDescriptor<Profile>(predicate: #Predicate<Profile> { $0.customer_id == targetId })
    //                        fd.fetchLimit = 1
    //                        return try? ctx.fetch(fd).first
    //                    } else {
    //                        var fd = FetchDescriptor<Profile>(predicate: #Predicate<Profile> { $0.user_id == targetId })
    //                        fd.fetchLimit = 1
    //                        return try? ctx.fetch(fd).first
    //                    }
    //                }()
    //
    //                guard let profile else {
    //                    throw PreferabliException(type: .DatabaseError)
    //                }
    //
    //                profileId = profile.id
    //            }
    //
    //            try await canWeContinue(needsToBeLoggedIn: true)
    //
    //            guard let idCopy = profileId else {
    //                throw PreferabliException(type: .DatabaseError)
    //            }
    //
    //            await MainActor.run {
    //                onCompletion(idCopy)
    //            }
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    //
    //
    //    private func getProfileActual(force_refresh: Bool) async throws {
    //        // 1) Fetch JSON
    //        var resp = try Preferabli.api.getAlamo().get(
    //            Preferabli.isCustomerLoggedIn()
    //            ? APIEndpoints.customerProfile(id: Preferabli.CHANNEL_ID, and: PreferabliTools.getCustomerId())
    //            : APIEndpoints.profile(id: PreferabliTools.getPreferabliUserId())
    //        )
    //        resp = try await APIService.continueOrThrowPreferabliException(response: resp)
    //        guard let profileJSON = try APIService.continueOrThrowJSONException(data: resp.data!) as? [String: Any]
    //        else { throw PreferabliException(type: .MappingNotFound) }
    //
    //        // 2) Upsert profile + preference styles
    //        try await Storage.withContext { ctx in
    //            let profile = try Storage.upsertProfile(from: profileJSON, in: ctx)
    //            profile.customer_id = PreferabliTools.getCustomerId()
    //            profile.user_id     = PreferabliTools.getPreferabliUserId()
    //
    //            var styleIdsToFetch: [Int] = []
    //            var prefMapByStyleId: [Int: ProfileStyle] = [:]
    //
    //            if let prefStyles = profileJSON["preference_styles"] as? [[String: Any]] {
    //                for psJSON in prefStyles {
    //                    let ps = try Storage.upsertProfileStyle(from: psJSON, in: ctx)
    //                    ps.profile = profile
    //                    if let sid = ps.style_id, sid != 0 {
    //                        if force_refresh || ((try? Storage.fetchById(Style.self, id: sid, in: ctx)) == nil) {
    //                            styleIdsToFetch.append(sid)
    //                            prefMapByStyleId[sid] = ps
    //                        } else if let s = try Storage.fetchById(Style.self, id: sid, in: ctx) {
    //                            ps.style = s
    //                        }
    //                    }
    //                }
    //            }
    //
    //            // 3) Fetch any missing styles and wire them up
    //            if !styleIdsToFetch.isEmpty {
    //                var stylesResp = try Preferabli.api.getAlamo().get(APIEndpoints.styles,
    //                                                                   params: ["style_ids": styleIdsToFetch])
    //                stylesResp = try await APIService.continueOrThrowPreferabliException(response: stylesResp)
    //                let styleArray = try APIService.continueOrThrowJSONException(data: stylesResp.data!) as! [[String: Any]]
    //                for dict in styleArray {
    //                    let style = try Storage.upsertStyle(from: dict, in: ctx)
    //                    if let ps = prefMapByStyleId[style.id] {
    //                        ps.style = style
    //                    }
    //                }
    //            }
    //
    //            try ctx.save()
    //            Storage.getKeyStore().set(Date(), forKey: "lastCalledProfile")
    //            Storage.getKeyStore().setValue(true, forKey: "hasLoadedProfile")
    //        }
    //    }
    
    
    
    //    /// Get a list of foods to choose from to be used in ``getRecs(product_category:product_type:collection_id:price_min:price_max:style_ids:food_ids:include_merchant_links:onCompletion:onFailure:)``.
    //    /// - Parameters:
    //    ///   - force_refresh: pass true if you want to force a refresh from the API and wait for the results to return. Otherwise, the call will load locally if available and run a background refresh only if one has not been initiated in the past 5 minutes. Defaults to *false*.
    //    ///   - onCompletion: returns an an array of ``Food`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func getFoods(force_refresh : Bool = false, onCompletion : @escaping ([Food]) -> () = {_ in }, onFailure : @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh, {
    //            self.getFoodsActual(force_refresh: force_refresh, onCompletion: onCompletion, onFailure: onFailure)
    //        })
    //    }
    //
    //    private func getFoodsActual(
    //        force_refresh: Bool,
    //        onCompletion: @escaping ([Food]) -> (),
    //        onFailure: @escaping (PreferabliException) -> ()
    //    ) async {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: true)
    //            Analytics.track( ["event" : "get_foods"])
    //
    //            let ks = Storage.getKeyStore()
    //
    //            // Refresh now if needed
    //            if force_refresh || !ks.bool(forKey: "hasLoadedFoods") {
    //                // Assumes you've converted `loadFoods` to SwiftData (no Core Data context arg)
    //                try await loadFoods()
    //            } else if PreferabliTools.hasMinutesPassed(minutes: 5, startDate: ks.object(forKey: "lastCalledFoods") as? Date) {
    //                // Opportunistic background refresh
    //                PreferabliTools.startNewAsyncWorkThread(priority: .low) {
    //                    do {
    //                        try self.loadFoods()
    //                    } catch {
    //                        if Preferabli.loggingEnabled { print(error) }
    //                    }
    //                }
    //            }
    //
    //            // Fetch Foods from SwiftData
    //            let ctx = await Preferabli.storage.newContext()
    //            let foods: [Food] = try ctx.fetch(FetchDescriptor<Food>())
    //
    //            // Sort alphabetically by name (case-insensitive), nils last
    //            let foodArray = foods.sorted {
    //                switch ($0.name, $1.name) {
    //                case let (l?, r?): return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
    //                case (nil, _?):    return false
    //                case (_?, nil):    return true
    //                default:           return false
    //                }
    //            }
    //
    //            try await canWeContinue(needsToBeLoggedIn: true)
    //
    //            DispatchQueue.main.async {
    //                onCompletion(foodArray)
    //            }
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    //
    //
    //    // SwiftData version (no Core Data context param)
    //    private func loadFoods() async throws {
    //        // 1) Fetch from API
    //        var resp = try Preferabli.api.getAlamo().get(APIEndpoints.foods)
    //        resp = try await APIService.continueOrThrowPreferabliException(response: resp)
    //
    //        guard let foodDicts = try APIService.continueOrThrowJSONException(data: resp.data!) as? [[String: Any]]
    //        else {
    //            throw PreferabliException(type: .MappingNotFound)
    //        }
    //
    //        // 2) Upsert into SwiftData
    //        let ctx = await Preferabli.storage.newContext()
    //        for fd in foodDicts {
    //            _ = try Storage.upsertFood(from: fd, in: ctx)
    //        }
    //        try ctx.save()
    //
    //        // 3) Flags (same as before)
    //        let ks = Storage.getKeyStore()
    //        ks.set(Date(), forKey: "lastCalledFoods")
    //        ks.setValue(true, forKey: "hasLoadedFoods")
    //    }
    //
    //
    //    /// Get a personalized, preference based recommendation for a customer.
    //    /// - Parameters:
    //    ///   - product_category: pass a ``ProductCategory`` that you would like the results to conform to.
    //    ///   - product_type: pass a ``ProductType`` that you would like the results to conform to. Pass ``ProductType/OTHER`` if ``ProductCategory`` is not set  to ``ProductCategory/WINE``. If ``ProductCategory/WINE`` is passed, a type of wine *must* be passed here.
    //    ///   - collection_id: the id of a specific ``Collection`` that you want to draw results from. Defaults to ``PRIMARY_INVENTORY_ID``. Pass *nil* for results from anywhere.
    //    ///   - price_min: pass if you want to lock results to a minimum price. Defaults to *nil*.
    //    ///   - price_max: pass if you want to lock results to a maximum price. Defaults to *nil*.
    //    ///   - style_ids: an array of ``Style`` ids that you want to constrain results to. Get available styles from ``getProfile(force_refresh:onCompletion:onFailure:)``. Defaults to *nil*.
    //    ///   - food_ids: an array of ``Food`` ids that should pair with the recommendation. Get available foods from ``getFoods(force_refresh:onCompletion:onFailure:)`` Defaults to *nil*.
    //    ///   - include_merchant_links: pass true if you want the results to include an array of ``MerchantProductLink`` embedded in ``Variant``. These connect Preferabli products to your own. Passing true requires additional resources and therefore will take longer. Defaults to *true*.
    //    ///   - onCompletion: returns an optional message as a string along with an array of ``Product`` if the call was successful. *Returns on the main thread.*
    //    ///   - onFailure: returns ``PreferabliException``  if the call fails. *Returns on the main thread.*
    //    public func getRecs(product_category : ProductCategory, product_type : ProductType,  collection_id : Int = Preferabli.PRIMARY_INVENTORY_ID, price_min : Int? = nil, price_max : Int? = nil, style_ids : [Int]? = nil, food_ids : [Int]? = nil, include_merchant_links: Bool = true, onCompletion: @escaping (String?, [Product]) -> () = {_,_  in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
    //        PreferabliTools.startNewAsyncWorkThread(priority: .veryHigh, {
    //            self.getRecsActual(product_category: product_category, product_type: product_type, price_min: price_min, price_max: price_max, collection_id: collection_id, style_ids: style_ids, food_ids: food_ids, include_merchant_links: include_merchant_links, onCompletion: onCompletion, onFailure: onFailure)
    //        })
    //    }
    //
    //    private func getRecsActual(
    //        product_category: ProductCategory,
    //        product_type: ProductType,
    //        price_min: Int?,
    //        price_max: Int?,
    //        collection_id: Int,
    //        style_ids: [Int]?,
    //        food_ids: [Int]?,
    //        include_merchant_links: Bool,
    //        onCompletion: @escaping (String?, [Product]) -> (),
    //        onFailure: @escaping (PreferabliException) -> ()
    //    ) async {
    //        do {
    //            try await canWeContinue(needsToBeLoggedIn: true)
    //            Analytics.track( ["event" : "get_recs"])
    //
    //            // Build constraints payload (same semantics as before)
    //            var constraints = [[String: Any]]()
    //
    //            if Preferabli.isCustomerLoggedIn() {
    //                constraints.append([
    //                    "type"   : "channel_customer_ids",
    //                    "values" : [PreferabliTools.getCustomerId()]
    //                ])
    //            } else {
    //                constraints.append([
    //                    "type"   : "user_ids",
    //                    "values" : [PreferabliTools.getPreferabliUserId()]
    //                ])
    //            }
    //
    //            let typeName = (product_type != .OTHER) ? product_type.getTypeName() : product_category.getCategoryName()
    //            constraints.append(["type": "collection_ids",      "values": [collection_id]])
    //            constraints.append(["type": "types",               "values": [typeName]])
    //            constraints.append(["type": "product_categories",  "values": [product_category.getCategoryName()]])
    //            constraints.append(["type": "precedence",          "values": false])
    //            constraints.append(["type": "single_style",        "values": false])
    //            constraints.append(["type": "rated_wines",         "values": "ignore"])
    //
    //            if let style_ids, !style_ids.isEmpty {
    //                constraints.append(["type": "style_ids", "values": style_ids])
    //            }
    //            if let food_ids, !food_ids.isEmpty {
    //                constraints.append(["type": "food_ids", "values": food_ids])
    //            }
    //            if let price_min { constraints.append(["type": "price_min", "values": price_min]) }
    //            if let price_max { constraints.append(["type": "price_max", "values": price_max]) }
    //
    //            let payload: [String: Any] = ["constraints": constraints]
    //
    //            // Call recommender
    //            var recResponse = try Preferabli.api.getAlamo().post(APIEndpoints.getRec, json: payload)
    //            recResponse = try await APIService.continueOrThrowPreferabliException(response: recResponse)
    //            let recDictionary = try APIService.continueOrThrowJSONException(data: recResponse.data!) as! [String: Any]
    //
    //            let message = recDictionary["message"] as? String
    //            let results  = recDictionary["results"] as? [[String: Any]] ?? []
    //
    //            // Collect variant ids and prediction metadata
    //            var variantIds: [Int] = []
    //            var predictByVariant: [Int: (rating: Int, code: Int)] = [:]
    //            for r in results {
    //                guard
    //                    let vid = (r["variant_id"] as? NSNumber)?.intValue ?? r["variant_id"] as? Int
    //                else { continue }
    //                let wili = (r["formatted_predict_rating"] as? NSNumber)?.intValue ?? (r["formatted_predict_rating"] as? Int) ?? 0
    //                let code = (r["confidence_code"] as? NSNumber)?.intValue ?? (r["confidence_code"] as? Int) ?? 0
    //                variantIds.append(vid)
    //                predictByVariant[vid] = (rating: wili, code: code)
    //            }
    //
    //            var productsToReturn: [Product] = []
    //            let ctx = await Preferabli.storage.newContext()
    //
    //            // Load products for those variants
    //            if !variantIds.isEmpty {
    //                var getProductsResponse = try Preferabli.api.getAlamo().get(APIEndpoints.products, params: ["variant_ids": variantIds])
    //                getProductsResponse = try await APIService.continueOrThrowPreferabliException(response: getProductsResponse)
    //                let productDictionaries = try APIService.continueOrThrowJSONException(data: getProductsResponse.data!) as! [[String: Any]]
    //
    //                // Upsert and attach preference data to matching variants
    //                for pd in productDictionaries {
    //                    let p = try Storage.upsertProduct(from: pd, in: ctx)
    //
    //                    for v in p.variants {
    //                        if let meta = predictByVariant[v.id] {
    //                            // Use your PreferenceData initializer signature
    //                            v.preference_data = PreferenceData(confidence_code: meta.code, formatted_predict_rating: meta.rating)
    //                        }
    //                    }
    //
    //                    productsToReturn.append(p)
    //                }
    //            }
    //
    //            try ctx.save()
    //
    //            if include_merchant_links {
    //                try await addMerchantDataToProducts(products: productsToReturn)
    //            }
    //
    //            try await canWeContinue(needsToBeLoggedIn: true)
    //
    //            DispatchQueue.main.async {
    //                onCompletion(message, productsToReturn)
    //            }
    //
    //        } catch {
    //            handleError(error: error, onFailure: onFailure)
    //        }
    //    }
    //
    //    private func addMerchantDataToProducts(products: [Product]) async throws {
    //        if (products.count == 0) {
    //            return
    //        }
    //
    //        var dictionaries = Array<[String : Any]>()
    //        for product in products {
    //            for variant in product.variants {
    //                var dictionary = [String : Any]()
    //                dictionary["number"] = variant.id
    //                dictionary["variant_ids"] = [variant.id]
    //                dictionaries.append(dictionary)
    //            }
    //        }
    //
    //        var conversionResponse = try Preferabli.api.getAlamo().post(APIEndpoints.lookupConversion(id: Preferabli.INTEGRATION_ID), jsonObject: dictionaries)
    //        conversionResponse = try await APIService.continueOrThrowPreferabliException(response: conversionResponse)
    //        let conversionDictionaries = try APIService.continueOrThrowJSONException(data: conversionResponse.data!) as! Array<[String : Any]>
    //
    //
    //    outerLoop:
    //        for dictionary in conversionDictionaries {
    //            let variant_id = dictionary["number"] as! Int
    //            for product in products {
    //                for variant in product.variants {
    //                    if (variant.id == variant_id) {
    //                        let lookups = dictionary["lookups"] as! Array<[String : Any]>
    //                        var merchant_links = Array<MerchantProductLink>()
    //                        for lookup in lookups {
    //                            let merchantProductLink = MerchantProductLink.init(map: lookup)
    //                            merchant_links.append(merchantProductLink)
    //                        }
    //                        variant.merchant_links = merchant_links
    //                        continue outerLoop
    //                    }
    //                }
    //            }
    //        }
    //    }
    //
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
        tag_type: TagType,
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
                
                let tagDTO : TagDTO = TagDTO.init(id: tempTagId, collection_id: collection_id, comment: notes, created_at: Date.init(), location: location, badge: nil, tagged_in_collection_id: tagged_in_collection_id, tagged_in_channel_id: nil, tagged_in_channel_name: nil, type: tag_type.getDatabaseName(), updated_at: Date.init(), user_id: PreferabliTools.getPreferabliUserId(), value: value, bin: bin, variant_id: variant.id, quantity: quantity, format_ml: format_ml, price: price, customer_id: PreferabliTools.getCustomerId())
                let tag = try Storage.upsertTag(from: tagDTO, variant: variant, in: ctx)
                product.updateCachedRelationships()
                try ctx.save()
            }
            
            let payload: SParams = [
                "type"         : tag_type.getDatabaseName(),
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
            let (product_id, collection_id, tag_type, value): (Int, Int, TagType, String?) =
            try Storage.withContext { ctx in
                guard let tag = try Storage.fetchById(Tag.self, id: tag_id, in: ctx) else {
                    throw PreferabliException.init(type: .BadSwiftData, message: "Tag not found.", code: 404)
                }
                return (tag.product_id, tag.collection_id, tag.tag_type, tag.value)
            }
            
            try await createOrEditTagActual(tag_id: tag_id, product_id: product_id, year: year, collection_id: collection_id, value: value, tag_type: tag_type, location: location, notes: notes, price: price, quantity: quantity, format_ml: format_ml)
        }
}
