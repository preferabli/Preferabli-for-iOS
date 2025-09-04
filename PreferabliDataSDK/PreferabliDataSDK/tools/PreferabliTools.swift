//
//  PreferabliTools.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/10/16.
//  Copyright © 2023 RingIT, Inc. All rights reserved.
//

import Foundation
import UIKit
import Alamofire
import SwiftData
import CoreLocation
import AVFoundation
import Contacts
import Photos
import Mixpanel

/// Contains lots of helper methods for private use within Preferabli's projects.
internal class PreferabliTools {
    
    private static let logoutDispatchGroup = DispatchGroup()
//    private static var loggingOut = false
    
    private static let operationQueue = OperationQueue()
    private static let apiOperationQueue = OperationQueue()
        
    internal class func isLoggedOutOrLoggingOut() -> Bool {
//        return loggingOut || (!isPreferabliUserLoggedIn() && !isCustomerLoggedIn())
        return (!isPreferabliUserLoggedIn() && !isCustomerLoggedIn())
    }
    
    internal class func startNewAsyncWorkThread(
        priority: Operation.QueuePriority,
        _ work: @escaping @Sendable () async -> Void
    ) {
        let op = BlockOperation {
            // Use a Task so we can call async code inside the Operation
            Task { await work() }
        }
        startNewWorkThread(priority: priority, operation: op)
    }

    
    internal class func startNewWorkThread(_ block: @escaping @convention(block) () -> Void, priority : Operation.QueuePriority) {
        startNewWorkThread(priority: priority, block)
    }
    
    internal class func startNewWorkThread(_ block: @escaping @convention(block) () -> Void) {
        startNewWorkThread(priority: .high, block)
    }
    
    internal class func startNewWorkThread(priority : Operation.QueuePriority, _ block: @escaping @convention(block) () -> Void) {
        let operation = BlockOperation()
        operation.addExecutionBlock {
            block()
        }
        startNewWorkThread(priority : priority, operation: operation)
    }
    
    internal class func startNewWorkThread(operation : Operation) {
        startNewWorkThread(priority: .high, operation: operation)
    }
    
    internal class func startNewWorkThread(priority : Operation.QueuePriority, operation : Operation) {
        operation.queuePriority = priority
        operationQueue.maxConcurrentOperationCount = 30
        operationQueue.addOperation(operation)
    }
    
    internal class func startNewAPIWorkThread(priority : Operation.QueuePriority, operation : Operation) {
        operation.queuePriority = priority
        apiOperationQueue.maxConcurrentOperationCount = 10
        apiOperationQueue.addOperation(operation)
    }
    
    internal class func saveCollectionEtag(response : AFDataResponse<Data?>, collectionId : Int) {
        if (response.response != nil) {
            let headers = response.response!.allHeaderFields
            if (!isNullOrWhitespace(string: headers["collection_etag"] as? String)) {
                var collectionEtags = PreferabliTools.getKeyStore().stringArray(forKey: "collection_etags_" + NSNumber(value: collectionId).stringValue) ?? Array<String>()
                if (!collectionEtags.contains(headers["collection_etag"] as! String)) {
                    collectionEtags.append(headers["collection_etag"] as! String)
                    PreferabliTools.getKeyStore().set(collectionEtags, forKey: "collection_etags_" + NSNumber(value: collectionId).stringValue)
                }
            }
        }
    }
    
    internal class func hasBeenLoaded(response : AFDataResponse<Data?>, collectionId : NSNumber) -> Bool {
        if (response.response != nil && PreferabliTools.getKeyStore().bool(forKey: "hasLoaded" + collectionId.stringValue)) {
            let headers = response.response!.allHeaderFields
            if (!isNullOrWhitespace(string: headers["collection_etag"] as? String)) {
                let collectionEtags = PreferabliTools.getKeyStore().stringArray(forKey: "collection_etags_" + collectionId.stringValue) ?? Array<String>()
                if (collectionEtags.contains(headers["collection_etag"] as! String)) {
                    return true
                }
            }
        }
        
        return false
    }
    
