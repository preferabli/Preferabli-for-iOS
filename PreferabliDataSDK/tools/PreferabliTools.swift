//
//  PreferabliTools.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/10/16.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
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
    
    private static let operationQueue = OperationQueue()
    private static let apiOperationQueue = OperationQueue()
    
    private actor LogoutCoordinator {
        private var inProgress = false
        
        /// Try to start a logout. Returns `false` if one is already running.
        func begin() -> Bool {
            guard !inProgress else { return false }
            inProgress = true
            return true
        }
        func end() { inProgress = false }
        func isRunning() -> Bool { inProgress }
    }
    private static let logoutCoord = LogoutCoordinator()
    
    // MARK: - Public API
    
    /// Serializes logouts and avoids blocking threads. If a logout is already
    /// running, this is a no-op (matching your original early-return).
    internal static func logout() async throws {
        // prevent re-entrance
        guard await logoutCoord.begin() else { return }
        defer { Task { await logoutCoord.end() } }
        
        // Cancel your outstanding work
        operationQueue.cancelAllOperations()
        apiOperationQueue.cancelAllOperations()
    }
    
    /// Async because it reads actor state.
    internal static func isLoggedOutOrLoggingOut() async -> Bool {
        let running = await logoutCoord.isRunning()
        return running || (!Preferabli.isPreferabliUserLoggedIn() && !Preferabli.isCustomerLoggedIn())
    }
    
    internal class func startNewAsyncWorkThread(priority: Operation.QueuePriority = .high,_ work: @escaping @Sendable () async -> Void) {
        let op = BlockOperation {
            // Use a Task so we can call async code inside the Operation
            Task { await work() }
        }
        startNewWorkThread(priority: priority, operation: op)
    }
    
    internal class func startNewWorkThread(priority: Operation.QueuePriority = .high, _ body: @escaping @Sendable () -> Void) {
        let operation = BlockOperation(block: body)
        operation.queuePriority = priority
        startNewWorkThread(priority: priority, operation: operation)
    }
    
    internal class func startNewWorkThread(priority : Operation.QueuePriority = .high, operation : Operation) {
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
            if (!(headers["collection_etag"] as? String).isEmptyOrWhitespace) {
                var collectionEtags = Storage.getKeyStore().stringArray(forKey: "collection_etags_" + NSNumber(value: collectionId).stringValue) ?? Array<String>()
                if (!collectionEtags.contains(headers["collection_etag"] as! String)) {
                    collectionEtags.append(headers["collection_etag"] as! String)
                    Storage.getKeyStore().set(collectionEtags, forKey: "collection_etags_" + NSNumber(value: collectionId).stringValue)
                }
            }
        }
    }
    
    internal class func hasBeenLoaded(response : AFDataResponse<Data?>, collectionId : NSNumber) -> Bool {
        if (response.response != nil && Storage.getKeyStore().bool(forKey: "hasLoaded" + collectionId.stringValue)) {
            let headers = response.response!.allHeaderFields
            if (!(headers["collection_etag"] as? String).isEmptyOrWhitespace) {
                let collectionEtags = Storage.getKeyStore().stringArray(forKey: "collection_etags_" + collectionId.stringValue) ?? Array<String>()
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
    
    internal class func addSDKProperties() {
        let id = Preferabli.isPreferabliUserLoggedIn() ? PreferabliTools.getPreferabliUserId() : PreferabliTools.getCustomerId()
        let email = Storage.getKeyStore().object(forKey: "email") as? String
        let zip = Storage.getKeyStore().object(forKey: "zipCode") as? String
        let display_name = Storage.getKeyStore().object(forKey: "displayName") as? String
        let isTeamPreferabli = Storage.getKeyStore().bool(forKey: "isTeamPreferabli")
        
        if (id != 0) {
            Mixpanel.mainInstance().identify(distinctId: String(id))
            Mixpanel.mainInstance().people.set(properties: [(Preferabli.isPreferabliUserLoggedIn() ? "user_id" : "customer_id") : id, "is_team_preferabli" : isTeamPreferabli])
            
            if (!email.isEmptyOrWhitespace) {
                Mixpanel.mainInstance().people.set(properties: ["$email": email!])
            }
            
            if (!zip.isEmptyOrWhitespace) {
                Mixpanel.mainInstance().people.set(properties: ["zip_code": zip!])
            }
            
            if (!display_name.isEmptyOrWhitespace) {
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
        return Storage.getKeyStore().integer(forKey: "user_id")
    }
    
    internal class func getCustomerId() -> Int {
        return Storage.getKeyStore().integer(forKey: "customer_id")
    }
    
    internal class func getAPIDateFormatter() -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return dateFormatter
    }
    
    internal class func setUserProperties(user : PreferabliUser) {
        // set user properties to defaults
        Storage.getKeyStore().set(user.id, forKey: "user_id")
        Storage.getKeyStore().set(user.fname, forKey: "firstName")
        Storage.getKeyStore().set(user.lname, forKey: "lastName")
        Storage.getKeyStore().set(user.display_name, forKey: "displayName")
        Storage.getKeyStore().set(user.country, forKey: "country")
        Storage.getKeyStore().set(user.avatar?.path, forKey: "avatar")
        Storage.getKeyStore().set(user.zip_code, forKey: "zipCode")
        Storage.getKeyStore().set(user.email, forKey: "email")
        Storage.getKeyStore().set(user.is_team_preferabli, forKey: "isTeamPreferabli")
        Storage.getKeyStore().set(user.rating_collection_id, forKey: "ratings_id")
        Storage.getKeyStore().set(user.wishlist_collection_id, forKey: "wishlist_id")
        Storage.getKeyStore().set(user.claim_code, forKey: "claim_code")
        Storage.getKeyStore().set(user.provided_feedback_at, forKey: "feedbackDate")
        Storage.getKeyStore().set(user.intercom_hmac, forKey: "intercom_hmac")
    }
    
    internal class func getSymbolForCurrencyCode(currencyCode: String?) -> String {
        if (currencyCode.isEmptyOrWhitespace) {
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
        let sorted = String.sortStringsByLength(list: candidates)
        if sorted.count < 1 {
            return ""
        }
        return sorted[0]
    }
    
    internal class func getLocaleForCurrencyCode(currencyCode: String?) -> Locale {
        if (currencyCode.isEmptyOrWhitespace) {
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
        let sorted = String.sortStringsByLength(list: candidates)
        if sorted.count < 1 {
            return Locale.current
        }
        return Locale(identifier: sorted[0] as String)
    }
    
    internal class func findMatchingSymbol(localeID: String, currencyCode: String) -> String? {
        let locale = Locale(identifier: localeID as String)
        guard let code = locale.currency?.identifier else {
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
    
    internal class func generateRandomLongId() -> Int {
        return -Int(arc4random() % 28147497)
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
    
    // Core, nonisolated builder (no main-actor APIs)
    nonisolated internal static func getImageUrl(image: String?, width: Int, height: Int, quality: Int, scale: Float = Storage.getKeyStore().float(forKey: "mainScale")) -> URL? {
        guard let raw = image, !raw.isEmptyOrWhitespace() else { return nil }
        if raw.contains("placeholder") { return nil }
        if raw.contains("winering.com") || raw.contains("preferabli.com") { return URL(string: raw) }
        if !raw.contains("s3.amazonaws.com/winering-production") { return URL(string: raw) }

        var key = raw
        let index = raw.range(of: "winering-production/", options: .backwards, range: nil, locale: nil)!.upperBound
        let start = raw.index(index, offsetBy: 0)
        let end = raw.endIndex
        let range = start..<end
        key = String(raw[range])

        let cloudfrontAppId = "ios_psdk/fit-in/"
        let sizeString = "\(Int(Float(width) * scale * 1.4))x\(Int(Float(height) * scale * 1.4))/"
        let qualityString = "filters:quality(\(quality))/"
        let pngString = key.containsIgnoreCase("png") ? "filters:format(png)/" : ""
        let urlString = "https://dxlu3le4zp2pd.cloudfront.net/wineringlabel/" + cloudfrontAppId + sizeString + qualityString + pngString + key
        return URL(string: urlString)
    }
}