    internal class func getTimezoneWithOffset(identifier : String) -> String {
        let timezone = TimeZone.init(identifier: identifier)!
        let seconds = timezone.secondsFromGMT()
        let hours = seconds/3600
        let minutes = abs(seconds/60) % 60
        return "(GMT" + String(format: "%+.2d:%.2d", hours, minutes) + ") " + timezone.localizedName(for: NSTimeZone.NameStyle.standard, locale: Locale.current)!
    }
    
    internal class func sortTimezonesByOffset(timezones: [TimeZone]) -> Array<TimeZone> {
        return timezones.sorted {
            if ($0.secondsFromGMT() == $1.secondsFromGMT()) {
                return $0.localizedName(for: NSTimeZone.NameStyle.standard, locale: Locale.current)!.caseInsensitiveCompare($1.localizedName(for: NSTimeZone.NameStyle.standard, locale: Locale.current)!) == ComparisonResult.orderedAscending
            }
            return $0.secondsFromGMT() < $1.secondsFromGMT()
        }
    }
    
    internal class func isKeyPresentInKeyStore(key: String) -> Bool {
        return PreferabliTools.getKeyStore().object(forKey: key) != nil
    }
    
    internal class func getKeyStore() -> UserDefaults {
        return UserDefaults.init(suiteName: "Preferabli")!
    }
    
    internal class func addSDKProperties() {
        let id = PreferabliTools.isPreferabliUserLoggedIn() ? PreferabliTools.getPreferabliUserId() : PreferabliTools.getCustomerId()
        let email = PreferabliTools.getKeyStore().object(forKey: "email") as? String
        let phone = PreferabliTools.getKeyStore().object(forKey: "phone") as? String
        let display_name = PreferabliTools.getKeyStore().object(forKey: "displayName") as? String
        let isTeamRingIt = PreferabliTools.getKeyStore().bool(forKey: "isTeamRingIT")
        
        if (id != 0) {
            Mixpanel.mainInstance().identify(distinctId: String(id))
            Mixpanel.mainInstance().people.set(properties: [(PreferabliTools.isPreferabliUserLoggedIn() ? "user_id" : "customer_id") : id, "is_team_ringit" : isTeamRingIt])
            
            if (!PreferabliTools.isNullOrWhitespace(string: email)) {
                Mixpanel.mainInstance().people.set(properties: ["$email": email!])
            }
            
            if (!PreferabliTools.isNullOrWhitespace(string: phone)) {
                Mixpanel.mainInstance().people.set(properties: ["phone": phone!])
            }
            
            if (!PreferabliTools.isNullOrWhitespace(string: display_name)) {
                Mixpanel.mainInstance().people.set(properties: ["display_name": display_name!])
            }
        }
    }
    
    internal class func calculateDistanceInMiles(lat1 : NSNumber?, lon1 : NSNumber?, lat2 : NSNumber?, lon2 : NSNumber?) -> Int? {
        if (lat1 == nil || lat1 == 0 || lat2 == nil || lat2 == 0 || lon1 == nil || lon1 == 0 || lon2 == nil || lon2 == 0) {
            return nil
        }
        let coordinate1 = CLLocation(latitude: lat1 as! CLLocationDegrees, longitude: lon1 as! CLLocationDegrees)
        let coordinate2 = CLLocation(latitude: lat2 as! CLLocationDegrees, longitude: lon2 as! CLLocationDegrees)
        
        let distanceInMeters = coordinate1.distance(from: coordinate2)
        let distanceInMiles = distanceInMeters / 1609.344
        return Int(distanceInMiles)
    }
    
    internal class func getPreferabliUserId() -> Int {
        return PreferabliTools.getKeyStore().integer(forKey: "user_id")
    }
    
    internal class func getCustomerId() -> Int {
        return PreferabliTools.getKeyStore().integer(forKey: "customer_id")
    }
    
    internal class func getUserImage() -> String {
        return PreferabliTools.getKeyStore().string(forKey: "avatar") ?? ""
    }
    
    internal class func isUserLocked() -> Bool {
        return PreferabliTools.getKeyStore().integer(forKey: "accountLevel") != 2
    }
    
    internal class func getAPIDateFormatter() -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
    }
    
    internal class func setUserProperties(user : PreferabliUser) {
        // set user properties to defaults
        PreferabliTools.getKeyStore().set(user.id, forKey: "user_id")
        PreferabliTools.getKeyStore().set(user.fname, forKey: "firstName")
        PreferabliTools.getKeyStore().set(user.lname, forKey: "lastName")
        PreferabliTools.getKeyStore().set(user.display_name, forKey: "displayName")
        PreferabliTools.getKeyStore().set(user.country, forKey: "country")
        PreferabliTools.getKeyStore().set(user.avatar?.path, forKey: "avatar")
        PreferabliTools.getKeyStore().set(user.zip_code, forKey: "zipCode")
        PreferabliTools.getKeyStore().set(user.email, forKey: "email")
        PreferabliTools.getKeyStore().set(user.is_team_ringit, forKey: "isTeamRingIT")
        PreferabliTools.getKeyStore().set(user.rating_collection_id, forKey: "ratings_id")
        PreferabliTools.getKeyStore().set(user.wishlist_collection_id, forKey: "wishlist_id")
        PreferabliTools.getKeyStore().set(user.claim_code, forKey: "claim_code")
        PreferabliTools.getKeyStore().set(user.provided_feedback_at, forKey: "feedbackDate")
        PreferabliTools.getKeyStore().set(user.intercom_hmac, forKey: "intercom_hmac")
    }
    
//    internal class func logout() async {
//        if (loggingOut) {
//            return
//        }
//        loggingOut = true
//        logoutDispatchGroup.wait()
//        logoutDispatchGroup.enter()
//        
//        operationQueue.cancelAllOperations()
//        apiOperationQueue.cancelAllOperations()
//        
//        await clearAllData()
//        
//        logoutDispatchGroup.leave()
//        loggingOut = false
//    }
    
    // SwiftData replacement for the old Core Data factory.
    // Creates/updates a PreferabliUser from values stored in KeyStore.
    // Returns nil if "user_id" is not present (since SwiftData requires an id).
//    internal static func createUserFromUserDefaults(in ctx: ModelContext) -> PreferabliUser? {
//        let ks = PreferabliTools.getKeyStore()
//
//        // Small local helpers to read types safely from KeyStore
//        func intForKey(_ key: String) -> Int? {
//            let v = ks.object(forKey: key)
//            if let i = v as? Int { return i }
//            if let n = v as? NSNumber { return n.intValue }
//            if let s = v as? String { return Int(s) }
//            return nil
//        }
//        func stringForKey(_ key: String) -> String? {
//            ks.object(forKey: key) as? String
//        }
//
//        // Need an id to build a SwiftData model
//         guard let id = intForKey("user_id") else { return nil }
//
//         // Fetch or create (id-only) without chained conditional binding
//        let existing: PreferabliUser? = (try? Storage.fetchById(PreferabliUser.self, id: id, in: ctx)) ?? nil
//         let user: PreferabliUser = existing ?? {
//             let u = PreferabliUser(id: id)   // <-- id-only init
//             ctx.insert(u)
//             return u
//         }()
//
//        // Single assignment pass: copy fields from KeyStore if present
//        if let v = stringForKey("firstName")               { user.fname = v }
//        if let v = stringForKey("lastName")                { user.lname = v }
//        if let v = stringForKey("displayName")             { user.display_name = v }
//        if let v = stringForKey("country")                 { user.country = v }
//        if let v = stringForKey("zipCode")                 { user.zip_code = v }
//        if let v = stringForKey("email")                   { user.email = v }
//        if let v = stringForKey("claim_code")              { user.claim_code = v }
//        if let v = intForKey("ratings_id")                 { user.rating_collection_id = v }
//        if let v = intForKey("wishlist_id")                { user.wishlist_collection_id = v }
//
//        // Avatar (stored as a path string in KeyStore)
//        if let avatarPath = stringForKey("avatar") {
//            if let existing = user.avatar {
//                existing.path = avatarPath
//            } else {
//                let avatar = Media(id: Int.random(in: 1...Int.max))  // id-only init
//                avatar.path = avatarPath
//                ctx.insert(avatar)
//                user.avatar = avatar
//            }
//        }
//
//        return user
//    }


    internal class func clearAllData() async {
        // delete all from core data
        await Storage.reset()
        
        // clear HTTP cache
        Preferabli.api.clearUrlCache()
        Preferabli.api.refreshDefaults()
        
        let integration_id = PreferabliTools.getKeyStore().integer(forKey: "INTEGRATION_ID")
        let client_interface = PreferabliTools.getKeyStore().string(forKey: "CLIENT_INTERFACE")
        
        UserDefaults.standard.removePersistentDomain(forName: "Preferabli")
        
        PreferabliTools.getKeyStore().set(integration_id, forKey: "INTEGRATION_ID")
        PreferabliTools.getKeyStore().set(client_interface, forKey: "CLIENT_INTERFACE")
    }
    
    internal class func getSymbolForCurrencyCode(currencyCode: String?) -> String {
        if (PreferabliTools.isNullOrWhitespace(string: currencyCode)) {
            return "$"
        }
        
        let code = currencyCode!
        var candidates: [String] = []
        let locales: [String] = NSLocale.availableLocaleIdentifiers
        for localeID in locales {
            guard let symbol = findMatchingSymbol(localeID: localeID, currencyCode: code) else {
                continue
            }
            if symbol.count == 1 {
                return symbol
            }
            candidates.append(symbol)
        }
        let sorted = sortStringsByLength(list: candidates)
        if sorted.count < 1 {
            return ""
        }
        return sorted[0]
    }
    
    internal class func getLocaleForCurrencyCode(currencyCode: String?) -> Locale {
        if (PreferabliTools.isNullOrWhitespace(string: currencyCode)) {
            return Locale.current
        }
        
        let code = currencyCode!
        var candidates: [String] = []
        let locales: [String] = NSLocale.availableLocaleIdentifiers
        for localeID in locales {
            guard let symbol = findMatchingSymbol(localeID: localeID, currencyCode: code) else {
                continue
            }
            if symbol.count == 1 {
                return  Locale(identifier: localeID as String)
            }
            candidates.append(localeID)
        }
        let sorted = sortStringsByLength(list: candidates)
        if sorted.count < 1 {
            return Locale.current
        }
        return Locale(identifier: sorted[0] as String)
    }
    
    internal class func findMatchingSymbol(localeID: String, currencyCode: String) -> String? {
        let locale = Locale(identifier: localeID as String)
        guard let code = locale.currencyCode else {
            return nil
        }
        if code != currencyCode {
            return nil
        }
        guard let symbol = locale.currencySymbol else {
            return nil
        }
        return symbol
    }
    
    internal class func isPreferabliUserLoggedIn() -> Bool {
        let accessToken = PreferabliTools.getKeyStore().string(forKey: "access_token")
        let userId = getPreferabliUserId()
        return accessToken != nil && userId != 0
    }
    
    internal class func isCustomerLoggedIn() -> Bool {
        let accessToken = PreferabliTools.getKeyStore().string(forKey: "access_token")
        let customerId = getCustomerId()
        return accessToken != nil && customerId != 0
    }
    
    internal class func resizeImage(image: UIImage, newDimension: CGFloat) -> UIImage? {
        var newHeight : CGFloat
        var newWidth : CGFloat
        
        if (image.size.width <= newDimension && image.size.height <= newDimension) {
            return image
        } else if (image.size.width > image.size.height) {
            newWidth = newDimension
            let scale = newWidth / image.size.width
            newHeight = image.size.height * scale
        } else {
            newHeight = newDimension
            let scale = newHeight / image.size.height
            newWidth = image.size.width * scale
        }
        
        UIGraphicsBeginImageContext(CGSize(width: newWidth, height: newHeight))
        image.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
    
    internal class func isNullOrWhitespace(string : String?) -> Bool {
        if (string == nil) {
            return true
        }
        
        return string!.isEmptyOrWhitespace()
    }
    
    internal class func isNullOrWhitespace(string : NSAttributedString?) -> Bool {
        if (string == nil) {
            return true
        }
        
        return string!.isEmptyOrWhitespace()
    }
    
    internal class func generateRandomLongId() -> Int32 {
        return -Int32(arc4random() % 28147497)
    }
    
    internal class func hasDaysPassed(days: Int, startDate: Date?) -> Bool {
        if let startDate = startDate {
            let calendar = NSCalendar.current
            let components = calendar.dateComponents([Calendar.Component.day], from: startDate, to: Date.init())
            return components.day! > (days - 1)
        } else {
            // never called API before!
            return true
        }
    }
    
    internal class func hasMinutesPassed(minutes: Int, startDate: Date?) -> Bool {
        if let startDate = startDate {
            let calendar = NSCalendar.current
            let components = calendar.dateComponents([Calendar.Component.minute], from: startDate, to: Date.init())
            return components.minute! > (minutes - 1)
        } else {
            // never called API before!
            return true
        }
    }
    
    internal class func alphaSortIgnoreThe(x : String?, y : String?) -> Bool {
        return alphaSortIgnoreThe(x: x, y: y, comparisonResult: ComparisonResult.orderedAscending)
    }
    
    internal class func alphaSortIgnoreThe(x : String?, y : String?, comparisonResult: ComparisonResult) -> Bool {
        var x = x
        var y = y
        if (isNullOrWhitespace(string: x)) {
            return false
        } else if (isNullOrWhitespace(string: y)) {
            return true
        }
        if (x!.hasPrefix("The ")) {
            x = String(x![x!.index(x!.startIndex, offsetBy: 4)...])
        }
        if (y!.hasPrefix("The ")) {
            y = String(y![y!.index(x!.startIndex, offsetBy: 4)...])
        }
        
        return x!.caseInsensitiveCompare(y!) == comparisonResult
    }

    internal class func databaseUpgraded() async {
        await Storage.reset()

        for key in PreferabliTools.getKeyStore().dictionaryRepresentation().keys {
            if key.starts(with: "hasLoaded") {
                PreferabliTools.getKeyStore().set(false, forKey: key)
            }
            if key.starts(with: "collection_etags") || key.starts(with: "lastCalled") {
                PreferabliTools.getKeyStore().set(nil, forKey: key)
            }
        }
    }
    
    internal class func handleUpgrade() async {
        let versionCode = Preferabli.versionCode
        let savedVersionCode = PreferabliTools.getKeyStore().integer(forKey: "versionCode")
        
        if (savedVersionCode != versionCode) {
            if (savedVersionCode == 0) {
                // new user do nothing for now
            } else {
                // user has upgraded the app always pull new data
                await databaseUpgraded()
            }
            // we handled either possible situation so update the version code to current version
            PreferabliTools.getKeyStore().set(versionCode, forKey: "versionCode")
        }
    }
    
    internal class func sortStringsByLength(list: [String]) -> [String] {
        return list.sorted(by: { $0.count < $1.count })
    }

    internal class func getImageUrl(image : String?, width : CGFloat, height : CGFloat, quality : Int) -> URL? {
        if (isNullOrWhitespace(string: image)) {
            return nil
        }
        
        var image = image!
        if (image.contains("placeholder")) {
            return nil
        } else if (image.contains("winering.com") || image.contains("preferabli.com")) {
            return URL.init(string: image)
        } else if (image.contains("s3.amazonaws.com/winering-production")) {
            let index = image.range(of: "/", options: .backwards, range: nil, locale: nil)!.upperBound
            if (image.containsIgnoreCase("/avatars")) {
                image = "avatars/" + image.substring(from: index)
            } else {
                image = image.substring(from: index)
            }
        } else {
            return URL.init(string: image)
        }
        
        let cloudfrontAppId = "ios_sdk/fit-in/"
        let sizeString = String(Int(width * UIScreen.main.scale)) + "x" + String(Int(height * UIScreen.main.scale)) + "/"
        let qualityString = "filters:quality(" + String(quality) + ")/"
        let pngString = image.containsIgnoreCase("png") ? "filters:format(png)/"  : ""
        var cloudFrontURL = "https://dxlu3le4zp2pd.cloudfront.net/wineringlabel/" + cloudfrontAppId + sizeString + qualityString + pngString + image
        return URL.init(string: cloudFrontURL)
    }
}
